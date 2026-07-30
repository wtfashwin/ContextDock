import Foundation
import Testing

@testable import ContextDockKit

// MARK: - Repository detection

@Suite struct ProjectResolverTests {
    func makeTempRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdtest-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let git = GitRunner()
        _ = git.run(["init", "-q"], in: dir)
        _ = git.run(["config", "user.email", "test@example.com"], in: dir)
        _ = git.run(["config", "user.name", "Test"], in: dir)
        try "hello".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = git.run(["add", "."], in: dir)
        _ = git.run(["commit", "-q", "-m", "initial"], in: dir)
        return dir
    }

    @Test func detectsRepository() throws {
        let dir = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = ProjectResolver().resolveRepository(at: dir)
        #expect(repo != nil)
        #expect(repo?.name == dir.lastPathComponent)
        #expect(repo?.latestCommit?.isEmpty == false)
        #expect(repo?.isWorktree == false)
    }

    @Test func nonRepoReturnsNil() {
        let repo = ProjectResolver().resolveRepository(at: FileManager.default.temporaryDirectory)
        #expect(repo == nil)
    }
}

// MARK: - Obsidian parsing

@Suite struct MarkdownTests {
    @Test func parsesFrontmatterScalarsAndLists() {
        let content = """
        ---
        id: project-iris-v2
        type: project
        status: active
        repositories:
          - Sylox_v2_Core_App
        tags:
          - iris
          - v2
        ---

        # IRIS V2
        Body text with [[F12 is a separate feature]] and [[Note|Alias]].
        """
        let note = MarkdownParser.parse(path: "Projects/IRIS V2.md", content: content)
        #expect(note.frontmatter["id"] == "project-iris-v2")
        #expect(note.frontmatter["type"] == "project")
        #expect(note.frontmatterLists["tags"] == ["iris", "v2"])
        #expect(note.frontmatterLists["repositories"] == ["Sylox_v2_Core_App"])
        #expect(note.wikilinks == ["F12 is a separate feature", "Note"])
        #expect(note.title == "IRIS V2")
    }

    @Test func wikilinkHeadingAndAliasStripped() {
        let links = MarkdownParser.wikilinks(in: "See [[Note#Section]] and [[Other|Nickname]] and [[  ]]")
        #expect(links == ["Note", "Other"])
    }

    @Test func noFrontmatterStillParses() {
        let note = MarkdownParser.parse(path: "x.md", content: "plain body")
        #expect(note.frontmatter.isEmpty)
        #expect(note.body == "plain body")
    }
}

// MARK: - Vault safety

@Suite struct VaultTests {
    func makeVault() throws -> ObsidianVault {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdtest-vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ObsidianVault(rootURL: dir)
    }

    @Test func rejectsPathTraversal() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault.rootURL) }
        #expect(throws: VaultError.self) {
            _ = try vault.resolve("../outside.md")
        }
        #expect(throws: VaultError.self) {
            _ = try vault.resolve("a/../../outside.md")
        }
    }

    @Test func atomicWriteCreatesBackupOnRewrite() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault.rootURL) }
        try vault.writeNote(at: "Projects/Test.md", content: "v1")
        try vault.writeNote(at: "Projects/Test.md", content: "v2")
        let note = try vault.readNote(at: "Projects/Test.md")
        #expect(note.body == "v2")
        let revisions = vault.rootURL.appendingPathComponent(".contextdock-revisions")
        let backups = try FileManager.default.contentsOfDirectory(atPath: revisions.path)
        #expect(backups.count == 1)
    }

    @Test func appendToSectionPreservesOtherContent() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault.rootURL) }
        try vault.writeNote(at: "P.md", content: "# Title\n\n## Current work\n\n- [ ] existing\n\n## Decisions\n\n- old decision")
        try vault.appendToSection(notePath: "P.md", heading: "Current work", lines: ["- [ ] new item"])
        let note = try vault.readNote(at: "P.md")
        #expect(note.body.contains("- [ ] existing"))
        #expect(note.body.contains("- [ ] new item"))
        #expect(note.body.contains("- old decision"))
        // New item inserted inside Current work section, before Decisions.
        let workRange = note.body.range(of: "- [ ] new item")!
        let decisionsRange = note.body.range(of: "## Decisions")!
        #expect(workRange.lowerBound < decisionsRange.lowerBound)
    }

    @Test func appendCreatesMissingSection() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault.rootURL) }
        try vault.appendToSection(notePath: "New.md", heading: "Inbox", lines: ["- captured"])
        let note = try vault.readNote(at: "New.md")
        #expect(note.body.contains("## Inbox"))
        #expect(note.body.contains("- captured"))
    }

    @Test func obsidianURIEncodes() {
        let url = ObsidianURI.open(vault: "My Vault", file: "Projects/IRIS V2")
        #expect(url?.scheme == "obsidian")
        #expect(url?.host == "open")
        #expect(url!.absoluteString.contains("My%20Vault"))
    }
}

