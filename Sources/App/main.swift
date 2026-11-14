import AppKit
import ServiceManagement

private let sampleNames: [(String, AgentState)] = [
    ("payment-webhooks-and-stripe-retry-logic", .cooking), ("fix-login-bug", .gate), ("dark-mode-ui", .building), ("api-docs", .reading),
    ("landing-page", .done), ("onboarding-flow", .thinking), ("db-migration", .sleeping), ("search-indexer", .error),
    ("image-optimizer", .cooking), ("email-templates", .reading), ("ci-pipeline", .building), ("analytics-dashboard", .done),
    ("billing-page", .building), ("admin-tools", .reading), ("seo-cleanup", .done),
]

private func sampleAgents(_ count: Int) -> [Agent] {
    let forced = argument(after: "--state").flatMap(AgentState.init(rawValue:))
    let jobs: [AgentState] = [.cooking, .building, .reading, .thinking]
    let helpers = (0..<(argument(after: "--helpers").flatMap(Int.init) ?? 0)).map { jobs[$0 % jobs.count] }
    return sortedAgents(sampleNames.prefix(count).enumerated().map { i, item in
        Agent(id: item.0, name: item.0, state: forced ?? item.1, pid: 0, startedAt: Double(i), helpers: helpers)
    })
}

private func argument(after flag: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

private func parentPID(of pid: pid_t) -> pid_t? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    return info.kp_eproc.e_ppid
}

