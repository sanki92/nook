import Foundation

func isProcessAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}

final class SessionStore {
    private struct Cached {
        var url: URL?
        var lastLookup = Date.distantPast
        var size: UInt64 = 0
        var modified = Date.distantPast
        var summary = TranscriptSummary()
        var title: String?
        var lastTitleScan = Date.distantPast
    }

    private struct CachedHelper {
        var size: UInt64
        var modified: Date
        var job: AgentState
    }

    private let root: URL
    private let alive: (Int32) -> Bool
    private var cache: [String: Cached] = [:]
    private var helperCache: [String: CachedHelper] = [:]
    private var lastRecords: [String: SessionRecord] = [:]
    private let tailBytes: UInt64 = 1_000_000

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
         alive: @escaping (Int32) -> Bool = isProcessAlive) {
        self.root = root
        self.alive = alive
    }

    func snapshot(now: Date = Date()) -> [Agent] {
        let dir = root.appendingPathComponent("sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var agents: [Agent] = []
        var seen = Set<String>()
        var seenHelpers = Set<String>()
        var records: [String: SessionRecord] = [:]

        for file in files where file.pathExtension == "json" {
            let decoded = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(SessionRecord.self, from: $0) }
            guard let record = decoded ?? lastRecords[file.path],
                  let pid = record.pid, let id = record.sessionId, alive(pid) else { continue }
            records[file.path] = record
            seen.insert(id)
            let entry = refreshed(id: id, now: now)
            let helpers = runningHelpers(transcript: entry.url, now: now, seen: &seenHelpers)
            agents.append(Agent(
                id: id,
                name: displayName(record: record, aiTitle: entry.title),
                state: deriveState(status: record.status, summary: entry.summary, statusUpdatedAt: record.statusUpdatedAt, helperCount: helpers.count, now: now),
                pid: pid,
                startedAt: record.startedAt ?? 0,
                helpers: helpers))
        }
        cache = cache.filter { seen.contains($0.key) }
        helperCache = helperCache.filter { seenHelpers.contains($0.key) }
        lastRecords = records
        return sortedAgents(agents)
    }

    private func refreshed(id: String, now: Date) -> Cached {
        var entry = cache[id] ?? Cached()
        if entry.url == nil, now.timeIntervalSince(entry.lastLookup) > 3 {
            entry.url = findTranscript(id: id)
            entry.lastLookup = now
        }
        if let url = entry.url,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64,
           let modified = attrs[.modificationDate] as? Date,
           size != entry.size || modified != entry.modified {
            entry.size = size
            entry.modified = modified
            entry.summary = readSummary(url: url, size: size)
            if entry.title == nil || now.timeIntervalSince(entry.lastTitleScan) > 15 {
                entry.title = findAITitle(in: url) ?? entry.title
                entry.lastTitleScan = now
            }
        }
        cache[id] = entry
        return entry
    }

    private func runningHelpers(transcript: URL?, now: Date, seen: inout Set<String>) -> [AgentState] {
        guard let transcript else { return [] }
        let dir = transcript.deletingPathExtension().appendingPathComponent("subagents")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var running: [(created: Date, job: AgentState)] = []
        for file in files where file.pathExtension == "jsonl" {
            let meta = file.deletingPathExtension().appendingPathExtension("meta.json")
            guard let data = try? Data(contentsOf: meta),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (json["finished"] as? Bool) != true,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let size = attrs[.size] as? UInt64,
                  let modified = attrs[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) < 600 else { continue }
            seen.insert(file.path)
            var helper = helperCache[file.path]
            if helper == nil || helper?.size != size || helper?.modified != modified {
                helper = CachedHelper(size: size, modified: modified, job: state(for: readSummary(url: file, size: size, includeSidechain: true).lastTool))
                helperCache[file.path] = helper
            }
            running.append((attrs[.creationDate] as? Date ?? modified, helper!.job))
        }
        return running.sorted { $0.created < $1.created }.map(\.job)
    }

    private func readSummary(url: URL, size: UInt64, includeSidechain: Bool = false) -> TranscriptSummary {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return TranscriptSummary() }
        defer { try? handle.close() }
        let offset = size > tailBytes ? size - tailBytes : 0
        try? handle.seek(toOffset: offset)
        let tail = (try? handle.readToEnd()) ?? Data()
        return summarizeTranscript(tail: tail, startsMidLine: offset > 0, includeSidechain: includeSidechain)
    }

    private func findTranscript(id: String) -> URL? {
        let projects = root.appendingPathComponent("projects")
        let dirs = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let candidate = dir.appendingPathComponent("\(id).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
