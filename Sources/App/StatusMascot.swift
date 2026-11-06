import AppKit

final class StatusMascot: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let context = pixelContext(width: 64, height: 44)
    private var agents: [Agent] = []
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
        let working = agents.filter { $0.state.rank <= 2 }.count
        item.button?.title = working > 1 ? "\(working)" : ""
    }

    func render(frame: Int) {
        guard let g = context else { return }
        g.clear(CGRect(x: 0, y: 0, width: 16, height: 11))
        Pen(g: g, width: 16, height: 11).statusMascot(agents.first?.state, frame: frame)
        guard let image = g.makeImage() else { return }
        item.button?.image = NSImage(cgImage: image, size: NSSize(width: 32, height: 22))
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
