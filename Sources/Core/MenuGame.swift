import Foundation

let menuGameMax = 4
let passFrames = 5

struct MenuGame: Equatable {
    let players: [AgentState]
    let extra: Int
    var frozen: Bool { players.contains(.gate) }
}

func menuGame(_ agents: [Agent]) -> MenuGame? {
    let playing = sortedAgents(agents).map(\.state).filter { $0 == .gate || $0.rank == 2 }
    guard !playing.isEmpty else { return nil }
    return MenuGame(players: Array(playing.prefix(menuGameMax)), extra: max(0, playing.count - menuGameMax))
}

func menuGameXs(_ game: MenuGame) -> [Int] {
    var x = 1
    return game.players.map { state in
        defer { x += 12 + (state == .gate ? 3 : 0) }
        return x
    }
}

func menuGameWidth(_ game: MenuGame) -> Int {
    guard let last = menuGameXs(game).last else { return 0 }
    return last + 11 + (game.players.last == .gate ? 2 : 0)
}

struct Pass: Equatable {
    let from: Int
    let to: Int
    let step: Int
}

func pass(players n: Int, frame f: Int) -> Pass? {
    guard n > 1 else { return nil }
    let k = (max(0, f) / passFrames) % (2 * (n - 1))
    let from = k < n - 1 ? k : 2 * (n - 1) - k
    return Pass(from: from, to: k < n - 1 ? from + 1 : from - 1, step: max(0, f) % passFrames)
}

struct AlertTracker {
    private var last: [String: AgentState]?

    mutating func entered(_ agents: [Agent]) -> [Agent] {
        defer { last = Dictionary(agents.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first }) }
        guard let last else { return [] }
        return agents.filter { ($0.state == .gate || $0.state == .error) && last[$0.id] != $0.state }
    }
}
