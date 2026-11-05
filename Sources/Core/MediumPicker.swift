struct MediumPicker {
    private(set) var chosen: String?
    private(set) var waitingChoice: String?

    mutating func current(in agents: [Agent]) -> Int? {
        guard !agents.isEmpty else { return nil }
        let waiting = agents.indices.filter { agents[$0].state == .gate }
        if !waiting.isEmpty {
            if let id = waitingChoice, let index = waiting.first(where: { agents[$0].id == id }) {
                return index
            }
            waitingChoice = agents[waiting[0]].id
            return waiting[0]
        }
        waitingChoice = nil
        if let id = chosen, let index = agents.firstIndex(where: { $0.id == id }) {
            return index
        }
        chosen = nil
        return 0
    }

    mutating func step(_ direction: Int, in agents: [Agent]) {
        guard let index = current(in: agents) else { return }
        let waiting = agents.indices.filter { agents[$0].state == .gate }
        if waiting.isEmpty {
            guard agents.count > 1 else { return }
            chosen = agents[(index + direction + agents.count) % agents.count].id
        } else {
            guard waiting.count > 1, let position = waiting.firstIndex(of: index) else { return }
            waitingChoice = agents[waiting[(position + direction + waiting.count) % waiting.count]].id
        }
    }
}
