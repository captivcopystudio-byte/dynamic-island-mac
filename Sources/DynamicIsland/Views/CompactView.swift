import SwiftUI

/// Collapsed island: content lives in the two "ears" either side of the camera.
struct CompactView: View {
    let kind: CompactKind
    @ObservedObject var vm: IslandViewModel

    var body: some View {
        let ear = vm.earWidth(kind)
        HStack(spacing: 0) {
            left
                .frame(width: ear - 10, alignment: .leading)
                .padding(.leading, 10)
            Color.clear
                .frame(width: vm.geometry.notchSize.width)
            right
                .frame(width: ear - 10, alignment: .trailing)
                .padding(.trailing, 10)
        }
        .padding(.horizontal, 6)
        .frame(width: vm.compactSize(kind).width, height: vm.geometry.notchSize.height)
    }

    private var symbolSize: CGFloat { 13 }

    @ViewBuilder private var left: some View {
        switch kind {
        case .music:
            Color.clear // album art is drawn by IslandRootView so it can glide when expanding
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.orange)
        case .timerDone:
            Image(systemName: "bell.fill")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, options: .repeating, value: kind)
        case .volume:
            Image(systemName: vm.volume.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
                  variableValue: Double(vm.volume.volume))
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, alignment: .leading)
        case .charging:
            Text("Charging")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize()
        case .lowBattery:
            Text("Low Battery")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize()
        case .headphonesOn, .headphonesOff:
            HStack(spacing: 6) {
                Image(systemName: vm.headphones.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(kind == .headphonesOn ? Color.white : Color.white.opacity(0.5))
                Text(shortName(vm.headphones.name))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 92, alignment: .leading)
                    .fixedSize()
            }
        case .focusOn, .focusOff:
            label("moon.fill", "Focus", tint: kind == .focusOn ? Color.indigo : Color.white.opacity(0.5))
        case .capsOn, .capsOff:
            label(kind == .capsOn ? "capslock.fill" : "capslock", "Caps Lock",
                  tint: kind == .capsOn ? Color.green : Color.white.opacity(0.5))
        case .calendar:
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: vm.calendar.imminentEvent()?.color ?? .systemRed))
                    .frame(width: 3, height: 15)
                Image(systemName: "calendar")
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
        case .privacy:
            Image(systemName: vm.privacy.cameraInUse ? "video.fill" : "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(vm.privacy.cameraInUse ? Color.green : Color.orange)
        }
    }

    @ViewBuilder private var right: some View {
        switch kind {
        case .music:
            Color.clear // waveform likewise
        case .timer:
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                Text(TimeFormat.countdown(vm.timer.remaining(at: ctx.date)))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .fixedSize()
            }
        case .timerDone:
            Text("Done")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
        case .volume:
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule().fill(Color.white)
                        .frame(width: geo.size.width * CGFloat(vm.volume.isMuted ? 0 : vm.volume.volume))
                }
            }
            .frame(height: 5)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: vm.volume.volume)
        case .charging:
            HStack(spacing: 5) {
                Text("\(vm.battery.level)%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.green)
                BatteryIcon(level: vm.battery.level, charging: false, tint: .green)
            }
            .fixedSize()
        case .lowBattery:
            HStack(spacing: 5) {
                Text("\(vm.battery.level)%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.red)
                BatteryIcon(level: vm.battery.level, charging: false, tint: .red)
            }
            .fixedSize()
        case .headphonesOn:
            if let battery = vm.headphones.battery {
                HStack(spacing: 5) {
                    Text("\(battery)%")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(battery <= 20 ? Color.red : Color.green)
                    BatteryIcon(level: battery, charging: false, tint: battery <= 20 ? .red : .green)
                }
                .fixedSize()
            } else {
                status("Connected", .green)
            }
        case .headphonesOff:
            status("Disconnected", .white.opacity(0.55))
        case .focusOn, .capsOn:
            status("On", kind == .focusOn ? .indigo : .green)
        case .focusOff, .capsOff:
            status("Off", .white.opacity(0.55))
        case .calendar:
            Text(countdown)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(nsColor: vm.calendar.imminentEvent()?.color ?? .systemRed))
                .fixedSize()
        case .privacy:
            Circle()
                .fill(vm.privacy.cameraInUse ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
        }
    }

    private func label(_ symbol: String, _ text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize()
        }
    }

    private func status(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .fixedSize()
    }

    /// "Mo's AirPods Pro" is too long for the notch; keep the product name.
    private func shortName(_ name: String) -> String {
        for product in ["AirPods Max", "AirPods Pro", "AirPods"] where name.contains(product) { return product }
        return name
    }

    private var countdown: String {
        guard let event = vm.calendar.imminentEvent() else { return "" }
        let minutes = Int((event.start.timeIntervalSinceNow / 60).rounded(.up))
        return minutes <= 0 ? "Now" : "in \(minutes)m"
    }
}