// MARK: - Knowledge graph

@Suite struct GraphTests {
    func seeded() -> KnowledgeGraph {
        var graph = KnowledgeGraph()
        graph.upsertNode(KnowledgeNode(id: StableID("n1"), title: "IRIS V2", type: .project, source: "test"))
        graph.upsertNode(KnowledgeNode(id: StableID("n2"), title: "F09 Access Governance", type: .feature, source: "test"))
        return graph
    }

    @Test func nodeAndEdgeCreation() {
        var graph = seeded()
        graph.addEdge(KnowledgeEdge(sourceID: StableID("n2"), targetID: StableID("n1"), type: .belongsTo, evidence: "frontmatter"))
        #expect(graph.edges.count == 1)
        #expect(graph.neighbours(of: StableID("n1")).map(\.title) == ["F09 Access Governance"])
    }

    @Test func edgeToMissingNodeRejected() {
        var graph = seeded()
        graph.addEdge(KnowledgeEdge(sourceID: StableID("n2"), targetID: StableID("ghost"), type: .relatesTo, evidence: "x"))
        #expect(graph.edges.isEmpty)
    }

    @Test func duplicateEdgeIgnored() {
        var graph = seeded()
        let edge = KnowledgeEdge(sourceID: StableID("n2"), targetID: StableID("n1"), type: .belongsTo, evidence: "a")
        graph.addEdge(edge)
        graph.addEdge(edge)
        #expect(graph.edges.count == 1)
    }

    @Test func mergeRepointsEdgesAndArchives() {
        var graph = seeded()
        graph.upsertNode(KnowledgeNode(id: StableID("n3"), title: "IRIS V2 (dup)", type: .project, source: "test"))
        graph.addEdge(KnowledgeEdge(sourceID: StableID("n2"), targetID: StableID("n3"), type: .belongsTo, evidence: "x"))
        graph.merge(duplicate: StableID("n3"), into: StableID("n1"))
        #expect(graph.edges.first?.targetID == StableID("n1"))
        #expect(graph.nodes[StableID("n3")]?.archived == true)
    }

    @Test func undoRestoresPreviousState() {
        var graph = seeded()
        graph.archiveNode(id: StableID("n1"))
        #expect(graph.nodes[StableID("n1")]?.archived == true)
        let undone = graph.undo()
        #expect(undone)
        #expect(graph.nodes[StableID("n1")]?.archived == false)
    }
}

// MARK: - Context engine

@Suite struct ContextEngineTests {
    func input(_ text: String) -> ContextEngineInput {
        var graph = KnowledgeGraph()
        let project = Project(id: StableID("p-iris"), name: "IRIS V2", aliases: ["iris"])
        graph.upsertNode(KnowledgeNode(id: StableID("f09"), title: "F09 Access Governance", type: .feature, projectID: project.id, source: "vault", tags: ["F09"]))
        graph.upsertNode(KnowledgeNode(id: StableID("dec1"), title: "PostgreSQL and OneDrive first", type: .decision, projectID: project.id, source: "vault"))
        graph.upsertNode(KnowledgeNode(id: StableID("other"), title: "Unrelated Concept", type: .concept, source: "vault"))
        let repo = Repository(id: StableID("repo-sylox"), rootPath: "/tmp/x", name: "Sylox_v2_Core_App")
        return ContextEngineInput(
            userInput: text, repository: repo, graph: graph, projects: [project],
            mappings: [RepositoryMapping(repositoryName: "Sylox_v2_Core_App", projectID: project.id)]
        )
    }

