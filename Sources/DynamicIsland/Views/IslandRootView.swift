import SwiftUI

struct IslandRootView: View {
    @ObservedObject var vm: IslandViewModel

    private static let morph = Animation.spring(response: 0.44, dampingFraction: 0.8)

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        let size = vm.size
        let shape = NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius)

        return ZStack(alignment: .top) {
            if vm.isExpanded {
                ExpandedView(vm: vm)
                    .transition(.islandContent)
            } else if let kind = vm.compactKind {
                CompactView(kind: kind, vm: vm)
                    .id(kind)
                    .transition(.islandContent)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { vm.handleTap() }
        .shadow(color: .black.opacity(vm.isExpanded ? 0.55 : 0), radius: 18, y: 8)
        .overlay(alignment: .trailing) {
            if vm.showsTimerBubble {
                TimerBubble(timer: vm.timer, size: vm.geometry.notchSize.height)
                    .offset(x: vm.geometry.notchSize.height + 6)
                    .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
            }
        }
        .opacity(vm.isVisible ? 1 : 0)
        .animation(Self.morph, value: vm.layoutKey)
        .environment(\.colorScheme, .dark)
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
