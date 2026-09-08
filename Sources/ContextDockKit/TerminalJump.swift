import Foundation

// MARK: - Jump: click a session -> land in the exact terminal
//
// Kit stays UI-free: it builds the AppleScript / open commands,
// the App target executes them. Pure + tested here.

public struct JumpTarget: Hashable, Sendable {
    public var terminal: String
    public var workingDirectory: String?
    public var pid: Int32?
    public var tty: String?
    public var tmuxTarget: String?
    public init(terminal: String, workingDirectory: String? = nil, pid: Int32? = nil, tty: String? = nil, tmuxTarget: String? = nil) {
        self.terminal = terminal; self.workingDirectory = workingDirectory; self.pid = pid
        self.tty = tty; self.tmuxTarget = tmuxTarget
    }
    public init(session: LiveSession) {
        self.init(terminal: session.terminal, workingDirectory: session.repositoryPath, pid: session.pid, tty: session.tty, tmuxTarget: session.tmuxTarget)
    }
}

public enum TerminalJump: Sendable {
    /// Bundle IDs in preference order for activation.
    public static func bundleID(for terminal: String) -> String? {
        switch terminal.lowercased() {
        case let t where t.contains("iterm"): return "com.googlecode.iterm2"
        case let t where t.contains("ghostty"): return "com.mitchellh.ghostty"
        case let t where t.contains("warp"): return "dev.warp.Warp-Stable"
        case let t where t.contains("wezterm"): return "com.github.wez.wezterm"
        case let t where t.contains("kitty"): return "net.kovidgoyal.kitty"
        case let t where t.contains("cursor"): return "com.todesktop.230313mzl4w4u92"
        case let t where t.contains("vs code") || t.contains("vscode"): return "com.microsoft.VSCode"
        case let t where t.contains("terminal"): return "com.apple.Terminal"
        case let t where t.contains("zed"): return "dev.zed.Zed"
        case let t where t.contains("alacritty"): return "org.alacritty"
        default: return nil
        }
    }

    /// Human app name for `open -a` fallback (works even when bundle ID lookup fails).
    public static func appName(for terminal: String) -> String {
        let t = terminal.lowercased()
        if t.contains("iterm") { return "iTerm" }
        if t.contains("ghostty") { return "Ghostty" }
        if t.contains("warp") { return "Warp" }
        if t.contains("wezterm") { return "WezTerm" }
        if t.contains("kitty") { return "kitty" }
        if t.contains("cursor") { return "Cursor" }
        if t.contains("vs code") || t.contains("vscode") { return "Visual Studio Code" }
        if t.contains("zed") { return "Zed" }
        if t.contains("alacritty") { return "Alacritty" }
        if terminal == "Terminal" || t.contains("terminal") { return "Terminal" }
        return terminal
    }

    /// `open -a <App> <cwd>` argv — opens/focuses the terminal AT the repo.
    /// This is the reliable jump: activation APIs focus the app, `open` lands it.
    public static func openArguments(for target: JumpTarget) -> [String] {
        var args = ["-a", appName(for: target.terminal)]
        if let cwd = target.workingDirectory, !cwd.isEmpty {
            args += [cwd]
        }
        return args
    }

    /// AppleScript that focuses the window whose session sits in cwd.
    /// Falls back to plain activation when no cwd is known.
    public static func appleScript(for target: JumpTarget) -> String {
        if let cwd = target.workingDirectory, !cwd.isEmpty {
            let q = cwd.replacingOccurrences(of: "\"", with: "\\\"")
            switch target.terminal.lowercased() {
            case let t where t.contains("iterm"):
                return #"tell application "iTerm" to activate"# + "\n" +
                    #"tell application "iTerm" to tell current window to tell current session to select"# +
                    "\n-- cwd hint: \"\(q)\""
            default:
                return "activate application \"\(target.terminal)\"\n-- cwd hint: \"\(q)\""
            }
        }
        return "activate application \"\(target.terminal)\""
    }
}
