import Foundation

/// Talks to the system-wide "Now Playing" service (the same one Control Center uses), which
/// covers every app: browsers (YouTube, Netflix, ...), Music, Spotify, podcasts.
///
/// macOS 15.4+ only answers Apple-signed processes, so the work happens in a helper:
/// `/usr/bin/perl` loading `MediaRemoteAdapter.dylib` (see `bridge/`). The helper prints one
/// JSON line per change and accepts commands on stdin.
final class MediaRemoteBridge {
    struct Update {
        var isEmpty = false
        var title = ""
        var artist = ""
        var album = ""
        var id = ""
        var bundle = ""
        var parent = ""
        var duration = 0.0
        var elapsed = 0.0
        var timestamp = 0.0
        var rate = 0.0
        var playing = false
        var artworkHash: UInt64 = 0
        var artwork: Data?
    }

    var onUpdate: ((Update) -> Void)?
    var onExit: (() -> Void)?

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var buffer = Data() // only touched on the pipe's read queue
    private var consecutiveFailures = 0

    private var resources: (script: URL, dylib: URL)? {
        guard let dir = Bundle.main.resourceURL else { return nil }
        let script = dir.appendingPathComponent("mr-bridge.pl")
        let dylib = dir.appendingPathComponent("MediaRemoteAdapter.dylib")
        let fm = FileManager.default
        guard fm.fileExists(atPath: script.path), fm.fileExists(atPath: dylib.path),
              fm.isExecutableFile(atPath: "/usr/bin/perl") else { return nil }
        return (script, dylib)
    }

    var isAvailable: Bool { resources != nil }

    func start() {
        guard process == nil, let res = resources else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [res.script.path, res.dylib.path]
        let output = Pipe()
        let input = Pipe()
        p.standardOutput = output
        p.standardInput = input
        p.standardError = FileHandle.nullDevice

        buffer.removeAll()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.consume(data)
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.handleExit() }
        }
        do {
            try p.run()
        } catch {
            return
        }
        process = p
        stdinHandle = input.fileHandleForWriting
    }

    /// Commands: play, pause, toggle, next, previous, seek <seconds>, refresh
    func send(_ command: String) {
        guard let stdinHandle, process?.isRunning == true else { return }
        try? stdinHandle.write(contentsOf: Data((command + "\n").utf8))
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  object["error"] == nil else { continue }

            var update = Update()
            if object["empty"] != nil {
                update.isEmpty = true
            } else {
                update.title = object["title"] as? String ?? ""
                update.artist = object["artist"] as? String ?? ""
                update.album = object["album"] as? String ?? ""
                update.id = object["id"] as? String ?? ""
                update.bundle = object["bundle"] as? String ?? ""
                update.parent = object["parent"] as? String ?? ""
                update.duration = (object["duration"] as? NSNumber)?.doubleValue ?? 0
                update.elapsed = (object["elapsed"] as? NSNumber)?.doubleValue ?? 0
                update.timestamp = (object["timestamp"] as? NSNumber)?.doubleValue ?? 0
                update.rate = (object["rate"] as? NSNumber)?.doubleValue ?? 0
                update.playing = (object["playing"] as? NSNumber)?.boolValue ?? false
                update.artworkHash = (object["artworkHash"] as? NSNumber)?.uint64Value ?? 0
                if let base64 = object["artwork"] as? String {
                    update.artwork = Data(base64Encoded: base64)
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.consecutiveFailures = 0
                self?.onUpdate?(update)
            }
        }
    }

    private func handleExit() {
        process = nil
        stdinHandle = nil
        onExit?()
        // Restart with backoff; give up if the helper never manages to report anything.
        consecutiveFailures += 1
        guard consecutiveFailures <= 5 else { return }
        let delay = min(30, pow(2, Double(consecutiveFailures)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.start()
        }
    }
}
