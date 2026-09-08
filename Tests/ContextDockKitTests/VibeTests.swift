import Foundation
import Testing

@testable import ContextDockKit

@Suite struct SessionFeedTests {
    @Test func permissionFlow() {
        let sid = StableID("s1")
        var s = SessionState.apply(
            AgentEvent(adapter: .claudeCode, sessionID: sid, task: "fix auth bug", summary: "start", type: .sessionStarted), to: nil)
        #expect(s.status == .working)
        s = SessionState.apply(
            AgentEvent(adapter: .claudeCode, sessionID: sid, summary: "Edit middleware", filePath: "src/auth/middleware.ts", type: .permissionRequested, diffText: "+x", additions: 3, deletions: 1), to: s)
        #expect(s.status == .needsApproval)
        #expect(s.permission?.filePath == "src/auth/middleware.ts")
        s = SessionState.apply(
            AgentEvent(adapter: .claudeCode, sessionID: sid, summary: "ok", type: .permissionApproved), to: s)
        #expect(s.status == .working)
        #expect(s.permission == nil)
        #expect(s.approvedCount == 1)
    }

    @Test func questionFlow() {
        let sid = StableID("s2")
        var s = SessionState.apply(
            AgentEvent(adapter: .codex, sessionID: sid, task: "deploy", summary: "q", type: .questionAsked, question: "Which target?", questionOptions: ["Prod", "Staging"]), to: nil)
        #expect(s.status == .asking)
        #expect(s.question?.options.count == 2)
    }

    @Test func urgentSortsFirst() {
        let a = LiveSession(id: StableID("a"), agent: .codex, task: "bg", status: .working, updatedAt: Date())
        let b = LiveSession(id: StableID("b"), agent: .claudeCode, task: "urgent", status: .needsApproval, updatedAt: Date().addingTimeInterval(-100))
        #expect(SessionState.sorted([a, b]).first?.id == StableID("b"))
    }

    @Test func legacyCodexPayloadStillDecodes() throws {
        let json = """
        {"schemaVersion":1,"eventID":{"raw":"e1"},"adapter":"codex","sessionID":{"raw":"s1"},"timestamp":"2026-01-01T00:00:00Z","status":"ok","summary":"hi","type":"completed"}
        """.data(using: .utf8)!
        let evt = try EventValidation.decodeEvent(from: json).get()
        #expect(evt.adapter == .codex)
        #expect(evt.terminal == nil)
    }

    @Test func jumpBundleIDs() {
        #expect(TerminalJump.bundleID(for: "iTerm") == "com.googlecode.iterm2")
        #expect(TerminalJump.bundleID(for: "Ghostty") != nil)
        #expect(TerminalJump.bundleID(for: "Nope-xyz") == nil)
    }

    @Test func notchGeometryMath() {
        // 14" lived measurement: 1470 wide, aux 646/645, top 32 → notch 179x32.
        let g = NotchGeometry(screenWidth: 1470, auxLeftWidth: 646, auxRightWidth: 645, safeTop: 32, menuBarHeight: 26)
        #expect(g.hasNotch)
        #expect(abs((g.notchWidth ?? 0) - 179) < 0.5)
        #expect(g.collapsedWidth == g.notchWidth)
        #expect(g.expandedWidth(full: true) > g.expandedWidth(full: false))
        let plain = NotchGeometry(screenWidth: 2560, auxLeftWidth: nil, auxRightWidth: nil, safeTop: 0, menuBarHeight: 26)
        #expect(!plain.hasNotch)
        #expect(plain.notchWidth == nil)
        #expect(plain.collapsedWidth == 300)
    }

    @Test func jumpOpenArgsLandAtCwd() {
        let t = JumpTarget(terminal: "iTerm", workingDirectory: "/repo/x")
        #expect(TerminalJump.openArguments(for: t) == ["-a", "iTerm", "/repo/x"])
        #expect(TerminalJump.appName(for: "Ghostty") == "Ghostty")
    }

