import Foundation

enum AgentState: String {
    case gate, error, thinking, cooking, building, reading, delegating, done, sleeping

    var rank: Int {
        switch self {
        case .gate: return 0
        case .error: return 1
        case .thinking, .cooking, .building, .reading, .delegating: return 2
        case .done: return 3
        case .sleeping: return 4
        }
    }
}

struct Agent: Equatable {
    let id: String
    let name: String
    let state: AgentState
    let pid: Int32
    let startedAt: Double
    var helpers: [AgentState] = []
}

func sortedAgents(_ agents: [Agent]) -> [Agent] {
    agents.sorted {
        if $0.state.rank != $1.state.rank { return $0.state.rank < $1.state.rank }
        if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
        return $0.id < $1.id
    }
}

struct SessionRecord: Decodable {
    let pid: Int32?
    let sessionId: String?
    let cwd: String?
    let name: String?
    let nameSource: String?
    let status: String?
    let waitingFor: String?
    let startedAt: Double?
    let statusUpdatedAt: Double?
}

struct TranscriptSummary: Equatable {
    var lastTool: String?
    var hasReply = false
    var failed = false
    var interrupted = false
}

let doneWindow: TimeInterval = 10 * 60

func state(for tool: String?) -> AgentState {
    switch tool {
    case "Bash", "BashOutput", "KillShell", "PowerShell", "Monitor":
        return .cooking
    case "Edit", "Write", "MultiEdit", "NotebookEdit":
        return .building
    case "Read", "Grep", "Glob", "LS", "WebFetch", "WebSearch", "ToolSearch":
        return .reading
    default:
        return .thinking
    }
}

func deriveState(status: String?, summary: TranscriptSummary, statusUpdatedAt: Double?, helperCount: Int = 0, now: Date) -> AgentState {
    switch status {
    case "waiting":
        return .gate
    case "busy":
        return state(for: summary.lastTool)
    case "idle":
        if summary.failed { return .error }
        if helperCount > 0 { return .delegating }
        if summary.interrupted || !summary.hasReply { return .sleeping }
        guard let updated = statusUpdatedAt else { return .sleeping }
        return now.timeIntervalSince1970 - updated / 1000 < doneWindow ? .done : .sleeping
    default:
        return .sleeping
    }
}

func displayName(record: SessionRecord, aiTitle: String?) -> String {
    if let name = record.name, !name.isEmpty, let source = record.nameSource, source != "derived" {
        return name
    }
    if let aiTitle, !aiTitle.isEmpty { return aiTitle }
    if let name = record.name, !name.isEmpty { return name }
    if let cwd = record.cwd { return (cwd as NSString).lastPathComponent }
    return "Claude session"
}

func summarizeTranscript(tail: Data, startsMidLine: Bool, includeSidechain: Bool = false) -> TranscriptSummary {
    var summary = TranscriptSummary()
    var lines = tail.split(separator: 0x0A, omittingEmptySubsequences: true)
    if startsMidLine, !lines.isEmpty { lines.removeFirst() }

    var seenMessage = false
    for line in lines.reversed() {
        guard let entry = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
              includeSidechain || (entry["isSidechain"] as? Bool) != true else { continue }

        switch entry["type"] as? String {
        case "assistant":
            let isLast = !seenMessage
            seenMessage = true
            if isLast, (entry["isApiErrorMessage"] as? Bool) == true { summary.failed = true }
            summary.hasReply = true
            let blocks = (entry["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            if summary.lastTool == nil,
               let tool = blocks.last(where: { $0["type"] as? String == "tool_use" })?["name"] as? String {
                summary.lastTool = tool
            }
        case "user":
            if (entry["isMeta"] as? Bool) == true { continue }
            let content = (entry["message"] as? [String: Any])?["content"]
            var text = content as? String ?? ""
            var hasToolResult = false
            for block in content as? [[String: Any]] ?? [] {
                if block["type"] as? String == "tool_result" { hasToolResult = true }
                if block["type"] as? String == "text" { text += block["text"] as? String ?? "" }
            }
            let isInterruptMarker = text.contains("[Request interrupted by user")
            if !seenMessage {
                seenMessage = true
                if isInterruptMarker { summary.interrupted = true }
            }
            if !hasToolResult, !isInterruptMarker, !text.isEmpty { return summary }
        case "system":
            if !seenMessage, entry["subtype"] as? String == "api_error" { summary.failed = true }
        default:
            continue
        }
    }
    return summary
}

func findAITitle(in url: URL, from start: UInt64 = 0, to end: UInt64? = nil) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    let marker = Data("\"ai-title\"".utf8), newline = Data([0x0A])
    let chunk: UInt64 = 4_000_000, overlap: UInt64 = 65_536
    let stop = end ?? ((try? handle.seekToEnd()) ?? 0)
    var upper = stop
    while upper > start {
        let lower = upper > start + chunk ? upper - chunk : start
        let from = lower > overlap ? lower - overlap : 0
        guard (try? handle.seek(toOffset: from)) != nil,
              let data = try? handle.read(upToCount: Int(min(upper + overlap, stop) - from)) else { return nil }
        var searchEnd = data.endIndex
        while let hit = data.range(of: marker, options: .backwards, in: data.startIndex..<searchEnd) {
            searchEnd = hit.lowerBound
            guard let open = data.range(of: newline, options: .backwards, in: data.startIndex..<hit.lowerBound)?.upperBound ?? (from == 0 ? data.startIndex : nil),
                  let close = data.range(of: newline, in: hit.upperBound..<data.endIndex)?.lowerBound ?? (from + UInt64(data.count) == stop ? data.endIndex : nil),
                  let entry = (try? JSONSerialization.jsonObject(with: data.subdata(in: open..<close))) as? [String: Any],
                  let title = entry["aiTitle"] as? String else { continue }
            return title
        }
        upper = lower
    }
    return nil
}
