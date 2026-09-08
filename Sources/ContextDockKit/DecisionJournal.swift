import Foundation

// MARK: - Decision journal: learn in daylight, never automate
//
// Rule the user asked for: after 3–4 similar decisions, the 5th must NOT be
// automated. Instead the island surfaces a pattern insight — "here's what I
// noticed about how you decide" — with Apply / Keep asking / Never for this.
// Insights are suggestions with confidence; the user always decides.

public enum DecisionKind: String, Codable, Sendable, CaseIterable {
    case planChoice, approval, questionAnswer, jump, dismissal
}

public struct UserDecision: Codable, Hashable, Sendable {
    public var id: StableID
    public var kind: DecisionKind
    public var label: String
    public var projectID: StableID?
    public var at: Date
    public init(id: StableID = .generate(prefix: "dec"), kind: DecisionKind, label: String, projectID: StableID? = nil, at: Date = .init()) {
        self.id = id; self.kind = kind; self.label = label; self.projectID = projectID; self.at = at
    }
}

public struct PatternInsight: Hashable, Sendable {
    public var title: String
    public var detail: String
    public var confidence: Double
    public var decisionIDs: [StableID]
    public init(title: String, detail: String, confidence: Double, decisionIDs: [StableID]) {
        self.title = title; self.detail = detail; self.confidence = confidence; self.decisionIDs = decisionIDs
    }
}

public enum DecisionJournal: Sendable {
    public static let capacity = 200
    public static let patternThreshold = 4
    public static let windowDays = 7.0

    public static func record(_ decisions: inout [UserDecision], _ decision: UserDecision) {
        decisions.append(decision)
        if decisions.count > capacity { decisions.removeFirst(decisions.count - capacity) }
    }

    /// Returns an insight when ≥4 same-kind (+same project scope) decisions
    /// land inside 7 days and none was already surfaced (seenIDs excludes them).
    public static func insight(
        in decisions: [UserDecision], seenIDs: Set<StableID> = []
    ) -> PatternInsight? {
        let cutoff = Date().addingTimeInterval(-windowDays * 86400)
        let fresh = decisions.filter { $0.at >= cutoff && !seenIDs.contains($0.id) }
        guard fresh.count >= patternThreshold else { return nil }
        // Group by (kind, project) — a dedicated key: UserDecision's synthesized
        // Hashable includes its random id + timestamp, which would shard every
        // decision into a group of one (caught by test).
        struct Key: Hashable { var kind: DecisionKind; var project: StableID? }
        var byKey: [Key: [UserDecision]] = [:]
        for d in fresh {
            byKey[Key(kind: d.kind, project: d.projectID), default: []].append(d)
        }
        guard let best = byKey.values.max(by: { $0.count < $1.count }),
              best.count >= patternThreshold else { return nil }
        let kind = best[0].kind
        let confidence = min(0.9, 0.5 + Double(best.count - patternThreshold) * 0.1)
        let scope = best[0].projectID.map { _ in "in this project " } ?? ""
        return PatternInsight(
            title: "Your call, \(kindNoun(kind)) ×\(best.count)",
            detail: "You've made this kind of call \(best.count)× \(scope)this week (\(examples(best))). I won't automate it — want a one-tap shortcut next time, or keep deciding fresh?",
            confidence: confidence,
            decisionIDs: best.map(\.id)
        )
    }

    private static func kindNoun(_ kind: DecisionKind) -> String {
        switch kind {
        case .planChoice: return "plan picks"
        case .approval: return "approvals"
        case .questionAnswer: return "answers"
        case .jump: return "jumps"
        case .dismissal: return "dismissals"
        }
    }

    private static func examples(_ ds: [UserDecision]) -> String {
        ds.prefix(2).map { $0.label.truncated(to: 28) }.joined(separator: "; ")
    }
}

private extension String {
    func truncated(to n: Int) -> String {
        count <= n ? self : String(prefix(n)) + "…"
    }
}
