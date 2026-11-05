import AppKit
import QuartzCore

private let tileColors: [AgentState: (String, String)] = [
    .thinking: ("#232A58", "#31386E"),
    .cooking: ("#2A1B18", "#5A2B1A"),
    .building: ("#262A33", "#454B58"),
    .reading: ("#14303C", "#1F4F5E"),
    .gate: ("#B9600D", "#7C2F0B"),
    .done: ("#123D30", "#1B6A4D"),
    .sleeping: ("#0F1428", "#191F3A"),
    .error: ("#3D1519", "#651F24"),
]

private func topToBottom(_ layer: CAGradientLayer, _ top: CGColor, _ bottom: CGColor) {
    layer.colors = [top, bottom]
    layer.startPoint = CGPoint(x: 0.5, y: 1)
    layer.endPoint = CGPoint(x: 0.5, y: 0)
}

final class TileView: NSView {
    enum Content: Equatable { case agent(AgentState), noAgents }

    private let canvas = CALayer()
    private let tint = CAGradientLayer()
    private let label = NSTextField(labelWithString: "")
    private let moreBadge = NSTextField(labelWithString: "")
    private var context: CGContext?
    private var geometry = TileGeometry(pixel: 2, compact: false, canvasWidth: 1, canvasHeight: 1, offsetX: 0, offsetY: 0, nameFontSize: 14, nameBottom: 7)
    private var content = Content.noAgents
    var pid: Int32?
    var phase = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let root = layer else { return }
        root.cornerCurve = .continuous
        root.masksToBounds = true

        tint.frame = bounds
        tint.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        tint.opacity = 0.78
        root.addSublayer(tint)

        canvas.magnificationFilter = .nearest
        canvas.minificationFilter = .nearest
        root.addSublayer(canvas)

        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        addSubview(label)