    @Test func featureIDExtraction() {
        #expect(ContextEngine.featureID(in: "Continue the IRIS V2 F09 PRD") == "F09")
        #expect(ContextEngine.featureID(in: "no feature here") == nil)
        #expect(ContextEngine.featureID(in: "f12 lowercase") == "F12")
    }

    @Test func deterministicMatchWithReasons() {
        let bundle = ContextEngine().resolve(input("Continue the IRIS V2 F09 PRD"))
        #expect(bundle.project?.name == "IRIS V2")
        #expect(bundle.featureID == "F09")
        let top = bundle.matches.first
        #expect(top?.node.title == "F09 Access Governance")
        #expect(top?.reason.contains("F09") == true)
        #expect(bundle.matches.allSatisfy { !$0.reason.isEmpty })
        #expect(bundle.confidence > 0.5)
        #expect(!bundle.explanation.isEmpty)
    }

    @Test func unrelatedNodesExcluded() {
        let bundle = ContextEngine().resolve(input("Continue the IRIS V2 F09 PRD"))
        #expect(!bundle.matches.contains { $0.node.id == StableID("other") })
    }

    @Test func unknownInputReportsMissingInfo() {
        var inp = input("totally unrelated request about gardening")
        inp.mappings = []
        inp.projects = []
        let bundle = ContextEngine().resolve(inp)
        #expect(bundle.confidence < 0.5)
        #expect(!bundle.missingInformation.isEmpty)
    }
}

// MARK: - Planner

@Suite struct PlannerTests {
    @Test func threeDistinctPlansWithRecommendation() async throws {
        let context = ContextBundle(project: Project(id: StableID("p"), name: "IRIS V2"), featureID: "F09", confidence: 0.9, explanation: "test")
        let set = try await LocalRulesPlanner().plan(PlannerInput(request: "Continue F09 PRD", context: context))
        #expect(PlanValidation.validate(set).isEmpty)
        #expect(set.options.count == 3)
        let kinds = Set(set.options.map(\.kind))
        #expect(kinds == Set([PlanKind.fastest, .recommended, .safest]))
        let recommended = set.options.first { $0.id == set.recommendedID }
        #expect(recommended?.kind == .recommended)
        for opt in set.options {
            #expect(!opt.steps.isEmpty)
            #expect(!opt.benefit.isEmpty)
            #expect(!opt.risk.isEmpty)
            #expect(!opt.willChange.isEmpty)
            #expect(!opt.willNotChange.isEmpty)
        }
    }

    @Test func planValidationCatchesDuplicates() {
        let opt = PlanOption(kind: .recommended, title: "Same", resultLine: "r", steps: ["s"], workSize: .small, benefit: "b", risk: "r", willChange: ["c"], willNotChange: ["n"])
        var dup = opt
        dup = PlanOption(id: .generate(prefix: "plan"), kind: .recommended, title: "Same", resultLine: "r", steps: ["s"], workSize: .small, benefit: "b", risk: "r", willChange: ["c"], willNotChange: ["n"])
        let set = PlanSet(options: [opt, dup], recommendedID: opt.id, explanation: "x", contextSources: [])
        let problems = PlanValidation.validate(set)
        #expect(!problems.isEmpty)
    }
}

// MARK: - Checklist

