import AppKit
import SwiftUI

// Owns the two panels and the concealed / revealed / card state machine.
// Hover drives everything, like the Codenotch demo: the cursor at the screen
// edge slides the pill in, a ring under the cursor opens its card, leaving the
// ring fades the card, leaving the pill slides it back out. The cursor is
// tracked by mouse-move monitors and resolved against window frames, because
// the panels are never key and per-view tracking areas cannot be trusted.
// Everything here runs on the main actor; the stores poll on their own tasks.
@MainActor
final class HUDController: NSObject, NSMenuDelegate {
    let usage: AIUsageStore
    let portless: PortlessStore
    let ports: PortsStore
    let actions: ServerActions
    let activity = ActivityStore()
    let state = HUDState()
    // A pinned card ignores the hover timers until unpinned.
    private var pinned: HUDSelection?
    // Hide for an hour: no reveal until this passes.
    private var hiddenUntil: Date?
    private var activityObservation: Task<Void, Never>?

    private var pillPanel: HUDPanel?
    private var pillHost: NSView?
    private var cardPanel: HUDPanel?
    private var gearPanel: HUDPanel?
    private var gearHideTask: Task<Void, Never>?
    private var cardHost: HUDHostingView<DetailCardView>?
    private var concealTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var hoverTarget: HoverTarget = .none
    private var menuOpen = false
    // Drag in progress: where the cursor started, where the window was, and
    // whether it has moved far enough to count as a drag rather than a click.
    private var drag: (start: CGPoint, origin: CGPoint, moved: Bool)?
    private var mouseMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    #if DEBUG
    private var debugObserver: NSObjectProtocol?
    #endif

    static let concealDelay: Duration = .seconds(0.8)
    static let closeDelay: Duration = .seconds(0.35)

    override init() {
        var providers: [any UsageProvider] = ClaudeUsageProvider.discovered()
        providers.append(CopilotUsageProvider())
        providers.append(CodexUsageProvider())
        if let cursor = CursorUsageProvider.discovered() { providers.append(cursor) }
        usage = AIUsageStore(providers: providers)
        portless = PortlessStore()
        ports = PortsStore(portless: portless)
        actions = ServerActions(ports: ports)
        super.init()
    }

    // The chosen display when it is attached, otherwise the primary one (the
    // one with the menu bar). Not NSScreen.main: that follows the active app's
    // key window and wanders between displays.
    private var screen: NSScreen? {
        if let name = state.placement.screenName, let match = NSScreen.screens.first(where: { $0.localizedName == name }) {
            return match
        }
        return NSScreen.screens.first
    }