func owningApp(of pid: pid_t) -> NSRunningApplication? {
    var current = pid
    for _ in 0..<32 {
        if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular { return app }
        guard let parent = parentPID(of: current), parent > 1 else { return nil }
        current = parent
    }
    return nil
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let store = SessionStore()
    private let poller = DispatchQueue(label: "agents.poll", qos: .utility, autoreleaseFrequency: .workItem)
    private let demoCount = argument(after: "--demo").flatMap(Int.init)
    private var panel: NSPanel!
    private var host: GlassHost!
    private var outline: PlacementOutline!
    private var pollTimer: Timer?
    private var frameTimer: Timer?
    private var size = WidgetSize.extraLarge
    private var realWidgets: [CGRect] = []
    private var currentSlot: SavedSlot?
    private var dragging = false
    private var moving = false
    private var screensChangedWhileDragging = false
    private var status: StatusMascot!
    private var statusTimer: Timer?
    private var alerts: Alerts?
    private var statusFrame = 0
    private var frameCount = 0
    private var awake = true
    private var polling = false

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for key in ["originX", "originY", "keepOnTop"] { defaults.removeObject(forKey: key) }
        size = defaults.string(forKey: "size").flatMap(WidgetSize.init(rawValue:)) ?? .extraLarge
        let frame = NSRect(origin: .zero, size: size.points)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = widgetLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.colorSpace = .sRGB
        outline = PlacementOutline(below: panel)

        host = GlassHost(size: size)
        panel.contentView = host
        host.interaction.makeMenu = { [weak self] in self?.buildMenu() ?? NSMenu() }
        host.interaction.onClick = { [weak self] point in self?.clicked(point) }
        host.interaction.onDrag = { [weak self] start in self?.drag(from: start) }
        host.interaction.onSwipe = { [weak self] direction in
            guard let self, self.size == .medium else { return }
            self.host.card.step(direction)
        }

        realWidgets = realWidgetFrames()
        let launch = placement(for: size, from: savedSlot)
        panel.setFrame(launch.frame, display: false)
        currentSlot = launch.slot
        if launch.free && launch.remember { savedSlot = launch.slot }
        panel.orderFrontRegardless()

        status = StatusMascot()
        status.onOpen = { pid in owningApp(of: pid)?.activate() }
        if demoCount == nil {
            alerts = Alerts()
            alerts?.onOpen = { pid in owningApp(of: pid)?.activate() }
        }

        fade(for: NSWorkspace.shared.frontmostApplication)
        refresh(animated: false)
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh(animated: true) }
        poll.tolerance = 0.5
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll

        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: NSApplication.didChangeOcclusionStateNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(self, selector: #selector(wentAway), name: name, object: nil)
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(cameBack), name: name, object: nil)
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(wentAway), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(cameBack), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        visibilityChanged()

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc private func wentAway() {
        awake = false
        visibilityChanged()
    }

    @objc private func cameBack() {
        awake = true
        visibilityChanged()
    }

    @objc private func visibilityChanged() {
        let widget = awake && panel.occlusionState.contains(.visible)
        let menuBar = awake && !widget && NSApp.occlusionState.contains(.visible)
        if widget != (frameTimer != nil) {
            frameTimer?.invalidate()
            frameTimer = widget ? repeating(0.1, tolerance: 0.02) { [weak self] in self?.tick() } : nil
            if widget { watchRealWidgets() }
        }
        if menuBar != (statusTimer != nil) {
            statusTimer?.invalidate()
            statusTimer = menuBar ? repeating(0.2, tolerance: 0.04) { [weak self] in self?.renderStatus() } : nil
        }
    }

    private func repeating(_ interval: TimeInterval, tolerance: TimeInterval, _ body: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in body() }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func tick() {
        frameCount += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.tick()
        CATransaction.commit()
        if frameCount % 2 == 0 { renderStatus() }
        if frameCount % 3 == 0 { watchRealWidgets() }
    }

    private func renderStatus() {
        statusFrame += 1
        status.render(frame: statusFrame)
    }

    private func watchRealWidgets() {
        guard !dragging, !moving, let current = currentSlot else { return }
        let taken = realWidgetFrames()
        let displays = currentDisplays()
        guard let next = stepAside(current: current, size: size, displays: displays, taken: taken),
              let grid = displays.first(where: { $0.id == next.display })?.grid else { return }
        realWidgets = taken
        currentSlot = next
        savedSlot = next
        move(to: grid.frame(next.cell, size))
    }

    private func refresh(animated: Bool) {
        if let demoCount {
            let agents = sampleAgents(demoCount)
            host.update(agents: agents, animated: animated)
            status.update(agents: agents)
            return
        }
        guard !polling else { return }
        polling = true
        poller.async { [weak self] in
            guard let self else { return }
            let agents = self.store.snapshot()
            DispatchQueue.main.async {
                self.polling = false
                self.host.update(agents: agents, animated: animated)
                self.status.update(agents: agents)
                self.alerts?.update(agents: agents)
            }
        }
    }

    private func clicked(_ point: NSPoint) {
        let pid: Int32?
        if size == .medium {
            let card = host.card
            card.layoutSubtreeIfNeeded()
            if let index = card.dot(at: card.convert(point, from: host.interaction)) {
                card.select(index: index)
                return
            }
            pid = card.shownPID
        } else {
            pid = host.board.tile(at: host.board.convert(point, from: host.interaction))?.pid
        }
        guard let pid, pid > 0 else { return }
        owningApp(of: pid)?.activate()
    }

    @objc private func appActivated(_ note: Notification) {
        fade(for: note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
    }

    private func fade(for app: NSRunningApplication?) {
        let id = app?.bundleIdentifier
        host.setFaded(id != "com.apple.finder" && (id == nil || id != Bundle.main.bundleIdentifier))
    }

    private var savedSlot: SavedSlot? {
        get {
            guard defaults.object(forKey: "slotDisplay") != nil else { return nil }
            return SavedSlot(display: UInt32(truncatingIfNeeded: defaults.integer(forKey: "slotDisplay")),
                             cell: Cell(column: defaults.integer(forKey: "slotColumn"), row: defaults.integer(forKey: "slotRow")))
        }
        set {
            guard let newValue else { return }
            defaults.set(Int(newValue.display), forKey: "slotDisplay")
            defaults.set(newValue.cell.column, forKey: "slotColumn")
            defaults.set(newValue.cell.row, forKey: "slotRow")
        }
    }

    private func placement(for size: WidgetSize, from start: SavedSlot?) -> (slot: SavedSlot, frame: CGRect, free: Bool, remember: Bool) {
        let displays = currentDisplays()
        let slot = resolvePlacement(saved: start, size: size, displays: displays, taken: realWidgets)
        let grid = displays.first { $0.id == slot.display }?.grid ?? SlotGrid(visibleFrame: .zero)
        return (slot, grid.frame(slot.cell, size), grid.isFree(slot.cell, size, taken: realWidgets), shouldRemember(slot, saved: start, displays: displays))
    }

    private func move(to frame: CGRect) {
        moving = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in self?.moving = false })
    }

    @objc private func screensChanged() {
        if dragging {
            screensChangedWhileDragging = true
            return
        }
        realWidgets = realWidgetFrames()
        let next = placement(for: size, from: savedSlot)
        let lost = !NSScreen.screens.contains { $0.frame.intersects(panel.frame) }
        guard next.free || lost else { return }
        currentSlot = next.slot
        if next.free && next.remember { savedSlot = next.slot }
        move(to: next.frame)
    }

    private func drag(from start: NSPoint) {
        let home = NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.points.height, width: size.points.width, height: size.points.height)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().setFrame(home, display: true)
        }
        dragging = true
        realWidgets = realWidgetFrames()
        var target: (slot: SavedSlot, frame: CGRect)?

        func follow() {
            let mouse = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x: home.minX + mouse.x - start.x, y: home.minY + mouse.y - start.y))
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
            let grid = SlotGrid(visibleFrame: screen.visibleFrame)
            if let cell = grid.nearestFree(toTopLeft: CGPoint(x: panel.frame.minX, y: panel.frame.maxY), size, taken: realWidgets) {
                let slot = (slot: SavedSlot(display: screen.displayID, cell: cell), frame: grid.frame(cell, size))
                target = slot
                outline.show(around: slot.frame)
            } else {
                target = nil
                outline.hide()
            }
        }

        follow()
        while let next = panel.nextLeftMouseEvent(), next.type == .leftMouseDragged { follow() }
        outline.hide()
        dragging = false
        if let target {
            savedSlot = target.slot
            currentSlot = target.slot
        }
        move(to: target?.frame ?? home)
        if screensChangedWhileDragging {
            screensChangedWhileDragging = false
            screensChanged()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "Size"))
        for option in WidgetSize.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(chooseSize), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == size ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let remove = NSMenuItem(title: "Remove Widget", action: #selector(removeWidget), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        return menu
    }

    @objc private func chooseSize(_ item: NSMenuItem) {
        guard let next = (item.representedObject as? String).flatMap(WidgetSize.init(rawValue:)), next != size else { return }
        realWidgets = realWidgetFrames()
        let target = placement(for: next, from: currentSlot)
        guard target.free else { return }
        size = next
        defaults.set(next.rawValue, forKey: "size")
        savedSlot = target.slot
        currentSlot = target.slot
        host.resize(to: next)
        move(to: target.frame)
    }

    @objc private func removeWidget() {
        try? SMAppService.mainApp.unregister()
        NSApp.terminate(nil)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate()
            alert.runModal()
        }
    }
}

