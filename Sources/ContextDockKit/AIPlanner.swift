import Foundation

/// AI-assisted planner backed by a local agent CLI (Claude Code or Codex).
/// Same PlannerEngine surface as LocalRulesPlanner; falls back to local rules
/// whenever the CLI is missing, times out, or returns unparseable output —
/// the island never blocks on a model.
public struct CLIPlanner: PlannerEngine {
    public let kind: AgentKind
    public let executablePath: String
    public let timeout: TimeInterval
    public let lessons: [String]
    private let fallback = LocalRulesPlanner()

    public init(kind: AgentKind, executablePath: String, lessons: [String] = [], timeout: TimeInterval = 45) {
        self.kind = kind
        self.executablePath = executablePath
        self.lessons = lessons
        self.timeout = timeout
    }

    public var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    public func plan(_ input: PlannerInput) async throws -> PlanSet {
        guard isAvailable else { return try await fallback.plan(input) }
        let prompt = Self.prompt(for: input, lessons: lessons)
        let args: [String]
        switch kind {
        case .claudeCode:
            args = ["-p", prompt, "--output-format", "json", "--max-turns", "1"]
        case .codex:
            args = ["exec", "--json", prompt]
        case .fake:
            return try await fallback.plan(input)
        }
        guard let stdout = await Self.run(executablePath: executablePath, args: args, timeout: timeout),
              let set = Self.parsePlanSet(from: stdout, context: input.context)
        else {
            return try await fallback.plan(input)
        }
        let problems = PlanValidation.validate(set)
        guard problems.isEmpty else { return try await fallback.plan(input) }
        return set
    }

    // MARK: - Prompt

    static func prompt(for input: PlannerInput, lessons: [String]) -> String {
        var lines: [String] = [
            "You are the planning engine inside ContextDock, a macOS thinking island.",
            "Produce exactly three meaningfully different plans for the request below.",
            "Respond with ONLY a JSON object, no markdown fences, matching:",
            #"{"plans":[{"kind":"recommended|fastest|safest","title":"...","resultLine":"...","steps":["..."],"workSize":"small|medium|large","benefit":"...","risk":"...","willChange":["..."],"willNotChange":["..."]}]}"#,
            "One plan per kind: recommended, fastest, safest.",
            "",
            "## Request",
            input.request,
        ]
        if let project = input.context.project { lines.append("Project: \(project.name)") }
        if let repo = input.context.repository { lines.append("Repository: \(repo.rootPath) (branch \(repo.branch ?? "?"))") }
        if !input.context.matches.isEmpty {
            lines.append("## Matched context")
            lines += input.context.matches.prefix(8).map { "- \($0.node.title): \($0.reason)" }
        }
        if !lessons.isEmpty {
            lines.append("## Learned preferences (apply where sensible)")
            lines += lessons.map { "- \($0)" }
        }
        if !input.constraints.isEmpty {
            lines.append("## Constraints")
            lines += input.constraints.map { "- \($0)" }
        }
        return SecretRedactor.redact(lines.joined(separator: "\n"))
    }

    // MARK: - CLI execution

    static func run(executablePath: String, args: [String], timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = args
                let out = Pipe()
                process.standardOutput = out
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let deadline = DispatchTime.now() + timeout
                DispatchQueue.global().asyncAfter(deadline: deadline) {
                    if process.isRunning { process.terminate() }
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    // MARK: - Parsing

    struct WirePlan: Codable {
        var kind: String
        var title: String
        var resultLine: String
        var steps: [String]
        var workSize: String
        var benefit: String
        var risk: String
        var willChange: [String]
        var willNotChange: [String]
    }
    struct WirePlanSet: Codable { var plans: [WirePlan] }

    /// Accepts raw model text, a Claude Code `--output-format json` envelope
    /// (`{"result": "..."}`), or Codex JSONL — finds the first parseable
    /// `{"plans": ...}` object anywhere in the output.
    static func parsePlanSet(from stdout: String, context: ContextBundle) -> PlanSet? {
        var texts: [String] = [stdout]
        // Claude envelope
        if let data = stdout.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = obj["result"] as? String {
            texts.insert(result, at: 0)
        }
        // Codex JSONL: collect message text fields
        for line in stdout.split(separator: "\n") {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let msg = obj["msg"] as? [String: Any], let text = msg["message"] as? String {
                    texts.insert(text, at: 0)
                }
                if let text = obj["text"] as? String { texts.insert(text, at: 0) }
            }
        }
        for text in texts {
            if let set = decodePlans(in: text, context: context) { return set }
        }
        return nil
    }

    private static func decodePlans(in text: String, context: ContextBundle) -> PlanSet? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        // Scan balanced braces from each '{' until a decodable object is found.
        var index: String.Index? = start
        while let open = index {
            if let close = matchingBrace(in: text, from: open) {
                let candidate = String(text[open...close])
                if let data = candidate.data(using: .utf8),
                   let wire = try? JSONDecoder().decode(WirePlanSet.self, from: data),
                   wire.plans.count == 3 {
                    return build(from: wire, context: context)
                }
            }
            let next = text.index(after: open)
            index = text[next...].firstIndex(of: "{")
        }
        return nil
    }

    private static func matchingBrace(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if escaped { escaped = false } else if ch == "\\" { escaped = true } else if ch == "\"" { inString.toggle() } else if !inString {
                if ch == "{" { depth += 1 }
                if ch == "}" { depth -= 1; if depth == 0 { return i } }
            }
            i = text.index(after: i)
        }
        return nil
    }

    private static func build(from wire: WirePlanSet, context: ContextBundle) -> PlanSet? {
        var options: [PlanOption] = []
        for plan in wire.plans {
            guard let kind = PlanKind(rawValue: plan.kind),
                  let size = WorkSize(rawValue: plan.workSize),
                  !plan.steps.isEmpty
            else { return nil }
            options.append(PlanOption(
                kind: kind, title: plan.title, resultLine: plan.resultLine,
                steps: plan.steps, workSize: size, benefit: plan.benefit,
                risk: plan.risk, willChange: plan.willChange, willNotChange: plan.willNotChange
            ))
        }
        guard let recommended = options.first(where: { $0.kind == .recommended }) else { return nil }
        return PlanSet(
            options: options,
            recommendedID: recommended.id,
            explanation: "AI planner: plans generated from live context (confidence \(String(format: "%.0f", context.confidence * 100))%). " + context.explanation,
            contextSources: context.matches.map { "\($0.node.title) — \($0.reason)" },
            missingInformation: context.missingInformation,
            risks: context.conflicts
        )
    }
}