        moreBadge.font = .systemFont(ofSize: 10.5, weight: .bold)
        moreBadge.textColor = .white
        moreBadge.drawsBackground = true
        moreBadge.backgroundColor = NSColor.black.withAlphaComponent(0.45)
        moreBadge.wantsLayer = true
        moreBadge.layer?.cornerRadius = 4
        moreBadge.isHidden = true
        addSubview(moreBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(content: Content, name: String, pid: Int32?, size: CGSize, cornerRadius: CGFloat, campfirePixel: Int, extra: Int) {
        self.pid = pid
        var geo = tileGeometry(size: size)
        if content == .noAgents {
            let p = CGFloat(campfirePixel), tall = size.height > 200
            geo = TileGeometry(pixel: campfirePixel, compact: false, canvasWidth: Int((size.width / p).rounded(.up)), canvasHeight: Int((size.height / p).rounded(.up)), offsetX: 0, offsetY: 0, nameFontSize: tall ? 19 : 15, nameBottom: tall ? 14 : 8)
        }
        let contentChanged = content != self.content
        self.content = content

        if geo != geometry || context == nil {
            geometry = geo
            context = CGContext(data: nil, width: geo.canvasWidth, height: geo.canvasHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.translateBy(x: 0, y: CGFloat(geo.canvasHeight))
            context?.scaleBy(x: 1, y: -1)
            context?.setShouldAntialias(false)
        }

        layer?.cornerRadius = cornerRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let canvasSize = CGSize(width: geo.canvasWidth * geo.pixel, height: geo.canvasHeight * geo.pixel)
        canvas.frame = CGRect(x: (size.width - canvasSize.width) / 2, y: size.height - canvasSize.height, width: canvasSize.width, height: canvasSize.height)
        CATransaction.commit()

        let state: AgentState
        if case .agent(let s) = content { state = s } else { state = .sleeping }
        let colors = tileColors[state]!
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topToBottom(tint, hex(colors.0), hex(colors.1))
        CATransaction.commit()
        if contentChanged { setPulse(state == .gate) }

        label.stringValue = name
        label.font = .systemFont(ofSize: geo.nameFontSize, weight: .bold)
        let lineHeight = ceil(geo.nameFontSize * 1.3)
        label.frame = CGRect(x: 13, y: geo.nameBottom, width: size.width - 26, height: lineHeight)

        moreBadge.isHidden = extra == 0
        if extra > 0 {
            moreBadge.stringValue = " +\(extra) more "
            moreBadge.sizeToFit()
            moreBadge.frame.origin = CGPoint(x: size.width - moreBadge.frame.width - 7, y: size.height - moreBadge.frame.height - 7)
        }
    }

    func setFaded(_ faded: Bool) {
        let target: Float = faded ? (content == .agent(.gate) ? 0.66 : 0.10) : 0.78
        guard tint.opacity != target else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = tint.presentation()?.opacity ?? tint.opacity
        fade.toValue = target
        fade.duration = 0.3
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tint.opacity = target
        tint.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    private func setPulse(_ on: Bool) {
        guard let root = layer else { return }
        root.removeAnimation(forKey: "pulse")
        root.removeAnimation(forKey: "pulse-color")
        guard on else {
            root.borderWidth = 0
            return
        }
        root.borderWidth = 1
        root.borderColor = rgba(255, 214, 140, 0.45)
        let width = CAKeyframeAnimation(keyPath: "borderWidth")
        width.values = [1, 1.3, 1.7, 2, 1.7, 1.3]
        width.calculationMode = .discrete
        width.duration = 1.6
        width.repeatCount = .infinity
        width.isRemovedOnCompletion = false
        root.add(width, forKey: "pulse")
        let color = CAKeyframeAnimation(keyPath: "borderColor")
        color.values = [0.45, 0.6, 0.8, 0.95, 0.8, 0.6].map { rgba(255, 214, 140, $0) }
        color.calculationMode = .discrete
        color.duration = 1.6
        color.repeatCount = .infinity
        color.isRemovedOnCompletion = false
        root.add(color, forKey: "pulse-color")
    }

    func render(frame: Int) {
        guard let g = context else { return }
        let f = frame + phase
        g.clear(CGRect(x: 0, y: 0, width: geometry.canvasWidth, height: geometry.canvasHeight))
        g.saveGState()
        g.translateBy(x: CGFloat(geometry.offsetX), y: CGFloat(geometry.offsetY))
        let pen = Pen(g: g, extraX: max(0, geometry.offsetX), extraY: max(0, geometry.offsetY), width: geometry.canvasWidth, height: geometry.canvasHeight)
        switch content {
        case .noAgents: pen.campfire(frame: f)
        case .agent(let state):
            if geometry.compact { pen.drawIcon(state, frame: f) } else { pen.draw(state, frame: f) }
        }
        g.restoreGState()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.contents = g.makeImage()
        CATransaction.commit()
    }
}

final class InteractionView: NSView {
    var onClick: ((NSPoint) -> Void)?
    var makeMenu: (() -> NSMenu)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { showMenu(event); return }
        guard let window else { return }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp {
                onClick?(convert(next.locationInWindow, from: nil))
                return
            }
            let moved = hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y)
            if moved > 3 {
                window.performDrag(with: event)
                return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) { showMenu(event) }

    private func showMenu(_ event: NSEvent) {
        guard let menu = makeMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class BoardView: NSView {
    private var tiles: [String: TileView] = [:]
    private var shown: [Agent]?
    private var laidOutSize: WidgetSize?
    private let overlay = InteractionView()
    private let noAgentsID = "__none"
    private var frameNumber = 0
    private var faded = false

    var interaction: InteractionView { overlay }
    var size = WidgetSize.extraLarge {
        didSet { if let shown, size != oldValue { update(agents: shown, animated: true) } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func update(agents: [Agent], animated: Bool) {
        if shown == agents && laidOutSize == size { return }
        let first = shown == nil
        shown = agents
        laidOutSize = size

        let visible = Array(agents.prefix(size.maxTiles))
        let extra = agents.count - visible.count
        let rects = tileRects(count: visible.count, size: size)
        let height = size.points.height
        let cornerRadius: CGFloat = visible.count > 1 ? 20 : 26
        let campfirePixel: Int
        switch size {
        case .extraLarge: campfirePixel = 4
        case .large: campfirePixel = 3
        case .medium: campfirePixel = 2
        }
        func flipped(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height) }

        var ids: [String] = []
        var work: [(TileView, CGRect, Bool)] = []
        func place(id: String, content: TileView.Content, name: String, pid: Int32?, rect: CGRect, extra: Int) {
            ids.append(id)
            let target = flipped(rect)
            var isNew = false
            let tile: TileView
            if let existing = tiles[id] {
                tile = existing
            } else {
                tile = TileView(frame: target)
                tile.phase = id.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF } % 500
                tile.alphaValue = animated && !first ? 0 : 1
                tiles[id] = tile
                addSubview(tile, positioned: .below, relativeTo: overlay)
                isNew = true
            }
            tile.configure(content: content, name: name, pid: pid, size: target.size, cornerRadius: cornerRadius, campfirePixel: campfirePixel, extra: extra)
            tile.setFaded(faded)
            work.append((tile, target, isNew))
        }

        if visible.isEmpty {
            place(id: noAgentsID, content: .noAgents, name: "No agents running", pid: nil, rect: rects[0], extra: 0)
        } else {
            for (i, agent) in visible.enumerated() {
                place(id: agent.id, content: .agent(agent.state), name: agent.name, pid: agent.pid, rect: rects[i], extra: i == visible.count - 1 ? extra : 0)
            }
        }

        for id in tiles.keys where !ids.contains(id) {
            tiles[id]?.removeFromSuperview()
            tiles[id] = nil
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated && !first ? 0.38 : 0
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            ctx.allowsImplicitAnimation = true
            for (tile, target, isNew) in work {
                if isNew { tile.animator().alphaValue = 1 } else { tile.animator().frame = target }
            }
        }
        renderTiles()
    }

    func setFaded(_ faded: Bool) {
        self.faded = faded
        for tile in tiles.values { tile.setFaded(faded) }
    }

    func tick() {
        frameNumber += 1
        renderTiles()
    }

    func renderTiles(frame: Int? = nil) {
        let f = frame ?? frameNumber
        for tile in tiles.values { tile.render(frame: f) }
    }

    func tile(at point: NSPoint) -> TileView? {
        tiles.values.first { $0.frame.contains(point) }
    }
}

final class GlassHost: NSView {
    let board: BoardView

    init(size: WidgetSize, snapshot: Bool = false) {
        let rect = NSRect(origin: .zero, size: size.points)
        board = BoardView(frame: rect)
        super.init(frame: rect)
        board.size = size
        board.autoresizingMask = [.width, .height]
        wantsLayer = true
        if snapshot {
            layer?.backgroundColor = hex("#1B1E28")
            layer?.cornerRadius = 26
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
            addSubview(board)
        } else if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: rect)
            glass.cornerRadius = 26
            glass.autoresizingMask = [.width, .height]
            glass.contentView = board
            addSubview(glass)
        } else {
            let effect = NSVisualEffectView(frame: rect)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            let mask = NSImage(size: NSSize(width: 53, height: 53), flipped: false) { bounds in
                NSBezierPath(roundedRect: bounds, xRadius: 26, yRadius: 26).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: 26, left: 26, bottom: 26, right: 26)
            mask.resizingMode = .stretch
            effect.maskImage = mask
            effect.autoresizingMask = [.width, .height]
            effect.addSubview(board)
            addSubview(effect)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func resize(to size: WidgetSize) {
        setFrameSize(size.points)
        board.size = size
    }
}
