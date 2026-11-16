import SwiftUI

struct IslandRootView: View {
    @ObservedObject var vm: IslandViewModel

    // Opening has a little bounce; closing settles quickly without overshoot (as on iPhone).
    private static let open = Animation.spring(response: 0.46, dampingFraction: 0.72)
    private static let close = Animation.spring(response: 0.38, dampingFraction: 0.9)

    var body: some View {
        VStack(spacing: 0) {
            island
                .padding(.top, vm.geometry.topInset)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        let size = vm.size
        let shape = NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius,
                               floating: !vm.geometry.hasNotch)

        return ZStack(alignment: .top) {
            if vm.isExpanded {
                ExpandedView(vm: vm)
                    .transition(.islandContent)
            } else if let kind = vm.compactKind {
                CompactView(kind: kind, vm: vm)
                    .id(kind)
                    .transition(.islandContent)
            }
            musicElements
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { vm.handleTap() }
        .shadow(color: .black.opacity(vm.isExpanded ? 0.45 : 0), radius: 20, y: 10)
        .overlay(alignment: .trailing) {
            if vm.showsTimerBubble {
                TimerBubble(timer: vm.timer, size: vm.geometry.notchSize.height)
                    .offset(x: vm.geometry.notchSize.height + 6)
                    .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
            }
        }
        .opacity(vm.isVisible ? 1 : 0)
        .animation(vm.isExpanded ? Self.open : Self.close, value: vm.layoutKey)
        .environment(\.colorScheme, .dark)
    }

    /// The album art and waveform are never swapped out between compact and expanded:
    /// the same two views slide and grow, so the island feels like one continuous object.
    @ViewBuilder private var musicElements: some View {
        if vm.showsMusicElements {
            let m = MusicLayout(expanded: vm.isExpanded, notchHeight: vm.geometry.notchSize.height,
                                flare: vm.topRadius, contentTop: vm.contentTop)
            ArtworkView(image: vm.nowPlaying.artwork, radius: m.artRadius)
                .frame(width: m.artSize, height: m.artSize)
                .shadow(color: vm.nowPlaying.accent.opacity(vm.isExpanded ? 0.3 : 0), radius: 12)
                .padding(.leading, m.artLeading)
                .padding(.top, m.artTop)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .topLeading)))

            WaveformView(isPlaying: vm.nowPlaying.isPlaying, color: vm.nowPlaying.accent)
                .scaleEffect(m.waveScale, anchor: .trailing)
                .padding(.trailing, m.waveTrailing)
                .padding(.top, m.waveTop)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .topTrailing)))
        }
    }
}

/// Where the shared music elements sit in each state. `ExpandedView` reserves matching gaps.
struct MusicLayout {
    static let expandedArt: CGFloat = 58
    static let expandedMargin: CGFloat = 18 // from the island body edge (inside the flare)
    static let waveHeight: CGFloat = 14

    let artSize: CGFloat
    let artRadius: CGFloat
    let artLeading: CGFloat
    let artTop: CGFloat
    let waveScale: CGFloat
    let waveTrailing: CGFloat
    let waveTop: CGFloat

    init(expanded: Bool, notchHeight: CGFloat, flare: CGFloat, contentTop: CGFloat) {
        if expanded {
            artSize = Self.expandedArt
            artRadius = 14
            artLeading = flare + Self.expandedMargin
            artTop = contentTop
            waveScale = 1.5
            waveTrailing = flare + Self.expandedMargin + 2
            waveTop = contentTop + (Self.expandedArt - Self.waveHeight) / 2
        } else {
            artSize = 22
            artRadius = 6.5
            artLeading = flare + 10
            artTop = (notchHeight - 22) / 2
            waveScale = 1
            waveTrailing = flare + 10
            waveTop = (notchHeight - Self.waveHeight) / 2
        }
    }
}

/// Little detached circle that holds a second live activity (timer) while music plays.
struct TimerBubble: View {
    @ObservedObject var timer: TimerService
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            ZStack {
                Circle().fill(Color.black)
                Circle()
                    .stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
                    .padding(5)
                Circle()
                    .trim(from: 0, to: timer.progress(at: ctx.date))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
                Image(systemName: "timer")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: size, height: size)
        }
    }
}
