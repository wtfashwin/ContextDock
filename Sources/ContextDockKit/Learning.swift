import Foundation

/// Hermes-style self-learning on top of PreferenceLearner: every user choice
/// and agent outcome becomes a transparent, reversible preference signal.
/// Active signals feed back into planning (as lessons in the planner prompt)
/// and dispatch (preferred agent per project). No rule from a single action.
public enum LearningEngine {
    // MARK: - Observation

    public static func recordPlanChoice(
        _ preferences: inout [PreferenceSignal], kind: PlanKind, projectID: StableID?
    ) {
        PreferenceLearner.observe(
            &preferences,
            learned: "Prefers '\(kind.rawValue)' plans",
            why: "User repeatedly picked the \(kind.rawValue) option for this project.",
            sourceAction: "plan.selected:\(kind.rawValue)",
            projectScope: projectID
        )
    }

    public static func recordAgentOutcome(
        _ preferences: inout [PreferenceSignal], agent: AgentKind, succeeded: Bool, projectID: StableID?
    ) {
        if succeeded {
            PreferenceLearner.observe(
                &preferences,
                learned: "Agent '\(agent.rawValue)' works well",
                why: "Dispatches to \(agent.rawValue) completed successfully.",
                sourceAction: "agent.completed:\(agent.rawValue)",
                projectScope: projectID
            )
        } else {
            PreferenceLearner.observe(
                &preferences,
                learned: "Agent '\(agent.rawValue)' has failed here",
                why: "Dispatches to \(agent.rawValue) failed; treat with caution.",
                sourceAction: "agent.failed:\(agent.rawValue)",
                projectScope: projectID
            )
        }
    }

    public static func recordCorrection(
        _ preferences: inout [PreferenceSignal], lesson: String, projectID: StableID?
    ) {
        PreferenceLearner.observe(
            &preferences,
            learned: lesson,
            why: "Explicit user correction.",
            sourceAction: "user.correction",
            projectScope: projectID
        )
    }

    // MARK: - Application

    /// Active lessons for a project (plus global ones), for planner prompts and UI.
    public static func lessons(_ preferences: [PreferenceSignal], projectID: StableID?) -> [String] {
        preferences
            .filter { PreferenceLearner.isActive($0) }
            .filter { $0.projectScope == nil || $0.projectScope == projectID }
            .sorted { $0.confidence > $1.confidence }
            .map(\.whatWasLearned)
    }

    /// Preferred plan kind once the user has shown a consistent pattern.
    public static func preferredPlanKind(_ preferences: [PreferenceSignal], projectID: StableID?) -> PlanKind? {
        for kind in [PlanKind.recommended, .fastest, .safest] {
            let match = preferences.first {
                PreferenceLearner.isActive($0)
                    && ($0.projectScope == nil || $0.projectScope == projectID)
                    && $0.whatWasLearned == "Prefers '\(kind.rawValue)' plans"
            }
            if match != nil { return kind }
        }
        return nil
    }

    /// Agent with the strongest active success signal and no stronger failure signal.
    public static func preferredAgent(_ preferences: [PreferenceSignal], projectID: StableID?) -> AgentKind? {
        func signal(_ learned: String) -> Double {
            preferences
                .filter { ($0.projectScope == nil || $0.projectScope == projectID) && $0.whatWasLearned == learned }
                .map(\.confidence).max() ?? 0
        }
        let scored: [(AgentKind, Double)] = [AgentKind.claudeCode, .codex].map { agent in
            (agent, signal("Agent '\(agent.rawValue)' works well") - signal("Agent '\(agent.rawValue)' has failed here"))
        }
        let best = scored.max { $0.1 < $1.1 }
        guard let best, best.1 >= 0.6 else { return nil }
        return best.0
    }
}
