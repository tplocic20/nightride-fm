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

    /// Whether the egg is on screen. Set from the UI; gates attaching.
    var isActive = false

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
    private var ring = [Float](repeating: 0, count: 4096)  // mono accumulation
    private var ringWrite = 0
    private var window = [Float](repeating: 1, count: 1024)
    private var fftReal = [Float](repeating: 0, count: 1024)
    private var fftImag = [Float](repeating: 0, count: 1024)
    private var fftSetup: FFTSetup?
    private var scratch = [Float](repeating: 0, count: AudioSpectrum.bandCount)

    init() {
        fftSetup = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2))
        vDSP_hann_window(&window, vDSP_Length(window.count), Int32(vDSP_HANN_NORM))
    }

    /// Latest smoothed band levels, 0...1. Called every UI frame; decays the
    /// bars toward zero when the stream is paused and callbacks stop firing.
    func snapshot() -> [Float] {
        let now = CFAbsoluteTimeGetCurrent()
        return lock.withLock { state in
            if now - state.lastCompute > 0.12 {
                for i in state.levels.indices { state.levels[i] *= 0.88 }
                state.lastCompute = now
            }
            return state.levels
        }
    }

    // MARK: – Attach / detach (main thread)

    /// Attach the (persistent) tap to `item` if the egg is active and not
    /// already on it. Called from the flip gesture and after each play(),
    /// because play() replaces the AVPlayerItem.
    func attach(to item: AVPlayerItem) {
        guard isActive, attachedItem !== item, let tap = ensureTap() else { return }
        let params = AVMutableAudioMixInputParameters(track: nil)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
        attachedItem = item
    }

    func detach() {
        // Only drops the mix — the tap itself outlives every attach cycle.
        attachedItem?.audioMix = nil
        attachedItem = nil
    }

    private func ensureTap() -> MTAudioProcessingTap? {
        if let tap { return tap }
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(),
            init: nil,
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
        formatOK = asbd.mFormatID == kAudioFormatLinearPCM
            && asbd.mBitsPerChannel == 32
            && (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            && (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
    }

    // MARK: – DSP (render thread)

    private func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard formatOK, frames > 0 else { return }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        // Mix channels to mono into the ring buffer.
        for f in 0..<frames {
            var sum: Float = 0
            var channels: Float = 0
            for buf in abl where buf.mNumberChannels > 0 {
                guard f < Int(buf.mDataByteSize) / 4, let data = buf.mData else { continue }
                sum += data.bindMemory(to: Float.self, capacity: Int(buf.mDataByteSize) / 4)[f]
                channels += 1
            }
            guard channels > 0 else { continue }
            ring[ringWrite] = sum / channels
            ringWrite = (ringWrite + 1) % ring.count
        }
        // Throttle analysis to ~25fps of bar updates.
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAnalysis > 0.04 else { return }
        lastAnalysis = now
        analyse()
    }

    private func analyse() {
        let n = 1024
        fftReal.withUnsafeMutableBufferPointer { real in
            fftImag.withUnsafeMutableBufferPointer { imag in
                // Last n mono samples from the ring, windowed.
                for i in 0..<n {
                    real[i] = ring[(ringWrite + i) % ring.count] * window[i]
                }
                imag.update(repeating: 0)
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imag.baseAddress!)
                vDSP_fft_zrip(fftSetup!, &split, 1, vDSP_Length(10), FFTDirection(FFT_FORWARD))

                // 14 log-spaced bands, 50 Hz .. 14 kHz, dB-mapped to 0...1.
                // No allocations in here — this runs on the render thread.
                let binHz = sampleRate / Float(n)
                for (band, edges) in AudioSpectrum.bandEdges.enumerated() {
                    let b0 = max(1, Int(edges.0 / binHz))
                    let b1 = min(n / 2 - 1, Int(edges.1 / binHz))
                    guard b1 > b0 else { scratch[band] = 0; continue }
                    var energy: Float = 0
                    for b in b0...b1 { energy += sqrt(real[b] * real[b] + imag[b] * imag[b]) }
                    let db = 20 * log10(energy / Float((b1 - b0) * n) + 1e-6)
                    scratch[band] = min(1, max(0, (db + 66) / 60))
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
