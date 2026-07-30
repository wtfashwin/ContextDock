import Foundation

public struct PlannerInput: Sendable {
    public var request: String
    public var context: ContextBundle
    public var constraints: [String]
    public var currentChecklist: Checklist?
    public init(request: String, context: ContextBundle, constraints: [String] = [], currentChecklist: Checklist? = nil) {
        self.request = request
        self.context = context
        self.constraints = constraints
        self.currentChecklist = currentChecklist
    }
}

/// Provider-agnostic planning. Local rules mode ships first; AI-assisted mode
/// conforms to the same protocol so no provider is hard-coded into the core.
public protocol PlannerEngine: Sendable {
    func plan(_ input: PlannerInput) async throws -> PlanSet
}

/// Deterministic local-rules planner. Always returns three meaningfully
/// different plans: recommended / fastest / safest.
public struct LocalRulesPlanner: PlannerEngine {
    public init() {}

    public func plan(_ input: PlannerInput) async throws -> PlanSet {
        let subject = Self.subject(from: input.request, context: input.context)
        let sources = input.context.matches.map { "\($0.node.title) — \($0.reason)" }

        let recommended = PlanOption(
            kind: .recommended,
            title: "Continue \(subject) from last known state",
            resultLine: "Resume the work where it stopped, verified against current sources.",
            steps: [
                "Re-read the matched notes and latest session summary for \(subject).",
                "List open items and pick the first incomplete one.",
                "Draft the next section or change.",
                "Record the outcome back to the project note.",
            ],
            workSize: .medium,
            benefit: "Best balance of correctness, speed, and future value.",
            risk: "Assumes matched context is current; verify sources before deep work.",
            willChange: ["Project note '\(subject)'", "Checklist state"],
            willNotChange: ["Unrelated projects", "Repository files without an explicit task"]
        )
        let fastest = PlanOption(
            kind: .fastest,
            title: "Smallest useful next step",
            resultLine: "One concrete increment shipped in a single sitting.",
            steps: [
                "Pick the single most obvious open item for \(subject).",
                "Do only that item.",
                "Note the result in the Inbox.",
            ],
            workSize: .small,
            benefit: "Momentum with minimal time investment.",
            risk: "May skip context review; larger gaps stay unaddressed.",
            willChange: ["One checklist item", "Inbox note"],
            willNotChange: ["Project structure", "Other open items"]
        )
        let safest = PlanOption(
            kind: .safest,
            title: "Audit context, then continue",
            resultLine: "Verified, low-risk continuation with a full source review.",
            steps: [
                "Cross-check every matched source for staleness.",
                "Reconcile conflicts between notes and repository state.",
                "Write a short state-of-work summary.",
                "Then continue \(subject) with confirmed context.",
                "Ask for review before finalising.",
            ],
            workSize: .large,
            benefit: "Lowest risk of building on stale or wrong context.",
            risk: "Slowest path; audit may surface work you did not plan for.",
            willChange: ["Project note", "A new state-of-work summary note", "Checklist"],
            willNotChange: ["Anything without a verified source"]
        )

        return PlanSet(
            options: [recommended, fastest, safest],
            recommendedID: recommended.id,
            explanation: "Local rules mode: plans derived from matched context (confidence \(String(format: "%.0f", input.context.confidence * 100))%). "
                + input.context.explanation,
            contextSources: sources,
            missingInformation: input.context.missingInformation,
            risks: input.context.conflicts
        )
    }

    static func subject(from request: String, context: ContextBundle) -> String {
        if let fid = context.featureID, let project = context.project {
            return "\(project.name) \(fid)"
        }
        if let project = context.project { return project.name }
        let words = request.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "the current work" : words
    }
}

public enum PlanValidation {
    /// A plan set is valid only when it has exactly three meaningfully different options.
    public static func validate(_ set: PlanSet) -> [String] {
        var problems: [String] = []
        if set.options.count != 3 { problems.append("Expected 3 options, got \(set.options.count).") }
        if !set.options.contains(where: { $0.id == set.recommendedID }) {
            problems.append("Recommended plan ID not present in options.")
        }
        let titles = Set(set.options.map(\.title))
        if titles.count != set.options.count { problems.append("Plan titles are not distinct.") }
        let kinds = Set(set.options.map(\.kind))
        if kinds.count != set.options.count { problems.append("Plan kinds are not distinct.") }
        for opt in set.options where opt.steps.isEmpty {
            problems.append("Plan '\(opt.title)' has no steps.")
        }
        return problems
    }
}

/// Builds a checklist from a selected plan. Evidence-based completion only.
public enum ChecklistBuilder {
    public static func build(from plan: PlanOption, context: ContextBundle, notePath: String?) -> Checklist {
        let items = plan.steps.map { step in
            ChecklistItem(
                action: step,
                status: .ready,
                owner: "user",
                source: "plan:\(plan.id.raw)",
                projectID: context.project?.id,
                repositoryID: context.repository?.id,
                obsidianNote: notePath
            )
        }
        return Checklist(title: plan.title, planID: plan.id, items: items)
    }
}
