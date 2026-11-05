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
func rowShape(_ rects: [CGRect]) -> [Int] { Dictionary(grouping: rects, by: \.minY).sorted { $0.key < $1.key }.map(\.value.count) }
let largeShapes: [Int: [Int]] = [4: [2, 2], 5: [2, 3], 6: [3, 3], 7: [2, 2, 3], 8: [2, 3, 3], 9: [3, 3, 3]]
for (count, shape) in largeShapes.sorted(by: { $0.key < $1.key }) {
    check(rowShape(tileRects(count: count, size: .large)) == shape, "\(count) on Large sit in rows of \(shape.map(String.init).joined(separator: "-"))")
}
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

print("Grid")
let mainGrid = SlotGrid(visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 923))
check(mainGrid.columns == 8 && mainGrid.rows == 5, "this Mac's screen has 8 × 5 slots")
check(mainGrid.frame(Cell(column: 0, row: 0), .medium) == CGRect(x: 16, y: 923 - 16 - 164, width: 344, height: 164), "slot 0,0 matches Apple's widget position")
let calendar = CGRect(x: 8, y: 923 - 8 - 180, width: 180, height: 180)
let weather = CGRect(x: 188, y: 923 - 8 - 180, width: 180, height: 180)
check(!mainGrid.isFree(Cell(column: 0, row: 0), .large, taken: [calendar]), "a slot under a real widget is taken")
check(mainGrid.isFree(Cell(column: 0, row: 1), .extraLarge, taken: [calendar, weather]), "the row below real widgets is free")
check(!mainGrid.isFree(Cell(column: 6, row: 0), .extraLarge, taken: []), "a size that runs off the edge isn't free")
check(!mainGrid.isFree(Cell(column: 2, row: 0), .medium, taken: [CGRect(x: 380, y: 800, width: 60, height: 60)]), "a widget touching part of a slot makes it taken")
let near = mainGrid.nearestFree(toTopLeft: CGPoint(x: 20, y: 900), .extraLarge, taken: [calendar, weather])
check(near == Cell(column: 0, row: 1), "dropping near the top-left lands below the real widgets")
let external = Display(id: 2, grid: SlotGrid(visibleFrame: CGRect(x: 1470, y: 0, width: 1920, height: 1050)), isMain: false)
let main = Display(id: 1, grid: mainGrid, isMain: true)
let kept = resolvePlacement(saved: SavedSlot(display: 2, cell: Cell(column: 3, row: 2)), size: .large, displays: [main, external], taken: [])
check(kept == SavedSlot(display: 2, cell: Cell(column: 3, row: 2)), "a free saved slot on another display is kept")
let unplugged = resolvePlacement(saved: SavedSlot(display: 2, cell: Cell(column: 3, row: 2)), size: .large, displays: [main], taken: [calendar])
check(unplugged.display == 1 && mainGrid.isFree(unplugged.cell, .large, taken: [calendar]), "an unplugged display moves the widget to a free slot on the main display")
let covered = resolvePlacement(saved: SavedSlot(display: 1, cell: Cell(column: 0, row: 0)), size: .medium, displays: [main], taken: [calendar])
check(covered.cell != Cell(column: 0, row: 0) && mainGrid.isFree(covered.cell, .medium, taken: [calendar]), "a saved slot that a real widget now covers moves")
let grown = resolvePlacement(saved: SavedSlot(display: 1, cell: Cell(column: 7, row: 4)), size: .extraLarge, displays: [main], taken: [])
check(mainGrid.isFree(grown.cell, .extraLarge, taken: []), "growing past the edge moves to the nearest slot that fits")
let tiny = Display(id: 1, grid: SlotGrid(visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 300)), isMain: true)
check(resolvePlacement(saved: nil, size: .extraLarge, displays: [tiny], taken: []) == SavedSlot(display: 1, cell: Cell(column: 0, row: 0)), "with no free slot it falls back to 0,0 on the main display")
check(resolvePlacement(saved: SavedSlot(display: 2, cell: Cell(column: 3, row: 2)), size: .extraLarge, displays: [tiny], taken: []) == SavedSlot(display: 1, cell: Cell(column: 0, row: 0)), "a missing display with a full main display still lands at 0,0 on the main display")
let externalFull = [CGRect(x: 1470, y: 0, width: 1920, height: 1050)]
check(resolvePlacement(saved: SavedSlot(display: 2, cell: Cell(column: 3, row: 2)), size: .large, displays: [main, external], taken: externalFull) == SavedSlot(display: 1, cell: Cell(column: 0, row: 0)), "a full external display sends the widget to the main display")
let away = SavedSlot(display: 2, cell: Cell(column: 3, row: 2))
check(!shouldRemember(unplugged, saved: away, displays: [main]), "a move forced by a missing display isn't saved")
check(resolvePlacement(saved: away, size: .large, displays: [main, external], taken: []) == away, "the widget goes back when its display returns")
check(shouldRemember(covered, saved: SavedSlot(display: 1, cell: Cell(column: 0, row: 0)), displays: [main]), "a move off a covered slot on a present display is saved")
check(!shouldRemember(kept, saved: kept, displays: [main, external]), "an unchanged slot isn't saved again")
check(shouldRemember(SavedSlot(display: 1, cell: Cell(column: 0, row: 1)), saved: nil, displays: [main]), "the first launch saves its slot")
check(resolvePlacement(saved: nil, size: .extraLarge, displays: [main], taken: [calendar, weather]).cell == Cell(column: 0, row: 1), "the first launch picks the free slot nearest the top-left")

