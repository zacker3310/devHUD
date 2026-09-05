import AppKit
import SwiftUI

// A borderless, non-activating, transparent panel that floats over everything
// on every Space. Two of these make the HUD: the pill and the detail card.
// The window draws its own shadow from the content's alpha, so a click on a
// transparent pixel falls through to whatever is underneath.
final class HUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Frames are computed by the controller; AppKit must not second-guess them.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// The app is never active, so the first click must count as a click.
final class HUDHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
