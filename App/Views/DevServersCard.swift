import AppKit
import SwiftUI

struct DevServersCard: View {
    let ports: PortsStore
    let actions: ServerActions
    var docker: DockerStore? = nil
    let maxRows = 8

    private var containerCount: Int { docker?.containers.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(HUDColor.icon)
                Text("Dev Servers")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(HUDColor.textPrimary)
                Spacer()
                Text("\(ports.servers.count + containerCount)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(HUDColor.textSecondary)
            }
            if ports.servers.isEmpty {
                Text(ports.lastError.map { "-- \($0)" } ?? "No dev servers listening")
                    .font(.system(size: 12))
                    .foregroundStyle(HUDColor.textSecondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(ports.servers.prefix(maxRows)) { server in
                    ServerRow(server: server, actions: actions)
                }
                if ports.servers.count > maxRows {
                    Text("+\(ports.servers.count - maxRows) more")
                        .font(.system(size: 11))
                        .foregroundStyle(HUDColor.textSecondary)
                }
            }
            if let docker, docker.isInstalled {
                ContainersSection(docker: docker, maxRows: maxRows)
            }
        }
        .onChange(of: ports.servers.map(\.id)) { _, ids in
            actions.prune(keeping: Set(ids))
        }
    }
}

private struct ServerRow: View {
    let server: DevServer
    let actions: ServerActions
    @State private var hovering = false

    private var pending: PendingAction? { actions.state(for: server) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HUDColor.textPrimary)
                        .lineLimit(1)
                    if let tag = server.kind.tag {
                        Chip(text: tag, filled: server.kind.isOpenable)
                    }
                    if server.portlessHost != nil {
                        Chip(text: "portless", filled: true)
                    }
                    if server.kind.isOpenable {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(hovering ? HUDColor.textPrimary : HUDColor.textSecondary)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.06 : 0))
                .padding(-4)
        )
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: hovering)
        .onTapGesture {
            // The one outward action in the app: open a web UI or API root.
            if let url = server.url { NSWorkspace.shared.open(url) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(server.kind.isOpenable ? .isLink : [])
    }

    // Metrics at rest; the action strip on hover; the kill question when asked.
    @ViewBuilder
    private var trailing: some View {
        switch pending {
        case .confirmKill:
            HStack(spacing: 8) {
                Text("Kill?")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HUDColor.textPrimary)
                RowButton(title: "Kill", destructive: true) { actions.confirmKill(server) }
                RowButton(title: "Cancel", destructive: false) { actions.cancelKill(server) }
            }
        case .killing, .restarting:
            ProgressView()
                .controlSize(.small)
                .tint(HUDColor.icon)
        default:
            if hovering {
                HStack(spacing: 4) {
                    IconButton(symbol: "chevron.left.forwardslash.chevron.right", help: "Open in \(actions.editorApp)", enabled: server.cwd != nil) { actions.openEditor(server) }
                    IconButton(symbol: "terminal", help: "Open Terminal here", enabled: server.cwd != nil) { actions.openTerminal(server) }
                    IconButton(symbol: "arrow.clockwise", help: "Restart", enabled: server.cwd != nil) { actions.restart(server) }
                    IconButton(symbol: "xmark.circle", help: "Kill", enabled: true, destructive: true) { actions.requestKill(server) }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Text(metrics)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(HUDColor.textSecondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
    }

    private var subtitle: String {
        switch pending {
        case .killing: return "stopping"
        case .restarting: return "restarting"
        case .failed(let why): return why
        default: break
        }
        var parts = [server.addressText]
        if server.portlessHost != nil { parts.append("port \(server.port)") }
        if server.projectName != nil, server.command != server.projectName { parts.append(server.command) }
        return parts.joined(separator: "  ")
    }

    private var subtitleColor: Color {
        if case .failed = pending { return HUDColor.claude }
        return HUDColor.textSecondary
    }

    private var metrics: String {
        [
            UsageFormat.cpu(server.cpuPercent).map { "\($0) cpu" },
            UsageFormat.memory(server.rssBytes),
            UsageFormat.uptime(since: server.startedAt),
        ].compactMap { $0 }.joined(separator: "  ")
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let enabled: Bool
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(destructive ? HUDColor.claude : HUDColor.icon)
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(HUDColor.ringTrack))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct RowButton: View {
    let title: String
    let destructive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(destructive ? HUDColor.notchBackground : HUDColor.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(destructive ? HUDColor.claude : HUDColor.ringTrack))
        }
        .buttonStyle(.plain)
    }
}

// Running containers, grouped under their own heading. Docker not running is
// one quiet line, not an error.
private struct ContainersSection: View {
    let docker: DockerStore
    let maxRows: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Containers")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HUDColor.textPrimary)
                Spacer()
                Text(docker.isAvailable ? "\(docker.containers.count)" : "Docker not running")
                    .font(.system(size: 11))
                    .foregroundStyle(HUDColor.textSecondary)
            }
            if docker.isAvailable, docker.containers.isEmpty {
                Text("No containers running")
                    .font(.system(size: 12))
                    .foregroundStyle(HUDColor.textSecondary)
            }
            ForEach(docker.containers.prefix(maxRows)) { container in
                ContainerRow(container: container, docker: docker)
            }
            if docker.containers.count > maxRows {
                Text("+\(docker.containers.count - maxRows) more")
                    .font(.system(size: 11))
                    .foregroundStyle(HUDColor.textSecondary)
            }
        }
        .padding(.top, 6)
    }
}