print("Medium")
var picker = MediumPicker()
let calm = [agent("a", .cooking, 1), agent("b", .reading, 2), agent("c", .done, 3)]
check(picker.current(in: []) == nil, "no agents shows nothing")
check(picker.current(in: calm) == 0, "it starts on the first agent")
picker.step(1, in: calm)
check(calm[picker.current(in: calm)!].id == "b", "a swipe moves to the next agent")
picker.step(-1, in: calm); picker.step(-1, in: calm)
check(calm[picker.current(in: calm)!].id == "c", "swiping back from the first wraps around")
let reordered = [agent("c", .done, 3), agent("a", .cooking, 1), agent("b", .reading, 2)]
check(reordered[picker.current(in: reordered)!].id == "c", "a swiped agent stays shown when the order changes")
check(picker.current(in: [agent("a", .cooking, 1)]) == 0 && picker.chosen == nil, "a swiped agent that ends is forgotten")
var solo = MediumPicker()
solo.step(1, in: [agent("x", .cooking, 1)])
check(solo.current(in: [agent("x", .cooking, 1)]) == 0, "one agent: a swipe does nothing")
var jump = MediumPicker()
let before = [agent("a", .cooking, 1), agent("b", .reading, 2)]
jump.step(1, in: before)
let oneWaiting = [agent("a", .gate, 1), agent("b", .reading, 2)]
check(oneWaiting[jump.current(in: oneWaiting)!].id == "a", "an agent that needs you takes over")
let twoWaiting = [agent("z", .gate, 0), agent("a", .gate, 1), agent("b", .reading, 2)]
check(twoWaiting[jump.current(in: twoWaiting)!].id == "a", "a second waiting agent doesn't take over")
jump.step(1, in: twoWaiting)
check(twoWaiting[jump.current(in: twoWaiting)!].id == "z", "swiping during a jump moves only between waiting agents")
let answered = [agent("a", .gate, 1), agent("b", .reading, 2), agent("z", .cooking, 0)]
check(answered[jump.current(in: answered)!].id == "a", "after one is answered it moves to the next waiting agent")
check(before[jump.current(in: before)!].id == "b", "once none are waiting it returns to the swiped agent")
var fresh = MediumPicker()
_ = fresh.current(in: oneWaiting)
let later = [agent("b", .reading, 2), agent("a", .cooking, 1)]
check(fresh.current(in: later) == 0, "with no swipe it returns to whatever is first")

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
