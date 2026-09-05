import SwiftUI

// Sampled from the Codenotch reference screenshots (TASKS.md, "Color tokens").
enum HUDColor {
    static let notchBackground = Color.black
    static let ringTrack = Color(hex: 0x2C2D2C)
    static let claude = Color(hex: 0xF04A15)
    static let codex = Color(hex: 0x2BE99A)
    static let copilot = Color(hex: 0xEFFD31)
    static let icon = Color(hex: 0xE8E8E8)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)

    static func accent(for provider: ProviderID) -> Color {
        switch provider {
        case .claude: return claude
        case .codex: return codex
        case .copilot: return copilot
        case .cursor: return icon
        }
    }

    // Ring and bar colour by how close the window is to its limit.
    static func band(_ band: UsageBand) -> Color {
        switch band {
        case .ample: return codex
        case .watch: return copilot
        case .critical, .exhausted: return claude
        }
    }

    static let waiting = copilot

    // Circle stroke for a watch row: quiet track, yellow while busy, orange
    // when something failed.
    static func watch(_ state: WatchItem.State) -> Color {
        switch state {
        case .ok: return ringTrack
        case .busy: return copilot
        case .attention: return copilot
        case .failed: return claude
        }
    }

}

enum HUDMetric {
    static let barHeight: CGFloat = 6
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
