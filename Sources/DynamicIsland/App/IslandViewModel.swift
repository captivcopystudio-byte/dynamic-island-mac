import AppKit
import Combine
import SwiftUI

enum IslandTab: String, CaseIterable, Hashable {
    case media, timer

    var symbol: String {
        switch self {
        case .media: return "music.note"
        case .timer: return "timer"
        }
    }
}

/// Short-lived alerts that take over the compact island for a moment.
enum Transient: Hashable {
    case volume, charging, lowBattery, timerDone
}

/// What the collapsed island is currently showing.
enum CompactKind: Hashable {
    case music, timer, volume, charging, lowBattery, timerDone
}

struct LayoutKey: Hashable {
    var expanded: Bool
    var compact: CompactKind?
    var bubble: Bool
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
            timer.objectWillChange.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.objectWillChange.send() }
        .store(in: &cancellables)

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

    // MARK: - Derived state

    var compactKind: CompactKind? {
        if let transient {
            switch transient {
            case .volume: return .volume
            case .charging: return .charging
            case .lowBattery: return .lowBattery
            case .timerDone: return .timerDone
            }
        }
        if nowPlaying.isPlaying && nowPlaying.track != nil { return .music }
        if timer.isActive { return .timer }
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
        LayoutKey(expanded: isExpanded, compact: compactKind, bubble: showsTimerBubble, tab: tab, visible: isVisible)
    }

    var topRadius: CGFloat { isExpanded ? 14 : 6 }
    var bottomRadius: CGFloat { isExpanded ? 34 : (compactKind == nil ? 10 : 13) }

    var expandedSize: CGSize {
        CGSize(width: 500, height: geometry.notchSize.height + 160)
    }

    func earWidth(_ kind: CompactKind) -> CGFloat {
        switch kind {
        case .music: return 42
        case .timer: return 60
        case .timerDone: return 64
        case .volume: return 82
        case .charging: return 88
        case .lowBattery: return 98
        }
    }

    func compactSize(_ kind: CompactKind) -> CGSize {
        let n = geometry.notchSize
        return CGSize(width: n.width + 2 * earWidth(kind) + 2 * 6, height: n.height)
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
