import AppKit
import ContextDockKit
import Foundation
import Observation

/// MainActor UI state + orchestration. All engine work runs off the main thread.
@Observable
@MainActor
final class DockModel {
    var panelState: PanelState = .hidden {
        didSet { onStateChange?() }
    }
    var onStateChange: (() -> Void)?

    // Collapsed island info
    var status: String = "Idle"
    var activeAgentCount: Int = 0
    var waitingForUser = false

    // Context
    var repository: Repository?
    var contextBundle: ContextBundle?
    var planSet: PlanSet?
    var selectedPlan: PlanOption?
    var checklist: Checklist?
    var session: AgentSession?
    var recentEvents: [AgentEvent] = []
    var lastError: String?
    var showSources = false

    // Persistence
    private var document = StoreDocument()
    private let store = LocalStore()
    private let planner = LocalRulesPlanner()
    private let resolver = ProjectResolver()
    var vaultPath: String? {
        get { document.settings["vaultPath"] }
        set {
            document.settings["vaultPath"] = newValue
            persist()
        }
    }

    /// Active learned lessons for the current project (self-learning surface).
    var activeLessons: [String] {
        LearningEngine.lessons(document.preferences, projectID: contextBundle?.project?.id)
    }

    /// Agent the learning engine currently trusts most for this project.
    var preferredAgent: AgentKind? {
        LearningEngine.preferredAgent(document.preferences, projectID: contextBundle?.project?.id)
    }

    func currentExpandedState() -> PanelState {
        if planSet != nil && selectedPlan == nil { return .planChoices }
        if checklist != nil && session != nil { return .agentRunning }
        if checklist != nil { return .checklist }
        return .expandedCapture
    }

    // MARK: - Lifecycle

    func bootstrap() {
        if let loaded = try? store.load() { document = loaded }
        refreshRepository()
    }

