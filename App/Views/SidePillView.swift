import AppKit
import SwiftUI

// Vertical pill flush with the right screen edge: rounded on the left, concave
// ears top and bottom where it meets the edge, like a notch turned sideways.
// The ears are true quarter circles (cubic k = 0.5523) so the pill sweeps
// out of the screen edge instead of kinking; the left corners are wide.
struct SidePillShape: Shape {
    var edge: PillEdge = .right

    func path(in rect: CGRect) -> Path {
        let p = rightEdgePath(in: rect)
        guard edge == .left else { return p }
        return p.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width - 2 * rect.minX, y: 0))
    }

    private func rightEdgePath(in rect: CGRect) -> Path {
        let ear = PillMetric.ear
        let r = PillMetric.cornerRadius
        let k: CGFloat = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addCurve(
            to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear),
            control1: CGPoint(x: rect.maxX, y: rect.minY + ear * k),
            control2: CGPoint(x: rect.maxX - ear + ear * k, y: rect.minY + ear)
        )
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY + ear))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY + ear), tangent2End: CGPoint(x: rect.minX, y: rect.minY + ear + r), radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - ear - r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY - ear), tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY - ear), radius: r)
        p.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - ear))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - ear + ear * k, y: rect.maxY - ear),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - ear * k)
        )
        p.closeSubpath()
        return p
    }
}

// Hover is resolved by the controller from the cursor location, so the view
// only draws. The gear lives in its own circle below the pill.
struct SidePillView: View {
    let usage: AIUsageStore
    let ports: PortsStore
    let docker: DockerStore
    let github: GitHubStore
    let vercel: VercelStore
    let activity: ActivityStore
    let state: HUDState

    var body: some View {
        ZStack(alignment: .trailing) {
            SidePillShape(edge: state.placement.edge)
                .fill(HUDColor.notchBackground)
                .overlay(SidePillShape(edge: state.placement.edge).stroke(Color.white.opacity(0.08), lineWidth: 1))
            VStack(spacing: PillMetric.itemSpacing) {
                ForEach(state.rows, id: \.self) { row in
                    switch row {
                    case .provider(let slot):
                        PillItem(
                            label: UsageFormat.percentOrDash(usage.state(for: slot).lastGood?.primary.percentUsed),
                            selected: state.selection == row,
                            hovered: state.hoveredRow == row,
                            anyHovered: state.hoveredRow != nil
                        ) {
                            UsageRing(
                                provider: slot.kind,
                                percentUsed: usage.state(for: slot).lastGood?.primary.percentUsed,
                                size: PillMetric.ringSize,
                                stale: usage.state(for: slot).isStale(),
                                activity: activity.summary(for: slot.kind)?.state
                            )
                        }
                        .accessibilityLabel(slot.title)
                    case .servers:
                        PillItem(label: "\(ports.servers.count + docker.containers.count)", selected: state.selection == .servers, hovered: state.hoveredRow == .servers, anyHovered: state.hoveredRow != nil) {
                            ZStack {
                                Circle().stroke(HUDColor.ringTrack, lineWidth: PillMetric.ringSize * 0.14)
                                Image(systemName: "server.rack")
                                    .font(.system(size: PillMetric.ringSize * 0.38, weight: .semibold))
                                    .foregroundStyle(HUDColor.icon)
                            }
                            .frame(width: PillMetric.ringSize, height: PillMetric.ringSize)
                        }
                    case .github:
                        PillItem(label: "\(github.summary.badge)", selected: state.selection == .github, hovered: state.hoveredRow == .github, anyHovered: state.hoveredRow != nil) {
                            WatchCircle(imageName: "brand-github", state: github.summary.worst)
                        }
                    case .vercel:
                        PillItem(label: "\(vercel.summary.badge)", selected: state.selection == .vercel, hovered: state.hoveredRow == .vercel, anyHovered: state.hoveredRow != nil) {
                            WatchCircle(imageName: "brand-vercel", state: vercel.summary.worst)
                        }
                    }
                }
            }
            .padding(.top, PillMetric.ear + PillMetric.topPad)
            .padding(.bottom, PillMetric.ear + PillMetric.bottomPad)
            .frame(width: PillMetric.pillWidth)
        }
        .frame(width: PillMetric.pillWidth, height: PillMetric.windowHeight(rows: state.rows.count))
        .contentShape(SidePillShape(edge: state.placement.edge))
        .preferredColorScheme(.dark)
    }
}

// The ring under the cursor lifts; the rest step back. Numbers roll.
private struct PillItem<Ring: View>: View {
    let label: String
    let selected: Bool
    var hovered = false
    var anyHovered = false
    @ViewBuilder let ring: () -> Ring

    private var receded: Bool { anyHovered && !hovered }

    var body: some View {
        VStack(spacing: PillMetric.ringLabelGap) {
            ring()
                .scaleEffect(hovered ? 1.1 : 1)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(hovered || selected ? HUDColor.textPrimary : HUDColor.textPrimary.opacity(0.85))
                .frame(height: PillMetric.labelHeight)
        }
        .frame(height: PillMetric.itemHeight)
        .opacity(receded ? 0.7 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: anyHovered)
        .animation(.snappy(duration: 0.3), value: label)
    }
}

// The settings button: a black circle that appears under the pill on hover.
struct GearButtonView: View {
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(HUDColor.notchBackground)
                .overlay(Circle().stroke(Color.white.opacity(hovering ? 0.18 : 0.08), lineWidth: 1))
            Image(systemName: "gearshape.fill")
                .font(.system(size: PillMetric.gearSize, weight: .semibold))
                .foregroundStyle(hovering ? HUDColor.textPrimary : HUDColor.icon.opacity(0.85))
                .rotationEffect(.degrees(hovering ? 40 : 0))
        }
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: hovering)
        .frame(width: PillMetric.gearDiameter, height: PillMetric.gearDiameter)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .accessibilityLabel("devHUD menu")
        .preferredColorScheme(.dark)
    }
}

// A brand mark in a circle whose stroke says whether anything needs a look.
struct WatchCircle: View {
    let imageName: String
    let state: WatchItem.State

    var body: some View {
        ZStack {
            Circle().stroke(HUDColor.watch(state), lineWidth: PillMetric.ringSize * 0.14)
                .animation(.smooth(duration: 0.4), value: state)
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: PillMetric.ringSize * 0.42, height: PillMetric.ringSize * 0.42)
                .foregroundStyle(HUDColor.icon)
        }
        .frame(width: PillMetric.ringSize, height: PillMetric.ringSize)
    }
}
