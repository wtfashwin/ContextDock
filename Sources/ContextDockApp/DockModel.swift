import AppKit
import ContextDockKit
import Foundation
import Observation

/// MainActor UI state + orchestration. All engine work runs off the main thread.
@Observable
@MainActor
final class DockModel {
    enum IslandTab: String, Sendable { case monitor, capture }
    var panelState: PanelState = .hidden {
        didSet { onStateChange?() }
    }
    var onStateChange: (() -> Void)?

    // Collapsed island info
    var status: String = "Idle"
    var activeAgentCount: Int = 0
    var waitingForUser = false
    // Vibe Island parity: live multi-agent feed
    var liveSessions: [LiveSession] = []
    var selectedSessionID: StableID?
    var islandTab: IslandTab = .monitor
    // Finish: persisted island settings + easter-egg state
    var islandSettings = IslandSettings()
    var eggQuote: String?
    var partyMode = false

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
        islandSettings = IslandSettings.decode(from: document.settings["island"])
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

    /// Immediate flush (terminate / lock / explicit saves). Cancels debounce first.
    func persist() {
        persistGen += 1
        document.settings["island"] = islandSettings.encode()
        var doc = document
        if doc.events.count > 5000 { doc.events.removeFirst(doc.events.count - 5000) }
        if doc.audit.count > 2000 { doc.audit.removeFirst(doc.audit.count - 2000) }
        try? store.save(doc)
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
        case .codex, .codexCLI:
            adapter = CLIAgentAdapter(kind: .codex, executablePath: Self.findExecutable("codex") ?? "/usr/local/bin/codex")
        case .gemini:
            adapter = CLIAgentAdapter(kind: .gemini, executablePath: Self.findExecutable("gemini") ?? "/usr/local/bin/gemini")
        case .cursor:
            adapter = CLIAgentAdapter(kind: .cursor, executablePath: Self.findExecutable("cursor-agent") ?? "/usr/local/bin/cursor-agent")
        case .opencode:
            adapter = CLIAgentAdapter(kind: .opencode, executablePath: Self.findExecutable("opencode") ?? "/usr/local/bin/opencode")
        case .qwen:
            adapter = CLIAgentAdapter(kind: .qwen, executablePath: Self.findExecutable("qwen") ?? "/usr/local/bin/qwen")
        case .copilot:
            adapter = CLIAgentAdapter(kind: .copilot, executablePath: Self.findExecutable("copilot") ?? "/usr/local/bin/copilot")
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

    // O(1) session lookup: rebuilt whenever the feed array is assigned.
    // Linear firstIndex scans per event turned ingest into O(n) per event.
    private var sessionIndex: [StableID: Int] = [:]
    private func reindex() {
        var idx: [StableID: Int] = [:]
        idx.reserveCapacity(liveSessions.count)
        for (i, s) in liveSessions.enumerated() { idx[s.id] = i }
        sessionIndex = idx
    }
    private func setFeed(_ sessions: [LiveSession]) {
        // Skip the assignment entirely when nothing changed: every assignment
        // invalidates SwiftUI + re-sorts + re-renders, which was firing per poll.
        if sessions == liveSessions { return }
        liveSessions = sessions.count > 40 ? Array(sessions.prefix(40)) : sessions
        sortedSessions = liveSessions.sorted { // cached: views must NOT re-sort per read
            if $0.status.isUrgent != $1.status.isUrgent { return $0.status.isUrgent }
            return $0.updatedAt > $1.updatedAt
        }
        reindex()
    }
    /// Pre-sorted feed for views. SessionState.sorted() is O(n log n) — never
    /// call it from a view body; read this instead.
    private(set) var sortedSessions: [LiveSession] = []
    var midnightMode = false

    // Debounced persistence: ingest bursts used to JSON-encode the whole
    // document on the main thread per event. Now: mark dirty, encode the
    // value-type copy off-main once quiet for 1.5s, single-writer queue.
    private var persistGen = 0
    private static let persistQueue = DispatchQueue(label: "contextdock.persist", qos: .utility)
    func schedulePersist() {
        persistGen += 1
        let gen = persistGen
        let store = store
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { [weak self] in
                guard let self, gen == self.persistGen else { return }
                var doc = self.document
                if doc.events.count > 5000 { doc.events.removeFirst(doc.events.count - 5000) }
                if doc.audit.count > 2000 { doc.audit.removeFirst(doc.audit.count - 2000) }
                Self.persistQueue.async {
                    let t0 = Date()
                    try? store.save(doc)
                    DockLog.info("persist \(doc.events.count) events in \(Int(Date().timeIntervalSince(t0) * 1000))ms")
                }
            }
        }
    }

