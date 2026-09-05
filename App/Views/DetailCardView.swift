import SwiftUI

// Speech-bubble card with a pointer on the trailing edge at `pointerY` (from the top).
struct CardBubbleShape: Shape {
    let pointerY: CGFloat
    var pointerEdge: PillEdge = .right   // the pill's edge: the pointer faces it
    let radius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let pw = PillMetric.cardPointerWidth
        let ph = PillMetric.cardPointerHeight
        let body = pointerEdge == .right
            ? CGRect(x: rect.minX, y: rect.minY, width: rect.width - pw, height: rect.height)
            : CGRect(x: rect.minX + pw, y: rect.minY, width: rect.width - pw, height: rect.height)
        var p = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        var tip = Path()
        if pointerEdge == .right {
            tip.move(to: CGPoint(x: body.maxX - 1, y: pointerY - ph / 2))
            tip.addLine(to: CGPoint(x: rect.maxX, y: pointerY))
            tip.addLine(to: CGPoint(x: body.maxX - 1, y: pointerY + ph / 2))
        } else {
            tip.move(to: CGPoint(x: body.minX + 1, y: pointerY - ph / 2))
            tip.addLine(to: CGPoint(x: rect.minX, y: pointerY))
            tip.addLine(to: CGPoint(x: body.minX + 1, y: pointerY + ph / 2))
        }
        tip.closeSubpath()
        p.addPath(tip)
        return p
    }
}

struct DetailCardView: View {
    let selection: HUDSelection
    let pointerY: CGFloat
    var pointerEdge: PillEdge = .right
    let usage: AIUsageStore
    let ports: PortsStore
    let actions: ServerActions
    var activity: ActivityStore? = nil
    @State private var appeared = false

    var body: some View {
        Group {
            switch selection {
            case .provider(let slot):
                ProviderDetailView(slot: slot, state: usage.state(for: slot), sessions: activity?.summary(for: slot.kind))
            case .servers:
                DevServersCard(ports: ports, actions: actions)
            }
        }
        // Switching rings crossfades the content; the bubble stays.
        .id(selection)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(.snappy(duration: 0.18), value: selection)
        .frame(width: PillMetric.cardWidth, alignment: .leading)
        .padding(16)
        .padding(pointerEdge == .right ? .trailing : .leading, PillMetric.cardPointerWidth)
        .background(
            CardBubbleShape(pointerY: pointerY, pointerEdge: pointerEdge)
                .fill(HUDColor.notchBackground)
                .overlay(CardBubbleShape(pointerY: pointerY, pointerEdge: pointerEdge).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
        // Springs out of the pill's side: scale from the tail, slide 8 pt.
        .scaleEffect(appeared ? 1 : 0.96, anchor: pointerEdge == .right ? .trailing : .leading)
        .offset(x: appeared ? 0 : (pointerEdge == .right ? 8 : -8))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { appeared = true }
        }
        .preferredColorScheme(.dark)
    }
}

struct ProviderDetailView: View {
    let slot: ProviderSlot
    let state: ProviderState
    var sessions: ActivitySummary? = nil
    private var provider: ProviderID { slot.kind }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(provider.brandImageName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(HUDColor.accent(for: provider))
                Text("\(slot.title) Usage")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(HUDColor.textPrimary)
                Spacer()
                Text(trailingText)
                    .font(.system(size: 11))
                    .foregroundStyle(HUDColor.textSecondary)
            }
            if let snapshot = state.lastGood {
                let stale = UsageFormat.staleText(snapshot.fetchedAt) != nil
                ForEach(Array(([snapshot.primary] + snapshot.secondary).enumerated()), id: \.offset) { _, window in
                    WindowRow(provider: provider, window: window, stale: stale)
                }
            } else {
                UsageBar(provider: provider, percentUsed: 0)
                Text(state.statusText().map { "-- \($0)" } ?? (state.lastAttempt == nil ? "loading" : "--"))
                    .font(.system(size: 11))
                    .foregroundStyle(HUDColor.textSecondary)
                    .lineLimit(2)
            }
            if let sessions {
                SessionsSection(summary: sessions)
            }
        }
    }

    private var trailingText: String {
        guard let snapshot = state.lastGood else { return "" }
        if let next = state.nextAttempt, next > Date() { return "rate limited" }
        if let stale = UsageFormat.staleText(snapshot.fetchedAt) { return stale }
        return snapshot.planLabel ?? ""
    }
}

// Every live session for this provider: what it is doing and where.
private struct SessionsSection: View {
    let summary: ActivitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sessions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HUDColor.textPrimary)
                Spacer()
                Text(summary.label)
                    .font(.system(size: 11))
                    .foregroundStyle(summary.state == .waiting ? HUDColor.waiting : HUDColor.textSecondary)
            }
            ForEach(summary.sessions) { session in
                HStack(spacing: 8) {
                    Circle()
                        .fill(dot(session.state))
                        .frame(width: 6, height: 6)
                    Text(session.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HUDColor.textPrimary)
                        .lineLimit(1)
                    Text([session.surface, session.folder].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(HUDColor.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(stateText(session))
                        .font(.system(size: 11))
                        .foregroundStyle(session.state == .waiting ? HUDColor.waiting : HUDColor.textSecondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func dot(_ state: AgentSession.State) -> Color {
        switch state {
        case .busy: return HUDColor.textPrimary
        case .waiting: return HUDColor.waiting
        case .idle: return HUDColor.ringTrack
        }
    }

    private func stateText(_ session: AgentSession) -> String {
        let since = UsageFormat.uptime(since: session.since) ?? ""
        switch session.state {
        case .busy: return "working \(since)"
        case .waiting: return "waiting \(since)"
        case .idle: return "idle \(since)"
        }
    }
}

private struct WindowRow: View {
    let provider: ProviderID
    let window: UsageWindow
    // A countdown on a snapshot hours old is noise, and a past reset means the
    // percentage itself has rolled over. Show the bar, drop the countdown.
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HUDColor.textPrimary)
                Spacer()
                if !stale, let reset = UsageFormat.resetText(window.resetsAt) {
                    Text(reset)
                        .font(.system(size: 11))
                        .foregroundStyle(HUDColor.textSecondary)
                }
            }
            UsageBar(provider: provider, percentUsed: window.percentUsed)
            Text("\(UsageFormat.percent(window.percentUsed)) Used")
                .font(.system(size: 11))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: window.percentUsed)
                .foregroundStyle(HUDColor.textSecondary)
        }
    }
}
