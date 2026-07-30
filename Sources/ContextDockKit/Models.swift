import Foundation

// MARK: - Schema version

public enum Schema {
    /// Versioned schema for all persisted / transported payloads.
    public static let version = 1
}

// MARK: - Identifiers

public struct StableID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public static func generate(prefix: String) -> StableID {
        StableID("\(prefix)-\(UUID().uuidString.lowercased())")
    }
    public var description: String { raw }
}

// MARK: - Project / Repository

public struct Project: Codable, Hashable, Sendable {
    public var id: StableID
    public var name: String
    public var aliases: [String]
    public var obsidianFolder: String?
    public init(id: StableID, name: String, aliases: [String] = [], obsidianFolder: String? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.obsidianFolder = obsidianFolder
    }
}

public struct Repository: Codable, Hashable, Sendable {
    public var id: StableID
    public var rootPath: String
    public var name: String
    public var branch: String?
    public var remoteURL: String?
    public var latestCommit: String?
    public var modifiedFileCount: Int?
    public var isWorktree: Bool
    public init(
        id: StableID, rootPath: String, name: String, branch: String? = nil,
        remoteURL: String? = nil, latestCommit: String? = nil,
        modifiedFileCount: Int? = nil, isWorktree: Bool = false
    ) {
        self.id = id
        self.rootPath = rootPath
        self.name = name
        self.branch = branch
        self.remoteURL = remoteURL
        self.latestCommit = latestCommit
        self.modifiedFileCount = modifiedFileCount
        self.isWorktree = isWorktree
    }
}

// MARK: - Knowledge graph

public enum NodeType: String, Codable, CaseIterable, Sendable {
    case project, repository, worktree, feature, decision, requirement, task
    case checklist, document, file, person, team, concept, question, risk
    case agent, agentSession, conversation, plan, build, test, release
}

public enum EdgeType: String, Codable, CaseIterable, Sendable {
    case belongsTo, relatesTo, dependsOn, blocks, implements, verifies
    case createdBy, updatedBy, discussedIn, derivedFrom, supersedes
    case conflictsWith, approvedBy, storedIn, executedBy, produced, references
}

public struct KnowledgeNode: Codable, Hashable, Sendable {
    public var id: StableID
    public var title: String
    public var type: NodeType
    public var projectID: StableID?
    public var source: String
    public var sourcePath: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var confidence: Double
    public var tags: [String]
    public var summary: String?
    public var archived: Bool
    public init(
        id: StableID, title: String, type: NodeType, projectID: StableID? = nil,
        source: String, sourcePath: String? = nil, createdAt: Date = .init(),
        updatedAt: Date = .init(), confidence: Double = 1.0, tags: [String] = [],
        summary: String? = nil, archived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.projectID = projectID
        self.source = source
        self.sourcePath = sourcePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.confidence = confidence
        self.tags = tags
        self.summary = summary
        self.archived = archived
    }
}

public struct KnowledgeEdge: Codable, Hashable, Sendable {
    public var sourceID: StableID
    public var targetID: StableID
    public var type: EdgeType
    public var evidence: String
    public var confidence: Double
    public var createdAt: Date
    public var userConfirmed: Bool
    public init(
        sourceID: StableID, targetID: StableID, type: EdgeType, evidence: String,
        confidence: Double = 1.0, createdAt: Date = .init(), userConfirmed: Bool = false
    ) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.type = type
        self.evidence = evidence
        self.confidence = confidence
        self.createdAt = createdAt
        self.userConfirmed = userConfirmed
    }
}

// MARK: - Context

public struct ContextMatch: Codable, Hashable, Sendable {
    public var node: KnowledgeNode
    public var reason: String
    public var score: Double
    public init(node: KnowledgeNode, reason: String, score: Double) {
        self.node = node
        self.reason = reason
        self.score = score
    }
}

public struct ContextBundle: Codable, Sendable {
    public var project: Project?
    public var repository: Repository?
    public var featureID: String?
    public var matches: [ContextMatch]
    public var relatedFiles: [String]
    public var relatedSessions: [StableID]
    public var confidence: Double
    public var explanation: String
    public var missingInformation: [String]
    public var conflicts: [String]
    public init(
        project: Project? = nil, repository: Repository? = nil, featureID: String? = nil,
        matches: [ContextMatch] = [], relatedFiles: [String] = [],
        relatedSessions: [StableID] = [], confidence: Double = 0,
        explanation: String = "", missingInformation: [String] = [], conflicts: [String] = []
    ) {
        self.project = project
        self.repository = repository
        self.featureID = featureID
        self.matches = matches
        self.relatedFiles = relatedFiles
        self.relatedSessions = relatedSessions
        self.confidence = confidence
        self.explanation = explanation
        self.missingInformation = missingInformation
        self.conflicts = conflicts
    }
}

