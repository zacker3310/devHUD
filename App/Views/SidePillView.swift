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
                            selected: state.selection == row
                        ) {
                            UsageRing(provider: slot.kind, percentUsed: usage.state(for: slot).lastGood?.primary.percentUsed, size: PillMetric.ringSize)
                        }
                        .accessibilityLabel(slot.title)
                    case .servers:
                        PillItem(label: "\(ports.servers.count)", selected: state.selection == .servers) {
                            ZStack {
                                Circle().stroke(HUDColor.ringTrack, lineWidth: PillMetric.ringSize * 0.14)
                                Image(systemName: "server.rack")
                                    .font(.system(size: PillMetric.ringSize * 0.38, weight: .semibold))
                                    .foregroundStyle(HUDColor.icon)
                            }
                            .frame(width: PillMetric.ringSize, height: PillMetric.ringSize)
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

private struct PillItem<Ring: View>: View {
    let label: String
    let selected: Bool
    @ViewBuilder let ring: () -> Ring

    var body: some View {
        VStack(spacing: PillMetric.ringLabelGap) {
            ring()
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(HUDColor.textPrimary)
                .frame(height: PillMetric.labelHeight)
        }
        .frame(height: PillMetric.itemHeight)
        .opacity(selected ? 1 : 0.9)
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
        }
        .frame(width: PillMetric.gearDiameter, height: PillMetric.gearDiameter)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .accessibilityLabel("devHUD menu")
        .preferredColorScheme(.dark)
    }
}
