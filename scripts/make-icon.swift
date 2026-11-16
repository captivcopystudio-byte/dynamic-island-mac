// Renders the app icon (1024x1024 PNG). Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Squircle background with a soft gradient.
let inset: CGFloat = 100
let bgRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.30, blue: 0.95, alpha: 1),
                    NSColor(srgbRed: 0.85, green: 0.30, blue: 0.62, alpha: 1)])!
    .draw(in: bg, angle: -60)

// The island.
let pill = NSRect(x: 230, y: 560, width: 564, height: 150)
NSColor.black.setFill()
NSBezierPath(roundedRect: pill, xRadius: 75, yRadius: 75).fill()

// Album art square on the left.
NSGradient(colors: [NSColor.systemOrange, NSColor.systemPink])!
    .draw(in: NSBezierPath(roundedRect: NSRect(x: 275, y: 595, width: 80, height: 80), xRadius: 20, yRadius: 20), angle: -45)

// Waveform bars on the right.
NSColor.white.setFill()
let heights: [CGFloat] = [44, 84, 60, 96]
for (i, h) in heights.enumerated() {
    let x = 640 + CGFloat(i) * 30
    NSBezierPath(roundedRect: NSRect(x: x, y: 635 - h / 2, width: 16, height: h), xRadius: 8, yRadius: 8).fill()
}

// Expanded "player" hint below.
NSColor.white.withAlphaComponent(0.85).setFill()
NSBezierPath(roundedRect: NSRect(x: 300, y: 400, width: 424, height: 22), xRadius: 11, yRadius: 11).fill()
NSColor.white.withAlphaComponent(0.35).setFill()
NSBezierPath(roundedRect: NSRect(x: 300, y: 340, width: 300, height: 22), xRadius: 11, yRadius: 11).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
