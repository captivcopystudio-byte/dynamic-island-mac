import AppKit
import CoreAudio
import CoreMediaIO
import EventKit
import Intents

// MARK: - Calendar

struct UpcomingEvent: Equatable, Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var color: NSColor
}

/// Upcoming calendar events (next 24 hours) via EventKit.
final class CalendarService: ObservableObject {
    @Published private(set) var events: [UpcomingEvent] = []
    @Published private(set) var accessDenied = false
    /// Not asked yet. The app never asks on its own: only when the user clicks "Allow".
    @Published private(set) var needsPermission = false
    /// Bumped every 15 s so countdown labels and "starting soon" state stay fresh.
    @Published private(set) var tick = 0

    /// Called once when an event is about 10 minutes away, and once when it starts.
    var onEventSoon: ((UpcomingEvent) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var announcedSoon = Set<String>()
    private var announcedNow = Set<String>()

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged),
                                               name: .EKEventStoreChanged, object: store)
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.heartbeat() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: reload()
        case .notDetermined: needsPermission = true
        default: accessDenied = true
        }
    }

    func applyDemo(events: [UpcomingEvent]) {
        timer?.invalidate()
        self.events = events
    }

    func requestAccess() {
        // Permission prompts need the app bundle's usage descriptions (absent in --snapshot runs).
        guard Bundle.main.bundleIdentifier != nil else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            reload()
        case .notDetermined:
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.needsPermission = false
                    self?.accessDenied = !granted
                    if granted { self?.reload() }
                }
            }
        default:
            accessDenied = true
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The event to feature in the notch: starts within 10 minutes, or began under 2 minutes ago.
    func imminentEvent(at date: Date = Date()) -> UpcomingEvent? {
        events.first { $0.start.timeIntervalSince(date) <= 600 && date.timeIntervalSince($0.start) < 120 }
    }

    @objc private func storeChanged() {
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }

    private func heartbeat() {
        tick += 1
        if tick % 8 == 0 { reload() } // every 2 minutes, in case a change notification was missed
        let now = Date()
        for event in events {
            let until = event.start.timeIntervalSince(now)
            if until <= 600, until > 30, !announcedSoon.contains(event.id) {
                announcedSoon.insert(event.id)
                onEventSoon?(event)
            } else if until <= 0, until > -60, !announcedNow.contains(event.id) {
                announcedNow.insert(event.id)
                onEventSoon?(event)
            }
        }
    }

    private func reload() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-120),
                                                 end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let found = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(6)
            .map { UpcomingEvent(id: ($0.eventIdentifier ?? $0.title ?? "") + "\($0.startDate.timeIntervalSince1970)",
                                 title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate,
                                 color: $0.calendar?.color ?? .systemRed) }
        let list = Array(found)
        if list != events { events = list }
    }
}

// MARK: - Headphones (Bluetooth audio output)

/// Notices when Bluetooth headphones (AirPods etc.) become, or stop being, the audio output.
/// Uses the audio device list, so it needs no Bluetooth permission.
final class HeadphoneService: ObservableObject {
    @Published private(set) var name = ""
    @Published private(set) var battery: Int?

    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?

    private var currentID = AudioObjectID(kAudioObjectUnknown)
    private var currentIsBluetooth = false

    var symbol: String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    init() {
        check(initial: true)
    }

    func applyDemo(name: String, battery: Int?) {
        self.name = name
        self.battery = battery
    }

    /// Call when the default output device changes.
    func outputDeviceChanged() {
        check(initial: false)
    }

    private func check(initial: Bool) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != currentID else { return }

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        let isBluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE

        var deviceName = ""
        var cfName: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &cfName) == noErr, let cfName {
            deviceName = cfName.takeRetainedValue() as String
        }

        let wasBluetooth = currentIsBluetooth
        currentID = device
        currentIsBluetooth = isBluetooth
        guard !initial else {
            if isBluetooth { name = deviceName }
            return
        }

        if isBluetooth {
            name = deviceName
            battery = nil
            onConnect?()
            // Battery levels show up a moment after connecting.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { [weak self] in
                let level = Self.batteryLevel(for: deviceName)
                DispatchQueue.main.async {
                    guard let self, self.name == deviceName else { return }
                    self.battery = level
                }
            }
        } else if wasBluetooth {
            onDisconnect?()
        }
    }

    /// Reads headphone battery from the system's Bluetooth report (lowest of left/right buds).
    private static func batteryLevel(for deviceName: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                guard let info = entry[deviceName] as? [String: Any] else { continue }
                let keys = ["device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevelMain"]
                let levels = keys.compactMap { key -> Int? in
                    guard let text = info[key] as? String else { return nil }
                    return Int(text.replacingOccurrences(of: "%", with: ""))
                }
                return levels.min()
            }
        }
        return nil
    }
}

// MARK: - Camera / microphone in use

/// Whether any app is currently using a camera or the microphone.
final class PrivacyService: ObservableObject {
    @Published private(set) var cameraInUse = false
    @Published private(set) var micInUse = false

    private var timer: Timer?

    init() {
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    private func poll() {
        let camera = Self.isAnyCameraRunning()
        let mic = Self.isMicRunning()
        if camera != cameraInUse { cameraInUse = camera }
        if mic != micInUse { micInUse = mic }
    }

    func applyDemo(camera: Bool, mic: Bool) {
        timer?.invalidate()
        cameraInUse = camera
        micInUse = mic
    }

    private static func isAnyCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0,
              size > 0 else { return false }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0
        else { return false }

        address.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        for device in devices {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(device, &address, 0, nil, runningSize, &runningSize, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }

    private static func isMicRunning() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}

// MARK: - Focus and Caps Lock

/// Reports Focus (Do Not Disturb) and Caps Lock changes.
final class SystemStateService {
    var onFocusChange: ((Bool) -> Void)?
    var onCapsLockChange: ((Bool) -> Void)?

    private var timer: Timer?
    private var capsLock = NSEvent.modifierFlags.contains(.capsLock)
    private var focused: Bool?
    private var count = 0

    init() {
        focused = Self.readFocus()
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let caps = NSEvent.modifierFlags.contains(.capsLock)
        if caps != capsLock {
            capsLock = caps
            onCapsLockChange?(caps)
        }
        count += 1
        guard count % 7 == 0 else { return } // Focus about every 2 seconds
        let now = Self.readFocus()
        if let now, let before = focused, now != before { onFocusChange?(now) }
        if now != nil { focused = now }
    }

    /// nil when macOS won't tell us.
    private static func readFocus() -> Bool? {
        // The Focus database is readable only with Full Disk Access; it's the most reliable source.
        let path = NSHomeDirectory() + "/Library/DoNotDisturb/DB/Assertions.json"
        if let data = FileManager.default.contents(atPath: path),
           let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let entries = root["data"] as? [[String: Any]] {
            return entries.contains { ($0["storeAssertionRecords"] as? [Any])?.isEmpty == false }
        }
        if Bundle.main.bundleIdentifier != nil, INFocusStatusCenter.default.authorizationStatus == .authorized {
            return INFocusStatusCenter.default.focusStatus.isFocused
        }
        return nil
    }
}