// MARK: - Plans

public enum PlanKind: String, Codable, Sendable { case recommended, fastest, safest }

public enum WorkSize: String, Codable, Sendable { case small, medium, large }

public struct PlanOption: Codable, Hashable, Sendable, Identifiable {
    public var id: StableID
    public var kind: PlanKind
    public var title: String
    public var resultLine: String
    public var steps: [String]
    public var workSize: WorkSize
    public var benefit: String
    public var risk: String
    public var willChange: [String]
    public var willNotChange: [String]
    public init(
        id: StableID = .generate(prefix: "plan"), kind: PlanKind, title: String,
        resultLine: String, steps: [String], workSize: WorkSize, benefit: String,
        risk: String, willChange: [String], willNotChange: [String]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.resultLine = resultLine
        self.steps = steps
        self.workSize = workSize
        self.benefit = benefit
        self.risk = risk
        self.willChange = willChange
        self.willNotChange = willNotChange
    }
}

public struct PlanSet: Codable, Sendable {
    public var options: [PlanOption]
    public var recommendedID: StableID
    public var explanation: String
    public var contextSources: [String]
    public var missingInformation: [String]
    public var risks: [String]
    public init(
        options: [PlanOption], recommendedID: StableID, explanation: String,
        contextSources: [String], missingInformation: [String] = [], risks: [String] = []
    ) {
        self.options = options
        self.recommendedID = recommendedID
        self.explanation = explanation
        self.contextSources = contextSources
        self.missingInformation = missingInformation
        self.risks = risks
    }
}

// MARK: - Checklist

public enum ChecklistItemStatus: String, Codable, CaseIterable, Sendable {
    case notStarted, ready, running, waiting, blocked, needsApproval
    case completed, failed, cancelled
}

public enum CompletionEvidence: Codable, Hashable, Sendable {
    case fileCreated(path: String)
    case commitExists(sha: String)
    case testsPassed(summary: String)
    case buildPassed(summary: String)
    case documentProduced(path: String)
    case userConfirmed
}

public struct ChecklistItem: Codable, Hashable, Sendable, Identifiable {
    public var id: StableID
    public var action: String
    public var status: ChecklistItemStatus
    public var owner: String
    public var source: String
    public var projectID: StableID?
    public var repositoryID: StableID?
    public var obsidianNote: String?
    public var agentSessionID: StableID?
    public var createdAt: Date
    public var updatedAt: Date
    public var evidence: [CompletionEvidence]
    public init(
        id: StableID = .generate(prefix: "item"), action: String,
        status: ChecklistItemStatus = .notStarted, owner: String = "user",
        source: String, projectID: StableID? = nil, repositoryID: StableID? = nil,
        obsidianNote: String? = nil, agentSessionID: StableID? = nil,
        createdAt: Date = .init(), updatedAt: Date = .init(),
        evidence: [CompletionEvidence] = []
    ) {
        self.id = id
        self.action = action
        self.status = status
        self.owner = owner
        self.source = source
        self.projectID = projectID
        self.repositoryID = repositoryID
        self.obsidianNote = obsidianNote
        self.agentSessionID = agentSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.evidence = evidence
    }
}

public struct Checklist: Codable, Sendable {
    public var id: StableID
    public var title: String
    public var planID: StableID
    public var items: [ChecklistItem]
    public init(id: StableID = .generate(prefix: "cl"), title: String, planID: StableID, items: [ChecklistItem]) {
        self.id = id
        self.title = title
        self.planID = planID
        self.items = items
    }
}

