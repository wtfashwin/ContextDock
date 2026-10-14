import Foundation

// MARK: - Zero-config hook installer (Vibe Island parity)
//
// Writes local hook entries so Claude Code / Codex forward permission
// requests, questions, and completions to ContextDock's Unix socket.
// Fail-open: if the app isn't running, hooks exit 0 and agents continue.

public enum HookInstaller: Sendable {
    public static let socketDirName = "ContextDock"
    public static let socketFileName = "events.sock"

    public static func socketPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("\(socketDirName)/\(socketFileName)").path
    }

    /// Python one-liner hook body: reads $HOOK_INPUT JSON, emits AgentEvent JSONL.
    public static func senderScript(agent: String, socketPath: String? = nil) -> String {
        // JSON string literals are also Python string literals. Encoding the
        // values keeps quotes and backslashes in home/socket paths intact.
        guard let data = try? JSONSerialization.data(
            withJSONObject: [agent, socketPath ?? Self.socketPath()], options: [.withoutEscapingSlashes]
        ), let arguments = String(data: data, encoding: .utf8) else {
            return "#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n"
        }
        return """
        #!/usr/bin/env python3
        import json, os, socket, sys, time, uuid
        agent, sock = \(arguments)
        try:
            raw = os.environ.get("HOOK_INPUT") or sys.stdin.read()
            data = json.loads(raw) if raw.strip() else {}
        except Exception:
            sys.exit(0)
        etype = data.get("type") or data.get("event") or "toolFinished"
        summary = data.get("summary") or data.get("prompt") or data.get("tool") or etype
        evt = {
            "schemaVersion": 1,
            "eventID": {"raw": "evt-" + uuid.uuid4().hex[:8]},
            "adapter": agent,
            "sessionID": {"raw": data.get("session_id") or data.get("sessionID") or "live-external"},
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "task": data.get("task"),
            "status": "ok",
            "summary": str(summary)[:500],
            "filePath": data.get("file") or data.get("filePath"),
            "terminal": data.get("terminal") or "Terminal",
            "toolName": data.get("tool"),
            "diffText": data.get("diff"),
            "question": data.get("question"),
            "questionOptions": data.get("options"),
            "type": etype,
        }
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.5)
            s.connect(sock)
            s.sendall((json.dumps(evt) + "\\n").encode())
            s.close()
        except Exception:
            pass
        sys.exit(0)
        """
    }

    /// Installs (merges) hook entries without clobbering user config.
    /// Returns list of files written.
    @discardableResult
    public static func installAll(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        socketPath: String? = nil
    ) -> [String] {
        var written: [String] = []
        var claudeSenderInstalled = false
        let bin = home.appendingPathComponent(".contextdock/bin")
        try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for agent in ["claudeCode", "codex"] {
            let url = bin.appendingPathComponent("contextdock-hook-\(agent).py")
            do {
                try senderScript(agent: agent, socketPath: socketPath).write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                written.append(url.path)
                if agent == "claudeCode" { claudeSenderInstalled = true }
            } catch {
                continue
            }
        }
        // Claude Code settings merge: ~/.claude/settings.json hooks.
        let claudeSettings = home.appendingPathComponent(".claude/settings.json")
        if claudeSenderInstalled && mergeClaudeSettings(at: claudeSettings, bin: bin) {
            written.append(claudeSettings.path)
        }
        return written
    }

    @discardableResult
    static func mergeClaudeSettings(at url: URL, bin: URL) -> Bool {
        var root: [String: Any] = [:]
        let exists = FileManager.default.fileExists(atPath: url.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
        if exists {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            root = obj
        }
        var hooks: [String: Any] = [:]
        if let existing = root["hooks"] {
            guard let obj = existing as? [String: Any] else { return false }
            hooks = obj
        }
        let hookPath = bin.appendingPathComponent("contextdock-hook-claudeCode.py").path
        for event in ["PreToolUse", "PermissionRequest", "UserPromptSubmit", "Stop"] {
            var arr: [[String: Any]] = []
            if let existing = hooks[event] {
                guard let entries = existing as? [[String: Any]] else { return false }
                arr = entries
            }
            for entry in arr where entry["hooks"] != nil {
                guard entry["hooks"] is [[String: Any]] else { return false }
            }
            if !arr.contains(where: { entry in
                (entry["hooks"] as? [[String: Any]])?.contains(where: {
                    $0["type"] as? String == "command" && $0["command"] as? String == hookPath
                }) == true
            }) {
                arr.append(["matcher": "*", "hooks": [["type": "command", "command": hookPath]]])
            }
            hooks[event] = arr
        }
        root["hooks"] = hooks
        do {
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