private struct ContainerRow: View {
    let container: DockerContainer
    let docker: DockerStore
    @State private var hovering = false

    private var pending: PendingAction? { docker.state(for: container) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(container.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HUDColor.textPrimary)
                        .lineLimit(1)
                    if let project = container.project {
                        Chip(text: project, filled: false)
                    }
                    if container.url != nil {
                        Chip(text: "web", filled: true)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(hovering ? HUDColor.textPrimary : HUDColor.textSecondary)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.06 : 0))
                .padding(-4)
        )
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: hovering)
        .onTapGesture {
            if let url = container.url { NSWorkspace.shared.open(url) }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var trailing: some View {
        switch pending {
        case .confirmKill:
            HStack(spacing: 8) {
                Text("Stop?")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HUDColor.textPrimary)
                RowButton(title: "Stop", destructive: true) { docker.confirmStop(container) }
                RowButton(title: "Cancel", destructive: false) { docker.cancelStop(container) }
            }
        case .killing, .restarting:
            ProgressView().controlSize(.small).tint(HUDColor.icon)
        default:
            if hovering {
                HStack(spacing: 4) {
                    IconButton(symbol: "arrow.clockwise", help: "Restart container", enabled: true) { docker.restart(container) }
                    IconButton(symbol: "stop.circle", help: "Stop container", enabled: true, destructive: true) { docker.requestStop(container) }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Text(metrics)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(HUDColor.textSecondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
    }

    private var subtitle: String {
        switch pending {
        case .killing: return "stopping"
        case .restarting: return "restarting"
        case .failed(let why): return why
        default: break
        }
        var parts = [container.shortImage]
        let ports = container.ports.map { "\($0.host)\u{2192}\($0.container)" }
        if !ports.isEmpty { parts.append(ports.joined(separator: " ")) }
        if let health = container.health { parts.append(health) } else if !container.isRunning { parts.append(container.state) }
        return parts.joined(separator: "  ")
    }

    private var subtitleColor: Color {
        if case .failed = pending { return HUDColor.claude }
        if container.health == "unhealthy" { return HUDColor.claude }
        return HUDColor.textSecondary
    }

    private var metrics: String {
        [
            container.cpuPercent.map { String(format: "%.0f%% cpu", $0) },
            container.memory,
        ].compactMap { $0 }.joined(separator: "  ")
    }
}

// Small label on a row: filled for something you can open, outlined for a name.
private struct Chip: View {
    let text: String
    let filled: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(filled ? HUDColor.notchBackground : HUDColor.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(filled ? HUDColor.icon : Color.clear)
                    .overlay(Capsule().stroke(HUDColor.ringTrack, lineWidth: filled ? 0 : 1))
            )
    }
}
