import AVFoundation
import Accelerate

/// Real-time 14-band spectrum from the playing stream, feeding the artwork
/// easter egg. Built on an MTAudioProcessingTap attached to the current
/// AVPlayerItem **only while the visualizer is on screen** — when the egg is
/// hidden the audio path is completely stock. The tap runs on the render
/// thread, so everything here is fixed-size number crunching: mono ring
/// buffer → Hann window → vDSP radix-2 FFT → log-spaced band energies.
/// Buffers pass through untouched, so output is bit-identical with or without
/// the tap attached.
final class AudioSpectrum {
    static let bandCount = 14

    private let lock = OSAllocatedUnfairLock<State>(initialState: State())
    private struct State {
        var levels = [Float](repeating: 0, count: AudioSpectrum.bandCount)
        var lastCompute: CFAbsoluteTime = 0
    }

    /// Whether the egg is on screen. Set from the UI; gates only the FFT, so
    /// showing and hiding it never touches the audio pipeline.
    var isActive = false

    /// Set by the player. While true, a gap in tap callbacks is a buffer
    /// refill rather than silence, and the bars hold instead of sagging.
    var isStreaming = false

    static let holdStreaming: CFAbsoluteTime = 2.5
    static let holdStopped: CFAbsoluteTime = 0.15
    static let fadeTau: CFAbsoluteTime = 0.5

    // The tap is created ONCE and never freed while the engine lives. Early
    // versions allocated + freed a tap on every flip, and the device audio
    // pipeline would still be executing process() on the dying tap —
    // use-after-free, SIGSEGV on real hardware (the simulator tolerated it).
    // With a persistent tap there is nothing to race over: attach/detach only
    // swap the audioMix, and buffers pass through untouched.
    private var attachedItem: AVPlayerItem?
    private var tap: MTAudioProcessingTap?

    // Render-thread state, touched only from tap callbacks.
    private var sampleRate: Float = 0
    private var formatOK = false
    private var lastAnalysis: CFAbsoluteTime = 0
    // Mono accumulation, exactly one transform long: analyse() reads the
    // whole ring, oldest to newest.
    private var ring = [Float](repeating: 0, count: AudioSpectrum.fftSize)
    private var ringWrite = 0
    private var window = [Float](repeating: 1, count: AudioSpectrum.fftSize)
    private var windowed = [Float](repeating: 0, count: AudioSpectrum.fftSize)
    // vDSP_fft_zrip works on packed split-complex: n real samples in, n/2
    // complex bins out, so these are half-length by design.
    private var fftReal = [Float](repeating: 0, count: AudioSpectrum.fftSize / 2)
    private var fftImag = [Float](repeating: 0, count: AudioSpectrum.fftSize / 2)
    private var fftSetup: FFTSetup?
    private var scratch = [Float](repeating: 0, count: AudioSpectrum.bandCount)



    // 4096 @ 44.1kHz is ~10.8 Hz per bin. The bottom band (50..75 Hz) is
    // only 25 Hz wide, so a shorter transform cannot separate it from its
    // neighbour — 1024 put a 120 Hz tone in the wrong band.
    static let fftSize = 4096
    static let log2n = vDSP_Length(12)  // 2^12 == fftSize
    // Display window in dBFS — the knob to turn if the bars sit too low or peg.
    // The tap is PostEffects, so band levels scale with player volume and these
    // are calibrated for the normal volume of 1.0. Measured on the live stream,
    // bands span about -51 dBFS in quiet passages to -5 on bass hits.
    static let floorDB: Float = -55
    static let ceilingDB: Float = -5
    init() {
        fftSetup = vDSP_create_fftsetup(AudioSpectrum.log2n, FFTRadix(kFFTRadix2))
        vDSP_hann_window(&window, vDSP_Length(window.count), Int32(vDSP_HANN_NORM))
    }

