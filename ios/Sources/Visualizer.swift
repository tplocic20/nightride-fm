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
        var lastCompute = Date.distantPast
    }

    /// Whether the egg is on screen. Set from the UI; gates attaching.
    var isActive = false

    // Attach/detach happens on the main thread only. Raw ref: create returns
    // a +1 we own and release on detach; the mix holds its own retain.
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

    init() {
        // Hann window over the 1024-sample analysis frame.
        for i in 0..<1024 {
            window[i] = 0.5 * (1 - cos(2 * .pi * Float(i) / 1023))
        }
        fftSetup = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2)).map { $0 }
    }

    /// Latest smoothed band levels, 0...1. Called every UI frame; decays the
    /// bars toward zero when the stream is paused and callbacks stop firing.
    func snapshot() -> [Float] {
        lock.withLock { state in
            if Date().timeIntervalSince(state.lastCompute) > 0.12 {
                for i in state.levels.indices { state.levels[i] *= 0.88 }
                state.lastCompute = Date()
            }
            return state.levels
        }
    }

    // MARK: – Attach / detach (main thread)

    /// Attach the tap to `item` if the egg is active. Called after each play()
    /// because play() replaces the AVPlayerItem.
    func attachIfNeeded(to item: AVPlayerItem) {
        guard isActive, attachedItem !== item else { return }
        attach(to: item)
    }

    func attach(to item: AVPlayerItem) {
        detach()
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
            Unmanaged.passRetained(self).release()  // balance the passRetained
            return
        }
        tap = tapRef
        // The track-parameters route: audioTapProcessor per track.
        let params = AVMutableAudioMixInputParameters(track: nil)
        params.audioTapProcessor = tapRef
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
        attachedItem = item
    }

    func detach() {
        attachedItem?.audioMix = nil
        if let tapRef = tap { Unmanaged.passUnretained(tapRef).release() }  // create's +1
        attachedItem = nil
        tap = nil
        formatOK = false
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
                imag.assign(repeating: 0)
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imag.baseAddress!)
                vDSP_fft_zrip(fftSetup!, &split, 1, vDSP_Length(10), FFTDirection(FFT_FORWARD))

                // 14 log-spaced bands, 50 Hz .. 14 kHz, dB-mapped to 0...1.
                let binHz = sampleRate / Float(n)
                let newLevels = AudioSpectrum.bandEdges.map { lo, hi -> Float in
                    let b0 = max(1, Int(lo / binHz))
                    let b1 = min(n / 2 - 1, Int(hi / binHz))
                    guard b1 > b0 else { return 0 }
                    var energy: Float = 0
                    for b in b0...b1 { energy += sqrt(real[b] * real[b] + imag[b] * imag[b]) }
                    let db = 20 * log10(energy / Float((b1 - b0) * n) + 1e-6)
                    return min(1, max(0, (db + 66) / 60))
                }
                lock.withLock { state in
                    for i in state.levels.indices {
                        // Fast attack, slow decay — the classic VU feel.
                        state.levels[i] = max(newLevels[i], state.levels[i] * 0.82)
                    }
                    state.lastCompute = Date()
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
