import AppKit
import Combine
import SwiftUI

enum IslandTab: String, CaseIterable, Hashable {
    case media, timer, calendar

    var symbol: String {
        switch self {
        case .media: return "music.note"
        case .timer: return "timer"
        case .calendar: return "calendar"
        }
    }
}

/// Short-lived alerts that take over the compact island for a moment.
enum Transient: Hashable {
    case volume, charging, lowBattery, timerDone
    case headphonesOn, headphonesOff, focusOn, focusOff, capsOn, capsOff, eventSoon

    var kind: CompactKind {
        switch self {
        case .volume: return .volume
        case .charging: return .charging
        case .lowBattery: return .lowBattery
        case .timerDone: return .timerDone
        case .headphonesOn: return .headphonesOn
        case .headphonesOff: return .headphonesOff
        case .focusOn: return .focusOn
        case .focusOff: return .focusOff
        case .capsOn: return .capsOn
        case .capsOff: return .capsOff
        case .eventSoon: return .calendar
        }
    }
}

/// What the collapsed island is currently showing.
enum CompactKind: Hashable {
    case music, timer, volume, charging, lowBattery, timerDone
    case headphonesOn, headphonesOff, focusOn, focusOff, capsOn, capsOff
    case calendar // an event is about to start
    case privacy  // camera or microphone in use
}

struct LayoutKey: Hashable {
    var expanded: Bool
    var compact: CompactKind?
    var bubble: Bool
    var music: Bool
    var tab: IslandTab
    var visible: Bool
}

final class IslandViewModel: ObservableObject {
    @Published var geometry = NotchGeometry.fallback
    @Published private(set) var isExpanded = false
    @Published private(set) var transient: Transient?
    @Published var tab: IslandTab = .media

    let nowPlaying = NowPlayingService()
    let battery = BatteryService()
    let volume = VolumeService()
    let timer = TimerService()
    let calendar = CalendarService()
    let headphones = HeadphoneService()
    let privacy = PrivacyService()
    private let systemState = SystemStateService()

    private var isHovering = false
    private var hoverWork: DispatchWorkItem?
    private var transientWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Re-render whenever any service changes.
        Publishers.MergeMany(
            nowPlaying.objectWillChange.eraseToAnyPublisher(),
            battery.objectWillChange.eraseToAnyPublisher(),
            volume.objectWillChange.eraseToAnyPublisher(),
            timer.objectWillChange.eraseToAnyPublisher(),
            calendar.objectWillChange.eraseToAnyPublisher(),
            headphones.objectWillChange.eraseToAnyPublisher(),
            privacy.objectWillChange.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.objectWillChange.send() }
        .store(in: &cancellables)