    @Test func petsAndSettingsRoundTrip() {
        let pet = PetStore.pet(for: .claudeCode, style: .ember)
        #expect(!pet.emoji.isEmpty)
        let s = IslandSettings(petStyle: .pixel, soundsEnabled: false, onboarded: true)
        #expect(IslandSettings.decode(from: s.encode()).petStyle == .pixel)
    }

    @Test func processTreeResolvesTerminalAncestor() {
        let snap = """
        100 1 ?? launchd
        200 100 ?? Ghostty
        300 200 s001 zsh
        400 300 s001 claude
        500 300 s002 codex
        """
        let rows = ProcessTree.parseSnapshot(snap)
        #expect(rows.count == 5)
        let links = ProcessTree.resolve(agentPids: [400, 500], rows: rows)
        #expect(links[400]?.terminalName == "Ghostty")
        #expect(links[400]?.tty == "s001")
        #expect(links[500]?.tty == "s002")
    }

    @Test func processTreeCycleSafe() {
        // pid↔ppid loop must terminate (16-hop guard) without hanging.
        let rows = [PsRow(pid: 1, ppid: 2, tty: "s0", comm: "x"),
                    PsRow(pid: 2, ppid: 1, tty: "s0", comm: "y")]
        #expect(ProcessTree.resolve(agentPids: [1], rows: rows)[1] == nil)
    }

    @Test func tmuxPaneMatchAndFocus() {
        let panes = Tmux.parsePanes("123 main:0.1 /repo/x\n124 main:0.2 /repo/y")
        #expect(panes.count == 2)
        #expect(Tmux.match(panes: panes, pid: 123)?.target == "main:0.1")
        #expect(Tmux.focusArguments(target: "main:0.1").count == 2)
        #expect(ItermJump.script(tty: "s001").contains("s001"))
    }

    @Test func decisionJournalSurfacesOnFifth() {
        var ds: [UserDecision] = []
        #expect(DecisionJournal.insight(in: ds) == nil)
        for i in 0..<3 {
            DecisionJournal.record(&ds, UserDecision(kind: .approval, label: "ok \(i)"))
        }
        #expect(DecisionJournal.insight(in: ds) == nil)
        DecisionJournal.record(&ds, UserDecision(kind: .approval, label: "ok 3"))
        let insight = DecisionJournal.insight(in: ds)
        #expect(insight != nil)
        #expect(insight?.confidence ?? 0 >= 0.5)
        // Seen IDs suppress repeats.
        let seen = Set((insight?.decisionIDs ?? []))
        #expect(DecisionJournal.insight(in: ds, seenIDs: seen) == nil)
        // Capacity bound holds under flood.
        for i in 0..<300 { DecisionJournal.record(&ds, UserDecision(kind: .jump, label: "j\(i)")) }
        #expect(ds.count == DecisionJournal.capacity)
    }

    @Test func shadowPetsExplainTheirLock() {
        let fresh = IslandSettings()
        #expect(!PetStore.unlocked(.shadow, settings: fresh).open)
        #expect(!PetStore.unlocked(.shadow, settings: fresh).hint.isEmpty)
        var earned = IslandSettings()
        earned.questionsAnswered = 5
        #expect(PetStore.unlocked(.shadow, settings: earned).open)
    }

