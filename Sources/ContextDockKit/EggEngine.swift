import Foundation

// MARK: - EggEngine: every easter egg is pure, named, and tested
//
// Eggs trigger on (text typed) or (feed events). Each returns a Trigger
// describing what happens AND what it means — the UI shows both, so no egg
// is ever a mystery checkbox.

public enum EggID: String, Codable, Sendable, CaseIterable {
    case party, midnight, gg
    public var title: String {
        switch self {
        case .party: return "Parade mode"
        case .midnight: return "Midnight watch"
        case .gg: return "Good game"
        }
    }
    public var meaning: String {
        switch self {
        case .party: return "Everything shipping, nothing blocked — a celebration, not a setting. Also unlocks the Retro pack."
        case .midnight: return "For the 2am sessions. The island dims to void-black and the Abyss residents nod at you. Type it between midnight and 5am."
        case .gg: return "Fires itself when the last active engine goes green with nothing waiting. Respect for a clean board."
        }
    }
}

public struct EggTrigger: Hashable, Sendable {
    public var id: EggID
    public init(_ id: EggID) { self.id = id }
}

public enum EggEngine: Sendable {
    /// Text-typed eggs. Pure: same text → same result.
    public static func typed(_ text: String) -> EggTrigger? {
        let t = text.lowercased()
        if t.contains("party") { return EggTrigger(.party) }
        if t.contains("midnight") { return EggTrigger(.midnight) }
        return nil
    }

    /// Feed-driven eggs: last active session just finished, nothing urgent left.
    public static func feedDrained(activeBefore: Int, activeAfter: Int, urgentAfter: Int, hadDone: Bool) -> EggTrigger? {
        if activeBefore > 0 && activeAfter == 0 && urgentAfter == 0 && hadDone {
            return EggTrigger(.gg)
        }
        return nil
    }
}