        // Listen to the audio output only while something is actually playing.
        nowPlaying.$isPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateAudioTap() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: Prefs.didChange)
            .sink { [weak self] _ in self?.updateAudioTap() }
            .store(in: &cancellables)
        volume.onDeviceChange = { [weak self] in
            AudioTap.shared.restart()
            self?.headphones.outputDeviceChanged()
        }
        headphones.onConnect = { [weak self] in
            guard Prefs.bool(Prefs.deviceAlerts) else { return }
            self?.showTransient(.headphonesOn, for: 4)
        }
        headphones.onDisconnect = { [weak self] in
            guard Prefs.bool(Prefs.deviceAlerts) else { return }
            self?.showTransient(.headphonesOff, for: 2.5)
        }
        calendar.onEventSoon = { [weak self] _ in
            guard Prefs.bool(Prefs.calendarAlerts) else { return }
            self?.showTransient(.eventSoon, for: 6)
        }
        systemState.onFocusChange = { [weak self] on in
            guard Prefs.bool(Prefs.systemAlerts) else { return }
            self?.showTransient(on ? .focusOn : .focusOff, for: 2.5)
        }
        systemState.onCapsLockChange = { [weak self] on in
            guard Prefs.bool(Prefs.systemAlerts) else { return }
            self?.showTransient(on ? .capsOn : .capsOff, for: 1.6)
        }

        volume.onChange = { [weak self] in
            guard Prefs.bool(Prefs.volumeHUD) else { return }
            self?.showTransient(.volume, for: 1.6)
        }
        battery.onPluggedIn = { [weak self] in
            guard Prefs.bool(Prefs.batteryAlerts) else { return }
            self?.showTransient(.charging, for: 3.5)
        }
        battery.onLowBattery = { [weak self] in
            guard Prefs.bool(Prefs.batteryAlerts) else { return }
            self?.showTransient(.lowBattery, for: 4)
        }
        timer.onFinish = { [weak self] in
            NSSound(named: "Glass")?.play()
            self?.showTransient(.timerDone, for: 6)
        }
    }

    private func updateAudioTap() {
        if nowPlaying.isPlaying && Prefs.bool(Prefs.liveWaveform) {
            AudioTap.shared.start()
        } else {
            AudioTap.shared.stop()
        }
    }

    // MARK: - Derived state

    var compactKind: CompactKind? {
        if let transient { return transient.kind }
        if nowPlaying.isPlaying && nowPlaying.track != nil { return .music }
        if timer.isActive { return .timer }
        if Prefs.bool(Prefs.calendarAlerts), calendar.imminentEvent() != nil { return .calendar }
        if Prefs.bool(Prefs.privacyIndicator), privacy.cameraInUse || privacy.micInUse { return .privacy }
        return nil
    }

    /// Detached circle to the right of the island (like iPhone's split island).
    var showsTimerBubble: Bool {
        !isExpanded && compactKind == .music && timer.isActive
    }

    var isVisible: Bool {
        geometry.hasNotch || isExpanded || compactKind != nil
    }

    var layoutKey: LayoutKey {
        LayoutKey(expanded: isExpanded, compact: compactKind, bubble: showsTimerBubble, music: showsMusicElements, tab: tab, visible: isVisible)
    }

    private var pill: Bool { !geometry.hasNotch }

    /// Concave flares only make sense when attached to the top edge.
    var topRadius: CGFloat { pill ? 0 : (isExpanded ? 12 : 6) }
    var bottomRadius: CGFloat {
        if isExpanded { return 38 }
        if pill { return geometry.notchSize.height / 2 } // capsule
        return compactKind == nil ? 10 : 14
    }

    /// Where expanded content starts. A MacBook notch is wide (185 pt of a 400 pt island), so
    /// content goes fully below it; the floating pill has no camera to avoid.
    var contentTop: CGFloat { pill ? 14 : geometry.notchSize.height + 6 }

    /// Apple's expanded island is ~371-408 pt wide and up to 160 pt tall (HIG, Live Activities).
    var expandedSize: CGSize {
        CGSize(width: 400, height: contentTop + 134)
    }

    /// Album art + waveform stay on screen and glide between compact and expanded.
    var showsMusicElements: Bool {
        guard nowPlaying.track != nil else { return false }
        return isExpanded ? tab == .media : compactKind == .music
    }

    func earWidth(_ kind: CompactKind) -> CGFloat {
        switch kind {
        case .music: return 42
        case .timer: return 60
        case .timerDone: return 64
        case .volume: return 82
        case .charging: return 88
        case .lowBattery: return 98
        case .headphonesOn, .headphonesOff: return 128
        case .focusOn, .focusOff: return 78
        case .capsOn, .capsOff: return 100
        case .calendar: return 70
        case .privacy: return 38
        }
    }

    func compactSize(_ kind: CompactKind) -> CGSize {
        let n = geometry.notchSize
        return CGSize(width: n.width + 2 * earWidth(kind) + 2 * topRadius, height: n.height)
    }

    var size: CGSize {
        if isExpanded { return expandedSize }
        if let kind = compactKind { return compactSize(kind) }
        return geometry.notchSize
    }

    // MARK: - Interaction

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        hoverWork?.cancel()

        let work: DispatchWorkItem
        if hovering {
            guard Prefs.bool(Prefs.expandOnHover) else { return }
            work = DispatchWorkItem { [weak self] in
                guard let self, self.isHovering else { return }
                self.expand()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        } else {
            work = DispatchWorkItem { [weak self] in
                guard let self, !self.isHovering else { return }
                self.collapse()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        hoverWork = work
    }

    func handleTap() {
        if transient == .timerDone {
            transient = nil
            return
        }
        if !isExpanded { expand() }
    }

    func expand() {
        guard !isExpanded else { return }
        if transient != .timerDone { transient = nil }
        if nowPlaying.track == nil && timer.isActive {
            tab = .timer
        } else if nowPlaying.isPlaying {
            tab = .media
        }
        isExpanded = true
        if Prefs.bool(Prefs.haptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
    }

    func applyDemo(expanded: Bool, transient: Transient?, tab: IslandTab) {
        isExpanded = expanded
        self.transient = transient
        self.tab = tab
    }

    private func showTransient(_ t: Transient, for seconds: Double) {
        // Don't cover the expanded island with small HUDs.
        if isExpanded && t != .timerDone { return }
        if t == .timerDone { isExpanded = false }
        transient = t
        transientWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.transient == t { self?.transient = nil }
        }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
