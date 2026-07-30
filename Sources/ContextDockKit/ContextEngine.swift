import Foundation

/// Optional second-layer semantic matcher. The app works without one.
public protocol SemanticMatcher: Sendable {
    func similarity(_ a: String, _ b: String) -> Double
}

public struct ContextEngineInput: Sendable {
    public var userInput: String
    public var repository: Repository?
    public var recentSessionIDs: [StableID]
    public var graph: KnowledgeGraph
    public var projects: [Project]
    public var mappings: [RepositoryMapping]
    public var pinnedNodeIDs: Set<StableID>
    public init(
        userInput: String, repository: Repository? = nil,
        recentSessionIDs: [StableID] = [], graph: KnowledgeGraph = .init(),
        projects: [Project] = [], mappings: [RepositoryMapping] = [],
        pinnedNodeIDs: Set<StableID> = []
    ) {
        self.userInput = userInput
        self.repository = repository
        self.recentSessionIDs = recentSessionIDs
        self.graph = graph
        self.projects = projects
        self.mappings = mappings
        self.pinnedNodeIDs = pinnedNodeIDs
    }
}

/// Deterministic-first context matching. Every match carries a human-readable reason.
public struct ContextEngine: Sendable {
    private let semantic: SemanticMatcher?

    public init(semantic: SemanticMatcher? = nil) { self.semantic = semantic }

    public func resolve(_ input: ContextEngineInput) -> ContextBundle {
        var matches: [ContextMatch] = []
        var missing: [String] = []
        var explanationParts: [String] = []
        let lowered = input.userInput.lowercased()

        // 1. Project via explicit mapping, then alias/name mention.
        var project: Project?
        if let repo = input.repository {
            if let mapping = input.mappings.first(where: { $0.repositoryName == repo.name }) {
                project = input.projects.first { $0.id == mapping.projectID }
                if project != nil { explanationParts.append("Repository '\(repo.name)' is mapped to project '\(project!.name)'.") }
            }
        }
        if project == nil {
            project = input.projects.first { proj in
                lowered.contains(proj.name.lowercased())
                    || proj.aliases.contains { lowered.contains($0.lowercased()) }
            }
            if let p = project { explanationParts.append("Input mentions project '\(p.name)' by name or alias.") }
        }
        if project == nil, input.repository != nil {
            missing.append("No project mapping for repository '\(input.repository!.name)'. Map it in Settings.")
        }

        // 2. Feature ID: F09-style tokens.
        let featureID = Self.featureID(in: input.userInput)
        if let fid = featureID { explanationParts.append("Input references feature ID \(fid).") }

        // 3. Node matching with explicit reasons.
        for node in input.graph.nodes.values where !node.archived {
            var reason: String?
            var score = 0.0
            if input.pinnedNodeIDs.contains(node.id) {
                reason = "manually pinned by the user"
                score = 1.0
            } else if let fid = featureID,
                      node.title.localizedCaseInsensitiveContains(fid) || node.tags.contains(where: { $0.caseInsensitiveCompare(fid) == .orderedSame }) {
                reason = "same feature ID (\(fid))"
                score = 0.95
            } else if let p = project, node.projectID == p.id {
                reason = "belongs to project '\(p.name)'"
                score = 0.7
            } else if lowered.contains(node.title.lowercased()) {
                reason = "mentioned by title in the input"
                score = 0.85
            } else if let repo = input.repository, node.type == .repository, node.title == repo.name {
                reason = "same repository"
                score = 0.9
            } else if node.type == .agentSession, input.recentSessionIDs.contains(node.id) {
                reason = "used in a recent agent session"
                score = 0.6
            } else if let sem = semantic {
                let sim = sem.similarity(input.userInput, node.title + " " + (node.summary ?? ""))
                if sim > 0.6 {
                    reason = "semantically similar (score \(String(format: "%.2f", sim)))"
                    score = sim * 0.5  // semantic layer never outranks deterministic hits
                }
            }
            if let reason { matches.append(ContextMatch(node: node, reason: reason, score: score)) }
        }
        matches.sort { $0.score > $1.score }
        matches = Array(matches.prefix(12))

        let confidence: Double
        if matches.isEmpty {
            confidence = project != nil ? 0.4 : 0.15
            missing.append("No knowledge nodes matched this input yet.")
        } else {
            confidence = min(0.95, matches.map(\.score).max()! * (project != nil ? 1.0 : 0.8))
        }

        let sessions = matches.filter { $0.node.type == .agentSession }.map(\.node.id)

        return ContextBundle(
            project: project,
            repository: input.repository,
            featureID: featureID,
            matches: matches,
            relatedFiles: [],
            relatedSessions: sessions,
            confidence: confidence,
            explanation: explanationParts.isEmpty
                ? "No deterministic signals matched; showing best-effort context only."
                : explanationParts.joined(separator: " "),
            missingInformation: missing,
            conflicts: []
        )
    }

    /// Finds tokens like "F09" / "f12" used as feature identifiers.
    public static func featureID(in text: String) -> String? {
        let pattern = /\b[Ff]([0-9]{1,3})\b/
        guard let match = text.firstMatch(of: pattern) else { return nil }
        return "F" + match.1
    }
}
