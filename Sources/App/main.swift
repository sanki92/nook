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
    return sortedAgents(sampleNames.prefix(count).enumerated().map { i, item in
        Agent(id: item.0, name: item.0, state: forced ?? item.1, pid: 0, startedAt: Double(i))
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let defaults = UserDefaults.standard
    private let store = SessionStore()
    private let poller = DispatchQueue(label: "agents.poll", qos: .utility)
    private let demoCount = argument(after: "--demo").flatMap(Int.init)
    private var panel: NSPanel!
    private var host: GlassHost!
    private var pollTimer: Timer?
    private var frameTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let frame = NSRect(origin: .zero, size: WidgetSize.extraLarge.points)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        applyLevel()

        host = GlassHost(size: .extraLarge)
        panel.contentView = host
        host.interaction.makeMenu = { [weak self] in self?.buildMenu() ?? NSMenu() }
        host.interaction.onClick = { [weak self] point in self?.clicked(point) }

        restorePosition()
        panel.orderFrontRegardless()

        refresh(animated: false)
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh(animated: true) }
        poll.tolerance = 0.2
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll

        let frames = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        frames.tolerance = 0.01
        RunLoop.main.add(frames, forMode: .common)
        frameTimer = frames

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func tick() {
        guard panel.occlusionState.contains(.visible) else { return }
        host.tick()
    }

    private func refresh(animated: Bool) {
        if let demoCount {
            host.update(agents: sampleAgents(demoCount), animated: animated)
            return
        }
        poller.async { [weak self] in
            guard let self else { return }
            let agents = self.store.snapshot()
            DispatchQueue.main.async { self.host.update(agents: agents, animated: animated) }
        }
    }

    private func clicked(_ point: NSPoint) {
        guard let pid = host.board.tile(at: point)?.pid, pid > 0 else { return }
        owningApp(of: pid)?.activate()
    }

    private var keepOnTop: Bool {
        get { defaults.bool(forKey: "keepOnTop") }
        set { defaults.set(newValue, forKey: "keepOnTop") }
    }

    private func applyLevel() {
        if keepOnTop {
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        } else {
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }

    private func restorePosition() {
        if defaults.object(forKey: "originX") != nil {
            panel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "originX"), y: defaults.double(forKey: "originY")))
        } else {
            placeAtDefault()
        }
        keepOnScreen()
    }

    private func placeAtDefault() {
        guard let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: area.maxX - panel.frame.width - 24, y: area.maxY - panel.frame.height - 24))
    }

    private func keepOnScreen() {
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersection(panel.frame).width > 80 && $0.visibleFrame.intersection(panel.frame).height > 80 }
        if !onScreen { placeAtDefault() }
    }

    @objc private func screensChanged() { keepOnScreen() }

    func windowDidMove(_ note: Notification) {
        defaults.set(panel.frame.origin.x, forKey: "originX")
        defaults.set(panel.frame.origin.y, forKey: "originY")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let top = NSMenuItem(title: "Keep on Top", action: #selector(toggleTop), keyEquivalent: "")
        top.target = self
        top.state = keepOnTop ? .on : .off
        menu.addItem(top)
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Claude Agents", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleTop() {
        keepOnTop.toggle()
        applyLevel()
        panel.orderFrontRegardless()
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
    snapshot(to: path, size: argument(after: "--size").flatMap(WidgetSize.init(rawValue:)) ?? .extraLarge, count: argument(after: "--demo").flatMap(Int.init) ?? 4, frame: argument(after: "--frame").flatMap(Int.init) ?? 7)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