@Suite struct ChecklistTests {
    @Test func buildFromPlan() {
        let plan = PlanOption(kind: .recommended, title: "T", resultLine: "r", steps: ["a", "b"], workSize: .small, benefit: "b", risk: "r", willChange: [], willNotChange: [])
        let checklist = ChecklistBuilder.build(from: plan, context: ContextBundle(), notePath: "Projects/X.md")
        #expect(checklist.items.count == 2)
        #expect(checklist.items.allSatisfy { $0.status == .ready })
        #expect(checklist.items.allSatisfy { $0.obsidianNote == "Projects/X.md" })
    }

    @Test func legalTransitions() {
        #expect(ChecklistTransition.isAllowed(from: .ready, to: .running))
        #expect(ChecklistTransition.isAllowed(from: .running, to: .completed))
        #expect(ChecklistTransition.isAllowed(from: .running, to: .waiting))
        #expect(ChecklistTransition.isAllowed(from: .failed, to: .ready))
        #expect(!ChecklistTransition.isAllowed(from: .notStarted, to: .completed))
        #expect(!ChecklistTransition.isAllowed(from: .completed, to: .running))
        #expect(!ChecklistTransition.isAllowed(from: .cancelled, to: .running))
    }
}

// MARK: - Security

@Suite struct SecurityTests {
    @Test func redactsSecrets() {
        let text = """
        api_key = "sk_live_abcdefghijklmnop"
        AKIAABCDEFGHIJKLMNOP
        Bearer aaaaaaaaaaaaaaaaaaaaaaaa
        postgres://user:Sylox%402026@host:5432/db
        ghp_abcdefghijklmnopqrstuvwxyz123456
        normal text stays
        """
        let redacted = SecretRedactor.redact(text)
        #expect(!redacted.contains("sk_live_abcdefghijklmnop"))
        #expect(!redacted.contains("AKIAABCDEFGHIJKLMNOP"))
        #expect(!redacted.contains("Sylox%402026"))
        #expect(!redacted.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"))
        #expect(redacted.contains("normal text stays"))
        #expect(SecretRedactor.containsLikelySecret(text))
        #expect(!SecretRedactor.containsLikelySecret("plain sentence"))
    }

    @Test func rejectsOversizedEvent() {
        let big = Data(repeating: 0x41, count: EventValidation.maxMessageBytes + 1)
        #expect(EventValidation.decodeEvent(from: big) == .failure(.oversized(big.count)))
    }

    @Test func rejectsMalformedEvent() {
        let junk = Data("not json at all".utf8)
        if case .success = EventValidation.decodeEvent(from: junk) {
            Issue.record("malformed payload was accepted")
        }
    }

    @Test func acceptsValidEventRoundTrip() throws {
        let event = AgentEvent(adapter: .fake, sessionID: StableID("s1"), summary: "hi", type: .completed)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let decoded = try EventValidation.decodeEvent(from: data).get()
        #expect(decoded.eventID == event.eventID)
        #expect(decoded.type == .completed)
    }

    @Test func deduplicatorDropsRepeats() {
        var dedup = EventDeduplicator(capacity: 4)
        let event = AgentEvent(adapter: .fake, sessionID: StableID("s"), summary: "x", type: .completed)
        let first = dedup.admit(event)
        let second = dedup.admit(event)
        #expect(first)
        #expect(!second)
        // Eviction after capacity keeps memory bounded.
        for _ in 0..<5 {
            _ = dedup.admit(AgentEvent(adapter: .fake, sessionID: StableID("s"), summary: "y", type: .completed))
        }
        let readmitted = dedup.admit(event)  // evicted, admitted again
        #expect(readmitted)
    }
}

// MARK: - Preference learning

@Suite struct PreferenceTests {
    @Test func oneActionDoesNotCreateActiveRule() {
        var prefs: [PreferenceSignal] = []
        PreferenceLearner.observe(&prefs, learned: "prefers fastest plan", why: "selected fastest", sourceAction: "plan-select", projectScope: nil)
        #expect(prefs.count == 1)
        #expect(!PreferenceLearner.isActive(prefs[0]))
    }

