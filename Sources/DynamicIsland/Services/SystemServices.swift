import AppKit
import AudioToolbox
import CoreAudio
import IOKit.ps

// MARK: - Battery

final class BatteryService: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false

    var onPluggedIn: (() -> Void)?
    var onLowBattery: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var warnedLow = false

    init() {
        update(initial: true)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { service.update(initial: false) }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }
    }

    func applyDemo(level: Int, charging: Bool) {
        hasBattery = true
        self.level = level
        isCharging = charging
        isPluggedIn = charging
    }

    private func update(initial: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(1, desc[kIOPSMaxCapacityKey] as? Int ?? 100)
            let newLevel = Int((Double(current) / Double(maximum) * 100).rounded())
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            let justPlugged = !initial && plugged && !isPluggedIn
            hasBattery = true
            level = newLevel
            isCharging = charging
            isPluggedIn = plugged

            if justPlugged { onPluggedIn?() }

            if plugged || newLevel > 20 {
                warnedLow = false
            } else if !warnedLow {
                warnedLow = true
                if !initial { onLowBattery?() }
            }
            return
        }
        hasBattery = false
    }
}

// MARK: - Volume

final class VolumeService: ObservableObject {
    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false

    var onChange: (() -> Void)?
    var onDeviceChange: (() -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private lazy var valueListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.read(notify: true)
    }
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.attachToDefaultDevice()
        self?.onDeviceChange?()
    }

    init() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &defaultDeviceAddress, .main, deviceListener)
        attachToDefaultDevice()
    }

    private func attachToDefaultDevice() {
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &volumeAddress, .main, valueListener)
            AudioObjectRemovePropertyListenerBlock(device, &muteAddress, .main, valueListener)
        }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &size, &id)
        device = id
        guard device != kAudioObjectUnknown else { return }
        AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main, valueListener)
        AudioObjectAddPropertyListenerBlock(device, &muteAddress, .main, valueListener)
        read(notify: false)
    }

    private func read(notify: Bool) {
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &v) == noErr {
            volume = v
        }
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted) == noErr {
            isMuted = muted != 0
        }
        if notify { onChange?() }
    }

    func applyDemo(volume: Float) {
        self.volume = volume
        isMuted = false
    }

    func setVolume(_ value: Float) {
        var v = Float32(min(1, max(0, value)))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, size, &v)
    }
}

// MARK: - Timer

final class TimerService: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var total: TimeInterval = 0

    /// true when the timer on show was started in the macOS Clock app, not here.
    @Published private(set) var isClockTimer = false

    /// Argument: whether the finished timer belonged to the Clock app (which plays its own alarm).
    var onFinish: ((Bool) -> Void)?
    private var ticker: Timer?
    private var clockPoll: Timer?

    init() {
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.syncWithClockApp() }
        RunLoop.main.add(t, forMode: .common)
        clockPoll = t
        syncWithClockApp()
    }

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return 0
    }

    func progress(at date: Date) -> Double {
        total > 0 ? remaining(at: date) / total : 0
    }

    func start(seconds: TimeInterval) {
        isClockTimer = false
        total = seconds
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(seconds)
        startTicker()
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        ticker?.invalidate()
    }

    func resume() {
        guard let pausedRemaining else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
        startTicker()
    }

    func cancel() {
        isClockTimer = false
        ticker?.invalidate()
        endDate = nil
        pausedRemaining = nil
        total = 0
    }

    // MARK: Clock app

    func openClockApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Mirrors a timer running in the macOS Clock app. Clock keeps its timers in the
    /// `com.apple.mobiletimerd` preferences; there is no public API, so this is read-only:
    /// the island can show a Clock timer but can't pause or cancel it.
    private func syncWithClockApp() {
        // A timer started from the island takes priority.
        if isActive && !isClockTimer { return }

        let domain = "com.apple.mobiletimerd" as CFString
        CFPreferencesAppSynchronize(domain)
        let root = CFPreferencesCopyAppValue("MTTimers" as CFString, domain) as? [String: Any]
        let entries = root?["MTTimers"] as? [[String: Any]] ?? []

        var running: (end: Date, total: TimeInterval)?
        var paused: (remaining: TimeInterval, total: TimeInterval)?
        let now = Date()
        for entry in entries {
            guard let timer = entry["$MTTimer"] as? [String: Any] else { continue }
            let state = (timer["MTTimerState"] as? NSNumber)?.intValue ?? 1
            let duration = (timer["MTTimerDuration"] as? NSNumber)?.doubleValue ?? 0
            let fire = timer["MTTimerFireTime"] as? [String: Any] ?? [:]
            if let date = (fire["$MTTimerDate"] as? [String: Any])?["MTTimerDate"] as? Date {
                // A fire date means it's counting down.
                if date > now, state != 1, running == nil || date < running!.end {
                    running = (date, max(duration, date.timeIntervalSince(now)))
                }
            } else if state == 2,
                      let left = ((fire["$MTTimerTimeInterval"] as? [String: Any])?["MTTimerTimeInterval"] as? NSNumber)?.doubleValue,
                      left > 0 {
                paused = (left, max(duration, left))
            }
        }

        if let running {
            if !isClockTimer || endDate == nil || abs(endDate!.timeIntervalSince(running.end)) > 0.5 {
                isClockTimer = true
                total = running.total
                pausedRemaining = nil
                endDate = running.end
                startTicker()
            }
        } else if let paused {
            if !isClockTimer || pausedRemaining == nil || abs(pausedRemaining! - paused.remaining) > 0.5 {
                ticker?.invalidate()
                isClockTimer = true
                total = paused.total
                endDate = nil
                pausedRemaining = paused.remaining
            }
        } else if isClockTimer {
            // It was cancelled in Clock (a timer that ran out is handled by the ticker).
            if let endDate, endDate.timeIntervalSinceNow < 1 { return }
            cancel()
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let end = self.endDate, end <= Date() else { return }
            let fromClock = self.isClockTimer
            self.cancel()
            self.onFinish?(fromClock)
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }
}
