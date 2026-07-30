import Foundation

/// Everything ContextDock persists locally, versioned as one document.
/// Storage choice: JSON in Application Support via atomic writes.
/// Rationale (ADR-003): the dataset is small (nodes/edges/checklists), human-
/// debuggable JSON beats SQLite for a v1, and the repository pattern below
/// means swapping in SQLite/SwiftData later touches only this file.
public struct StoreDocument: Codable, Sendable {
    public var schemaVersion: Int = Schema.version
    public var projects: [Project] = []
    public var repositories: [Repository] = []
    public var mappings: [RepositoryMapping] = []
    public var graph: KnowledgeGraph = .init()
    public var checklists: [Checklist] = []
    public var sessions: [AgentSession] = []
    public var events: [AgentEvent] = []
    public var preferences: [PreferenceSignal] = []
    public var audit: [AuditEvent] = []
    public var settings: [String: String] = [:]
    public init() {}
}

public protocol LocalStoreProtocol: Sendable {
    func load() throws -> StoreDocument
    func save(_ document: StoreDocument) throws
}

/// Atomic JSON persistence under Application Support/ContextDock.
public struct LocalStore: LocalStoreProtocol {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appendingPathComponent("ContextDock/store.json")
        }
    }

    public func load() throws -> StoreDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return StoreDocument() }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoreDocument.self, from: data)
    }

    public func save(_ document: StoreDocument) throws {
        var document = document
        // Bounded history: keep the newest 5k events / 2k audit records.
        if document.events.count > 5000 { document.events.removeFirst(document.events.count - 5000) }
        if document.audit.count > 2000 { document.audit.removeFirst(document.audit.count - 2000) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Preference learning

/// Transparent, reversible preference learning. Nothing becomes a permanent
/// rule from a single action: signals accumulate confidence per observation.
public enum PreferenceLearner {
    public static func observe(
        _ preferences: inout [PreferenceSignal],
        learned: String, why: String, sourceAction: String, projectScope: StableID?
    ) {
        if let index = preferences.firstIndex(where: { $0.whatWasLearned == learned && $0.projectScope == projectScope }) {
            var existing = preferences[index]
            existing.sourceActions.append(sourceAction)
            existing.confidence = min(1.0, existing.confidence + 0.15)
            existing.lastUsed = Date()
            preferences[index] = existing
        } else {
            preferences.append(PreferenceSignal(
                whatWasLearned: learned, why: why, sourceActions: [sourceAction],
                confidence: 0.3, projectScope: projectScope
            ))
        }
    }

    /// A preference only influences behaviour once confident or user-confirmed.
    public static func isActive(_ signal: PreferenceSignal) -> Bool {
        signal.confirmedByUser || signal.confidence >= 0.6
    }
}
