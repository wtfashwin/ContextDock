import Foundation

/// Runs `/usr/bin/git` with argument arrays only (never shell strings).
public struct GitRunner: Sendable {
    public init() {}

    public func run(_ args: [String], in directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Resolves the repository for a directory using deterministic git signals.
public struct ProjectResolver: Sendable {
    private let git: GitRunner

    public init(git: GitRunner = GitRunner()) { self.git = git }

    public func resolveRepository(at directory: URL) -> Repository? {
        guard let root = git.run(["rev-parse", "--show-toplevel"], in: directory) else { return nil }
        let rootURL = URL(fileURLWithPath: root)
        let name = rootURL.lastPathComponent
        let branch = git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: rootURL)
        let remote = git.run(["remote", "get-url", "origin"], in: rootURL)
        let commit = git.run(["rev-parse", "--short", "HEAD"], in: rootURL)
        let statusOut = git.run(["status", "--porcelain"], in: rootURL)
        let modified = statusOut.map { $0.isEmpty ? 0 : $0.split(separator: "\n").count }
        let gitDirCommon = git.run(["rev-parse", "--git-common-dir"], in: rootURL)
        let gitDir = git.run(["rev-parse", "--git-dir"], in: rootURL)
        let isWorktree = gitDirCommon != nil && gitDir != nil && gitDirCommon != gitDir
        return Repository(
            id: StableID("repo-\(name.lowercased())"),
            rootPath: root,
            name: name,
            branch: branch,
            remoteURL: remote,
            latestCommit: commit,
            modifiedFileCount: modified,
            isWorktree: isWorktree
        )
    }
}

/// Learned mapping repository → project, persisted locally by LocalStore.
public struct RepositoryMapping: Codable, Sendable {
    public var repositoryName: String
    public var projectID: StableID
    public init(repositoryName: String, projectID: StableID) {
        self.repositoryName = repositoryName
        self.projectID = projectID
    }
}
