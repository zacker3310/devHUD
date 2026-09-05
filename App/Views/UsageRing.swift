import SwiftUI

// Apple Activity-ring pattern: visible track, round caps, 12 o'clock start.
struct UsageRing: View {
    let provider: ProviderID
    let percentUsed: Double?
    let size: CGFloat

    private var lineWidth: CGFloat { size * 0.14 }
    private var progress: Double { min(max((percentUsed ?? 0) / 100, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(HUDColor.ringTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(HUDColor.accent(for: provider), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: progress)
            Image(provider.brandImageName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.42, height: size * 0.42)
                .foregroundStyle(HUDColor.icon)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(provider.title) usage")
        .accessibilityValue(percentUsed.map(UsageFormat.percent) ?? "unknown")
    }
}

struct UsageBar: View {
    let provider: ProviderID
    let percentUsed: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(HUDColor.ringTrack)
                Capsule()
                    .fill(HUDColor.accent(for: provider))
                    .frame(width: geo.size.width * min(max(percentUsed / 100, 0), 1))
                    .animation(.smooth(duration: 0.6), value: percentUsed)
            }
        }
        .frame(height: HUDMetric.barHeight)
    }
}
