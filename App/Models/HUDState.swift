import Foundation
import Observation

enum HUDSelection: Hashable {
    case provider(ProviderSlot)
    case servers

    var slot: ProviderSlot? {
        if case .provider(let slot) = self { return slot }
        return nil
    }
}

@MainActor
@Observable
final class HUDState {
    // Pill rows top to bottom: one per provider slot, then the servers badge.
    var rows: [HUDSelection] = [.servers]
    var placement = PillPlacement.load()
    // The ring under the cursor, for the lift; nil when the cursor is elsewhere.
    var hoveredRow: HUDSelection?
    var selection: HUDSelection?
    var isRevealed = false
    // Mirror of the login-item status, refreshed when a menu opens.
    var launchAtLogin = false
    var autoHide: Bool {
        didSet { UserDefaults.standard.set(autoHide, forKey: "autoHide") }
    }

    init() {
        let defaults = UserDefaults.standard
        autoHide = defaults.object(forKey: "autoHide") == nil ? true : defaults.bool(forKey: "autoHide")
    }
}

// All pill geometry in one place so the controller can place the card pointer
// and hit-test the cursor without measuring views. Points, y from the top.
enum PillMetric {
    // Kind order for the pill; slots of the same kind keep discovery order.
    static let kindOrder: [ProviderID] = [.claude, .copilot, .codex, .cursor]

    static func rows(for slots: [ProviderSlot]) -> [HUDSelection] {
        let ordered = kindOrder.flatMap { kind in slots.filter { $0.kind == kind } }
        return ordered.map(HUDSelection.provider) + [.servers]
    }

    // Sized against the Codenotch demo frame: ring about 40 pt, bold white
    // percent under it, deep concave ears where the pill meets the edge.
    static let pillWidth: CGFloat = 64
    static let ear: CGFloat = 26             // swept quarter circle into the screen edge
    static let cornerRadius: CGFloat = 28
    static let topPad: CGFloat = 16
    static let bottomPad: CGFloat = 14
    static let ringSize: CGFloat = 40
    static let labelHeight: CGFloat = 15
    static let ringLabelGap: CGFloat = 4
    static let itemSpacing: CGFloat = 12
    static let gearSize: CGFloat = 15        // icon inside the circle
    static let gearDiameter: CGFloat = 32    // the circle below the pill
    static let gearGap: CGFloat = 4          // below the pill body, inside the ear zone
    static let peek: CGFloat = 5             // visible when concealed; the demo shows a few pixels
    static let verticalAnchor: CGFloat = 0.58 // pill center, fraction of screen height from the bottom

    static let itemHeight: CGFloat = ringSize + ringLabelGap + labelHeight

    static func windowHeight(rows: Int) -> CGFloat {
        ear * 2 + topPad + CGFloat(rows) * itemHeight + CGFloat(max(rows - 1, 0)) * itemSpacing + bottomPad
    }

    // The gear circle hangs off the pill body (the window's bottom `ear`
    // points are the transparent sweep into the edge), centered on the pill.
    static func gearFrame(belowPill pill: CGRect) -> CGRect {
        CGRect(x: pill.midX - gearDiameter / 2, y: pill.minY + ear - gearGap - gearDiameter, width: gearDiameter, height: gearDiameter)
    }

    static func itemTop(index: Int) -> CGFloat {
        ear + topPad + CGFloat(index) * (itemHeight + itemSpacing)
    }

    static func ringCenterY(index: Int) -> CGFloat {
        itemTop(index: index) + ringSize / 2
    }

    // Which row sits at `yFromTop` inside the pill, if any. The gap between
    // rows belongs to the row above so a cursor sliding down keeps its card.
    static func item(atYFromTop y: CGFloat, rows: [HUDSelection]) -> HUDSelection? {
        for index in rows.indices {
            let top = itemTop(index: index)
            let bottom = top + itemHeight + (index < rows.count - 1 ? itemSpacing : 0)
            if y >= top, y < bottom { return rows[index] }
        }
        return nil
    }

    static let cardWidth: CGFloat = 300
    static let cardPointerWidth: CGFloat = 10
    static let cardPointerHeight: CGFloat = 18
    static let cardPointerInset: CGFloat = 34 // preferred pointer distance from the card top