/// Legal checklist state machine. Completion always requires evidence.
public enum ChecklistTransition {
    public static func isAllowed(from: ChecklistItemStatus, to: ChecklistItemStatus) -> Bool {
        if from == to { return false }
        switch (from, to) {
        case (.notStarted, .ready), (.notStarted, .cancelled),
             (.ready, .running), (.ready, .blocked), (.ready, .cancelled),
             (.running, .waiting), (.running, .needsApproval), (.running, .completed),
             (.running, .failed), (.running, .blocked), (.running, .cancelled),
             (.waiting, .running), (.waiting, .cancelled),
             (.blocked, .ready), (.blocked, .cancelled),
             (.needsApproval, .running), (.needsApproval, .cancelled),
             (.failed, .ready):
            return true
        default:
            return false
        }
    }
}

// MARK: - Agent

public enum AgentKind: String, Codable, Sendable { case claudeCode, codex, fake }

public enum AgentEventType: String, Codable, CaseIterable, Sendable {
    case sessionStarted, sessionResumed, userPromptReceived, thinkingStarted
    case planProposed, checklistCreated, checklistUpdated, questionAsked
    case permissionRequested, permissionApproved, permissionRejected
    case toolStarted, toolFinished, fileChanged, commandStarted, commandFinished
    case testStarted, testFinished, waitingForUser, completed, failed, cancelled
    case sessionEnded
}

public struct AgentEvent: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var eventID: StableID
    public var adapter: AgentKind
    public var sessionID: StableID
    public var timestamp: Date
    public var repositoryPath: String?
    public var workingDirectory: String?
    public var task: String?
    public var status: String
    public var summary: String
    public var filePath: String?
    public var command: String?
    public var checklistItemID: StableID?
    public var rawSource: String?
    public var type: AgentEventType
    public init(
        schemaVersion: Int = Schema.version, eventID: StableID = .generate(prefix: "evt"),
        adapter: AgentKind, sessionID: StableID, timestamp: Date = .init(),
        repositoryPath: String? = nil, workingDirectory: String? = nil,
        task: String? = nil, status: String = "ok", summary: String,
        filePath: String? = nil, command: String? = nil,
        checklistItemID: StableID? = nil, rawSource: String? = nil,
        type: AgentEventType
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.adapter = adapter
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.repositoryPath = repositoryPath
        self.workingDirectory = workingDirectory
        self.task = task
        self.status = status
        self.summary = summary
        self.filePath = filePath
        self.command = command
        self.checklistItemID = checklistItemID
        self.rawSource = rawSource
        self.type = type
    }
}

public struct AgentSession: Codable, Hashable, Sendable {
    public var id: StableID
    public var adapter: AgentKind
    public var repositoryID: StableID?
    public var task: String
    public var startedAt: Date
    public var endedAt: Date?
    public var state: String
    public init(
        id: StableID = .generate(prefix: "sess"), adapter: AgentKind,
        repositoryID: StableID? = nil, task: String, startedAt: Date = .init(),
        endedAt: Date? = nil, state: String = "running"
    ) {
        self.id = id
        self.adapter = adapter
        self.repositoryID = repositoryID
        self.task = task
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.state = state
    }
}

// MARK: - Preferences / audit

public struct PreferenceSignal: Codable, Hashable, Sendable, Identifiable {
    public var id: StableID
    public var whatWasLearned: String
    public var why: String
    public var sourceActions: [String]
    public var confidence: Double
    public var projectScope: StableID?
    public var lastUsed: Date?
    public var confirmedByUser: Bool
    public var createdAt: Date
    public init(
        id: StableID = .generate(prefix: "pref"), whatWasLearned: String, why: String,
        sourceActions: [String], confidence: Double, projectScope: StableID? = nil,
        lastUsed: Date? = nil, confirmedByUser: Bool = false, createdAt: Date = .init()
    ) {
        self.id = id
        self.whatWasLearned = whatWasLearned
        self.why = why
        self.sourceActions = sourceActions
        self.confidence = confidence
        self.projectScope = projectScope
        self.lastUsed = lastUsed
        self.confirmedByUser = confirmedByUser
        self.createdAt = createdAt
    }
}

public struct AuditEvent: Codable, Hashable, Sendable {
    public var id: StableID
    public var timestamp: Date
    public var action: String
    public var detail: String
    public init(id: StableID = .generate(prefix: "audit"), timestamp: Date = .init(), action: String, detail: String) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.detail = detail
    }
}

// MARK: - Panel state

public enum PanelState: String, Codable, Sendable {
    case hidden, collapsed, hovered, expandedCapture, thinking, planChoices
    case checklist, agentRunning, waitingForUser, completed, error, offline
}