private func dumpLiveAgents() -> Never {
    for agent in SessionStore().snapshot() {
        let app = owningApp(of: agent.pid)?.localizedName ?? "no app found"
        print("\(agent.state.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(agent.name)  [pid \(agent.pid), opens \(app)]")
    }
    exit(0)
}

private func snapshot(to path: String, size: WidgetSize, count: Int, frame: Int) -> Never {
    let host = GlassHost(size: size, snapshot: true)
    let rect = host.bounds
    host.update(agents: sampleAgents(count), animated: false)
    host.board.renderTiles(frame: frame)
    host.card.render(frame: frame)
    let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    CATransaction.flush()

    let scale = 2
    let context = CGContext(data: nil, width: Int(rect.width) * scale, height: Int(rect.height) * scale, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.interpolationQuality = .none
    host.layer?.render(in: context)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print("saved \(path)")
    exit(0)
}

if CommandLine.arguments.contains("--dump") { dumpLiveAgents() }

let app = NSApplication.shared
if let path = argument(after: "--snapshot") {
    app.setActivationPolicy(.prohibited)
    snapshot(to: path, size: argument(after: "--size").flatMap { $0 == "xl" ? .extraLarge : WidgetSize(rawValue: $0) } ?? .extraLarge, count: argument(after: "--demo").flatMap(Int.init) ?? 4, frame: argument(after: "--frame").flatMap(Int.init) ?? 7)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
