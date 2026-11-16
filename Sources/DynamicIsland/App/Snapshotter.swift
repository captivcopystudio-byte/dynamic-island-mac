import AppKit
import SwiftUI

/// `DynamicIsland --snapshot <dir>` renders every island state to PNGs (used for the README).
@MainActor
enum Snapshotter {
    static func run(outputDir: String) {
        let dir = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let vm = IslandViewModel()
        vm.geometry = NotchGeometry(notchSize: CGSize(width: 185, height: 33.5), hasNotch: true)
        let track = TrackInfo(id: "demo", title: "Midnight Drive", artist: "The Neon Coast",
                              album: "Afterglow", duration: 214)
        let art = demoArtwork()

        func shot(_ name: String, _ setup: () -> Void) {
            vm.timer.cancel()
            vm.nowPlaying.applyDemo(track: nil, playing: false, artwork: nil, position: 0)
            vm.battery.applyDemo(level: 82, charging: false)
            vm.applyDemo(expanded: false, transient: nil, tab: .media)
            setup()
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.20, green: 0.24, blue: 0.42),
                                        Color(red: 0.48, green: 0.32, blue: 0.52)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(Color.black.opacity(0.18)).frame(height: 33.5) // menu bar
                IslandRootView(vm: vm)
            }
            .frame(width: 600, height: 250)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("failed: \(name)"); return
            }
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }

        shot("01-idle") {}
        shot("02-compact-music") {
            vm.nowPlaying.applyDemo(track: track, playing: true, artwork: art, position: 62)
        }
        shot("03-expanded-music") {
            vm.nowPlaying.applyDemo(track: track, playing: true, artwork: art, position: 62)
            vm.applyDemo(expanded: true, transient: nil, tab: .media)
        }
        shot("04-compact-timer") {
            vm.timer.start(seconds: 300)
        }
        shot("05-music-plus-timer") {
            vm.nowPlaying.applyDemo(track: track, playing: true, artwork: art, position: 62)
            vm.timer.start(seconds: 300)
        }
        shot("06-expanded-timer") {
            vm.timer.start(seconds: 1500)
            vm.applyDemo(expanded: true, transient: nil, tab: .timer)
        }
        shot("07-expanded-timer-picker") {
            vm.applyDemo(expanded: true, transient: nil, tab: .timer)
        }
        shot("08-volume") {
            vm.volume.applyDemo(volume: 0.62)
            vm.applyDemo(expanded: false, transient: .volume, tab: .media)
        }
        shot("09-charging") {
            vm.battery.applyDemo(level: 82, charging: true)
            vm.applyDemo(expanded: false, transient: .charging, tab: .media)
        }
        shot("10-nothing-playing") {
            vm.applyDemo(expanded: true, transient: nil, tab: .media)
        }
    }

    private static func demoArtwork() -> NSImage {
        let size = NSSize(width: 300, height: 300)
        let img = NSImage(size: size)
        img.lockFocus()
        NSGradient(colors: [NSColor.systemPink, NSColor.systemOrange, NSColor.systemPurple])!
            .draw(in: NSRect(origin: .zero, size: size), angle: -50)
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: 150, y: 40, width: 120, height: 120)).fill()
        img.unlockFocus()
        return img
    }
}