    @Test func repeatedActionsRaiseConfidence() {
        var prefs: [PreferenceSignal] = []
        for i in 0..<3 {
            PreferenceLearner.observe(&prefs, learned: "prefers fastest plan", why: "selected fastest", sourceAction: "plan-select-\(i)", projectScope: nil)
        }
        #expect(prefs.count == 1)
        #expect(PreferenceLearner.isActive(prefs[0]))
        #expect(prefs[0].sourceActions.count == 3)
    }
}

// MARK: - Store round-trip

@Suite struct StoreTests {
    @Test func roundTripPersistence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdtest-store-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LocalStore(fileURL: url)
        var doc = StoreDocument()
        doc.projects = [Project(id: StableID("p1"), name: "IRIS V2")]
        var graph = KnowledgeGraph()
        graph.upsertNode(KnowledgeNode(id: StableID("n1"), title: "N", type: .concept, source: "t"))
        doc.graph = graph
        doc.checklists = [Checklist(title: "c", planID: StableID("plan-1"), items: [ChecklistItem(action: "a", source: "s")])]
        try store.save(doc)
        let loaded = try store.load()
        #expect(loaded.projects.first?.name == "IRIS V2")
        #expect(loaded.graph.nodes.count == 1)
        #expect(loaded.checklists.first?.items.first?.action == "a")
    }

    @Test func missingFileYieldsEmptyDocument() throws {
        let store = LocalStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID()).json"))
        let doc = try store.load()
        #expect(doc.projects.isEmpty)
    }
}

// MARK: - Fake adapter + socket integration

@Suite struct AgentIntegrationTests {
    @Test func fakeAdapterEmitsFullLifecycle() async throws {
        let adapter = FakeAgentAdapter(stepDelayNanos: 1)
        let package = AgentTaskPackage(planTitle: "Demo", planSteps: ["step one", "step two"], checklist: ["step one", "step two"])
        let collected = Collector()
        _ = try await adapter.dispatch(task: package) { event in
            collected.append(event)
        }
        let types = collected.snapshot().map(\.type)
        #expect(types.first == .sessionStarted)
        #expect(types.contains(.thinkingStarted))
        #expect(types.filter { $0 == .checklistUpdated }.count == 2)
        #expect(types.contains(.completed))
        #expect(types.last == .sessionEnded)
    }

    @Test func taskPackagePreviewRedactsSecrets() {
        let package = AgentTaskPackage(
            planTitle: "T", planSteps: ["use api_key = \"abcdefgh12345678\""], checklist: []
        )
        let preview = package.preview()
        #expect(!preview.contains("abcdefgh12345678"))
        #expect(preview.contains("[REDACTED]"))
    }

    @Test func socketReceivesDeduplicatesAndRejects() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("cd-\(UUID().uuidString.prefix(8)).sock").path
        let collected = Collector()
        let audits = AuditCollector()
        let server = EventSocketServer(
            socketPath: path,
            onEvent: { collected.append($0) },
            onAudit: { audits.append($0) }
        )
        try server.start()
        defer { server.stop() }

        let event = AgentEvent(adapter: .fake, sessionID: StableID("s1"), summary: "hello", type: .toolFinished)
        try EventSocketClient.send(event, to: path)
        try EventSocketClient.send(event, to: path)  // duplicate
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(collected.snapshot().count == 1)
        #expect(audits.snapshot().contains { $0.action == "socket.duplicate" })
    }
}

final class Collector: @unchecked Sendable {
    private var events: [AgentEvent] = []
    private let lock = NSLock()
    func append(_ event: AgentEvent) { lock.lock(); events.append(event); lock.unlock() }
    func snapshot() -> [AgentEvent] { lock.lock(); defer { lock.unlock() }; return events }
}

final class AuditCollector: @unchecked Sendable {
    private var events: [AuditEvent] = []
    private let lock = NSLock()
    func append(_ event: AuditEvent) { lock.lock(); events.append(event); lock.unlock() }
    func snapshot() -> [AuditEvent] { lock.lock(); defer { lock.unlock() }; return events }
}
