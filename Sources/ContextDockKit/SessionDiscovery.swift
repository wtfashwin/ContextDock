import Foundation

// MARK: - Zero-config discovery: show Claude + Codex the moment they run
//
// Hard-won perf rules (these caused the memory/CPU reports):
// - ONE `ps` snapshot per poll, parsed once into a pid map. Never per-pid `ps`.
// - `lsof` only for agent pids (≤20), results cached 60s by pid.
// - `tmux list-panes` at most once per 10s, skipped when no tmux ancestor.
// - Everything runs on a utility queue (never the Swift cooperative pool:
//   blocking reads there starve structured concurrency and grow threads).
// - Fail-open: anything missing just yields fewer sessions, never an error.

public struct DiscoveredAgent: Hashable, Sendable {
    public var agent: AgentKind
    public var pid: Int32
    public var workingDirectory: String?
    public var terminal: String?
    public var tty: String?
    public var tmuxTarget: String?
    public init(agent: AgentKind, pid: Int32, workingDirectory: String? = nil, terminal: String? = nil, tty: String? = nil, tmuxTarget: String? = nil) {
        self.agent = agent; self.pid = pid
        self.workingDirectory = workingDirectory; self.terminal = terminal
        self.tty = tty; self.tmuxTarget = tmuxTarget
    }
}

public enum SessionDiscovery: Sendable {
    static let agentComms: [(kind: AgentKind, names: [String])] = [
        (.claudeCode, ["claude"]),
        (.codex, ["codex"]),
        (.gemini, ["gemini"]),
        (.cursor, ["cursor-agent"]),
        (.opencode, ["opencode"]),
        (.qwen, ["qwen"]),
        (.copilot, ["copilot"]),
    ]
    static let maxCwdLookups = 20

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cwdCache: [Int32: (dir: String, at: Date)] = [:]
    nonisolated(unsafe) private static var panesCache: (panes: [TmuxPane], at: Date)?

    /// One poll: single ps snapshot → links → bounded cwd/tmux enrichment.
    public static func poll() -> [LiveSession] {
        guard let snapshot = run("/bin/ps", ["-axo", "pid=,ppid=,tty=,comm=,args="], timeout: 8) else { return [] }
        let (rows, args) = parsePs(snapshot)
        var byPid: [Int32: PsRow] = [:]
        byPid.reserveCapacity(rows.count)
        for r in rows { byPid[r.pid] = r }
        let matched = agentPids(rows: rows, args: args)
        guard !matched.isEmpty else { return [] }
        let agentIDs = Set(matched.map(\.pid))
        let links = ProcessTree.resolve(agentPids: agentIDs, rows: rows)
        let titles = transcriptTasks()
        let panes = tmuxPanes(links: links)
        return matched.prefix(maxCwdLookups).compactMap { (pid, kind) -> LiveSession? in
            let link = links[pid]
            let dir = cachedCwd(of: pid)
            let project = dir.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "agent"
            let tmux = panes.flatMap { list in Tmux.match(panes: list, pid: pid)?.target }
            return LiveSession(
                id: StableID("live-\(pid)"), agent: kind,
                task: titles.first ?? project, terminal: link?.terminalName ?? "Terminal",
                status: .working, lastActivity: "Working in \(project)",
                startedAt: Date().addingTimeInterval(-120),
                repositoryPath: dir, pid: pid,
                tty: link?.tty, tmuxTarget: tmux ?? link?.tmuxTarget
            )
        }
    }

    /// Split `ps` output once: rows carry comm, args ride alongside for guards.
    static func parsePs(_ snapshot: String) -> (rows: [PsRow], args: [Int32: String]) {
        var rows: [PsRow] = []
        rows.reserveCapacity(512)
        var args: [Int32: String] = [:]
        for line in snapshot.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count >= 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            rows.append(PsRow(pid: pid, ppid: ppid, tty: String(parts[2]), comm: String(parts[3])))
            if parts.count == 5 { args[pid] = String(parts[4]) }
        }
        return (rows, args)
    }

    /// Single pass over rows; exact comm match (no substring false-positives).
    static func agentPids(rows: [PsRow], args: [Int32: String]) -> [(pid: Int32, kind: AgentKind)] {
        var out: [(Int32, AgentKind)] = []
        for r in rows {
            let comm = r.comm.lowercased()
            let base = comm.split(separator: "/").last.map(String.init) ?? comm
            for (kind, names) in agentComms where names.contains(base) {
                if (args[r.pid] ?? "").contains("ContextDock") { continue }
                out.append((r.pid, kind))
            }
        }
        return out
    }

    // MARK: Bounded, cached enrichment

    static func cachedCwd(of pid: Int32) -> String? {
        lock.lock()
        if let hit = cwdCache[pid], Date().timeIntervalSince(hit.at) < 60 {
            lock.unlock()
            return hit.dir
        }
        lock.unlock()
        guard let dir = cwd(of: pid) else { return nil }
        lock.lock(); cwdCache[pid] = (dir, Date())
        if cwdCache.count > 64 { cwdCache.removeAll() }
        lock.unlock()
        return dir
    }

    static func cwd(of pid: Int32) -> String? {
        guard let out = run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"], timeout: 6) else { return nil }
        for line in out.split(separator: "\n") where line.hasPrefix("n") {
            let path = String(line.dropFirst())
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    static func tmuxPanes(links: [Int32: TerminalLink]) -> [TmuxPane]? {
        guard links.values.contains(where: { $0.terminalName == "tmux" }) else { return nil }
        lock.lock()
        if let c = panesCache, Date().timeIntervalSince(c.at) < 10 { lock.unlock(); return c.panes }
        lock.unlock()
        guard let out = run("/opt/homebrew/bin/tmux", ["list-panes", "-a", "-F", "#{pane_pid} #{session_name}:#{window_index}.#{pane_index} #{pane_current_path}"], timeout: 5)
            ?? run("/usr/local/bin/tmux", ["list-panes", "-a", "-F", "#{pane_pid} #{session_name}:#{window_index}.#{pane_index} #{pane_current_path}"], timeout: 5) else { return nil }
        let panes = Tmux.parsePanes(out)
        lock.lock(); panesCache = (panes, Date()); lock.unlock()
        return panes
    }

    // MARK: Transcripts (task titles without any hooks; newest 2 slugs, 16KB heads)

    static func transcriptTasks() -> [String] {
        var titles: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeRoot = home.appendingPathComponent(".claude/projects")
        guard let slugs = try? FileManager.default.contentsOfDirectory(at: claudeRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return titles }
        let ordered = slugs.sorted {
            let da = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }.prefix(2)
        for slug in ordered {
            guard let files = try? FileManager.default.contentsOfDirectory(at: slug, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            let latest = files.filter { $0.pathExtension == "jsonl" }.max {
                let da = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
            if let latest, let title = firstUserMessage(in: latest) { titles.append(title) }
        }
        return titles
    }

    static func firstUserMessage(in file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 16 * 1024)) ?? Data()
        for line in String(data: data, encoding: .utf8)?.split(separator: "\n").prefix(30) ?? [] {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let type = obj["type"] as? String, type == "user",
                  let msg = (obj["message"] as? [String: Any])?["content"] as? String
                    ?? ((obj["message"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String
            else { continue }
            let clean = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { return String(clean.prefix(80)) }
        }
        return nil
    }

    // MARK: Timeout-guarded proc helper (utility QoS belongs to the caller)

    @discardableResult
    public static func run(_ executable: String, _ args: [String], timeout: TimeInterval = 8) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.qualityOfService = .utility
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.isEmpty ? nil : text
    }
}
