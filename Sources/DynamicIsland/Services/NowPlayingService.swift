import AppKit
import SwiftUI

enum PlayerApp: String, CaseIterable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    var appName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
    }

    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue)
    }
}

struct TrackInfo: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
}

private struct PlayerSnapshot {
    var app: PlayerApp
    var isPlaying: Bool
    var track: TrackInfo?
    var position: Double
    var artworkURL: String?
}

/// Reads and controls Apple Music / Spotify through Apple Events.
///
/// macOS 15.4+ blocks the private MediaRemote framework for third-party apps, so we use
/// AppleScript (needs one-time Automation permission) plus the players' distributed
/// notifications for instant updates.
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: TrackInfo?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    @Published private(set) var source: PlayerApp?
    @Published private(set) var automationDenied = false

    private var basePosition: Double = 0
    private var baseDate = Date()
    private var artworkTrackID: String?
    private var pollTimer: Timer?
    private var pollCount = 0

    private let queue = DispatchQueue(label: "dynamicisland.applescript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:] // only touched on `queue`

    init() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(playerChanged(_:)),
                        name: Notification.Name("com.apple.Music.playerInfo"), object: nil)
        dnc.addObserver(self, selector: #selector(playerChanged(_:)),
                        name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)

        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(self, selector: #selector(appsChanged(_:)),
                        name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        wnc.addObserver(self, selector: #selector(appsChanged(_:)),
                        name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // Light polling keeps the scrubber honest after seeks made inside the player.
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pollCount += 1
            if self.isPlaying || self.pollCount % 5 == 0 { self.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        refresh()
    }

    // MARK: - Position

    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        let p = isPlaying ? basePosition + date.timeIntervalSince(baseDate) : basePosition
        return track.duration > 0 ? min(max(0, p), track.duration) : max(0, p)
    }

    private func rebase(_ position: Double) {
        basePosition = position
        baseDate = Date()
    }

    // MARK: - Refresh

    @objc private func playerChanged(_ note: Notification) {
        // The notification carries the authoritative state, so use it immediately
        // instead of waiting for an AppleScript round-trip.
        if let state = note.userInfo?["Player State"] as? String {
            let app: PlayerApp = note.name.rawValue.hasPrefix("com.spotify") ? .spotify : .music
            if source == nil || source == app {
                let playing = state == "Playing"
                let resolved = resolvedPlaying(playing)
                if resolved != isPlaying, track != nil {
                    rebase(position(at: Date()))
                    isPlaying = resolved
                }
            }
        }
        refresh()
    }

    // MARK: - Command expectations
    //
    // After a click we know what the state *should* be. Players briefly report stale or
    // in-between states (e.g. "Paused" while skipping), which made the button flicker.
    // For a short window we trust the user's intent over what the player reports.

    private var commandGeneration = 0
    private var expectedPlaying: Bool?
    private var expectationDeadline = Date.distantPast

    private func expect(playing: Bool, for seconds: Double = 1.5) {
        commandGeneration += 1
        expectedPlaying = playing
        expectationDeadline = Date().addingTimeInterval(seconds)
        // Reconcile with the real player once things settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.15) { [weak self] in
            self?.refresh()
        }
    }

    private func resolvedPlaying(_ reported: Bool) -> Bool {
        if let expected = expectedPlaying {
            if Date() < expectationDeadline { return expected }
            expectedPlaying = nil
        }
        return reported
    }

    @objc private func appsChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier, PlayerApp(rawValue: id) != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    func refresh() {
        let apps = PlayerApp.allCases.filter { $0.isRunning }
        guard !apps.isEmpty else {
            apply(nil, denied: false)
            return
        }
        let preferred = source
        let generation = commandGeneration
        queue.async { [weak self] in
            guard let self else { return }
            var snapshots: [PlayerSnapshot] = []
            var denied = false
            for app in apps {
                switch self.query(app) {
                case .success(let snap): snapshots.append(snap)
                case .failure(let error): if error.code == -1743 { denied = true }
                }
            }
            let pick = snapshots.first { $0.isPlaying && $0.track != nil }
                ?? snapshots.first { $0.app == preferred && $0.track != nil }
                ?? snapshots.first { $0.track != nil }
            DispatchQueue.main.async {
                // A command was sent after this query started: its result is stale.
                guard generation == self.commandGeneration else { return }
                self.apply(pick, denied: denied)
            }
        }
    }

    private func apply(_ snap: PlayerSnapshot?, denied: Bool) {
        if automationDenied != denied { automationDenied = denied }

        guard let snap, let newTrack = snap.track else {
            if track != nil { track = nil }
            if isPlaying { isPlaying = false }
            if artwork != nil { artwork = nil }
            source = nil
            artworkTrackID = nil
            return
        }

        let playing = resolvedPlaying(snap.isPlaying)
        let trackChanged = newTrack != track
        let stateChanged = playing != isPlaying
        let drift = abs(position(at: Date()) - snap.position)

        if trackChanged { track = newTrack }
        if stateChanged { isPlaying = playing }
        if source != snap.app { source = snap.app }
        if trackChanged || stateChanged || drift > 1.5 { rebase(snap.position) }

        if artworkTrackID != newTrack.id {
            artworkTrackID = newTrack.id
            loadArtwork(for: snap)
        }
    }

    // MARK: - AppleScript

    private func script(_ source: String) -> NSAppleScript? {
        if let s = compiled[source] { return s }
        guard let s = NSAppleScript(source: source) else { return nil }
        compiled[source] = s
        return s
    }

    private func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        guard let s = script(source) else { return .failure(ScriptError(code: -1)) }
        var error: NSDictionary?
        let result = s.executeAndReturnError(&error)
        if let error {
            return .failure(ScriptError(code: error[NSAppleScript.errorNumber] as? Int ?? -1))
        }
        return .success(result)
    }

    private struct ScriptError: Error { let code: Int }

    private static func stateScript(_ app: PlayerApp) -> String {
        let durationExpr = app == .spotify ? "(duration of t) / 1000" : "duration of t"
        let idExpr = app == .spotify ? "id of t" : "persistent ID of t"
        let artExpr = app == .spotify ? "artwork url of t" : "\"\""
        return """
        tell application "\(app.appName)"
            set ps to (player state as string)
            if ps is "stopped" then return {ps}
            try
                set t to current track
            on error
                return {ps}
            end try
            set tn to ""
            set ta to ""
            set tal to ""
            set td to 0
            set tid to ""
            set tart to ""
            set pp to 0
            try
                set tn to name of t
            end try
            try
                set ta to artist of t
            end try
            try
                set tal to album of t
            end try
            try
                set td to \(durationExpr)
            end try
            try
                set tid to \(idExpr)
            end try
            try
                set tart to \(artExpr)
            end try
            try
                set pp to player position
            end try
            return {ps, tn, ta, tal, td, pp, tid, tart}
        end tell
        """
    }

    private func query(_ app: PlayerApp) -> Result<PlayerSnapshot, ScriptError> {
        switch run(Self.stateScript(app)) {
        case .failure(let e):
            return .failure(e)
        case .success(let d):
            let state = (d.atIndex(1)?.stringValue ?? "stopped").lowercased()
            // Some apps hand back raw four-char codes: kPSP = playing, kPSp = paused.
            let playing = state == "playing" || d.atIndex(1)?.stringValue == "kPSP"
            guard d.numberOfItems >= 8, let title = d.atIndex(2)?.stringValue, !title.isEmpty else {
                return .success(PlayerSnapshot(app: app, isPlaying: false, track: nil, position: 0, artworkURL: nil))
            }
            let track = TrackInfo(
                id: d.atIndex(7)?.stringValue ?? title,
                title: title,
                artist: d.atIndex(3)?.stringValue ?? "",
                album: d.atIndex(4)?.stringValue ?? "",
                duration: d.atIndex(5)?.doubleValue ?? 0
            )
            let art = d.atIndex(8)?.stringValue
            return .success(PlayerSnapshot(app: app, isPlaying: playing, track: track,
                                           position: d.atIndex(6)?.doubleValue ?? 0,
                                           artworkURL: (art?.isEmpty ?? true) ? nil : art))
        }
    }

    // MARK: - Artwork

    private func loadArtwork(for snap: PlayerSnapshot) {
        let trackID = snap.track?.id
        switch snap.app {
        case .music:
            queue.async { [weak self] in
                guard let self else { return }
                var image: NSImage?
                let src = """
                tell application "Music"
                    try
                        return data of artwork 1 of current track
                    end try
                end tell
                """
                if case .success(let d) = self.run(src) {
                    image = NSImage(data: d.data)
                }
                DispatchQueue.main.async { self.setArtwork(image, for: trackID) }
            }
        case .spotify:
            guard let s = snap.artworkURL, let url = URL(string: s) else {
                setArtwork(nil, for: trackID)
                return
            }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                let image = data.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async { self?.setArtwork(image, for: trackID) }
            }.resume()
        }
    }

    private func setArtwork(_ image: NSImage?, for trackID: String?) {
        guard trackID == artworkTrackID else { return }
        artwork = image
        accent = image.flatMap(Self.accentColor(from:)) ?? .white
    }

    /// Average colour of the artwork, brightened so it reads well on black (like iOS).
    private static func accentColor(from image: NSImage) -> Color? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let base = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                           blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.12 { return Color(white: 0.92) }
        return Color(hue: Double(h), saturation: Double(min(1, s * 1.25)), brightness: Double(max(0.8, b)))
    }

    // MARK: - Controls

    func playPause() {
        let target = !isPlaying
        rebase(position(at: Date()))
        isPlaying = target
        expect(playing: target)
        // Explicit play/pause (not the "playpause" toggle) so a stale UI state can
        // never toggle the player the wrong way.
        send(target ? "play" : "pause")
    }

    func next() { skip("next track") }

    func previous() { skip("previous track") }

    /// Skipping can leave Music paused (notably for streamed Apple Music tracks), so if
    /// we were playing, explicitly resume after the skip.
    private func skip(_ command: String) {
        let keepPlaying = isPlaying
        rebase(0)
        expect(playing: keepPlaying, for: 2)
        guard let app = source, app.isRunning else { return }
        var script = "tell application \"\(app.appName)\" to \(command)"
        if keepPlaying {
            script += """

            delay 0.15
            tell application "\(app.appName)"
                if player state is not playing then play
            end tell
            """
        }
        queue.async { [weak self] in
            _ = self?.run(script)
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func seek(to seconds: Double) {
        rebase(seconds)
        objectWillChange.send()
        send("set player position to \(seconds)")
    }

    func open(_ app: PlayerApp) {
        guard let url = app.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Used by `--snapshot` to render README images without a real player.
    func applyDemo(track: TrackInfo?, playing: Bool, artwork: NSImage?, position: Double) {
        self.track = track
        isPlaying = playing
        self.artwork = artwork
        accent = artwork.flatMap(Self.accentColor(from:)) ?? .white
        source = track == nil ? nil : .music
        rebase(position)
    }

    private func send(_ command: String) {
        guard let app = source, app.isRunning else { return }
        queue.async { [weak self] in
            _ = self?.run("tell application \"\(app.appName)\" to \(command)")
        }
    }
}
