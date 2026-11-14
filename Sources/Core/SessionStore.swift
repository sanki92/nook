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
        var titleScannedTo: UInt64 = 0
    }

    private struct CachedRecord {
        var modified: Date
        var size: Int
        var record: SessionRecord
    }

    private struct CachedMeta {
        var modified: Date
        var live: Bool
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
    private var records: [String: CachedRecord] = [:]
    private var metas: [String: CachedMeta] = [:]
    private let decoder = JSONDecoder()
    private let tailBytes: UInt64 = 1_000_000
    private let fileKeys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .creationDateKey]

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"),
         alive: @escaping (Int32) -> Bool = isProcessAlive) {
        self.root = root
        self.alive = alive
    }

    func snapshot(now: Date = Date()) -> [Agent] {
        let dir = root.appendingPathComponent("sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: fileKeys)) ?? []
        var agents: [Agent] = []
        var seen = Set<String>()
        var seenHelpers = Set<String>()
        var seenMetas = Set<String>()
        var kept: [String: CachedRecord] = [:]

        for file in files where file.pathExtension == "json" {
            guard let cached = record(at: file) else { continue }
            kept[file.path] = cached
            let record = cached.record
            guard let pid = record.pid, let id = record.sessionId, alive(pid) else { continue }
            seen.insert(id)
            let entry = refreshed(id: id, now: now)
            let helpers = runningHelpers(transcript: entry.url, now: now, seen: &seenHelpers, seenMetas: &seenMetas)
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
        metas = metas.filter { seenMetas.contains($0.key) }
        records = kept
        return sortedAgents(agents)
    }

    private func record(at file: URL) -> CachedRecord? {
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate ?? .distantPast, size = values?.fileSize ?? -1
        let cached = records[file.path]
        if let cached, cached.modified == modified, cached.size == size { return cached }
        guard let data = try? Data(contentsOf: file), let record = try? decoder.decode(SessionRecord.self, from: data) else { return cached }
        return CachedRecord(modified: modified, size: size, record: record)
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
            if size < entry.titleScannedTo { entry.titleScannedTo = 0 }
            entry.title = findAITitle(in: url, from: entry.titleScannedTo, to: size) ?? entry.title
            entry.titleScannedTo = size
        }
        cache[id] = entry
        return entry
    }

    private func runningHelpers(transcript: URL?, now: Date, seen: inout Set<String>, seenMetas: inout Set<String>) -> [AgentState] {
        guard let transcript else { return [] }
        let dir = transcript.deletingPathExtension().appendingPathComponent("subagents")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: fileKeys)) ?? []
        var modifiedAt: [String: Date] = [:]
        for file in files where file.lastPathComponent.hasSuffix(".meta.json") {
            modifiedAt[file.path] = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        var running: [(created: Date, path: String, job: AgentState)] = []
        for file in files where file.pathExtension == "jsonl" {
            guard let values = try? file.resourceValues(forKeys: Set(fileKeys)),
                  let size = values.fileSize.map(UInt64.init),
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) < 600 else { continue }
            let meta = file.deletingPathExtension().appendingPathExtension("meta.json").path
            seenMetas.insert(meta)
            guard live(meta: meta, modified: modifiedAt[meta]) else { continue }
            seen.insert(file.path)
            let cached = helperCache[file.path]
            let helper = cached.flatMap { $0.size == size && $0.modified == modified ? $0 : nil }
                ?? CachedHelper(size: size, modified: modified, job: state(for: readSummary(url: file, size: size, includeSidechain: true).lastTool))
            helperCache[file.path] = helper
            running.append((values.creationDate ?? modified, file.path, helper.job))
        }
        return running.sorted { ($0.created, $0.path) < ($1.created, $1.path) }.map(\.job)
    }

    private func live(meta path: String, modified: Date?) -> Bool {
        guard let modified else { return false }
        if let cached = metas[path], cached.modified == modified { return cached.live }
        let json = (try? Data(contentsOf: URL(fileURLWithPath: path))).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let live = json.map { ($0["finished"] as? Bool) != true } ?? false
        metas[path] = CachedMeta(modified: modified, live: live)
        return live
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
