import AppKit

final class StatusMascot: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let context = pixelContext(width: 256, height: 44)
    private var agents: [Agent] = []
    private var game: MenuGame?
    private let memo = FrameMemo()
    private var lastWidth = 0
    var onOpen: ((Int32) -> Void)?

    override init() {
        super.init()
        context?.scaleBy(x: 4, y: 4)
        item.button?.imagePosition = .imageLeft
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        render(frame: 0)
    }

    func update(agents: [Agent]) {
        self.agents = agents
        game = menuGame(agents)
        let title = (game?.extra ?? 0) > 0 ? "+\(game!.extra)" : ""
        if item.button?.title != title { item.button?.title = title }
    }

    func render(frame: Int) {
        guard let g = context else { return }
        g.clear(CGRect(x: 0, y: 0, width: 64, height: 11))
        let pen = Pen(g: g, width: 64, height: 11)
        let width: Int
        if let game {
            pen.menuGame(game, frame: frame)
            width = menuGameWidth(game)
        } else {
            pen.statusMascot(agents.first?.state, frame: frame)
            width = 16
        }
        guard memo.changed(g) || width != lastWidth,
              let image = g.makeImage()?.cropping(to: CGRect(x: 0, y: 0, width: width * 4, height: 44)) else { return }
        lastWidth = width
        item.button?.image = NSImage(cgImage: image, size: NSSize(width: width * 2, height: 22))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if agents.isEmpty { menu.addItem(withTitle: "No agents running", action: nil, keyEquivalent: "") }
        for agent in agents {
            let name = agent.name.count > 40 ? agent.name.prefix(39) + "…" : Substring(agent.name)
            let entry = NSMenuItem(title: "\(name) · \(stateWords[agent.state]!)", action: #selector(open), keyEquivalent: "")
            entry.target = self
            entry.tag = Int(agent.pid)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Widget"
        menu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func open(_ sender: NSMenuItem) {
        guard sender.tag > 0 else { return }
        onOpen?(Int32(sender.tag))
    }
}

extension Pen {
    func statusMascot(_ state: AgentState?, frame f: Int) {
        mini(state ?? .sleeping, x: 2, ground: 11, frame: f, index: 0)
        let gold = hex("#FFD166")
        switch state {
        case .gate?:
            if (f / 4) % 2 == 0 { px(gold, 14, 1, 2, 5); px(gold, 14, 7, 2, 2) }
        case .error?:
            let red = hex("#FF6B6B")
            px(red, 13, 2); px(red, 15, 2); px(red, 14, 3); px(red, 13, 4); px(red, 15, 4)
        case .done?:
            let phase = f % 12
            if phase < 8 { px(gold, 14, 2); if phase > 1 && phase < 6 { px(gold, 13, 2); px(gold, 15, 2); px(gold, 14, 1); px(gold, 14, 3) } }
        case .sleeping?, nil:
            let rise = (f / 6) % 4
            let z = rgba(190, 205, 240, 0.9)
            px(z, 13, 4 - rise, 3, 1); px(z, 14, 5 - rise); px(z, 13, 6 - rise, 3, 1)
        default:
            break
        }
    }
}

extension Pen {
    func menuGame(_ game: MenuGame, frame f: Int) {
        let xs = menuGameXs(game)
        let gold = hex("#FFD166"), ball = hex("#F4F1EA")
        if game.frozen {
            for (i, state) in game.players.enumerated() {
                let jump = state == .gate && f % 2 == 0
                player(xs[i], lifted: jump, frame: state == .gate ? f : 0, index: i)
                if state == .gate { px(gold, xs[i] + 11, jump ? 0 : 1, 2, 5); px(gold, xs[i] + 11, jump ? 6 : 7, 2, 2) }
            }
            return
        }
        guard let throwAt = pass(players: game.players.count, frame: f) else {
            player(xs[0], lifted: false, frame: f, index: 0)
            let up = [2, 1, 0, 0, 1][f % passFrames]
            px(ball, xs[0] + 4, up, 2, 1)
            return
        }
        for i in game.players.indices {
            let lift = (i == throwAt.from && throwAt.step == 0) || (i == throwAt.to && throwAt.step == passFrames - 1) ? 1 : 0
            player(xs[i], lifted: lift == 1, frame: f, index: i)
        }
        let t = Double(throwAt.step) / Double(passFrames - 1)
        let x = Double(xs[throwAt.from]) + Double(xs[throwAt.to] - xs[throwAt.from]) * t + 4
        let y = 2 - 8 * t * (1 - t)
        pxf(ball, x, max(0, y), 2, 1)
    }

    private func player(_ x: Int, lifted: Bool, frame f: Int, index i: Int) {
        mini(.done, x: x, ground: lifted ? 10 : 11, frame: f, index: i)
        if lifted { g.clear(CGRect(x: x - 1, y: 10, width: 12, height: 1)) }
    }
}
