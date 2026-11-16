import SwiftUI

/// The opened island. Sized like Apple's (about 400 x 150 pt) with snug, even margins.
struct ExpandedView: View {
    @ObservedObject var vm: IslandViewModel

    private var margin: CGFloat { vm.topRadius + MusicLayout.expandedMargin }

    var body: some View {
        Group {
            if vm.tab == .media, let track = vm.nowPlaying.track {
                MediaPlayerView(np: vm.nowPlaying, track: track, showTimer: { vm.tab = .timer },
                                timerActive: vm.timer.isActive)
                    .padding(.top, vm.contentTop)
            } else {
                VStack(spacing: 0) {
                    header
                        .padding(.top, vm.contentTop - 4)
                    Group {
                        switch vm.tab {
                        case .media: NothingPlayingView(np: vm.nowPlaying)
                        case .timer: TimerPanel(timer: vm.timer)
                        case .calendar: CalendarPanel(calendar: vm.calendar)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 14)
                }
            }
        }
        .padding(.horizontal, margin)
        .frame(width: vm.expandedSize.width, height: vm.expandedSize.height, alignment: .top)
    }

    /// Tabs on the left, battery on the right.
    private var header: some View {
        HStack(spacing: 0) {
            TabSwitcher(selection: $vm.tab)
            Spacer(minLength: 0)
            BatteryHeader(battery: vm.battery)
        }
        .frame(height: 24)
    }
}

private struct TabSwitcher: View {
    @Binding var selection: IslandTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(IslandTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(selection == tab ? Color.white : Color.white.opacity(0.4))
                        .frame(width: 28, height: 21)
                        .background {
                            Capsule().fill(Color.white.opacity(selection == tab ? 0.16 : 0))
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
            HStack(spacing: 5) {
                Text("\(battery.level)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                BatteryIcon(level: battery.level, charging: battery.isCharging)
            }
        }
    }
}

// MARK: - Media

/// Art top-left with title and artist beside it, then the scrubber, then transport controls.
/// The art itself is drawn by `IslandRootView` so it can glide in from the compact island;
/// this view just leaves room for it.
struct MediaPlayerView: View {
    @ObservedObject var np: NowPlayingService
    let track: TrackInfo
    let showTimer: () -> Void
    let timerActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                Color.clear.frame(width: MusicLayout.expandedArt, height: MusicLayout.expandedArt)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if track.isExplicit {
                            // Apple Music's explicit badge
                            Image(systemName: "e.square.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    Text(track.artist.isEmpty ? track.album : track.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .padding(.bottom, 2)
                Spacer(minLength: 0)
            }

            ProgressRow(np: np, duration: track.duration)
                .padding(.top, 9)

            ZStack {
                HStack(spacing: 34) {
                    transport("backward.fill", size: 19) { np.previous() }
                    transport(np.isPlaying ? "pause.fill" : "play.fill", size: 27) { np.playPause() }
                    transport("forward.fill", size: 19) { np.next() }
                }
                HStack {
                    Button(action: showTimer) {
                        Image(systemName: "timer")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(timerActive ? Color.orange : Color.white.opacity(0.55))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    Spacer()
                    if let icon = np.sourceIcon {
                        // Which app is playing (Safari, Chrome, Music, ...); click to open it.
                        Button { np.openSourceApp() } label: {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle(hoverCircle: false))
                    }
                }
            }
            .padding(.top, 3)
        }
    }

    private func transport(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 42, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

private struct ProgressRow: View {
    @ObservedObject var np: NowPlayingService
    let duration: Double
    @StateObject private var state = ScrubState()

    private var active: Bool { state.hovering || state.dragProgress != nil }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let current = state.dragProgress.map { $0 * duration } ?? np.position(at: ctx.date)
            let progress = duration > 0 ? current / duration : 0
            HStack(spacing: 8) {
                Text(TimeFormat.clock(current))
                    .frame(width: 36, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule().fill(Color.white.opacity(active ? 1 : 0.9))
                            .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, progress)))))
                    }
                    .frame(height: active ? 9 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                state.dragProgress = min(1, max(0, value.location.x / geo.size.width))
                            }
                            .onEnded { _ in
                                if let p = state.dragProgress, duration > 0 { np.seek(to: p * duration) }
                                state.dragProgress = nil
                            }
                    )
                }
                .frame(height: 14)
                .onHover { state.hovering = $0 }
                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: active)
                Text(duration > 0 ? "-" + TimeFormat.clock(max(0, duration - current)) : "LIVE")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
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
        HStack(spacing: 14) {
            Image(systemName: np.automationDenied ? "lock.fill" : "music.note")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 58, height: 58)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(np.automationDenied ? "Music Access Needed" : "Nothing Playing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(np.automationDenied
                     ? "Allow under Privacy › Automation."
                     : "Play music or a video.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if np.automationDenied {
                pill("Settings") { np.openAutomationSettings() }
            } else if PlayerApp.music.appURL != nil {
                pill("Open Music") { np.open(.music) }
            }
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle(hoverCircle: false))
    }
}

// MARK: - Calendar

struct CalendarPanel: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        if calendar.accessDenied {
            message("Calendar Access Needed", "Allow under Privacy › Calendars.", button: "Settings") {
                calendar.openPrivacySettings()
            }
        } else if calendar.events.isEmpty {
            message("No Upcoming Events", "Nothing in the next 24 hours.", button: nil) {}
        } else {
            VStack(spacing: 8) {
                ForEach(calendar.events.prefix(2)) { event in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(nsColor: event.color))
                            .frame(width: 4, height: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(event.start.formatted(date: .omitted, time: .shortened) + " – "
                                 + event.end.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer(minLength: 6)
                        Text(relative(event))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color(nsColor: event.color))
                            .fixedSize()
                    }
                }
            }
        }
    }

    private func relative(_ event: UpcomingEvent) -> String {
        _ = calendar.tick // refreshes the label
        let seconds = event.start.timeIntervalSinceNow
        if seconds <= 0 { return "Now" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        return minutes % 60 == 0 ? "in \(hours)h" : "in \(hours)h \(minutes % 60)m"
    }

    private func message(_ title: String, _ detail: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 58, height: 58)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let button {
                Button(action: action) {
                    Text(button)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle(hoverCircle: false))
            }
        }
    }
}

// MARK: - Timer

/// Mirrors the iPhone timer activity: round pause / cancel buttons on the left, a big
/// orange countdown on the right.
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
            HStack(spacing: 10) {
                circleButton(timer.isRunning ? "pause.fill" : "play.fill", fg: .orange,
                             bg: Color.orange.opacity(0.26)) {
                    timer.isRunning ? timer.pause() : timer.resume()
                }
                circleButton("xmark", fg: .white, bg: Color.white.opacity(0.2)) {
                    timer.cancel()
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(timer.isRunning ? "Timer" : "Paused")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    Text(TimeFormat.countdown(timer.remaining(at: ctx.date)))
                        .font(.system(size: 42, weight: .light).monospacedDigit())
                        .foregroundStyle(Color.orange)
                        .contentTransition(.numericText(countsDown: true))
                        .fixedSize()
                }
            }
        }
    }

    private var picker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
            ForEach(presets, id: \.self) { minutes in
                Button {
                    timer.start(seconds: TimeInterval(minutes * 60))
                } label: {
                    Text(minutes == 60 ? "1 hr" : "\(minutes) min")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle(hoverCircle: false))
            }
        }
    }

    private func circleButton(_ symbol: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(fg)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 50, height: 50)
                .background(Circle().fill(bg))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(hoverCircle: false))
    }
}
