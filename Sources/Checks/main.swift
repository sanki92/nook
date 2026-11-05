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
for count in 0...12 {
    let rects = tileRects(count: count)
    check(rects.count == max(count, 1), "\(count) agents get \(max(count, 1)) tiles")
    let bounds = CGRect(origin: .zero, size: WidgetMetrics.size).insetBy(dx: WidgetMetrics.inset - 0.01, dy: WidgetMetrics.inset - 0.01)
    check(rects.allSatisfy { bounds.contains($0) }, "\(count) agents stay inside the widget")
    var overlaps = false
    for i in rects.indices { for j in rects.indices where i < j && rects[i].insetBy(dx: 0.01, dy: 0.01).intersects(rects[j]) { overlaps = true } }
    check(!overlaps, "\(count) agents don't overlap")
    let area = rects.reduce(0) { $0 + $1.width * $1.height }
    check(area > 0.8 * (684 * 324), "\(count) agents fill the space")
}
check(tileRects(count: 3)[0].height > tileRects(count: 3)[1].height, "the first of 3 tiles is the biggest")
check(tileGeometry(size: tileRects(count: 1)[0].size, tileCount: 1).pixel == 5, "1 agent gets the biggest art")
check(tileGeometry(size: tileRects(count: 4)[0].size, tileCount: 4).pixel == 3, "4 agents get medium art")
check(tileGeometry(size: tileRects(count: 8)[0].size, tileCount: 8).pixel == 2, "8 agents get small art")
check(tileGeometry(size: tileRects(count: 9)[0].size, tileCount: 9).compact, "9 agents switch to compact")

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
