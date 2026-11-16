import AppKit
import SwiftUI

/// Borderless, transparent panel that sits on top of the menu bar, centred on the notch.
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Allow the window to overlap the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Lets buttons respond to the very first click even though the panel never becomes key.
final class IslandHostingView: NSHostingView<IslandRootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class IslandController {
    static let panelSize = NSSize(width: 680, height: 320)

    private let panel = IslandPanel()
    private let viewModel = IslandViewModel()
    private var screen: NSScreen?
    private var monitors: [Any] = []

    init() {
        let host = IslandHostingView(rootView: IslandRootView(vm: viewModel))
        host.sizingOptions = []
        panel.contentView = host

        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }

        // Mouse-moved monitors don't need Accessibility permission.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.updateHover()
        }) { monitors.append(global) }

        if let globalClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            // A click anywhere outside the island collapses it.
            guard let self, !self.isMouseInsideIsland() else { return }
            self.viewModel.collapse()
        }) { monitors.append(globalClick) }

        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            self?.updateHover()
            return event
        }) { monitors.append(local) }
    }

    /// The built-in (notched) display wins; otherwise the main display.
    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func reposition() {
        guard let screen = preferredScreen() else { return }
        self.screen = screen
        viewModel.geometry = NotchGeometry(screen: screen)
        let f = screen.frame
        let size = Self.panelSize
        panel.setFrame(NSRect(x: f.midX - size.width / 2,
                              y: f.maxY - size.height,
                              width: size.width,
                              height: size.height),
                       display: true)
    }

    private func islandRect() -> NSRect? {
        guard let screen else { return nil }
        let f = screen.frame
        let size = viewModel.size
        var rect = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                          width: size.width, height: size.height + 2) // +2: include the very top pixel row
        rect = viewModel.isExpanded ? rect.insetBy(dx: -4, dy: -4) : rect.insetBy(dx: -10, dy: -6)
        return rect
    }

    private func isMouseInsideIsland() -> Bool {
        guard let rect = islandRect() else { return false }
        return rect.contains(NSEvent.mouseLocation)
    }

    private func updateHover() {
        let inside = isMouseInsideIsland()
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        viewModel.setHovering(inside)
    }
}

struct NotchGeometry: Equatable {
    var notchSize: CGSize
    var hasNotch: Bool

    static let fallback = NotchGeometry(notchSize: CGSize(width: 185, height: 32), hasNotch: false)

    init(notchSize: CGSize, hasNotch: Bool) {
        self.notchSize = notchSize
        self.hasNotch = hasNotch
    }

    init(screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: top)
            hasNotch = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: 185, height: menuBar > 0 ? menuBar : 32)
            hasNotch = false
        }
    }
}
