import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Listens to the Mac's audio output (a Core Audio "process tap") and turns it into five
/// frequency-band levels so the waveform can move with the actual music.
///
/// Needs the "System Audio Recording" permission (asked once). Nothing is recorded or kept:
/// each buffer is reduced to five numbers and thrown away. Without permission the tap
/// delivers silence and the waveform falls back to its generic animation.
final class AudioTap {
    static let shared = AudioTap()
    static let bandCount = 5

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "dynamicisland.audiotap", qos: .userInteractive)
    private(set) var isRunning = false

    // FFT state (only touched on ioQueue)
    private static let fftSize = 1024
    private let log2n = vDSP_Length(10)
    private lazy var fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    private var window = [Float](repeating: 0, count: AudioTap.fftSize)
    private var ring = [Float](repeating: 0, count: AudioTap.fftSize)
    private var ringFill = 0
    private var sampleRate: Double = 48_000
    private var smoothed = [Float](repeating: 0, count: AudioTap.bandCount)
    private var peak: Float = 0.02

    // Shared with the UI
    private let lock = NSLock()
    private var bands = [Float](repeating: 0, count: AudioTap.bandCount)
    private var lastSignal = Date.distantPast

    private init() {
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
    }

    /// Current band levels (0...1), or nil when there's no live audio to show.
    func levels() -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning, Date().timeIntervalSince(lastSignal) < 0.5 else { return nil }
        return bands
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Dynamic Island Waveform"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { return }
        tapID = tap

        // Sample rate of what we'll receive.
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                       mScope: kAudioObjectPropertyScopeGlobal,
                                                       mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 {
            sampleRate = format.mSampleRate
            guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { stop(); return }
        }

        guard let outputUID = Self.defaultOutputUID() else { stop(); return }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dynamic Island Waveform",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device) == noErr else { stop(); return }
        aggregateID = device

        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, ioQueue) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }
        guard status == noErr, let proc else { stop(); return }
        procID = proc
        guard AudioDeviceStart(device, proc) == noErr else { stop(); return }
        isRunning = true
    }

    func stop() {
        isRunning = false
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Output device changed (e.g. AirPods connected): rebuild the tap around the new device.
    func restart() {
        guard isRunning else { return }
        stop()
        start()
    }

    private static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return nil }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    // MARK: - Analysis

    private func process(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = max(1, Int(first.mNumberChannels))
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        guard frames > 0 else { return }
        let samples = data.bindMemory(to: Float.self, capacity: frames * channels)

        // Append (first channel is enough for a visualizer) and analyse each full block.
        var i = 0
        while i < frames {
            ring[ringFill] = samples[i * channels]
            ringFill += 1
            i += 1
            if ringFill == Self.fftSize {
                analyse()
                ringFill = 0
            }
        }
    }

    private func analyse() {
        guard let fftSetup else { return }
        let n = Self.fftSize
        let half = n / 2
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(ring, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // Five bands from bass to treble.
        let edges: [Double] = [40, 160, 400, 1_000, 2_500, 8_000]
        let binWidth = sampleRate / Double(n)
        var raw = [Float](repeating: 0, count: Self.bandCount)
        for b in 0..<Self.bandCount {
            let lo = max(1, Int(edges[b] / binWidth))
            let hi = min(half - 1, max(lo + 1, Int(edges[b + 1] / binWidth)))
            var sum: Float = 0
            vDSP_meanv(Array(magnitudes[lo..<hi]), 1, &sum, vDSP_Length(hi - lo))
            // Higher bands carry less energy; tilt so every bar gets to move.
            raw[b] = sum * Float(1 + b) * 0.9
        }

        // Auto-gain: follow the loudest recent band so quiet and loud tracks both fill the bars.
        let loudest = raw.max() ?? 0
        peak = max(loudest, peak * 0.995, 0.02)
        var out = [Float](repeating: 0, count: Self.bandCount)
        for b in 0..<Self.bandCount {
            let target = min(1, sqrt(raw[b] / peak))
            // Jump up fast, fall back gently.
            smoothed[b] = target > smoothed[b] ? target : smoothed[b] * 0.72 + target * 0.28
            out[b] = smoothed[b]
        }

        lock.lock()
        bands = out
        if loudest > 0.0005 { lastSignal = Date() }
        lock.unlock()
    }
}
