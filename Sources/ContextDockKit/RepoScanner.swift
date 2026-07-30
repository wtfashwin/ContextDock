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
    /// active first. `lastUsedPath`, when still valid, always wins.
    public func scan(roots: [URL], lastUsedPath: String? = nil) -> [Repository] {
        let fm = FileManager.default
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
public struct RepoKnowledgeIngestor: Sendable {
    private let git: GitRunner
    public init(git: GitRunner = GitRunner()) { self.git = git }

    /// Ensures a project + mapping exist for the repository and refreshes
    /// its derived nodes in the graph. Derived nodes use stable IDs so
    /// re-ingesting updates instead of duplicating.
    public func ingest(repository: Repository, into document: inout StoreDocument) {
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

        let rootURL = URL(fileURLWithPath: repository.rootPath)
        var graph = document.graph

        graph.upsertNode(KnowledgeNode(
            id: StableID("repo-node-\(repository.name.lowercased())"),
            title: repository.name, type: .repository, projectID: project.id,
            source: "git", sourcePath: repository.rootPath,
            summary: "branch \(repository.branch ?? "?"), \(repository.modifiedFileCount ?? 0) modified files"
        ))

        if let log = git.run(["log", "--pretty=%h|%s", "-n", "8"], in: rootURL) {
            for line in log.split(separator: "\n") {
                let parts = line.split(separator: "|", maxSplits: 1)
                guard parts.count == 2 else { continue }
                graph.upsertNode(KnowledgeNode(
                    id: StableID("commit-\(repository.name.lowercased())-\(parts[0])"),
                    title: String(parts[1]), type: .task, projectID: project.id,
                    source: "git-log", summary: "commit \(parts[0])"
                ))
            }
        }

        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for doc in entries where doc.pathExtension.lowercased() == "md" {
                let name = doc.deletingPathExtension().lastPathComponent
                graph.upsertNode(KnowledgeNode(
                    id: StableID("doc-\(repository.name.lowercased())-\(name.lowercased())"),
                    title: name, type: .document, projectID: project.id,
                    source: "repo-docs", sourcePath: doc.path
                ))
            }
        }
        document.graph = graph
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
