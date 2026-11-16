import AppKit
import SwiftUI

/// The island outline: concave "flares" where it meets the top edge of the screen
/// (like the hardware notch) and round corners at the bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Free-floating (no notch): round all four corners like the iPhone's island.
    var floating = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        if floating {
            let r = max(0, min(bottomRadius, rect.height / 2, rect.width / 2))
            return RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect)
        }
        let t = max(0, min(topRadius, rect.width / 4, rect.height / 2))
        let b = max(0, min(bottomRadius, rect.height, (rect.width - 2 * t) / 2))
        // Body: Apple's "continuous" (squircle) corners at the bottom, square at the top.
        let body = CGRect(x: rect.minX + t, y: rect.minY, width: rect.width - 2 * t, height: rect.height)
        var p = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: b, bottomTrailing: b, topTrailing: 0),
            style: .continuous
        ).path(in: body)
        // Concave flares where the island meets the top edge of the screen.
        if t > 0 {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addArc(tangent1End: CGPoint(x: rect.minX + t, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX + t, y: rect.minY + t), radius: t)
            p.addLine(to: CGPoint(x: rect.minX + t, y: rect.minY))
            p.closeSubpath()
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addArc(tangent1End: CGPoint(x: rect.maxX - t, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX - t, y: rect.minY + t), radius: t)
            p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY))
            p.closeSubpath()
        }
        return p
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// Content fades/unblurs in slightly after the shape starts morphing — the iOS feel.
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0))
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.86, anchor: .top))
                .animation(.spring(response: 0.42, dampingFraction: 0.82).delay(0.06)),
            removal: .modifier(active: BlurModifier(radius: 8), identity: BlurModifier(radius: 0))
                .combined(with: .opacity)
                .animation(.easeOut(duration: 0.14))
        )
    }
}

/// Album art. Fills whatever frame the caller gives it, so its size can animate.
struct ArtworkView: View {
    let image: NSImage?
    let radius: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    LinearGradient(colors: [Color(white: 0.30), Color(white: 0.16)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: geo.size.width * 0.42, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// iOS-style battery glyph with a proportional fill.
struct BatteryIcon: View {
    let level: Int
    let charging: Bool
    var tint: Color? = nil

    private var fillColor: Color {
        if let tint { return tint }
        if charging { return .green }
        return level <= 20 ? .red : .white
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 24, height: 12)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fillColor)
                    .frame(width: max(2, 20 * CGFloat(level) / 100), height: 8)
                    .padding(.leading, 2)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 0.5)
                        .frame(width: 24)
                }
            }
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.28))
                .frame(width: 1.5, height: 4)
        }
    }
}

struct PressableButtonStyle: ButtonStyle {
    var hoverCircle: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, hoverCircle: hoverCircle)
    }

    private struct PressableBody: View {
        let configuration: Configuration
        let hoverCircle: Bool
        @StateObject private var hover = HoverState()
        private var hovering: Bool { hover.isOn }

        var body: some View {
            configuration.label
                .background {
                    if hoverCircle {
                        Circle()
                            .fill(Color.white.opacity(hovering ? 0.12 : 0))
                            .padding(-2)
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.84 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hover.isOn = $0 }
        }
    }
}

/// Tiny view-local state holder (the Command Line Tools SDK lacks the `@State` macro plugin).
final class HoverState: ObservableObject {
    @Published var isOn = false
}

enum TimeFormat {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Countdowns round up so "0:00" only shows when the timer is truly done.
    static func countdown(_ seconds: Double) -> String {
        clock(seconds.rounded(.up))
    }
}
