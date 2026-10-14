import Foundation
import Testing

@testable import ContextDockKit

@Suite struct HookInstallerTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("contextdock-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func repeatedMergePreservesUserHooksWithoutDuplicatingManagedCommands() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = directory.appendingPathComponent("settings.json")
        let bin = directory.appendingPathComponent("bin")
        let original = """
        {"permissions":{"allow":["Read"]},"custom":{"keep":true},"hooks":{
          "PreToolUse":[{"matcher":"Read","hooks":[{"type":"command","command":"echo user-hook"}]}],
          "PostToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"echo other-event"}]}]
        }}
        """
        try original.write(to: settings, atomically: true, encoding: .utf8)

        HookInstaller.mergeClaudeSettings(at: settings, bin: bin)
        HookInstaller.mergeClaudeSettings(at: settings, bin: bin)

        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        #expect((root["permissions"] as? [String: [String]])?["allow"] == ["Read"])
        #expect((root["custom"] as? [String: Bool])?["keep"] == true)
        let hooks = try #require(root["hooks"] as? [String: [[String: Any]]])
        let entries = try #require(hooks["PreToolUse"])
        #expect(entries.count == 2)
        #expect((entries.first?["hooks"] as? [[String: String]])?.first?["command"] == "echo user-hook")
        #expect(hooks["PostToolUse"]?.count == 1)
        for name in ["PermissionRequest", "UserPromptSubmit", "Stop"] {
            #expect(hooks[name]?.count == 1)
        }
    }

    @Test(arguments: [
        "not JSON", "[]", "null", "{\"hooks\":[]}",
        "{\"hooks\":{\"PreToolUse\":\"broken\"}}",
        "{\"hooks\":{\"PreToolUse\":[{\"hooks\":\"broken\"}]}}",
    ])
    func malformedExistingSettingsRemainByteForByteUnchanged(original: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = directory.appendingPathComponent("settings.json")
        let data = Data(original.utf8)
        try data.write(to: settings)

        HookInstaller.mergeClaudeSettings(at: settings, bin: directory.appendingPathComponent("bin"))

        #expect(try Data(contentsOf: settings) == data)
    }

    @Test func installUsesOnlyInjectedHomeAndReportsSuccessfulWrites() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let socketPath = "/tmp/cdh-unused-\(UUID().uuidString.prefix(8)).sock"
        let written = HookInstaller.installAll(home: directory, socketPath: socketPath)
        #expect(written.count == 3)
        #expect(written.allSatisfy { $0.hasPrefix(directory.path + "/") })
        for agent in ["claudeCode", "codex"] {
            let script = directory.appendingPathComponent(".contextdock/bin/contextdock-hook-\(agent).py")
            #expect(FileManager.default.isExecutableFile(atPath: script.path))
        }
        let settings = directory.appendingPathComponent(".claude/settings.json")
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        let hooks = try #require(root["hooks"] as? [String: [[String: Any]]])
        #expect(hooks.count == 4)
    }

    @Test func installDoesNotReportMalformedSettingsAsWritten() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = directory.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("malformed-user-settings".utf8)
        try original.write(to: settings)

        let written = HookInstaller.installAll(home: directory, socketPath: "/tmp/unused-contextdock-fixture.sock")

        #expect(written.count == 2)
        #expect(!written.contains(settings.path))
        #expect(try Data(contentsOf: settings) == original)
    }

    @Test func failedSenderInstallDoesNotRegisterMissingClaudeCommand() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contextDirectory = directory.appendingPathComponent(".contextdock")
        try FileManager.default.createDirectory(at: contextDirectory, withIntermediateDirectories: true)
        try Data("blocked-bin-directory".utf8).write(to: contextDirectory.appendingPathComponent("bin"))
        let settings = directory.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{\"custom\":{\"keep\":true}}".utf8)
        try original.write(to: settings)

        let written = HookInstaller.installAll(home: directory, socketPath: "/tmp/unused-contextdock-fixture.sock")

        #expect(written.isEmpty)
        #expect(try Data(contentsOf: settings) == original)
    }

    @Test(arguments: ["claudeCode", "codex"])
    func generatedPythonSenderDecodesThroughSwiftSocket(agent: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let socketPath = "/tmp/cdh-\(UUID().uuidString.prefix(8)).sock"
        let collected = Collector()
        let audits = AuditCollector()
        let server = EventSocketServer(socketPath: socketPath, onEvent: { collected.append($0) }, onAudit: { audits.append($0) })
        try server.start()
        defer { server.stop() }
        let script = HookInstaller.senderScript(agent: agent, socketPath: socketPath)
        let input = """
        {"type":"permissionRequested","session_id":"fixture-session","summary":"Review change","file":"fixture.swift","question":"Proceed?","options":["Allow","Deny"]}
        """
        try runPythonSender(script, directory: directory, input: input, throughStdin: agent == "codex")
        for _ in 0..<100 {
            if !collected.snapshot().isEmpty || audits.snapshot().contains(where: { $0.action == "socket.reject" }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let events = collected.snapshot()
        #expect(events.count == 1, "Generated sender was rejected: \(audits.snapshot())")
        let event = try #require(events.first)
        #expect(event.adapter.rawValue == agent)
        #expect(event.sessionID == StableID("fixture-session"))
        #expect(event.eventID.raw.hasPrefix("evt-"))
        #expect(event.type == .permissionRequested)
        #expect(event.summary == "Review change")
        #expect(event.filePath == "fixture.swift")
        #expect(event.questionOptions == ["Allow", "Deny"])
    }

    @Test(arguments: ["not JSON", "{\"summary\":\"offline\"}"])
    func generatedSenderFailsOpenForInvalidInputOrMissingSocket(input: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingSocket = directory.appendingPathComponent("missing.sock").path
        let script = HookInstaller.senderScript(agent: "claudeCode", socketPath: missingSocket)
        try runPythonSender(script, directory: directory, input: input)
    }

    private func runPythonSender(_ script: String, directory: URL, input: String, throughStdin: Bool = false) throws {
        let scriptURL = directory.appendingPathComponent("sender.py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": directory.path]
        if !throughStdin { process.environment?["HOOK_INPUT"] = input }
        let stdin = Pipe()
        let output = Pipe()
        process.standardInput = stdin
        process.standardOutput = output
        process.standardError = output
        try process.run()
        if throughStdin { try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let diagnostic = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, "Python sender failed: \(diagnostic)")
    }
}
