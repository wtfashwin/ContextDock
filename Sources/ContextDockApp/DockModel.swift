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

    func currentExpandedState() -> PanelState {
        if planSet != nil && selectedPlan == nil { return .planChoices }
        if checklist != nil && session != nil { return .agentRunning }
        if checklist != nil { return .checklist }
        return .expandedCapture
    }

    // MARK: - Lifecycle

    func bootstrap() {
        if let loaded = try? store.load() { document = loaded }
        seedDemoDataIfEmpty()
        // Detect repository from the front process's likely cwd is not possible
        // without extra permissions; use last-known or home-based detection.
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/IRIS_Allo_MVP_Dec_2025"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        ]
        Task.detached { [resolver] in
            let repo = candidates.compactMap { resolver.resolveRepository(at: $0) }.first
            await MainActor.run { [weak self] in
                self?.repository = repo
                self?.status = repo.map { "\($0.name) · \($0.branch ?? "?")" } ?? "No repository"
            }
        }
    }

    func persist() {
        try? store.save(document)
    }

    func recordAudit(_ audit: AuditEvent) {
        document.audit.append(audit)
    }

    private func seedDemoDataIfEmpty() {
        guard document.projects.isEmpty else { return }
        let project = Project(id: StableID("project-iris-v2"), name: "IRIS V2", aliases: ["iris", "iris v2"], obsidianFolder: "Projects")
        document.projects = [project]
        document.mappings = [
            RepositoryMapping(repositoryName: "IRIS_Allo_MVP_Dec_2025", projectID: project.id),
            RepositoryMapping(repositoryName: "Sylox_v2_Core_App", projectID: project.id),
        ]
        var graph = document.graph
        graph.upsertNode(KnowledgeNode(id: StableID("node-f09"), title: "F09 Access Governance", type: .feature, projectID: project.id, source: "seed", tags: ["F09"], summary: "Access governance PRD work"))
        graph.upsertNode(KnowledgeNode(id: StableID("node-dec-f12"), title: "F12 is a separate feature", type: .decision, projectID: project.id, source: "seed"))
        graph.upsertNode(KnowledgeNode(id: StableID("node-dec-pg"), title: "PostgreSQL and OneDrive first", type: .decision, projectID: project.id, source: "seed"))
        graph.addEdge(KnowledgeEdge(sourceID: StableID("node-dec-f12"), targetID: StableID("node-f09"), type: .relatesTo, evidence: "seed"))
        document.graph = graph
        persist()
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
        let planner = planner
        Task {
            let bundle = ContextEngine().resolve(engineInput)
            do {
                let plans = try await planner.plan(PlannerInput(request: input, context: bundle))
                self.contextBundle = bundle
                self.planSet = plans
                self.panelState = .planChoices
            } catch {
                self.lastError = "\(error)"
                self.panelState = .error
            }
        }
    }

    func select(plan: PlanOption) {
        selectedPlan = plan
        guard let bundle = contextBundle else { return }
        let notePath = "ContextDock/Projects/\(bundle.project?.name ?? "Inbox").md"
        let checklist = ChecklistBuilder.build(from: plan, context: bundle, notePath: notePath)
        self.checklist = checklist
        document.checklists.append(checklist)
        document.audit.append(AuditEvent(action: "plan.selected", detail: plan.title))
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
        case .failed:
            activeAgentCount = 0
            lastError = event.summary
            panelState = .error
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
