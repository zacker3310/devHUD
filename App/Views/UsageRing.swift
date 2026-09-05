import SwiftUI

// Apple Activity-ring pattern: visible track, round caps, 12 o'clock start.
// Colour is the usage band; the mark is the provider. A thin arc spins
// inside while an agent is working; the ring pulses amber while one waits.
struct UsageRing: View {
    let provider: ProviderID
    let percentUsed: Double?
    let size: CGFloat
    var stale = false
    var activity: ActivitySummary.State? = nil

    private var lineWidth: CGFloat { size * 0.14 }
    private var progress: Double { min(max((percentUsed ?? 0) / 100, 0), 1) }
    private var band: UsageBand? { percentUsed.map(UsageBand.init(percentUsed:)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(HUDColor.ringTrack, lineWidth: lineWidth)
            if let band {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(HUDColor.band(band), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: progress)
            }
            if activity == .waiting {
                WaitingPulse(size: size, lineWidth: lineWidth)
            }
            Image(provider.brandImageName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.42, height: size * 0.42)
                .foregroundStyle(HUDColor.icon)
                .opacity(band == .exhausted ? 0.45 : 1)
            if activity == .working {
                WorkingArc(size: size)
            }
        }
        .frame(width: size, height: size)
        .opacity(stale ? 0.55 : 1)
        .accessibilityLabel("\(provider.title) usage")
        .accessibilityValue(percentUsed.map(UsageFormat.percent) ?? "unknown")
    }
}

// A quarter arc just inside the ring that keeps turning while a session runs.
private struct WorkingArc: View {
    let size: CGFloat
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(HUDColor.textPrimary.opacity(0.85), style: StrokeStyle(lineWidth: max(size * 0.05, 1.5), lineCap: .round))
            .frame(width: size * 0.66, height: size * 0.66)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
            .accessibilityLabel("working")
    }
}

// The whole ring breathes amber: the agent stopped and wants you.
private struct WaitingPulse: View {
    let size: CGFloat
    let lineWidth: CGFloat
    @State private var bright = false

    var body: some View {
        Circle()
            .stroke(HUDColor.waiting.opacity(bright ? 0.9 : 0.25), lineWidth: lineWidth)
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: bright)
            .onAppear { bright = true }
            .accessibilityLabel("waiting for you")
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
                    .fill(HUDColor.band(UsageBand(percentUsed: percentUsed)))
                    .frame(width: geo.size.width * min(max(percentUsed / 100, 0), 1))
                    .animation(.smooth(duration: 0.6), value: percentUsed)
            }
        }
        .frame(height: HUDMetric.barHeight)
    }
}
