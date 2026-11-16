import SwiftUI

struct ExpandedView: View {
    @ObservedObject var vm: IslandViewModel

    var body: some View {
        let g = vm.geometry
        VStack(spacing: 0) {
            // Header row shares the strip beside the camera.
            HStack(spacing: 0) {
                TabSwitcher(selection: $vm.tab)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if g.hasNotch {
                    Color.clear.frame(width: g.notchSize.width)
                } else {
                    ClockLabel()
                        .frame(width: g.notchSize.width)
                }
                BatteryHeader(battery: vm.battery)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: g.notchSize.height)
            .padding(.horizontal, 22)

            Group {
                switch vm.tab {
                case .media: MediaPlayerView(np: vm.nowPlaying)
                case .timer: TimerPanel(timer: vm.timer)
                }
            }
            .transition(.opacity)
            .padding(.horizontal, 26)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, vm.topRadius)
        .frame(width: vm.expandedSize.width, height: vm.expandedSize.height, alignment: .top)
    }
}

private struct TabSwitcher: View {
    @Binding var selection: IslandTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(IslandTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == tab ? Color.white : Color.white.opacity(0.4))
                        .frame(width: 30, height: 22)
                        .background {
                            Capsule().fill(Color.white.opacity(selection == tab ? 0.14 : 0))
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle(hoverCircle: false))
            }
        }
    }
}

private struct BatteryHeader: View {
    @ObservedObject var battery: BatteryService

    var body: some View {
        if battery.hasBattery {
            HStack(spacing: 6) {
                Text("\(battery.level)%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                BatteryIcon(level: battery.level, charging: battery.isCharging)
            }
        }
    }
}

private struct ClockLabel: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            Text(ctx.date, format: .dateTime.hour().minute())
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Media

struct MediaPlayerView: View {
    @ObservedObject var np: NowPlayingService

    var body: some View {
        if let track = np.track {
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    ArtworkView(image: np.artwork, size: 58, radius: 13)
                        .shadow(color: np.accent.opacity(0.25), radius: 10)
                        .overlay(alignment: .bottomTrailing) {
                            // Which app is playing (Safari, Chrome, Music, ...), like iOS.
                            if let icon = np.sourceIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                    .shadow(color: .black.opacity(0.5), radius: 2)
                                    .offset(x: 7, y: 7)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(track.artist.isEmpty ? track.album : track.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    WaveformView(isPlaying: np.isPlaying, color: np.accent, barCount: 5, maxHeight: 20)
                }

                ProgressRow(np: np, duration: track.duration)

                HStack(spacing: 40) {
                    controlButton("backward.fill", size: 19) { np.previous() }
                    controlButton(np.isPlaying ? "pause.fill" : "play.fill", size: 26) { np.playPause() }
                    controlButton("forward.fill", size: 19) { np.next() }
                }
            }
        } else {
            NothingPlayingView(np: np)
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private struct ProgressRow: View {
    @ObservedObject var np: NowPlayingService
    let duration: Double
    @StateObject private var state = ScrubState()
    private var dragProgress: Double? { state.dragProgress }
    private var hovering: Bool { state.hovering }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let current = dragProgress.map { $0 * duration } ?? np.position(at: ctx.date)
            let progress = duration > 0 ? current / duration : 0
            HStack(spacing: 10) {
                Text(TimeFormat.clock(current))
                    .frame(width: 40, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(Color.white.opacity(hovering || dragProgress != nil ? 1 : 0.85))
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, progress))))
                    }
                    .frame(height: hovering || dragProgress != nil ? 8 : 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                state.dragProgress = min(1, max(0, value.location.x / geo.size.width))
                            }
                            .onEnded { _ in
                                if let p = dragProgress, duration > 0 { np.seek(to: p * duration) }
                                state.dragProgress = nil
                            }
                    )
                }
                .frame(height: 14)
                .onHover { state.hovering = $0 }
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
                Text(duration > 0 ? "-" + TimeFormat.clock(max(0, duration - current)) : "LIVE")
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }
}

final class ScrubState: ObservableObject {
    @Published var dragProgress: Double?
    @Published var hovering = false
}

private struct NothingPlayingView: View {
    @ObservedObject var np: NowPlayingService

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: np.automationDenied ? "lock.fill" : "music.note")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 2)
            Text(np.automationDenied ? "Music Access Needed" : "Nothing Playing")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(np.automationDenied
                 ? "Allow Dynamic Island under Privacy › Automation."
                 : "Play music, a YouTube video, or anything else.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                if np.automationDenied {
                    pill("Open Settings") { np.openAutomationSettings() }
                } else {
                    ForEach(PlayerApp.allCases.filter { $0.appURL != nil }, id: \.self) { app in
                        pill("Open \(app.appName)") { np.open(app) }
                    }
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle(hoverCircle: false))
    }
}

// MARK: - Timer

struct TimerPanel: View {
    @ObservedObject var timer: TimerService

    private let presets: [Int] = [1, 3, 5, 10, 15, 20, 30, 60]

    var body: some View {
        if timer.isActive {
            active
        } else {
            picker
        }
    }

    private var active: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.22), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: timer.progress(at: ctx.date))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: timer.progress(at: ctx.date))
                    Image(systemName: "timer")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 2) {
                    Text(TimeFormat.countdown(timer.remaining(at: ctx.date)))
                        .font(.system(size: 40, weight: .light).monospacedDigit())
                        .foregroundStyle(.orange)
                        .contentTransition(.numericText(countsDown: true))
                    Text(timer.isRunning ? endsAtLabel(ctx.date) : "Paused")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 0)

                circleButton(timer.isRunning ? "pause.fill" : "play.fill", fg: .orange,
                             bg: Color.orange.opacity(0.22)) {
                    timer.isRunning ? timer.pause() : timer.resume()
                }
                circleButton("xmark", fg: .white, bg: Color.white.opacity(0.16)) {
                    timer.cancel()
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func endsAtLabel(_ now: Date) -> String {
        let end = now.addingTimeInterval(timer.remaining(at: now))
        return "Ends at " + end.formatted(date: .omitted, time: .shortened)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(presets, id: \.self) { minutes in
                    Button {
                        timer.start(seconds: TimeInterval(minutes * 60))
                    } label: {
                        Text(minutes == 60 ? "1 hr" : "\(minutes) min")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.12)))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PressableButtonStyle(hoverCircle: false))
                }
            }
        }
    }

    private func circleButton(_ symbol: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(fg)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 46, height: 46)
                .background(Circle().fill(bg))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(hoverCircle: false))
    }
}