    func ingest(event: AgentEvent) {
        DockLog.eventSummary(event)
        let activeBefore = liveSessions.filter(\.status.isActive).count
        recentEvents.append(event)
        if recentEvents.count > 200 { recentEvents.removeFirst(recentEvents.count - 200) }
        document.events.append(event)
        // Live feed: every event updates its session card (O(1) via index).
        // Never mutate liveSessions in place: setFeed diffs, and in-place
        // edits would blind the diff and stale the sortedSessions cache.
        if let idx = sessionIndex[event.sessionID], idx < liveSessions.count,
           liveSessions[idx].id == event.sessionID {
            var feed = liveSessions
            feed[idx] = SessionState.apply(event, to: feed[idx])
            setFeed(SessionState.sorted(feed))
        } else {
            reindex()
            var feed = liveSessions
            feed.append(SessionState.apply(event, to: nil))
            setFeed(SessionState.sorted(feed))
        }
        refreshCollapsedSummary()
        switch event.type {
        case .checklistUpdated:
            advanceChecklist(evidence: event.summary)
        case .waitingForUser, .questionAsked, .permissionRequested:
            waitingForUser = true
            if panelState == .collapsed || panelState == .hidden { islandTab = .monitor }
            if islandSettings.soundsEnabled { SoundEffects.play(.needsAttention) }
        case .completed:
            waitingForUser = liveSessions.contains { $0.status.isUrgent }
            status = "Completed"
            if islandSettings.soundsEnabled { SoundEffects.play(.done) }
            if event.adapter != .fake {
                LearningEngine.recordAgentOutcome(
                    &document.preferences, agent: event.adapter, succeeded: true,
                    projectID: contextBundle?.project?.id
                )
            }
        case .failed:
            lastError = event.summary
            updateSettings { $0.failuresSeen += 1 }
            if islandSettings.soundsEnabled { SoundEffects.play(.failed) }
            if event.adapter != .fake {
                LearningEngine.recordAgentOutcome(
                    &document.preferences, agent: event.adapter, succeeded: false,
                    projectID: contextBundle?.project?.id
                )
            }
        default:
            break
        }
        // GG egg: the board just went fully green on its own.
        let activeAfter = liveSessions.filter(\.status.isActive).count
        let urgentAfter = liveSessions.filter(\.status.isUrgent).count
        if EggEngine.feedDrained(activeBefore: activeBefore, activeAfter: activeAfter,
                                 urgentAfter: urgentAfter,
                                 hadDone: liveSessions.contains { $0.status == .done }) != nil {
            eggQuote = "GG — clean board 🤝"
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await MainActor.run { [weak self] in
                    if self?.eggQuote == "GG — clean board 🤝" { self?.eggQuote = nil }
                }
            }
        }
        schedulePersist()
    }

    // MARK: - Decisions + pattern insights (learns in daylight, never automates)

    // MARK: - Live feed (Vibe Island parity)

    var urgentSessions: [LiveSession] { liveSessions.filter(\.status.isUrgent) }
    var urgentCount: Int { urgentSessions.count }
    var workingSessions: [LiveSession] { liveSessions.filter { $0.status == .working } }
    /// Right-wing ticker: freshest activity across the feed (cached sort).
    var tickerSnippet: String {
        sortedSessions.first?.lastActivity
            ?? repository.map { "\($0.name) · \($0.branch ?? "?")" } ?? "Idle"
    }
    /// Left-wing pets in feed order (cached sort — never re-sort in a view).
    func pets(style: PetStyle? = nil) -> [(session: LiveSession, pet: AgentPet)] {
        let st = style ?? islandSettings.petStyle
        return sortedSessions.map { ($0, PetStore.pet(for: $0.agent, style: st)) }
    }
    var usageLine: String {
        let n = liveSessions.filter(\.status.isActive).count
        if n == 0 { return status }
        if let u = urgentSessions.first {
            return "\(n) agents · \(u.agent.displayName) needs you"
        }
        return "\(n) agents working"
    }

    private func refreshCollapsedSummary() {
        activeAgentCount = liveSessions.filter(\.status.isActive).count
        waitingForUser = liveSessions.contains { $0.status.isUrgent }
        if activeAgentCount > 0 {
            status = usageLine
        } else if liveSessions.contains(where: { $0.status == .done }) {
            status = "All done"
        }
    }

    /// Merge passive discovery with event-backed sessions — without view churn:
    /// discovered entries keep their first-seen timestamps (stable sort), and
    /// the feed array is only assigned when something actually changed.
    func mergeDiscovered(_ discovered: [LiveSession]) {
        var byID = Dictionary(uniqueKeysWithValues: liveSessions.map { ($0.id, $0) })
        let eventPIDs = Set(liveSessions.compactMap(\.pid))
        for d in discovered {
            if let pid = d.pid, eventPIDs.contains(pid) { continue }
            if let keep = byID[d.id] {
                // Refresh linkage, preserve history + timestamps (no re-sort churn).
                var merged = keep
                merged.terminal = d.terminal
                merged.repositoryPath = d.repositoryPath ?? keep.repositoryPath
                merged.tty = d.tty ?? keep.tty
                merged.tmuxTarget = d.tmuxTarget ?? keep.tmuxTarget
                if merged.task == "agent" || merged.task.isEmpty { merged.task = d.task }
                byID[d.id] = merged
            } else {
                byID[d.id] = d
            }
        }
        let livePIDs = Set(discovered.compactMap(\.pid))
        setFeed(SessionState.sorted(byID.values.filter { s in
            guard s.id.raw.hasPrefix("live-"), let pid = s.pid else { return true }
            return livePIDs.contains(pid)
        }))
        refreshCollapsedSummary()
    }

    private var discoveryInFlight = false
    func pollDiscovery() {
        // Coalesce: overlapping polls spawned processes faster than they exited.
        guard !discoveryInFlight else { return }
        discoveryInFlight = true
        Task.detached(priority: .utility) {
            let found = SessionDiscovery.poll()
            await MainActor.run { [weak self] in
                self?.discoveryInFlight = false
                self?.mergeDiscovered(found)
            }
        }
    }

    // MARK: - Decisions (every user call records; the 5th surfaces, never automates)

    var activeInsight: PatternInsight?
    var celebrationKey = 0
    private func recordDecision(kind: DecisionKind, label: String) {
        var journal = document.decisions
        DecisionJournal.record(&journal, UserDecision(kind: kind, label: label, projectID: contextBundle?.project?.id))
        document.decisions = journal
        let seen = Set(islandSettings.seenInsightIDs.compactMap { StableID($0) })
        if let insight = DecisionJournal.insight(in: journal, seenIDs: seen) {
            activeInsight = insight
            DockLog.info("insight surfaced: \(insight.title) conf=\(insight.confidence)")
        }
    }

    func dismissInsight(remember: Bool) {
        if remember, let insight = activeInsight {
            islandSettings.seenInsightIDs += insight.decisionIDs.map(\.raw)
        }
        activeInsight = nil
        schedulePersist()
    }

    private func session(by id: StableID) -> LiveSession? {
        if let idx = sessionIndex[id], idx < liveSessions.count, liveSessions[idx].id == id {
            return liveSessions[idx]
        }
        return liveSessions.first { $0.id == id }
    }

    func approve(sessionID: StableID) {
        guard let s = session(by: sessionID) else { return }
        ingest(event: AgentEvent(adapter: s.agent, sessionID: s.id, task: s.task, summary: "✓ Approved", type: .permissionApproved))
        recordAudit(AuditEvent(action: "permission.approved", detail: s.permission?.filePath ?? s.task))
        recordDecision(kind: .approval, label: "Approved \(s.agent.displayName) \(s.permission?.filePath ?? s.task)")
        celebrationKey += 1
        // One-shot burst: the key clears itself so the TimelineView unmounts.
        let key = celebrationKey
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { [weak self] in
                if self?.celebrationKey == key { self?.celebrationKey = 0 }
            }
        }
        updateSettings { $0.approvalsGiven += 1 }
    }

    func deny(sessionID: StableID) {
        guard let s = session(by: sessionID) else { return }
        ingest(event: AgentEvent(adapter: s.agent, sessionID: s.id, task: s.task, summary: "Denied", type: .permissionRejected))
        recordAudit(AuditEvent(action: "permission.rejected", detail: s.permission?.filePath ?? s.task))
        recordDecision(kind: .approval, label: "Denied \(s.agent.displayName) \(s.permission?.filePath ?? s.task)")
    }

    func answer(sessionID: StableID, option: String) {
        guard let s = session(by: sessionID) else { return }
        ingest(event: AgentEvent(adapter: s.agent, sessionID: s.id, task: s.task, summary: "Answered: \(option)", type: .toolStarted, question: s.question?.question))
        recordAudit(AuditEvent(action: "question.answered", detail: "\(s.task): \(option)"))
        recordDecision(kind: .questionAnswer, label: "Answered “\(option)” for \(s.agent.displayName)")
        updateSettings { $0.questionsAnswered += 1 }
    }

    /// PID-accurate redirect: tmux pane → iTerm tty → app activation → open-at-cwd.
    /// Every step best-effort; the audit trail says exactly which step landed.
    func jump(to session: LiveSession) {
        let target = JumpTarget(session: session)
        DockLog.info("jump \(session.agent.rawValue) pid=\(session.pid ?? -1) tty=\(session.tty ?? "-") tmux=\(session.tmuxTarget ?? "-")")
        var how = "none"
        // 1. tmux pane first — the only truly exact tab address.
        if let tmux = session.tmuxTarget, !tmux.isEmpty {
            for argv in Tmux.focusArguments(target: tmux) {
                runTool("/opt/homebrew/bin/tmux", argv)
                runTool("/usr/local/bin/tmux", argv)
            }
            activateTerminalApp(target.terminal)
            how = "tmux \(tmux)"
        }
        // 2. iTerm session by tty — exact tab without tmux.
        else if target.terminal == "iTerm", let tty = session.tty, !tty.isEmpty {
            runAppleScript(ItermJump.script(tty: tty))
            how = "iterm tty \(tty)"
        }
        // 3. Activate the running app → modern open → legacy open → hint script.
        else {
            if activateTerminalApp(target.terminal) { how = "activate \(target.terminal)" }
            else if openTerminalApp(target.terminal, at: target.workingDirectory) { how = "open \(target.terminal)" }
            else {
                let args = TerminalJump.openArguments(for: target)
                if runTool("/usr/bin/open", args) { how = "open \(args.joined(separator: " "))" }
                runAppleScript(TerminalJump.appleScript(for: target))
            }
        }
        recordAudit(AuditEvent(action: "terminal.jump", detail: "\(session.agent.displayName) \(session.task) -> \(how)"))
        recordDecision(kind: .jump, label: "Jumped to \(session.agent.displayName) in \(session.terminal)")
        updateSettings { $0.jumpsMade += 1 }
    }

    @discardableResult
    private func activateTerminalApp(_ terminal: String) -> Bool {
        if let bundleID = TerminalJump.bundleID(for: terminal),
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app.activate()
        }
        return false
    }

    /// Modern workspace open (async API, best-effort) before shelling to /usr/bin/open.
    @discardableResult
    private func openTerminalApp(_ terminal: String, at path: String?) -> Bool {
        guard let bundleID = TerminalJump.bundleID(for: terminal),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        if let path { config.arguments = [path] }
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        return true
    }

    @discardableResult
    private func runTool(_ path: String, _ args: [String]) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit(); return proc.terminationStatus == 0 }
        catch { return false }
    }

    private func runAppleScript(_ source: String) {
        guard let appleScript = NSAppleScript(source: source) else { return }
        var err: NSDictionary?
        appleScript.executeAndReturnError(&err)
        if let err { DockLog.info("applescript note: \(err)") }
    }

    // MARK: - Notch taps + easter eggs

    /// Every island tap counts. Every 5th reveals a pet quote; "party" unlocks parade.
    func registerTap() {
        islandSettings.tapCount += 1
        if islandSettings.tapCount % 5 == 0, let first = sortedSessions.first {
            eggQuote = "\(PetStore.pet(for: first.agent, style: islandSettings.petStyle).name): \(PetStore.quote(for: first.agent))"
        } else if eggQuote?.hasPrefix("GG") != true {
            eggQuote = nil
        }
        schedulePersist()
    }

    func checkPartyCode(_ text: String) {
        guard let egg = EggEngine.typed(text) else { return }
        switch egg.id {
        case .party:
            partyMode = true
            islandSettings.partyUnlocked = true
            DockLog.info("egg: parade thrown")
        case .midnight:
            midnightMode.toggle()
            eggQuote = midnightMode ? "🌙 midnight watch — the abyss nods back" : nil
            DockLog.info("egg: midnight \(midnightMode ? "on" : "off")")
        case .gg: break // feed-driven only
        }
        schedulePersist()
    }

    func updateSettings(_ mutate: (inout IslandSettings) -> Void) {
        let before = islandSettings
        mutate(&islandSettings)
        // Earned banners fire exactly once, the moment a pack opens.
        let earned = PetStore.newlyUnlocked(before: before, after: islandSettings)
        if !earned.isEmpty {
            islandSettings.celebratedStyles += earned.map(\.rawValue)
            eggQuote = earned.map(PetStore.celebrationLine).joined(separator: " · ")
            DockLog.info("pack earned: \(earned.map(\.rawValue).joined(separator: ","))")
        }
        schedulePersist()
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