    /// Auto-detects the active repository: last used if still valid, else the
    /// most recently active git repo under Desktop/Projects/Developer/etc.
    func refreshRepository() {
        let lastUsed = document.settings["lastRepositoryPath"]
        Task.detached { [resolver] in
            let scanner = RepoScanner(resolver: resolver)
            let repo = scanner.detectActiveRepository(lastUsedPath: lastUsed)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.repository = repo
                self.status = repo.map { "\($0.name) · \($0.branch ?? "?")" } ?? "No repository"
                if let repo {
                    self.document.settings["lastRepositoryPath"] = repo.rootPath
                    RepoKnowledgeIngestor().ingest(repository: repo, into: &self.document)
                    self.persist()
                }
            }
        }
    }

    func persist() {
        try? store.save(document)
    }

    func recordAudit(_ audit: AuditEvent) {
        document.audit.append(audit)
    }

    // MARK: - Think flow

    func think(input: String) {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        panelState = .thinking
        lastError = nil
        let engineInput = ContextEngineInput(
            userInput: input, repository: repository,
            graph: document.graph, projects: document.projects, mappings: document.mappings
        )
        let planner = makePlanner()
        Task {
            let bundle = ContextEngine().resolve(engineInput)
            do {
                let plans = try await planner.plan(PlannerInput(request: input, context: bundle))
                self.contextBundle = bundle
                self.planSet = self.applyLearnedRecommendation(to: plans, projectID: bundle.project?.id)
                self.panelState = .planChoices
            } catch {
                self.lastError = "\(error)"
                self.panelState = .error
            }
        }
    }

    /// AI planner when a CLI is installed (learned agent preference decides
    /// which), local rules otherwise. Never hard-coded to one provider.
    private func makePlanner() -> any PlannerEngine {
        let projectID = contextBundle?.project?.id
        let lessons = LearningEngine.lessons(document.preferences, projectID: projectID)
        let preferred = LearningEngine.preferredAgent(document.preferences, projectID: projectID)
        let order: [AgentKind] = preferred == .codex ? [.codex, .claudeCode] : [.claudeCode, .codex]
        for kind in order {
            let name = kind == .claudeCode ? "claude" : "codex"
            if let path = Self.findExecutable(name) {
                return CLIPlanner(kind: kind, executablePath: path, lessons: lessons)
            }
        }
        return LocalRulesPlanner()
    }

    /// Learned plan-kind preference re-points the recommendation badge.
    private func applyLearnedRecommendation(to plans: PlanSet, projectID: StableID?) -> PlanSet {
        guard let kind = LearningEngine.preferredPlanKind(document.preferences, projectID: projectID),
              let match = plans.options.first(where: { $0.kind == kind })
        else { return plans }
        var plans = plans
        plans.recommendedID = match.id
        return plans
    }

    func select(plan: PlanOption) {
        selectedPlan = plan
        guard let bundle = contextBundle else { return }
        let notePath = "ContextDock/Projects/\(bundle.project?.name ?? "Inbox").md"
        let checklist = ChecklistBuilder.build(from: plan, context: bundle, notePath: notePath)
        self.checklist = checklist
        document.checklists.append(checklist)
        document.audit.append(AuditEvent(action: "plan.selected", detail: plan.title))
        LearningEngine.recordPlanChoice(&document.preferences, kind: plan.kind, projectID: bundle.project?.id)
        persist()
        writeChecklistToVault(checklist, project: bundle.project)
        panelState = .checklist
    }

    func regeneratePlans() {
        planSet = nil
        selectedPlan = nil
        panelState = .expandedCapture
    }

    private func writeChecklistToVault(_ checklist: Checklist, project: Project?) {
        guard let vaultPath else { return }
        let vault = ObsidianVault(rootURL: URL(fileURLWithPath: vaultPath))
        let notePath = "ContextDock/Projects/\(project?.name ?? "Inbox").md"
        let stamp = ISO8601DateFormatter().string(from: Date())
        var lines = ["", "### \(checklist.title) (\(stamp))"]
        lines += checklist.items.map { "- [ ] \($0.action) ^\($0.id.raw)" }
        do {
            try vault.appendToSection(notePath: notePath, heading: "Current work", lines: lines)
            document.audit.append(AuditEvent(action: "vault.write", detail: notePath))
        } catch {
            lastError = "Vault write failed: \(error)"
        }
        persist()
    }

    // MARK: - Agent dispatch

    func dispatch(kind: AgentKind) {
        guard let plan = selectedPlan, let checklist else { return }
        let package = AgentTaskPackage(
            planTitle: plan.title,
            planSteps: plan.steps,
            checklist: checklist.items.map(\.action),
            projectName: contextBundle?.project?.name,
            repositoryPath: repository?.rootPath,
            noteLinks: contextBundle?.matches.map(\.node.title) ?? [],
            expectedOutput: plan.resultLine,
            doneConditions: plan.willChange
        )
        let adapter: any AgentAdapter
        switch kind {
        case .fake: adapter = FakeAgentAdapter()
        case .claudeCode:
            adapter = CLIAgentAdapter(kind: .claudeCode, executablePath: Self.findExecutable("claude") ?? "/usr/local/bin/claude")
        case .codex:
            adapter = CLIAgentAdapter(kind: .codex, executablePath: Self.findExecutable("codex") ?? "/usr/local/bin/codex")
        }
        panelState = .agentRunning
        activeAgentCount = 1
        Task {
            do {
                let session = try await adapter.dispatch(task: package) { event in
                    Task { @MainActor in self.ingest(event: event) }
                }
                self.session = session
            } catch {
                self.lastError = "Dispatch failed: \(error)"
                self.panelState = .error
                self.activeAgentCount = 0
            }
        }
    }

    nonisolated static func findExecutable(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)",
            "\(NSHomeDirectory())/.claude/local/\(name)",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func ingest(event: AgentEvent) {
        recentEvents.append(event)
        if recentEvents.count > 200 { recentEvents.removeFirst(recentEvents.count - 200) }
        document.events.append(event)
        switch event.type {
        case .checklistUpdated:
            advanceChecklist(evidence: event.summary)
        case .waitingForUser, .questionAsked, .permissionRequested:
            waitingForUser = true
            panelState = .waitingForUser
        case .completed:
            waitingForUser = false
            activeAgentCount = 0
            panelState = .completed
            status = "Completed"
            if event.adapter != .fake {
                LearningEngine.recordAgentOutcome(
                    &document.preferences, agent: event.adapter, succeeded: true,
                    projectID: contextBundle?.project?.id
                )
            }
        case .failed:
            activeAgentCount = 0
            lastError = event.summary
            panelState = .error
            if event.adapter != .fake {
                LearningEngine.recordAgentOutcome(
                    &document.preferences, agent: event.adapter, succeeded: false,
                    projectID: contextBundle?.project?.id
                )
            }
        case .sessionEnded:
            activeAgentCount = 0
        default:
            break
        }
        persist()
    }

    /// Marks the first running/ready item complete with the event as evidence.
    private func advanceChecklist(evidence: String) {
        guard var checklist else { return }
        if let index = checklist.items.firstIndex(where: { $0.status == .ready || $0.status == .running }) {
            var item = checklist.items[index]
            if item.status == .ready { item.status = .running }
            if ChecklistTransition.isAllowed(from: item.status, to: .completed) {
                item.status = .completed
                item.evidence.append(.documentProduced(path: evidence))
                item.updatedAt = Date()
            }
            checklist.items[index] = item
            self.checklist = checklist
            if let docIndex = document.checklists.firstIndex(where: { $0.id == checklist.id }) {
                document.checklists[docIndex] = checklist
            }
        }
    }

    func reset() {
        contextBundle = nil
        planSet = nil
        selectedPlan = nil
        checklist = nil
        session = nil
        lastError = nil
        waitingForUser = false
        panelState = .expandedCapture
    }

    func openObsidianNote() {
        guard let vaultPath, let project = contextBundle?.project else { return }
        let vaultName = URL(fileURLWithPath: vaultPath).lastPathComponent
        if let url = ObsidianURI.open(vault: vaultName, file: "ContextDock/Projects/\(project.name)") {
            NSWorkspace.shared.open(url)
        }
    }
}