    /// Latest smoothed band levels, 0...1. Called every UI frame; decays the
    /// bars toward zero when the stream is paused and callbacks stop firing.
    func snapshot(at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> [Float] {
        // AVPlayer re-prepares the tap every 20-35s on a live stream and the
        // callbacks pause for up to ~1.6s while it refills. The audio never
        // stops, so those gaps must not drag the bars down — hold them while
        // the player is running, and only fade when playback really stops.
        let hold = isStreaming ? AudioSpectrum.holdStreaming : AudioSpectrum.holdStopped
        return lock.withLock { state in
            let idle = now - state.lastCompute
            guard idle > hold else { return state.levels }
            // Time-based, so the fade is the same at any frame rate. The stored
            // levels are left alone: this only dims what is displayed, so the
            // bars snap back the moment analysis resumes.
            let fade = Float(exp(-(idle - hold) / AudioSpectrum.fadeTau))
            return state.levels.map { $0 * fade }
        }
    }

    // MARK: – Attach / detach (main thread)

    /// Attach the (persistent) tap to `item`. Called from play() only, before
    /// playback starts: assigning `audioMix` to an item that is already playing
    /// makes AVPlayer rebuild the audio pipeline, which on a live stream is an
    /// audible drop-out and several seconds of silent tap.
    func attach(to item: AVPlayerItem) {
        guard attachedItem !== item, let tap = ensureTap() else { return }
        let params = AVMutableAudioMixInputParameters(track: nil)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
        attachedItem = item
    }

    private func ensureTap() -> MTAudioProcessingTap? {
        if let tap { return tap }
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(),
            // MTAudioProcessingTapGetStorage returns whatever the init
            // callback parks in tapStorageOut — nothing forwards clientInfo
            // on its own. Skipping this is what made prepare() dereference
            // NULL on device (aptapR_PrepareTapIfNeeded / EXC_BAD_ACCESS).
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<AudioSpectrum>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                let engine = Unmanaged<AudioSpectrum>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                engine.prepare(format.pointee)
            },
            unprepare: nil,
            process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
                // Pull source audio into the provided buffers, analyse in
                // place, pass straight through — the egg is read-only.
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap, numberFrames, bufferListInOut, nil, nil, numberFramesOut)
                guard status == noErr else { return }
                let engine = Unmanaged<AudioSpectrum>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                engine.process(bufferListInOut, frames: Int(numberFrames))
                flagsOut.pointee = flags
            }
        )
        var created: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                         kMTAudioProcessingTapCreationFlag_PostEffects, &created) == noErr,
              let tapRef = created else {
            Unmanaged.passRetained(self).release()
            return nil
        }
        tap = tapRef
        return tapRef
    }

    /// Render thread: capture stream format once per tap.
    private func prepare(_ asbd: AudioStreamBasicDescription) {
        sampleRate = Float(asbd.mSampleRate)
        // Interleaving is handled in the mixdown rather than demanded here,
        // so an interleaved tap format shows bars instead of a dead grid.
        formatOK = asbd.mFormatID == kAudioFormatLinearPCM
            && asbd.mBitsPerChannel == 32
            && (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    }

    // MARK: – DSP (render thread)

    private func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        // Hidden egg: buffers still pass through untouched, we just skip the
        // maths. Nothing about the audio path changes when it is shown.
        guard isActive, formatOK, frames > 0 else { return }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        // Mix channels to mono into the ring buffer.
        var peak: Float = 0
        for f in 0..<frames {
            var sum: Float = 0
            var channels: Float = 0
            for buf in abl {
                let stride = Int(buf.mNumberChannels)
                guard stride > 0, let data = buf.mData else { continue }
                let count = Int(buf.mDataByteSize) / 4
                let samples = data.bindMemory(to: Float.self, capacity: count)
                // Non-interleaved: one channel per buffer, stride 1.
                // Interleaved: every channel in one buffer, stride == count.
                for c in 0..<stride where f * stride + c < count {
                    sum += samples[f * stride + c]
                    channels += 1
                }
            }
            guard channels > 0 else { continue }
            let mono = sum / channels
            peak = max(peak, abs(mono))
            ring[ringWrite] = mono
            ringWrite = (ringWrite + 1) % ring.count
        }
        // While AVPlayer refills its buffer it feeds the tap digital silence
        // for a second or two, even though the speaker is still playing. That
        // silence is not something the listener hears, so analysing it would
        // slam the bars to zero for no reason. Treat an all-but-zero batch as
        // no data and let snapshot() hold the last levels instead. The floor
        // is ~-100 dBFS, far below anything the display can show.
        guard peak > 1e-5 else { return }

        // Throttle analysis to ~25fps of bar updates.
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAnalysis > 0.04 else { return }
        lastAnalysis = now
        analyse()
    }

    private func analyse() {
        let n = AudioSpectrum.fftSize
        let half = n / 2
        // Newest n samples from the ring (ringWrite points at the oldest),
        // Hann-windowed into the staging buffer.
        let start = (ringWrite + ring.count - n) % ring.count
        for i in 0..<n {
            windowed[i] = ring[(start + i) % ring.count] * window[i]
        }
        fftReal.withUnsafeMutableBufferPointer { real in
            fftImag.withUnsafeMutableBufferPointer { imag in
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imag.baseAddress!)
                // The documented real-signal route: vDSP_ctoz deinterleaves the
                // n real samples into n/2 packed split-complex pairs, then
                // vDSP_fft_zrip transforms them in place. Handing zrip a real
                // array with a zeroed imaginary half instead — as this did
                // before — is zero-stuffing, and mirrors the spectrum.
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!,
                              2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(fftSetup!, &split, 1, AudioSpectrum.log2n, FFTDirection(FFT_FORWARD))
                // zrip packs DC in realp[0] and Nyquist in imagp[0]; the bands
                // start at bin 1, so neither is read.

                // 14 log-spaced bands, 50 Hz .. 14 kHz, dB-mapped to 0...1.
                // No allocations in here — this runs on the render thread.
                let binHz = sampleRate / Float(n)
                for (band, edges) in AudioSpectrum.bandEdges.enumerated() {
                    // ceil on the low edge so neighbouring bands never
                    // share a bin and double-count it.
                    let b0 = max(1, Int((edges.0 / binHz).rounded(.up)))
                    let b1 = min(half - 1, Int(edges.1 / binHz))
                    guard b1 >= b0 else { scratch[band] = 0; continue }
                    // Summed band energy, not a per-bin mean: a tone reads
                    // the same whether it lands in a narrow low band or a wide
                    // high one. 2/n folds in zrip's factor-of-2 output scaling
                    // and the transform length, so a full-scale tone sits at
                    // roughly 0 dB in any band.
                    var energy: Float = 0
                    for b in b0...b1 { energy += real[b] * real[b] + imag[b] * imag[b] }
                    let db = 20 * log10(2 * sqrt(energy) / Float(n) + 1e-6)
                    // Display window: floor .. ceiling in dBFS. The knob to
                    // turn if the bars sit too low or peg on real streams.
                    scratch[band] = min(1, max(0, (db - AudioSpectrum.floorDB)
                                                  / (AudioSpectrum.ceilingDB - AudioSpectrum.floorDB)))
                }
                lock.withLock { state in
                    for i in state.levels.indices {
                        // Fast attack, slow decay — the classic VU feel.
                        state.levels[i] = max(scratch[i], state.levels[i] * 0.82)
                    }
                    state.lastCompute = CFAbsoluteTimeGetCurrent()
                }
            }
        }
    }

    /// Log-spaced band edges (Hz) for the spectrum bars.
    static let bandEdges: [(Float, Float)] = {
        (0..<bandCount).map { i in
            let lo = 50 * pow(14000.0 / 50.0, Float(i) / Float(bandCount))
            let hi = 50 * pow(14000.0 / 50.0, Float(i + 1) / Float(bandCount))
            return (lo, hi)
        }
    }()
}

