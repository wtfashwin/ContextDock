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
    public static func senderScript(agent: String) -> String {
        """
        #!/usr/bin/env python3
        import json, os, socket, sys, time, uuid
        sock = "\(socketPath())"
        try:
            raw = os.environ.get("HOOK_INPUT") or sys.stdin.read()
            data = json.loads(raw) if raw.strip() else {}
        except Exception:
            sys.exit(0)
        etype = data.get("type") or data.get("event") or "toolFinished"
        summary = data.get("summary") or data.get("prompt") or data.get("tool") or etype
        evt = {
            "schemaVersion": 1,
            "eventID": "evt-" + uuid.uuid4().hex[:8],
            "adapter": "\(agent)",
            "sessionID": data.get("session_id") or data.get("sessionID") or "live-external",
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
    public static func installAll() -> [String] {
        var written: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bin = home.appendingPathComponent(".contextdock/bin")
        try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for agent in ["claudeCode", "codex"] {
            let url = bin.appendingPathComponent("contextdock-hook-\(agent).py")
            try? senderScript(agent: agent).write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            written.append(url.path)
        }
        // Claude Code settings merge: ~/.claude/settings.json hooks.
        let claudeSettings = home.appendingPathComponent(".claude/settings.json")
        mergeClaudeSettings(at: claudeSettings, bin: bin)
        written.append(claudeSettings.path)
        return written
    }

    static func mergeClaudeSettings(at url: URL, bin: URL) {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { root = obj }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let hookPath = bin.appendingPathComponent("contextdock-hook-claudeCode.py").path
        for event in ["PreToolUse", "PermissionRequest", "UserPromptSubmit", "Stop"] {
            var arr = hooks[event] as? [[String: Any]] ?? []
            if !arr.contains(where: { ($0["command"] as? String)?.contains("contextdock-hook") == true }) {
                arr.append(["matcher": "*", "hooks": [["type": "command", "command": hookPath]]])
            }
            hooks[event] = arr
        }
        root["hooks"] = hooks
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
