import Foundation

/// Finds real git repositories on disk instead of relying on hard-coded paths.
/// Deterministic: scans well-known roots one level deep, ranks candidates by
/// most recent git activity (`.git/HEAD` mtime covers commits and checkouts).
public struct RepoScanner: Sendable {
    private let resolver: ProjectResolver

    public init(resolver: ProjectResolver = ProjectResolver()) {
        self.resolver = resolver
    }

    /// Default roots worth scanning for a personal machine.
    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Documents"),
            home,
        ]
    }

    /// All git repositories directly under the given roots, most recently
    /// active first. `lastUsedPath`, when still valid, answers immediately
    /// WITHOUT enumerating the roots: every enumeration of Desktop/Documents
    /// re-arms a TCC consent dialog while the app is ad-hoc signed (each
    /// rebuild is a new identity), so the steady state must not scan at all.
    /// Full scan runs only when the last repo moved or was deleted.
    public func scan(roots: [URL], lastUsedPath: String? = nil) -> [Repository] {
        let fm = FileManager.default
        if let lastUsedPath,
           fm.fileExists(atPath: lastUsedPath + "/.git"),
           let repo = resolver.resolveRepository(at: URL(fileURLWithPath: lastUsedPath)) {
            return [repo]
        }
        var candidates: [(url: URL, activity: Date)] = []
        var seen = Set<String>()

        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                let headURL = entry.appendingPathComponent(".git/HEAD")
                guard fm.fileExists(atPath: headURL.path) else { continue }
                let path = entry.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                let attrs = try? fm.attributesOfItem(atPath: headURL.path)
                let mtime = attrs?[.modificationDate] as? Date ?? .distantPast
                candidates.append((entry, mtime))
            }
        }
        candidates.sort { $0.activity > $1.activity }

        var ordered = candidates.map(\.url)
        if let lastUsedPath, fm.fileExists(atPath: lastUsedPath + "/.git") {
            let lastURL = URL(fileURLWithPath: lastUsedPath)
            ordered.removeAll { $0.standardizedFileURL.path == lastURL.standardizedFileURL.path }
            ordered.insert(lastURL, at: 0)
        }
        return ordered.prefix(10).compactMap { resolver.resolveRepository(at: $0) }
    }

    /// Single best candidate, in priority order:
    /// 1. cwd of a live `claude` / `codex` CLI process (the terminal you're in)
    /// 2. last used repository, if still valid
    /// 3. most recently active git repo under the scan roots
    public func detectActiveRepository(roots: [URL]? = nil, lastUsedPath: String? = nil) -> Repository? {
        if let cwd = AgentProcessLocator.liveAgentWorkingDirectory(),
           let repo = resolver.resolveRepository(at: URL(fileURLWithPath: cwd)) {
            return repo
        }
        return scan(roots: roots ?? Self.defaultRoots(), lastUsedPath: lastUsedPath).first
    }
}

/// Builds knowledge nodes from a real repository — recent commits and
/// top-level markdown docs — so context is fetched, never hand-seeded.
///
/// Split-brain design (postmortem 2026-09-08): `collect` does ALL blocking
/// I/O (git + directory reads) and runs off the main actor; `apply` only
/// mutates the document and never blocks, so no `&inout` scope ever spans
/// a runloop spin. `ingest` remains as the same-thread convenience wrapper.
public struct RepoKnowledgeIngestor: Sendable {
    private let git: GitRunner
    public init(git: GitRunner = GitRunner()) { self.git = git }

    /// Blocking I/O results. Value type, safe to ferry across actors.
    public struct CollectedRepo: Sendable {
        public var commits: [(sha: String, title: String)]
        public var docNames: [String]
        public var summary: String
    }

    public func collect(repository: Repository) -> CollectedRepo {
        let rootURL = URL(fileURLWithPath: repository.rootPath)
        var commits: [(String, String)] = []
        if let log = git.run(["log", "--pretty=%h|%s", "-n", "8"], in: rootURL) {
            for line in log.split(separator: "\n") {
                let parts = line.split(separator: "|", maxSplits: 1)
                guard parts.count == 2 else { continue }
                commits.append((String(parts[0]), String(parts[1])))
            }
        }
        var docs: [String] = []
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for doc in entries where doc.pathExtension.lowercased() == "md" {
                docs.append(doc.deletingPathExtension().lastPathComponent)
            }
        }
        return CollectedRepo(
            commits: commits, docNames: docs,
            summary: "branch \(repository.branch ?? "?"), \(repository.modifiedFileCount ?? 0) modified files"
        )
    }

    /// Fast, non-blocking document mutation. Safe on the main actor.
    public func apply(_ collected: CollectedRepo, for repository: Repository, into document: inout StoreDocument) {
        let project: Project
        if let mapping = document.mappings.first(where: { $0.repositoryName == repository.name }),
           let existing = document.projects.first(where: { $0.id == mapping.projectID }) {
            project = existing
        } else {
            let created = Project(
                id: StableID("project-\(repository.name.lowercased())"),
                name: repository.name,
                aliases: [repository.name.replacingOccurrences(of: "_", with: " ").lowercased()]
            )
            document.projects.append(created)
            document.mappings.append(RepositoryMapping(repositoryName: repository.name, projectID: created.id))
            project = created
        }

        var graph = document.graph
        graph.upsertNode(KnowledgeNode(
            id: StableID("repo-node-\(repository.name.lowercased())"),
            title: repository.name, type: .repository, projectID: project.id,
            source: "git", sourcePath: repository.rootPath,
            summary: collected.summary
        ))
        for (sha, title) in collected.commits {
            graph.upsertNode(KnowledgeNode(
                id: StableID("commit-\(repository.name.lowercased())-\(sha)"),
                title: title, type: .task, projectID: project.id,
                source: "git-log", summary: "commit \(sha)"
            ))
        }
        for name in collected.docNames {
            graph.upsertNode(KnowledgeNode(
                id: StableID("doc-\(repository.name.lowercased())-\(name.lowercased())"),
                title: name, type: .document, projectID: project.id,
                source: "repo-docs", sourcePath: repository.rootPath + "/\(name).md"
            ))
        }
        document.graph = graph
    }

    /// Same-thread convenience: collect + apply inline. Call only where
    /// blocking is legal (background tasks, tests) — never on MainActor.
    public func ingest(repository: Repository, into document: inout StoreDocument) {
        apply(collect(repository: repository), for: repository, into: &document)
    }
}

/// Finds the working directory of a running agent CLI (`claude` or `codex`)
/// so the island follows whatever terminal the user is actually working in.
/// Uses `pgrep` + `lsof -a -d cwd` with argument arrays only — no shell strings.
public enum AgentProcessLocator {
    public static func liveAgentWorkingDirectory(agents: [String] = ["claude", "codex"]) -> String? {
        for agent in agents {
            guard let pidsOut = run("/usr/bin/pgrep", ["-x", agent]) else { continue }
            // Newest process first: the terminal the user opened most recently.
            let pids = pidsOut.split(separator: "\n").compactMap { Int($0) }.sorted(by: >)
            for pid in pids {
                if let cwd = workingDirectory(ofPID: pid) { return cwd }
            }
        }
        return nil
    }

    static func workingDirectory(ofPID pid: Int) -> String? {
        guard let out = run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]) else { return nil }
        // -Fn output: lines like "p<pid>", "fcwd", "n/path/to/dir"
        for line in out.split(separator: "\n") where line.hasPrefix("n") {
            let path = String(line.dropFirst())
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private static func run(_ executable: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
        } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }
}
