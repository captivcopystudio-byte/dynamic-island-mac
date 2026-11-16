import AppKit
import ServiceManagement

@main
enum Main {
    static func main() {
        signal(SIGPIPE, SIG_IGN) // a dead media helper must never take the app down
        let app = NSApplication.shared
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "screenshots"
            Prefs.registerDefaults()
            MainActor.assumeIsolated { Snapshotter.run(outputDir: dir) }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon, lives in the notch + menu bar
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        controller = IslandController()
        setupStatusItem()
    }

    // MARK: - Menu bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Island")
            image?.isTemplate = true
            button.image = image
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let title = NSMenuItem(title: "Dynamic Island", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(toggleItem("Floating Pill Style (No Notch)", key: Prefs.pillStyleKey))
        menu.addItem(toggleItem("Expand on Hover", key: Prefs.expandOnHover))
        menu.addItem(toggleItem("Haptic Feedback", key: Prefs.haptics))
        menu.addItem(toggleItem("Show Volume HUD", key: Prefs.volumeHUD))
        menu.addItem(toggleItem("Show Battery Alerts", key: Prefs.batteryAlerts))
        menu.addItem(toggleItem("Show Calendar Events", key: Prefs.calendarAlerts))
        menu.addItem(toggleItem("Show Headphone Alerts", key: Prefs.deviceAlerts))
        menu.addItem(toggleItem("Show Camera / Mic Indicator", key: Prefs.privacyIndicator))
        menu.addItem(toggleItem("Show Focus & Caps Lock Alerts", key: Prefs.systemAlerts))
        menu.addItem(.separator())
        menu.addItem(toggleItem("Pause Other Audio When Something New Plays", key: Prefs.pauseOthers))

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dynamic Island", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func toggleItem(_ title: String, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(togglePref(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = key
        item.state = Prefs.bool(key) ? .on : .off
        return item
    }

    @objc private func togglePref(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        let newValue = !Prefs.bool(key)
        UserDefaults.standard.set(newValue, forKey: key)
        sender.state = newValue ? .on : .off
        NotificationCenter.default.post(name: Prefs.didChange, object: nil)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login failed: \(error)")
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

enum Prefs {
    static let expandOnHover = "expandOnHover"
    static let haptics = "haptics"
    static let volumeHUD = "showVolumeHUD"
    static let batteryAlerts = "showBatteryAlerts"
    static let calendarAlerts = "showCalendarEvents"
    static let deviceAlerts = "showHeadphoneAlerts"
    static let privacyIndicator = "showPrivacyIndicator"
    static let systemAlerts = "showSystemAlerts"
    static let pauseOthers = "pauseOtherAudio"

    static let didChange = Notification.Name("DynamicIslandPrefsDidChange")
    static let pillStyleKey = "floatingPillStyle"

    /// Floating pill instead of hugging the notch. The "No Notch" download turns this on by default.
    static var pillStyle: Bool { bool(pillStyleKey) }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            expandOnHover: true,
            haptics: true,
            volumeHUD: true,
            batteryAlerts: true,
            calendarAlerts: true,
            deviceAlerts: true,
            privacyIndicator: true,
            systemAlerts: true,
            pillStyleKey: (Bundle.main.object(forInfoDictionaryKey: "DIDefaultStyle") as? String) == "pill",
            pauseOthers: true,
        ])
    }

    static func bool(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}