    @Test func everyPackIsMutuallyExclusive() {
        // codex + codexCLI intentionally share cells (same CLI); all other
        // agents must differ within a pack, and every cell must be filled.
        for style in PetStyle.allCases {
            var seen: [String: AgentKind] = [:]
            for agent in AgentKind.allCases {
                let pet = PetStore.pet(for: agent, style: style)
                #expect(!pet.emoji.isEmpty)
                #expect(!pet.name.isEmpty)
                #expect(!pet.trait.isEmpty)
                if agent == .codexCLI { continue } // shares codex cell by design
                #expect(seen[pet.emoji] == nil,
                        "duplicate \(pet.emoji) in \(style.rawValue): \(seen[pet.emoji]?.rawValue ?? "?") vs \(agent.rawValue)")
                seen[pet.emoji] = agent
            }
            #expect(seen.count == AgentKind.allCases.count - 1)
        }
    }

    @Test func warAndAbyssUnlocksTrackProgress() {
        var s = IslandSettings()
        #expect(!PetStore.unlocked(.war, settings: s).open)
        #expect(!PetStore.unlocked(.abyss, settings: s).open)
        s.failuresSeen = 3
        #expect(PetStore.unlocked(.war, settings: s).open)
        s.jumpsMade = 15
        #expect(PetStore.unlocked(.abyss, settings: s).open)
    }

    @Test func eggEngineTriggers() {
        #expect(EggEngine.typed("throw a party")?.id == .party)
        #expect(EggEngine.typed("midnight oil")?.id == .midnight)
        #expect(EggEngine.typed("fix the bug") == nil)
        #expect(EggEngine.feedDrained(activeBefore: 2, activeAfter: 0, urgentAfter: 0, hadDone: true)?.id == .gg)
        #expect(EggEngine.feedDrained(activeBefore: 2, activeAfter: 1, urgentAfter: 0, hadDone: true) == nil)
        #expect(EggEngine.feedDrained(activeBefore: 1, activeAfter: 0, urgentAfter: 1, hadDone: true) == nil)
        #expect(EggEngine.feedDrained(activeBefore: 0, activeAfter: 0, urgentAfter: 0, hadDone: true) == nil)
    }

    @Test func quietEventsPreserveIdentity() {
        let sid = StableID("s9")
        let e1 = AgentEvent(adapter: .codex, sessionID: sid, task: "t", summary: "Working", type: .sessionStarted)
        let s1 = SessionState.apply(e1, to: nil)
        // Same state again (e.g. duplicate delivery) → identical value, no churn.
        let s2 = SessionState.apply(e1, to: s1)
        #expect(s2 == s1)
        #expect(s2.updatedAt == s1.updatedAt)
    }

        @Test func packCelebrationsFireOnce() {
        let before = IslandSettings()
        var after = IslandSettings()
        after.failuresSeen = 3
        #expect(PetStore.newlyUnlocked(before: before, after: after) == [.war])
        var celebrated = after
        celebrated.celebratedStyles = ["war"]
        #expect(PetStore.newlyUnlocked(before: before, after: celebrated).isEmpty)
        #expect(!PetStore.celebrationLine(for: .abyss).isEmpty)
    }
}

@Suite struct RepoFastPathTests {
    @Test func validLastUsedSkipsRootEnumeration() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("cdfast-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        // A decoy root containing a "newer" repo: fast path must ignore it.
        let decoyRoot = base.appendingPathComponent("roots")
        let decoyRepo = decoyRoot.appendingPathComponent("decoy")
        try fm.createDirectory(at: decoyRepo, withIntermediateDirectories: true)
        let git = GitRunner()
        _ = git.run(["init", "-q"], in: decoyRepo)
        // The real last-used repo elsewhere.
        let mine = base.appendingPathComponent("mine")
        try fm.createDirectory(at: mine, withIntermediateDirectories: true)
        _ = git.run(["init", "-q"], in: mine)
        _ = git.run(["config", "user.email", "t@e.com"], in: mine)
        _ = git.run(["config", "user.name", "T"], in: mine)
        try "x".write(to: mine.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        _ = git.run(["add", "."], in: mine)
        _ = git.run(["commit", "-q", "-m", "i"], in: mine)
        let found = RepoScanner().scan(roots: [decoyRoot], lastUsedPath: mine.path)
        #expect(found.count == 1)
        #expect(URL(fileURLWithPath: found.first?.rootPath ?? "").standardizedFileURL.path
            == mine.standardizedFileURL.path)
    }
}
