import Foundation

/// Redacts likely secrets before any text is shown in a context preview or
/// sent to an agent. Repository and note content is treated as untrusted.
public enum SecretRedactor {
    // Regex is immutable after creation; safe to share across threads.
    nonisolated(unsafe) private static let patterns: [(String, Regex<AnyRegexOutput>)] = {
        let raw: [String] = [
            // AWS access key id
            #"AKIA[0-9A-Z]{16}"#,
            // Generic api key / token / secret / password assignments
            #"(?i)(api[_-]?key|token|secret|passwd|password)\s*[:=]\s*['\"]?[A-Za-z0-9_\-\./+]{8,}['\"]?"#,
            // Bearer tokens
            #"(?i)bearer\s+[A-Za-z0-9\-_\.=]{16,}"#,
            // Private key blocks
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
            // Connection strings with embedded credentials
            #"[a-z][a-z0-9+\-.]*://[^\s:/@]+:[^\s@]+@[^\s]+"#,
            // GitHub tokens
            #"gh[pousr]_[A-Za-z0-9]{20,}"#,
        ]
        return raw.compactMap { pattern in
            (try? Regex(pattern)).map { (pattern, $0) }
        }
    }()

    public static func redact(_ text: String) -> String {
        var out = text
        for (_, regex) in patterns {
            out = out.replacing(regex) { _ in "[REDACTED]" }
        }
        return out
    }

    public static func containsLikelySecret(_ text: String) -> Bool {
        patterns.contains { _, regex in text.contains(regex) }
    }
}

/// Validates inbound local socket messages before they touch app state.
public enum EventValidation {
    public static let maxMessageBytes = 64 * 1024

    public enum Failure: Error, Equatable {
        case oversized(Int)
        case malformed(String)
        case unsupportedSchema(Int)
    }

    public static func decodeEvent(from data: Data) -> Result<AgentEvent, Failure> {
        guard data.count <= maxMessageBytes else { return .failure(.oversized(data.count)) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let event = try? decoder.decode(AgentEvent.self, from: data) else {
            return .failure(.malformed("not a valid AgentEvent payload"))
        }
        guard event.schemaVersion <= Schema.version else {
            return .failure(.unsupportedSchema(event.schemaVersion))
        }
        return .success(event)
    }
}

/// Deduplicates events by eventID with a bounded memory window.
public struct EventDeduplicator: Sendable {
    private var seen: Set<StableID> = []
    private var order: [StableID] = []
    private let capacity: Int

    public init(capacity: Int = 2048) { self.capacity = capacity }

    /// Returns true when the event is new.
    public mutating func admit(_ event: AgentEvent) -> Bool {
        if seen.contains(event.eventID) { return false }
        seen.insert(event.eventID)
        order.append(event.eventID)
        if order.count > capacity {
            let evicted = order.removeFirst()
            seen.remove(evicted)
        }
        return true
    }
}
