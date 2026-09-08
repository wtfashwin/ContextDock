import Foundation

// MARK: - Adapter protocol

/// One normalized surface for all agents. Claude Code, Codex, and the fake
/// adapter conform to this; the app core never talks to a specific CLI.
public protocol AgentAdapter: Sendable {
    var kind: AgentKind { get }
    var isAvailable: Bool { get }
    /// Dispatches a task; emits normalized AgentEvents via the handler.
    func dispatch(task: AgentTaskPackage, onEvent: @escaping @Sendable (AgentEvent) -> Void) async throws -> AgentSession
    func cancel(sessionID: StableID) async
}

/// Structured context package. Only user-approved items — never a whole vault.
public struct AgentTaskPackage: Codable, Sendable {
    public var schemaVersion: Int
    public var planTitle: String
    public var planSteps: [String]
    public var checklist: [String]
    public var projectName: String?
    public var repositoryPath: String?
    public var noteLinks: [String]
    public var decisions: [String]
    public var constraints: [String]
    public var sourceFiles: [String]
    public var expectedOutput: String
    public var doneConditions: [String]
    public init(
        schemaVersion: Int = Schema.version, planTitle: String, planSteps: [String],
        checklist: [String], projectName: String? = nil, repositoryPath: String? = nil,
        noteLinks: [String] = [], decisions: [String] = [], constraints: [String] = [],
        sourceFiles: [String] = [], expectedOutput: String = "", doneConditions: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.planTitle = planTitle
        self.planSteps = planSteps
        self.checklist = checklist
        self.projectName = projectName
        self.repositoryPath = repositoryPath
        self.noteLinks = noteLinks
        self.decisions = decisions
        self.constraints = constraints
        self.sourceFiles = sourceFiles
        self.expectedOutput = expectedOutput
        self.doneConditions = doneConditions
    }

    /// Redacted, human-reviewable preview shown before sending.
    public func preview() -> String {
        var lines: [String] = ["# Task: \(planTitle)"]
        if let projectName { lines.append("Project: \(projectName)") }
        if let repositoryPath { lines.append("Repository: \(repositoryPath)") }
        lines.append("## Steps")
        lines += planSteps.map { "- \($0)" }
        if !checklist.isEmpty { lines.append("## Checklist"); lines += checklist.map { "- [ ] \($0)" } }
        if !noteLinks.isEmpty { lines.append("## Notes"); lines += noteLinks.map { "- [[\($0)]]" } }
        if !decisions.isEmpty { lines.append("## Decisions"); lines += decisions.map { "- \($0)" } }
        if !constraints.isEmpty { lines.append("## Constraints"); lines += constraints.map { "- \($0)" } }
        if !doneConditions.isEmpty { lines.append("## Done when"); lines += doneConditions.map { "- \($0)" } }
        return SecretRedactor.redact(lines.joined(separator: "\n"))
    }
}

// MARK: - Fake adapter

/// Deterministic demo/test adapter: emits a realistic event stream for a task.
public struct FakeAgentAdapter: AgentAdapter {
    public let kind: AgentKind = .fake
    public let isAvailable = true
    private let stepDelayNanos: UInt64

    public init(stepDelayNanos: UInt64 = 200_000_000) { self.stepDelayNanos = stepDelayNanos }

    public func dispatch(task: AgentTaskPackage, onEvent: @escaping @Sendable (AgentEvent) -> Void) async throws -> AgentSession {
        let session = AgentSession(adapter: .fake, task: task.planTitle)
        let sid = session.id
        let repo = task.repositoryPath
        func emit(_ type: AgentEventType, _ summary: String, file: String? = nil) {
            onEvent(AgentEvent(
                adapter: .fake, sessionID: sid, repositoryPath: repo,
                task: task.planTitle, summary: summary, filePath: file, type: type
            ))
        }
        emit(.sessionStarted, "Fake agent session started")
        emit(.userPromptReceived, "Task received: \(task.planTitle)")
        emit(.thinkingStarted, "Reviewing context package")
        try? await Task.sleep(nanoseconds: stepDelayNanos)
        for (index, step) in task.planSteps.enumerated() {
            emit(.toolStarted, "Working on: \(step)")
            try? await Task.sleep(nanoseconds: stepDelayNanos)
            emit(.checklistUpdated, "Step \(index + 1) done: \(step)", file: nil)
        }
        emit(.fileChanged, "Produced demo output", file: "demo-output.md")
        emit(.completed, "All steps completed")
        emit(.sessionEnded, "Session ended")
        return session
    }

    public func cancel(sessionID: StableID) async {}
}

// MARK: - CLI-backed adapters (Claude Code / Codex)

/// Launches a CLI agent with argument arrays; parses stream-json output when
/// available. Availability is detected, never assumed.
public struct CLIAgentAdapter: AgentAdapter {
    public let kind: AgentKind
    public let executablePath: String

    public init(kind: AgentKind, executablePath: String) {
        self.kind = kind
        self.executablePath = executablePath
    }

    public var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    public func dispatch(task: AgentTaskPackage, onEvent: @escaping @Sendable (AgentEvent) -> Void) async throws -> AgentSession {
        let session = AgentSession(adapter: kind, task: task.planTitle)
        guard isAvailable else {
            onEvent(AgentEvent(
                adapter: kind, sessionID: session.id, status: "error",
                summary: "\(kind.rawValue) CLI not found at \(executablePath)", type: .failed
            ))
            throw AgentError.adapterUnavailable(kind)
        }
        let prompt = task.preview()
        let args: [String]
        switch kind {
        case .claudeCode:
            args = ["-p", prompt, "--output-format", "stream-json", "--verbose"]
        case .codex, .codexCLI:
            args = ["exec", "--json", prompt]
        case .gemini:
            args = [prompt]
        case .cursor:
            args = ["--print", prompt]
        case .opencode:
            args = ["run", prompt]
        case .qwen:
            args = [prompt]
        case .copilot:
            args = ["-p", prompt]
        case .fake:
            args = []
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        if let repo = task.repositoryPath {
            process.currentDirectoryURL = URL(fileURLWithPath: repo)
        }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()

        let sid = session.id
        let adapterKind = kind
        onEvent(AgentEvent(adapter: kind, sessionID: sid, task: task.planTitle, summary: "Launching \(kind.rawValue)", type: .sessionStarted))
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                onEvent(AgentEvent(
                    adapter: adapterKind, sessionID: sid,
                    summary: String(line.prefix(300)), rawSource: "stdout", type: .toolFinished
                ))
            }
        }
        try process.run()
        process.waitUntilExit()
        out.fileHandleForReading.readabilityHandler = nil
        let okExit = process.terminationStatus == 0
        onEvent(AgentEvent(
            adapter: kind, sessionID: sid, status: okExit ? "ok" : "error",
            summary: okExit ? "\(kind.rawValue) finished" : "\(kind.rawValue) exited with status \(process.terminationStatus)",
            type: okExit ? .completed : .failed
        ))
        return session
    }

    public func cancel(sessionID: StableID) async {}
}

public enum AgentError: Error {
    case adapterUnavailable(AgentKind)
}
