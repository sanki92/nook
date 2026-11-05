import AppKit
import QuartzCore

private let word: [AgentState: String] = [
    .gate: "Needs you", .cooking: "Cooking", .building: "Building", .reading: "Reading",
    .thinking: "Thinking", .done: "Done", .sleeping: "Resting", .error: "Hit a snag",
]

final class MediumCard: NSView {
    private let face = NSView()
    private let rail = NSView()
    private let tint = CAGradientLayer()
    private let canvas = CALayer()
    private let name = NSTextField(labelWithString: "")
    private let stateWord = NSTextField(labelWithString: "")
    private let context = pixelContext(width: 86, height: 50)
    private var dots: [CALayer] = []
    private var picker = MediumPicker()
    private var agents: [Agent] = []
    private var shown: Agent?
    private var faded = false
    private var frameNumber = 0

    var shownPID: Int32? { shown?.pid }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 26
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        face.wantsLayer = true
        addSubview(face)
        tint.opacity = 0.78
        face.layer?.addSublayer(tint)
        canvas.magnificationFilter = .nearest
        canvas.minificationFilter = .nearest
        face.layer?.addSublayer(canvas)

        name.font = .systemFont(ofSize: 14, weight: .bold)
        name.textColor = .white
        name.lineBreakMode = .byTruncatingTail
        name.maximumNumberOfLines = 1
        name.cell?.truncatesLastVisibleLine = true
        face.addSubview(name)
        face.addSubview(stateWord)
        rail.wantsLayer = true
        addSubview(rail)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        face.frame = bounds
        rail.frame = bounds
        tint.frame = bounds
        canvas.frame = CGRect(x: bounds.width - 12 - 172, y: 6, width: 172, height: 100)
        let nameHeight = name.intrinsicContentSize.height
        name.frame = CGRect(x: 16, y: bounds.height - 12 - nameHeight, width: bounds.width - 56, height: nameHeight)
        stateWord.frame = CGRect(x: 16, y: 12, width: bounds.width - 32, height: stateWord.intrinsicContentSize.height)
        let top = (bounds.height + CGFloat(dots.count) * 9 - 4) / 2
        for (i, dot) in dots.enumerated() {
            dot.frame = CGRect(x: bounds.width - 12, y: top - 5 - CGFloat(i) * 9, width: 5, height: 5)
        }
        CATransaction.commit()
    }

    func update(agents: [Agent], animated: Bool) {
        guard agents != self.agents else { return }
        let previous = shown
        self.agents = agents
        guard let index = picker.current(in: agents) else {
            shown = nil
            layer?.setPulse(false)
            return
        }
        guard animated, let previous, previous.id != agents[index].id else {
            show(index, slide: 0)
            return
        }
        let before = agents.firstIndex { $0.id == previous.id } ?? -1
        show(index, slide: index > before ? 1 : -1)
    }

    func step(_ direction: Int) {
        guard let before = picker.current(in: agents) else { return }
        picker.step(direction, in: agents)
        guard let index = picker.current(in: agents), index != before else { return }
        show(index, slide: direction)
    }

    func dot(at point: NSPoint) -> Int? {
        dots.firstIndex { $0.frame.insetBy(dx: -4, dy: -2).contains(point) }
    }

    func select(index: Int) {
        guard let start = picker.current(in: agents), index != start else { return }
        let direction = index > start ? 1 : -1
        var trial = picker
        var steps = 0
        while trial.current(in: agents) != index {
            guard steps < agents.count else { return }
            trial.step(direction, in: agents)
            steps += 1
        }
        for _ in 0..<steps { step(direction) }
    }

    func setFaded(_ faded: Bool) {
        self.faded = faded
        tint.fade(faded: faded, gate: shown?.state == .gate, animated: true)
    }

    func tick() {
        frameNumber += 1
        render(frame: frameNumber)
    }

    func render(frame: Int) {
        guard let shown, let g = context else { return }
        g.clear(CGRect(x: 0, y: 0, width: 86, height: 50))
        Pen(g: g).draw(shown.state, frame: frame + phase(for: shown.id))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.contents = g.makeImage()
        CATransaction.commit()
    }

    private func show(_ index: Int, slide direction: Int) {
        let agent = agents[index]
        let previous = shown
        shown = agent
        if direction != 0 {
            let push = CATransition()
            push.type = .push
            push.subtype = direction > 0 ? .fromBottom : .fromTop
            push.duration = 0.24
            push.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            face.layer?.add(push, forKey: "slide")
        }
        tint.paint(agent.state)
        tint.fade(faded: faded, gate: agent.state == .gate, animated: previous?.id == agent.id)
        if (previous?.state == .gate) != (agent.state == .gate) { layer?.setPulse(agent.state == .gate) }
        name.stringValue = agent.name
        stateWord.attributedStringValue = NSAttributedString(string: word[agent.state]!, attributes: [
            .font: NSFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: NSColor.white, .kern: -0.65,
        ])
        showDots(current: index)
        render(frame: frameNumber)
    }

    private func showDots(current: Int) {
        let count = agents.count > 1 ? agents.count : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while dots.count > count { dots.removeLast().removeFromSuperlayer() }
        while dots.count < count {
            let dot = CALayer()
            dot.cornerRadius = 2.5
            rail.layer?.addSublayer(dot)
            dots.append(dot)
        }
        for (i, dot) in dots.enumerated() {
            dot.backgroundColor = i == current ? rgba(255, 255, 255, 1) : agents[i].state == .gate ? hex("#FFB84D") : rgba(255, 255, 255, 0.34)
        }
        CATransaction.commit()
        needsLayout = true
    }
}
