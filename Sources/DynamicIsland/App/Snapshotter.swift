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
                              album: "Afterglow", duration: 214, isExplicit: true)
        let art = demoArtwork()

        func shot(_ name: String, _ setup: () -> Void) {
            vm.timer.cancel()
            vm.nowPlaying.applyDemo(track: nil, playing: false, artwork: nil, position: 0)
            vm.battery.applyDemo(level: 82, charging: false)
            vm.privacy.applyDemo(camera: false, mic: false)
            vm.calendar.applyDemo(events: [])
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
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            // Redraw into plain 8-bit sRGB (app icons can make the renderer emit 16-bit HDR).
            guard let cg = renderer.cgImage,
                  let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                print("failed: \(name)"); return
            }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            guard let flat = ctx.makeImage(),
                  let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else {
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
        let standup = UpcomingEvent(id: "a", title: "Design Review", start: Date().addingTimeInterval(290),
                                    end: Date().addingTimeInterval(2090), color: .systemBlue)
        let lunch = UpcomingEvent(id: "b", title: "Lunch with Sam", start: Date().addingTimeInterval(5400),
                                  end: Date().addingTimeInterval(9000), color: .systemOrange)
        shot("11-headphones") {
            vm.headphones.applyDemo(name: "AirPods Pro", battery: 87)
            vm.applyDemo(expanded: false, transient: .headphonesOn, tab: .media)
        }
        shot("12-calendar-soon") {
            vm.calendar.applyDemo(events: [standup, lunch])
        }
        shot("13-expanded-calendar") {
            vm.calendar.applyDemo(events: [standup, lunch])
            vm.applyDemo(expanded: true, transient: nil, tab: .calendar)
        }
        shot("14-camera-in-use") {
            vm.privacy.applyDemo(camera: true, mic: false)
        }
        shot("15-focus") {
            vm.applyDemo(expanded: false, transient: .focusOn, tab: .media)
        }
        shot("16-caps-lock") {
            vm.applyDemo(expanded: false, transient: .capsOn, tab: .media)
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
