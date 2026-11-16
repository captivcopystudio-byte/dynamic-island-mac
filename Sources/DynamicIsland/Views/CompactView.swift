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
        }
    }
}
