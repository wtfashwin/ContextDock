import Foundation

// MARK: - Vibe Island parity: live multi-agent session feed
//
// Single source of truth for "what agents are running".
// Every AgentEvent (socket, CLI stdout, discovery) funnels through
// SessionState.apply — the same reducer the UI and tests use.

public enum LiveStatus: String, Codable, Sendable, CaseIterable {
    case working, waiting, needsApproval, asking, done, failed
    public var isUrgent: Bool { self == .needsApproval || self == .asking || self == .waiting }
    public var isActive: Bool { self == .working || self == .waiting || self == .needsApproval || self == .asking }
}

public struct PermissionRequest: Codable, Hashable, Sendable {
    public var filePath: String
    public var diffText: String
    public var additions: Int
    public var deletions: Int
    public var toolName: String?
    public init(filePath: String, diffText: String = "", additions: Int = 0, deletions: Int = 0, toolName: String? = nil) {
        self.filePath = filePath; self.diffText = diffText
        self.additions = additions; self.deletions = deletions; self.toolName = toolName
    }
}

public struct AgentQuestion: Codable, Hashable, Sendable {
    public var question: String
    public var options: [String]
    public init(question: String, options: [String]) {
        self.question = question; self.options = options
    }
}

public struct ToolLogLine: Codable, Hashable, Sendable {
    public var text: String
    public var detail: String?
    public var timestamp: Date
    public init(text: String, detail: String? = nil, timestamp: Date = .init()) {
        self.text = text; self.detail = detail; self.timestamp = timestamp
    }
}

public struct LiveSession: Codable, Hashable, Sendable, Identifiable {
    public var id: StableID
    public var agent: AgentKind
    public var task: String
    public var terminal: String
    public var status: LiveStatus
    public var lastActivity: String
    public var startedAt: Date
    public var updatedAt: Date
    public var repositoryPath: String?
    public var pid: Int32?
    public var tty: String?
    public var tmuxTarget: String?
    public var permission: PermissionRequest?
    public var question: AgentQuestion?
    public var log: [ToolLogLine]
    public var approvedCount: Int
    public init(
        id: StableID = .generate(prefix: "sess"), agent: AgentKind,
        task: String, terminal: String = "Terminal",
        status: LiveStatus = .working, lastActivity: String = "",
        startedAt: Date = .init(), updatedAt: Date = .init(),
        repositoryPath: String? = nil, pid: Int32? = nil,
        tty: String? = nil, tmuxTarget: String? = nil,
        permission: PermissionRequest? = nil, question: AgentQuestion? = nil,
        log: [ToolLogLine] = [], approvedCount: Int = 0
    ) {
        self.id = id; self.agent = agent; self.task = task; self.terminal = terminal
        self.status = status; self.lastActivity = lastActivity
        self.startedAt = startedAt; self.updatedAt = updatedAt
        self.repositoryPath = repositoryPath; self.pid = pid
        self.tty = tty; self.tmuxTarget = tmuxTarget
        self.permission = permission; self.question = question
        self.log = log; self.approvedCount = approvedCount
    }
    public var elapsed: String {
        let s = max(0, Int(Date().timeIntervalSince(startedAt)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h\((s % 3600) / 60 > 0 ? "\( (s % 3600) / 60)m" : "")"
    }
}

/// Pure reducer: event + existing session -> updated session.
/// Tested directly; DockModel just holds the resulting array.
public enum SessionState {
    public static func apply(_ event: AgentEvent, to session: LiveSession?) -> LiveSession {
        var s = session ?? LiveSession(
            id: event.sessionID, agent: event.adapter,
            task: event.task ?? event.summary,
            terminal: event.terminal ?? "Terminal",
            startedAt: event.timestamp, updatedAt: event.timestamp,
            repositoryPath: event.repositoryPath ?? event.workingDirectory
        )
        // updatedAt moves only on material change (decided at the end).
        let incomingUpdatedAt = event.timestamp
        s.updatedAt = session?.updatedAt ?? event.timestamp
        if let t = event.task, !t.isEmpty { s.task = t }
        if let term = event.terminal, !term.isEmpty { s.terminal = term }
        if let repo = event.repositoryPath ?? event.workingDirectory { s.repositoryPath = repo }
        let line = event.logLine ?? event.summary
        switch event.type {
        case .sessionStarted, .sessionResumed, .thinkingStarted, .userPromptReceived:
            s.status = .working; s.lastActivity = line
        case .toolStarted, .commandStarted, .testStarted:
            s.status = .working; s.lastActivity = line
            s.log.append(ToolLogLine(text: event.toolName ?? event.command ?? "Working", detail: line, timestamp: event.timestamp))
        case .toolFinished, .commandFinished, .testFinished, .fileChanged:
            if s.status == .working { s.lastActivity = line }
            s.log.append(ToolLogLine(text: event.toolName ?? "Done", detail: line, timestamp: event.timestamp))
        case .checklistCreated, .checklistUpdated, .planProposed:
            s.lastActivity = line
            s.log.append(ToolLogLine(text: "Progress", detail: line, timestamp: event.timestamp))
        case .permissionRequested:
            s.status = .needsApproval
            s.lastActivity = "Needs approval: \(event.filePath ?? line)"
            s.permission = PermissionRequest(
                filePath: event.filePath ?? "unknown file",
                diffText: event.diffText ?? event.summary,
                additions: event.additions ?? 0, deletions: event.deletions ?? 0,
                toolName: event.toolName)
        case .permissionApproved:
            s.status = .working; s.permission = nil
            s.approvedCount += 1; s.lastActivity = "✓ Approved"
        case .permissionRejected:
            s.status = .working; s.permission = nil; s.lastActivity = "Rejected — continuing"
        case .questionAsked, .waitingForUser:
            s.status = event.type == .questionAsked ? .asking : .waiting
            s.lastActivity = event.question ?? line
            if let q = event.question {
                s.question = AgentQuestion(question: q, options: event.questionOptions ?? ["Yes", "No"])
            }
        case .completed:
            s.status = .done; s.lastActivity = "Done — click to jump"
            s.permission = nil; s.question = nil
        case .failed, .cancelled:
            s.status = .failed; s.lastActivity = line
            s.permission = nil; s.question = nil
        case .sessionEnded:
            if s.status.isActive { s.status = .done; s.lastActivity = "Done — click to jump" }
        }
        if s.log.count > 60 { s.log.removeFirst(s.log.count - 60) }
        // Identity preservation: repeated/duplicate events that change nothing
        // return the original value, so feed diffs stay quiet (no re-render,
        // no re-sort, no persist churn). updatedAt only moves on real change.
        if let orig = session, s == orig { return orig }
        s.updatedAt = incomingUpdatedAt
        return s
    }

    /// Sort: urgent first, then most recently updated.
    public static func sorted(_ sessions: [LiveSession]) -> [LiveSession] {
        sessions.sorted {
            if $0.status.isUrgent != $1.status.isUrgent { return $0.status.isUrgent }
            return $0.updatedAt > $1.updatedAt
        }
    }
}
