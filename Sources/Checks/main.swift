import Foundation

var failures = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "  ok    \(label)" : "  FAIL  \(label)")
    if !condition { failures += 1 }
}

func lines(_ rows: [String]) -> Data { rows.joined(separator: "\n").data(using: .utf8)! }
let prompt = #"{"type":"user","message":{"content":"fix the bug"}}"#
func toolCall(_ name: String) -> String { #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"\#(name)"}]}}"# }
let toolResult = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#
let reply = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Fixed it"}]}}"#
let now = Date()
let justNow = now.timeIntervalSince1970 * 1000

print("Transcript reading")
var s = summarizeTranscript(tail: lines([prompt]), startsMidLine: false)
check(s.lastTool == nil && !s.hasReply, "a new prompt has no tool and no reply")
s = summarizeTranscript(tail: lines([prompt, toolCall("Bash"), toolResult]), startsMidLine: false)
check(s.lastTool == "Bash", "the tool is still known after its result comes back")
s = summarizeTranscript(tail: lines([prompt, toolCall("Read"), toolResult, toolCall("Edit")]), startsMidLine: false)
check(s.lastTool == "Edit", "the newest tool wins")
s = summarizeTranscript(tail: lines([toolCall("Bash"), toolResult, prompt]), startsMidLine: false)
check(s.lastTool == nil, "tools from an earlier turn are ignored")
s = summarizeTranscript(tail: lines([prompt, reply, #"{"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#]), startsMidLine: false)
check(s.interrupted, "an interrupted turn is noticed")
s = summarizeTranscript(tail: lines([prompt, #"{"type":"assistant","isApiErrorMessage":true,"message":{"content":[{"type":"text","text":"Rate limit"}]}}"#]), startsMidLine: false)
check(s.failed, "an API error is noticed")
s = summarizeTranscript(tail: lines([#"{"type":"assistant","isApiErrorMessage":true,"message":{"content":[]}}"#, prompt, reply]), startsMidLine: false)
check(!s.failed, "an old error doesn't count after a later reply")
s = summarizeTranscript(tail: lines([#"m":"cut off"}"#, prompt, reply]), startsMidLine: true)
check(s.hasReply, "a line cut off at the start of the tail is skipped")
s = summarizeTranscript(tail: lines([prompt, #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#]), startsMidLine: false)
check(s.lastTool == nil, "subagent activity is ignored")
s = summarizeTranscript(tail: lines(["not json", prompt, reply]), startsMidLine: false)
check(s.hasReply, "a corrupt line doesn't break anything")

print("State")
func derive(_ status: String?, _ summary: TranscriptSummary, _ updated: Double? = nil) -> AgentState {
    deriveState(status: status, summary: summary, statusUpdatedAt: updated ?? justNow, now: now)
}
check(derive("waiting", TranscriptSummary()) == .gate, "waiting shows the roadblock")
check(derive("busy", TranscriptSummary()) == .thinking, "busy with no tool is thinking")
check(derive("busy", TranscriptSummary(lastTool: "Bash")) == .cooking, "Bash is cooking")
check(derive("busy", TranscriptSummary(lastTool: "Write")) == .building, "Write is building")
check(derive("busy", TranscriptSummary(lastTool: "Grep")) == .reading, "Grep is reading")
check(derive("busy", TranscriptSummary(lastTool: "mcp__x__y")) == .thinking, "an unknown tool is thinking")
check(derive("idle", TranscriptSummary(hasReply: true)) == .done, "a recent finish is done")
check(derive("idle", TranscriptSummary(hasReply: true), justNow - (doneWindow + 1) * 1000) == .sleeping, "an old finish is resting")
check(derive("idle", TranscriptSummary()) == .sleeping, "a session with no reply is resting")
check(derive("idle", TranscriptSummary(hasReply: true, interrupted: true)) == .sleeping, "a declined prompt rests instead of celebrating")
check(derive("idle", TranscriptSummary(hasReply: true, failed: true)) == .error, "a failed turn shows the error")
check(derive(nil, TranscriptSummary()) == .sleeping, "a missing status is resting")
check(derive("something-new", TranscriptSummary()) == .sleeping, "an unknown status is resting")

print("Names")
func record(_ json: String) -> SessionRecord { try! JSONDecoder().decode(SessionRecord.self, from: json.data(using: .utf8)!) }
check(displayName(record: record(#"{"name":"work-37","nameSource":"derived"}"#), aiTitle: "Fix login") == "Fix login", "a generated title beats a derived name")
check(displayName(record: record(#"{"name":"my-name","nameSource":"user"}"#), aiTitle: "Fix login") == "my-name", "a name you gave it beats the title")
check(displayName(record: record(#"{"name":"work-37","nameSource":"derived"}"#), aiTitle: nil) == "work-37", "falls back to the derived name")
check(displayName(record: record(#"{"cwd":"/a/shop-app"}"#), aiTitle: nil) == "shop-app", "falls back to the folder")

print("Order")
func agent(_ id: String, _ state: AgentState, _ started: Double = 0) -> Agent { Agent(id: id, name: id, state: state, pid: 1, startedAt: started) }
let order = sortedAgents([agent("a", .sleeping), agent("b", .done), agent("c", .cooking), agent("d", .error), agent("e", .gate)]).map(\.id)
check(order == ["e", "d", "c", "b", "a"], "needs you, error, working, done, resting")
check(sortedAgents([agent("new", .cooking, 2), agent("old", .reading, 1)]).map(\.id) == ["old", "new"], "working agents keep a stable order")

print("Layout")
for size in [WidgetSize.large, .extraLarge] {
    for count in 1...size.maxTiles {
        let rects = tileRects(count: count, size: size)
        check(rects.count == count, "\(size.title): \(count) agents get \(count) tiles")
        let bounds = CGRect(origin: .zero, size: size.points).insetBy(dx: -0.01, dy: -0.01)
        check(rects.allSatisfy { bounds.contains($0) }, "\(size.title): \(count) stay inside")
        var overlaps = false
        for i in rects.indices { for j in rects.indices where i < j && rects[i].insetBy(dx: 0.01, dy: 0.01).intersects(rects[j]) { overlaps = true } }
        check(!overlaps, "\(size.title): \(count) don't overlap")
    }
}
check(WidgetSize.medium.points == CGSize(width: 344, height: 164), "Medium is 344×164")
check(WidgetSize.large.points == CGSize(width: 344, height: 344), "Large is 344×344")
check(WidgetSize.extraLarge.points == CGSize(width: 704, height: 344), "Extra Large is 704×344")
check(tileRects(count: 1, size: .large) == [CGRect(x: 0, y: 0, width: 344, height: 344)], "one agent fills the widget")
let two = tileRects(count: 2, size: .large)
check(two[0].minX == two[1].minX && two[1].minY > two[0].maxY, "2 agents on Large stack top and bottom")
let three = tileRects(count: 3, size: .large)
check(three[0].width > three[1].width && three[1].minY == three[2].minY, "3 on Large: one wide tile on top, two below")
check(tileRects(count: 3, size: .extraLarge)[0].height > tileRects(count: 3, size: .extraLarge)[1].height, "3 on Extra Large: one tall tile plus two")
check(tileRects(count: 2, size: .large)[0].minX == 6, "tiles have a 6pt inset")
check(tileGeometry(size: CGSize(width: 157, height: 200)).compact, "narrower than 158 is compact")
check(tileGeometry(size: CGSize(width: 200, height: 113)).compact, "shorter than 114 is compact")
check(!tileGeometry(size: tileRects(count: 4, size: .large)[0].size).compact, "4 on Large keep full scenes")
check(tileGeometry(size: tileRects(count: 1, size: .extraLarge)[0].size).pixel == 5, "1 agent on Extra Large gets the biggest art")

print("Reading session files")
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("widget-checks-\(UUID().uuidString)")
let sessions = tmp.appendingPathComponent("sessions"), project = tmp.appendingPathComponent("projects/p")
try! FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }
func writeSession(_ pid: Int32, _ id: String, _ status: String, extra: String = "") {
    let json = #"{"pid":\#(pid),"sessionId":"\#(id)","cwd":"/x/app","name":"app-1","nameSource":"derived","status":"\#(status)","startedAt":\#(pid),"statusUpdatedAt":\#(justNow)\#(extra)}"#
    try! json.write(to: sessions.appendingPathComponent("\(pid).json"), atomically: true, encoding: .utf8)
}
writeSession(1, "alive", "waiting", extra: #","waitingFor":"permission prompt""#)
writeSession(2, "dead", "busy")
writeSession(3, "working", "busy")
try! "not json".write(to: sessions.appendingPathComponent("4.json"), atomically: true, encoding: .utf8)
try! "secret".write(to: sessions.appendingPathComponent("3.key"), atomically: true, encoding: .utf8)
try! lines([#"{"type":"ai-title","aiTitle":"Add payments"}"#, prompt, toolCall("Edit")]).write(to: project.appendingPathComponent("working.jsonl"))
let store = SessionStore(root: tmp, alive: { $0 != 2 })
let found = store.snapshot()
check(found.map(\.id) == ["alive", "working"], "dead sessions and unreadable files are left out")
check(found.first?.state == .gate, "a waiting session shows the roadblock")
check(found.last?.state == .building, "the transcript decides the activity")
check(found.last?.name == "Add payments", "the title comes from the transcript")
check(found.first?.name == "app-1", "a session with no transcript keeps its own name")
check(SessionStore(root: tmp.appendingPathComponent("missing")).snapshot().isEmpty, "no sessions folder means no agents")

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
