import AppKit

private final class BannerView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

final class Alerts {
    private var tracker = AlertTracker()
    private let size = NSSize(width: 344, height: 80)
    private let panel: NSPanel
    private let art = CALayer()
    private let context = pixelContext(width: 32, height: 48)
    private let memo = FrameMemo()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var state = AgentState.gate
    private var pid: Int32 = 0
    private var frame = 0
    private var hideAt = Date.distantPast
    private var timer: Timer?
    var onOpen: ((Int32) -> Void)?

    init() {
        let rect = NSRect(origin: .zero, size: size)
        panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.colorSpace = .sRGB

        let content = NSView(frame: rect)
        content.wantsLayer = true
        art.magnificationFilter = .nearest
        art.frame = CGRect(x: 12, y: 8, width: 64, height: 64)
        content.layer?.addSublayer(art)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 86, y: 41, width: size.width - 102, height: 18)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 86, y: 21, width: size.width - 102, height: 18)
        content.addSubview(title)
        content.addSubview(detail)

        let host = BannerView(frame: rect)
        host.addSubview(glassBackground(rect, content, radius: 22))
        host.onClick = { [weak self] in
            guard let self else { return }
            if self.pid > 0 { self.onOpen?(self.pid) }
            self.hide()
        }
        panel.contentView = host
    }

    func update(agents: [Agent]) {
        guard let agent = tracker.entered(agents).first else { return }
        show(agent)
    }

    private func show(_ agent: Agent) {
        state = agent.state
        pid = agent.pid
        title.stringValue = agent.name
        detail.stringValue = stateWords[agent.state] ?? ""
        hideAt = Date().addingTimeInterval(6)
        memo.reset()
        render()
        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let target = NSRect(x: area.maxX - size.width - 12, y: area.maxY - size.height - 10, width: size.width, height: size.height)
        if !panel.isVisible {
            panel.setFrame(target.offsetBy(dx: size.width + 24, dy: 0), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        if timer == nil {
            let tick = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.step() }
            tick.tolerance = 0.04
            RunLoop.main.add(tick, forMode: .common)
            timer = tick
        }
    }

    private func step() {
        frame += 1
        render()
        if Date() > hideAt, !NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) { hide() }
    }

    private func render() {
        guard let g = context else { return }
        g.clear(CGRect(x: 0, y: 0, width: 32, height: 48))
        Pen(g: g, width: 32, height: 48).drawIcon(state, frame: frame)
        guard memo.changed(g) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        art.contents = g.makeImage()?.cropping(to: CGRect(x: 0, y: 14, width: 32, height: 32))
        CATransaction.commit()
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        let gone = panel.frame.offsetBy(dx: size.width + 24, dy: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().setFrame(gone, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.timer == nil else { return }
            self.panel.orderOut(nil)
        })
    }
}