    // Card top edge (screen coords, y up) and pointer offset from the card top,
    // keeping the card inside the screen's vertical bounds. The top clamp is
    // applied last so a card taller than the screen still starts on screen.
    static func cardPlacement(ringCenterScreenY: CGFloat, cardHeight: CGFloat, screenMinY: CGFloat, screenMaxY: CGFloat, margin: CGFloat = 8) -> (top: CGFloat, pointerY: CGFloat) {
        var top = ringCenterScreenY + cardPointerInset
        top = max(top, screenMinY + margin + cardHeight)
        top = min(top, screenMaxY - margin)
        let pointerY = min(max(top - ringCenterScreenY, cardPointerHeight), cardHeight - cardPointerHeight)
        return (top, pointerY)
    }
}

// What the cursor is over, resolved from window frames rather than view
// tracking areas: the panels are never key, and enter/exit ordering across
// two windows is not something to build a state machine on.
enum HoverTarget: Equatable {
    case none
    case pill(HUDSelection?)
    case card
    case gear
}

enum HoverResolver {
    // The gear wins over the pill: its circle overlaps the pill window's
    // transparent ear zone.
    static func resolve(location: CGPoint, pillFrame: CGRect, cardFrame: CGRect?, gearFrame: CGRect? = nil, rows: [HUDSelection]) -> HoverTarget {
        if let gearFrame, gearFrame.contains(location) { return .gear }
        if pillFrame.contains(location) {
            let yFromTop = pillFrame.maxY - location.y
            return .pill(PillMetric.item(atYFromTop: yFromTop, rows: rows))
        }
        if let cardFrame, cardFrame.contains(location) { return .card }
        return .none
    }
}

enum PillEdge: String, CaseIterable {
    case left
    case right
}

// Where the pill lives: which edge, how far up it, and on which display.
struct PillPlacement: Equatable {
    var edge: PillEdge = .right
    var anchor: CGFloat = PillMetric.verticalAnchor // pill center, fraction of screen height from the bottom
    var screenName: String?

    static let defaults = PillPlacement()

    static func load(from store: UserDefaults = .standard) -> PillPlacement {
        var p = PillPlacement()
        if let raw = store.string(forKey: "pillEdge"), let edge = PillEdge(rawValue: raw) { p.edge = edge }
        if store.object(forKey: "pillAnchor") != nil { p.anchor = CGFloat(store.double(forKey: "pillAnchor")) }
        p.screenName = store.string(forKey: "pillScreen")
        return p
    }

    func save(to store: UserDefaults = .standard) {
        store.set(edge.rawValue, forKey: "pillEdge")
        store.set(Double(anchor), forKey: "pillAnchor")
        store.set(screenName, forKey: "pillScreen")
    }

    // Where a dropped pill lands: the nearer edge of the screen under the
    // cursor, at the cursor's height.
    static func snapped(cursor: CGPoint, screen: CGRect, screenName: String?) -> PillPlacement {
        let edge: PillEdge = (cursor.x - screen.minX) < (screen.maxX - cursor.x) ? .left : .right
        let anchor = screen.height > 0 ? (cursor.y - screen.minY) / screen.height : PillMetric.verticalAnchor
        return PillPlacement(edge: edge, anchor: min(max(anchor, 0), 1), screenName: screenName)
    }
}

extension PillMetric {
    // How far the gear circle reaches below the pill window, reserved so it
    // never sits on the Dock.
    static var gearReserve: CGFloat { max(gearGap + gearDiameter - ear, 0) }

    // The window never leaves the screen: concealed it is `peek` wide at the
    // docked edge, and the anchor is clamped so the pill and its gear fit
    // vertically. Pass the visible frame so the menu bar and Dock are excluded.
    static func pillFrame(placement: PillPlacement, screen: CGRect, revealed: Bool, rows: Int) -> CGRect {
        let width = revealed ? pillWidth : peek
        let height = windowHeight(rows: rows)
        let minCenter = screen.minY + gearReserve + height / 2
        let maxCenter = screen.maxY - height / 2
        let center = min(max(screen.minY + screen.height * placement.anchor, minCenter), maxCenter)
        let x = placement.edge == .right ? screen.maxX - width : screen.minX
        return CGRect(x: x, y: center - height / 2, width: width, height: height)
    }

    // Card x so its pointer tip overlaps the pill's inner edge by 2 pt,
    // clamped to the screen on the far side.
    static func cardX(edge: PillEdge, pill: CGRect, cardWidth: CGFloat, screen: CGRect) -> CGFloat {
        switch edge {
        case .right: return max(pill.minX - cardWidth + 2, screen.minX)
        case .left: return min(pill.maxX - 2, screen.maxX - cardWidth)
        }
    }
}
