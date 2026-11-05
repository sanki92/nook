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

    private let root: URL
    private let alive: (Int32) -> Bool
    private var cache: [String: Cached] = [:]
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

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(SessionRecord.self, from: data),
                  let pid = record.pid, let id = record.sessionId, alive(pid) else { continue }
            seen.insert(id)
            let entry = refreshed(id: id, now: now)
            agents.append(Agent(
                id: id,
                name: displayName(record: record, aiTitle: entry.title),
                state: deriveState(status: record.status, summary: entry.summary, statusUpdatedAt: record.statusUpdatedAt, now: now),
                pid: pid,
                startedAt: record.startedAt ?? 0))
        }
        cache = cache.filter { seen.contains($0.key) }
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

    private func readSummary(url: URL, size: UInt64) -> TranscriptSummary {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return TranscriptSummary() }
        defer { try? handle.close() }
        let offset = size > tailBytes ? size - tailBytes : 0
        try? handle.seek(toOffset: offset)
        let tail = (try? handle.readToEnd()) ?? Data()
        return summarizeTranscript(tail: tail, startsMidLine: offset > 0)
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