    func start() {
        portless.start()
        ports.start()
        activity.start()
        usage.agentsActive = activity.anyActive
        usage.start()
        observeActivity()

        state.rows = PillMetric.rows(for: usage.slots)
        let size = NSSize(width: PillMetric.pillWidth, height: PillMetric.windowHeight(rows: state.rows.count))
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: size))
        let root = SidePillView(usage: usage, ports: ports, activity: activity, state: state)
        let host = HUDHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = state.placement.edge == .left ? [.minXMargin] : [.maxXMargin]
        // The window narrows to the peek width when concealed; the hosting
        // view keeps its full size inside a plain container so the pill's left
        // edge is what stays on screen.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.addSubview(host)
        panel.contentView = container
        pillPanel = panel
        pillHost = host

        state.isRevealed = !state.autoHide
        if let frame = pillFrame(revealed: state.isRevealed) {
            panel.setFrame(frame, display: true)
        }
        anchorHost()
        panel.orderFrontRegardless()

        let gear = HUDPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: PillMetric.gearDiameter, height: PillMetric.gearDiameter)))
        let gearHost = HUDHostingView(rootView: GearButtonView(onTap: { [weak self] in self?.showMenu() }))
        gearHost.sizingOptions = []
        gearHost.frame = NSRect(origin: .zero, size: gear.frame.size)
        gear.contentView = gearHost
        gear.alphaValue = 0
        gearPanel = gear
        placeGear()
        if !state.autoHide { showGear() }

        installMouseMonitors()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        #if DEBUG
        installDebugHook()
        #endif
        refreshLoginItemStatus()
        HUDLog.hud.info("side pill up, autoHide=\(self.state.autoHide) loginItem=\(LoginItem.statusText, privacy: .public)")
    }

    // The usage poll cadence follows whether any agent is mid-turn.
    private func observeActivity() {
        activityObservation?.cancel()
        activityObservation = Task { [weak self] in
            while let self, !Task.isCancelled {
                let active = self.activity.anyActive
                if active != self.usage.agentsActive {
                    self.usage.agentsActive = active
                    HUDLog.usage.info("agents active=\(active), usage interval \(self.usage.interval)s")
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    #if DEBUG
    // Test hook for driving the state machine without Accessibility rights:
    // post "cloud.acker.devhud.action" with object reveal | conceal | close |
    // select:claude | select:copilot | select:codex | select:servers.
    private func installDebugHook() {
        debugObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("cloud.acker.devhud.action"), object: nil, queue: .main
        ) { [weak self] note in
            let action = note.object as? String ?? ""
            Task { @MainActor in self?.performDebugAction(action) }
        }
    }

    private func performDebugAction(_ action: String) {
        switch action {
        case "reveal": reveal()
        case "conceal": conceal()
        case "close": closeCard()
        case "select:servers": open(.servers)
        case "gear:show": showGear()
        case "hidehour": hideForAnHour()
        case "unhide": unhide()
        case let a where a.hasPrefix("pin:"):
            if let kind = ProviderID(rawValue: String(a.dropFirst(4))),
               let row = state.rows.first(where: { $0.slot?.kind == kind }) { togglePin(row) }
        case "dock:left": setEdge(.left)
        case "dock:right": setEdge(.right)
        case "position:reset": resetPlacement()
        case let a where a.hasPrefix("anchor:"):
            if let value = Double(a.dropFirst(7)) { setAnchor(CGFloat(value)) }
        case let a where a.hasPrefix("screen:"):
            setScreen(name: String(a.dropFirst(7)))
        case "login:on": setLaunchAtLogin(true); NSLog("login item: %@", LoginItem.statusText)
        case "login:off": setLaunchAtLogin(false); NSLog("login item: %@", LoginItem.statusText)
        case "login:status": NSLog("login item: %@ bundle=%@", LoginItem.statusText, Bundle.main.bundlePath)
        case let a where a.hasPrefix("askkill:"):
            if let port = Int(a.dropFirst(8)), let server = ports.servers.first(where: { $0.port == port }) { actions.requestKill(server) }
        case let a where a.hasPrefix("kill:"):
            if let port = Int(a.dropFirst(5)), let server = ports.servers.first(where: { $0.port == port }) { actions.confirmKill(server) }
        case let a where a.hasPrefix("restart:"):
            if let port = Int(a.dropFirst(8)), let server = ports.servers.first(where: { $0.port == port }) { actions.restart(server) }
        case let a where a.hasPrefix("select:"):
            // select:<kind> opens the first slot of that kind.
            if let kind = ProviderID(rawValue: String(a.dropFirst(7))),
               let row = state.rows.first(where: { $0.slot?.kind == kind }) { open(row) }
        default: HUDLog.hud.error("unknown debug action \(action, privacy: .public)")
        }
    }
    #endif

    // MARK: geometry

    // The window never crosses the screen's right edge: concealed, it is
    // `peek` points wide and the rest of the pill is simply not there, so a
    // display arranged to the right never sees a black slab.
    private func pillFrame(revealed: Bool) -> NSRect? {
        guard let screen else { return nil }
        return PillMetric.pillFrame(placement: state.placement, screen: screen.visibleFrame, revealed: revealed, rows: state.rows.count)
    }

    // Keep the pill's inner edge at the window's docked side so the concealed
    // sliver shows the pill's leading part on either edge.
    private func anchorHost() {
        guard let pillHost, let pillPanel else { return }
        pillHost.autoresizingMask = state.placement.edge == .left ? [.minXMargin] : [.maxXMargin]
        let x = state.placement.edge == .left ? pillPanel.frame.width - PillMetric.pillWidth : 0
        pillHost.frame.origin.x = x
    }

    private func reposition(animated: Bool = false) {
        guard let pillPanel, let frame = pillFrame(revealed: state.isRevealed) else { return }
        anchorHost()
        if animated {
            animate(pillPanel, to: frame)
        } else {
            pillPanel.setFrame(frame, display: true)
        }
        if let selection = state.selection { placeCard(for: selection) }
        placeGear()
        // Frames moved under the cursor; resolve again from scratch.
        hoverTarget = .none
        cursorMoved()
    }

    // MARK: placement

    func setEdge(_ edge: PillEdge) {
        dismissCard()
        state.placement.edge = edge
        state.placement.save()
        reposition(animated: true)
    }

    func setAnchor(_ anchor: CGFloat) {
        state.placement.anchor = min(max(anchor, 0), 1)
        state.placement.save()
        reposition(animated: true)
    }

    func setScreen(name: String?) {
        dismissCard()
        state.placement.screenName = name
        state.placement.save()
        reposition(animated: true)
    }

    func resetPlacement() {
        dismissCard()
        state.placement = PillPlacement.defaults
        state.placement.save()
        reposition(animated: true)
    }

    private func apply(_ placement: PillPlacement) {
        state.placement = placement
        placement.save()
        reposition(animated: true)
    }

    private func animate(_ panel: NSPanel, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: hover

    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            Task { @MainActor in self?.cursorMoved() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            Task { @MainActor in
                if event.type == .leftMouseDragged { self?.dragMoved() }
                self?.cursorMoved()
            }
            return event
        }) {
            mouseMonitors.append(local)
        }
        // Clicks on the pill can start a drag; the up event ends it wherever
        // it lands, so it is watched globally as well as locally.
        if let down = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            Task { @MainActor in self?.dragBegan(event) }
            return event
        }) {
            mouseMonitors.append(down)
        }
        if let upLocal = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            Task { @MainActor in self?.dragEnded() }
            return event
        }) {
            mouseMonitors.append(upLocal)
        }
        if let rightClick = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown, handler: { [weak self] event in
            guard let self, event.window === self.pillPanel || event.window === self.gearPanel else { return event }
            Task { @MainActor in self.showMenu() }
            return nil
        }) {
            mouseMonitors.append(rightClick)
        }
        if let upGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged], handler: { [weak self] event in
            Task { @MainActor in
                if event.type == .leftMouseUp { self?.dragEnded() } else { self?.dragMoved() }
            }
        }) {
            mouseMonitors.append(upGlobal)
        }
    }

    // MARK: drag

    private func dragBegan(_ event: NSEvent) {
        guard let pillPanel, event.window === pillPanel else { return }
        let location = NSEvent.mouseLocation
        guard pillPanel.frame.contains(location) else { return }
        drag = (location, pillPanel.frame.origin, false)
    }

    private func dragMoved() {
        guard var drag, let pillPanel else { return }
        let location = NSEvent.mouseLocation
        let dx = location.x - drag.start.x
        let dy = location.y - drag.start.y
        if !drag.moved {
            guard hypot(dx, dy) > 4 else { return }
            drag.moved = true
            concealTask?.cancel()
            closeTask?.cancel()
            dismissCard()
            hideGear()
            if !state.isRevealed, let frame = pillFrame(revealed: true) {
                state.isRevealed = true
                pillPanel.setFrame(frame, display: true)
                anchorHost()
                drag.origin = frame.origin
            }
        }
        self.drag = drag
        var frame = pillPanel.frame
        frame.origin = CGPoint(x: drag.origin.x + dx, y: drag.origin.y + dy)
        pillPanel.setFrame(frame, display: true)
    }

    private func dragEnded() {
        guard let drag else { return }
        self.drag = nil
        guard drag.moved else {
            // A click that did not move: on a ring it pins that ring's card.
            if case .pill(.some(let row)) = HoverResolver.resolve(location: NSEvent.mouseLocation, pillFrame: pillPanel?.frame ?? .zero, cardFrame: nil, rows: state.rows) {
                togglePin(row)
            }
            return
        }
        let location = NSEvent.mouseLocation
        let target = NSScreen.screens.first { $0.frame.contains(location) } ?? screen
        guard let target else { return }
        apply(PillPlacement.snapped(cursor: location, screen: target.frame, screenName: target.localizedName))
    }

    private func cursorMoved() {
        guard let pillPanel, drag?.moved != true else { return }
        let cardFrame = (state.selection != nil) ? cardPanel?.frame : nil
        let gearFrame = (gearPanel?.alphaValue ?? 0) > 0 ? gearPanel?.frame : nil
        let target = HoverResolver.resolve(location: NSEvent.mouseLocation, pillFrame: pillPanel.frame, cardFrame: cardFrame, gearFrame: gearFrame, rows: state.rows)
        guard target != hoverTarget else { return }
        hoverTarget = target
        switch target {
        case .none:
            if state.selection != nil { scheduleClose() }
            scheduleConceal()
            scheduleGearHide()
        case .pill(let item):
            reveal()
            showGear()
            if let item {
                open(item)
            } else if state.selection != nil {
                scheduleClose()
            }
        case .card:
            closeTask?.cancel()
            concealTask?.cancel()
            gearHideTask?.cancel()
        case .gear:
            concealTask?.cancel()
            gearHideTask?.cancel()
            if state.selection != nil { scheduleClose() }
        }
    }

    // MARK: gear

    private func placeGear() {
        guard let gearPanel, let pill = pillFrame(revealed: true) else { return }
        gearPanel.setFrame(PillMetric.gearFrame(belowPill: pill), display: true)
    }

    private func showGear() {
        gearHideTask?.cancel()
        guard let gearPanel else { return }
        placeGear()
        gearPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            gearPanel.animator().alphaValue = 1
        }
    }

    private func hideGear() {
        gearHideTask?.cancel()
        guard let gearPanel, !menuOpen else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            gearPanel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                if self.hoverTarget == .none { gearPanel.orderOut(nil) }
            }
        })
    }

    // The gear fades on the same delay as conceal, even when the pill itself
    // is kept visible.
    private func scheduleGearHide() {
        gearHideTask?.cancel()
        guard hoverTarget == .none, !menuOpen else { return }
        gearHideTask = Task { [weak self] in
            try? await Task.sleep(for: HUDController.concealDelay)
            guard !Task.isCancelled else { return }
            self?.hideGear()
        }
    }

    // MARK: reveal / conceal

    func reveal() {
        if let hiddenUntil, hiddenUntil > Date() { return }
        concealTask?.cancel()
        guard let pillPanel, !state.isRevealed, let frame = pillFrame(revealed: true) else { return }
        state.isRevealed = true
        animate(pillPanel, to: frame)
    }

    func conceal() {
        concealTask?.cancel()
        guard let pillPanel, state.isRevealed, state.autoHide, !menuOpen, let frame = pillFrame(revealed: false) else { return }
        dismissCard()
        hideGear()
        state.isRevealed = false
        animate(pillPanel, to: frame)
    }

    // Conceal only once the cursor has left both the pill and the card.
    private func scheduleConceal() {
        concealTask?.cancel()
        guard state.autoHide, !menuOpen, hoverTarget == .none, pinned == nil else { return }
        concealTask = Task { [weak self] in
            try? await Task.sleep(for: HUDController.concealDelay)
            guard !Task.isCancelled else { return }
            self?.conceal()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
        } catch {
            HUDLog.hud.error("login item: \(error.localizedDescription, privacy: .public)")
        }
        state.launchAtLogin = LoginItem.isEnabled
    }

    func refreshLoginItemStatus() {
        state.launchAtLogin = LoginItem.isEnabled
    }

    func setAutoHide(_ enabled: Bool) {
        state.autoHide = enabled
        if enabled { scheduleConceal(); scheduleGearHide() } else { reveal() }
    }

    // MARK: card

    private func open(_ selection: HUDSelection) {
        closeTask?.cancel()
        reveal()
        // A pinned card stays put while the cursor crosses other rings.
        if let pinned, pinned != selection { return }
        guard state.selection != selection else { return }
        state.selection = selection
        placeCard(for: selection)
    }

    private func scheduleClose() {
        closeTask?.cancel()
        guard pinned == nil else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: HUDController.closeDelay)
            guard !Task.isCancelled, let self else { return }
            if case .pill(.some) = self.hoverTarget { return }
            if self.hoverTarget == .card { return }
            // The `.none` transition already armed conceal; do not restart it.
            self.dismissCard()
        }
    }

    private func placeCard(for selection: HUDSelection) {
        guard let screen, let pill = pillFrame(revealed: true),
              let index = state.rows.firstIndex(of: selection) else { return }
        let ringScreenY = pill.maxY - PillMetric.ringCenterY(index: index)
        // Measure with a throwaway hosting controller (the hosting view reports
        // no size with sizing options off), display in a first-mouse-aware view.
        let provisional = DetailCardView(selection: selection, pointerY: PillMetric.cardPointerInset, pointerEdge: state.placement.edge, usage: usage, ports: ports, actions: actions, activity: activity)
        let size = NSHostingController(rootView: provisional).sizeThatFits(in: CGSize(width: 1000, height: 3000))
        let placement = PillMetric.cardPlacement(
            ringCenterScreenY: ringScreenY,
            cardHeight: size.height,
            screenMinY: screen.frame.minY,
            screenMaxY: screen.frame.maxY
        )
        let content = DetailCardView(selection: selection, pointerY: placement.pointerY, pointerEdge: state.placement.edge, usage: usage, ports: ports, actions: actions, activity: activity)
        let host = cardHost ?? HUDHostingView(rootView: content)
        host.rootView = content
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)

        let panel = cardPanel ?? HUDPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = host
        let x = PillMetric.cardX(edge: state.placement.edge, pill: pill, cardWidth: size.width, screen: screen.frame)
        let y = placement.top - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.alphaValue = cardPanel == nil ? 0 : panel.alphaValue
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        cardPanel = panel
        cardHost = host
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func closeCard() {
        dismissCard()
        scheduleConceal()
    }

    private func dismissCard() {
        closeTask?.cancel()
        state.selection = nil
        guard let cardPanel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            cardPanel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                if self.state.selection == nil { cardPanel.orderOut(nil) }
            }
        })
    }

    // MARK: pin and hide

    // Click a ring to keep its card open; click it again to let go.
    func togglePin(_ selection: HUDSelection) {
        if pinned == selection {
            pinned = nil
            if hoverTarget == .none { closeCard() } else { scheduleClose() }
            return
        }
        pinned = nil
        open(selection)
        pinned = selection
    }

    func hideForAnHour() {
        hiddenUntil = Date().addingTimeInterval(3600)
        pinned = nil
        dismissCard()
        if state.isRevealed, state.autoHide {
            conceal()
        } else if let pillPanel, let frame = pillFrame(revealed: false) {
            state.isRevealed = false
            hideGear()
            animate(pillPanel, to: frame)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3600))
            self?.unhide()
        }
    }

    func unhide() {
        hiddenUntil = nil
        if !state.autoHide { reveal() }
        hoverTarget = .none
        cursorMoved()
    }

    // MARK: menu

    func refresh() {
        usage.refreshNow()
        portless.refresh()
        Task { await ports.sample() }
    }

    // popUp runs a nested event loop, so it is deferred out of the tap
    // action, and the pill stays put while the menu is open.
    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self
        // Checked means the pill stays out; unchecked means it tucks away.
        let keepVisible = NSMenuItem(title: "Keep Pill Visible", action: #selector(toggleKeepVisible), keyEquivalent: "")
        keepVisible.target = self
        keepVisible.state = state.autoHide ? .off : .on
        menu.addItem(keepVisible)
        refreshLoginItemStatus()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = state.launchAtLogin ? .on : .off
        menu.addItem(login)
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let left = NSMenuItem(title: "Dock Left", action: #selector(dockLeft), keyEquivalent: "")
        left.target = self
        left.state = state.placement.edge == .left ? .on : .off
        menu.addItem(left)
        let right = NSMenuItem(title: "Dock Right", action: #selector(dockRight), keyEquivalent: "")
        right.target = self
        right.state = state.placement.edge == .right ? .on : .off
        menu.addItem(right)
        let displays = NSMenu()
        for candidate in NSScreen.screens {
            let item = NSMenuItem(title: candidate.localizedName, action: #selector(pickScreen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.localizedName
            item.state = candidate == screen ? .on : .off
            displays.addItem(item)
        }
        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        displayItem.submenu = displays
        menu.addItem(displayItem)
        let reset = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide for 1 Hour", action: #selector(hideHour), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit devHUD", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        let location = NSEvent.mouseLocation
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: location, in: nil)
        }
    }

    // NSMenu calls its delegate on the main thread; take the isolation
    // synchronously so a due conceal timer cannot slip in between.
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menuOpen = true
            concealTask?.cancel()
        }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menuOpen = false
            hoverTarget = .none
            cursorMoved()
            if hoverTarget == .none {
                scheduleConceal()
                scheduleGearHide()
            }
        }
    }

    @objc private func toggleKeepVisible() { setAutoHide(!state.autoHide) }
    @objc private func hideHour() { hideForAnHour() }
    @objc private func dockLeft() { setEdge(.left) }
    @objc private func dockRight() { setEdge(.right) }
    @objc private func resetPosition() { resetPlacement() }
    @objc private func pickScreen(_ sender: NSMenuItem) { setScreen(name: sender.representedObject as? String) }
    @objc private func toggleLaunchAtLogin() { setLaunchAtLogin(!state.launchAtLogin) }
    @objc private func refreshNow() { refresh() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