#if DEBUG
extension AudioSpectrum {
    /// The one runnable check for the analysis path: a pure tone has to light
    /// the band that contains it. Catches a broken FFT packing or band map,
    /// which is exactly how this shipped wrong the first time.
    ///
    ///     swiftc -DDEBUG -Onone ios/Sources/Visualizer.swift check.swift && ./…
    ///     // check.swift: AudioSpectrum.selfCheck()
    static func selfCheck() {
        let rate: Float = 44_100
        for tone: Float in [120, 1_000, 6_000] {
            let engine = AudioSpectrum()  // fresh, so no carry-over between tones
            engine.sampleRate = rate
            engine.formatOK = true
            for i in engine.ring.indices {
                engine.ring[i] = 0.2 * sin(2 * .pi * tone * Float(i) / rate)
            }
            engine.ringWrite = 0
            engine.analyse()
            let levels = engine.snapshot()
            let peak = levels.firstIndex(of: levels.max()!)!
            let expected = bandEdges.firstIndex { tone >= $0.0 && tone < $0.1 }!
            assert(peak == expected, "\(tone)Hz lit band \(peak), expected \(expected)")
            assert(levels[peak] > 0.6, "\(tone)Hz barely registered: \(levels[peak])")
            print("selfCheck: \(tone)Hz → band \(peak) at \(levels[peak])")
        }
        print("AudioSpectrum.selfCheck OK")
    }
}
#endif
