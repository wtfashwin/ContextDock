import Foundation

// MARK: - PID-accurate terminal links (the redirect engine)
//
// One `ps` snapshot → pid map → walk each agent's ppid chain to the exact
// terminal ancestor + tty. tmux panes resolve to `select-window/pane` targets.
// All parsing is pure string→struct; the App layer only executes argv/scripts.

public struct PsRow: Hashable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    public var tty: String
    public var comm: String
    public init(pid: Int32, ppid: Int32, tty: String, comm: String) {
        self.pid = pid; self.ppid = ppid; self.tty = tty; self.comm = comm
    }
}

public struct TerminalLink: Hashable, Sendable {
    public var agentPid: Int32
    public var terminalPid: Int32?
    public var terminalName: String
    public var tty: String
    public var tmuxTarget: String?
    public init(agentPid: Int32, terminalPid: Int32? = nil, terminalName: String, tty: String, tmuxTarget: String? = nil) {
        self.agentPid = agentPid; self.terminalPid = terminalPid
        self.terminalName = terminalName; self.tty = tty; self.tmuxTarget = tmuxTarget
    }
}

public struct TmuxPane: Hashable, Sendable {
    public var pid: Int32
    public var target: String
    public var path: String
    public init(pid: Int32, target: String, path: String) {
        self.pid = pid; self.target = target; self.path = path
    }
}

public enum ProcessTree: Sendable {
    /// Terminal ancestor binaries, checked lowercased-substring.
    public static let terminalComms = [
        "iterm2", "ghostty", "warp", "wezterm", "kitty",
        "terminal", "cursor", "code", "zed", "alacritty", "tmux",
    ]

    /// Parse `ps -axo pid=,ppid=,tty=,comm=` (comm may contain spaces → split capped).
    public static func parseSnapshot(_ text: String) -> [PsRow] {
        var rows: [PsRow] = []
        rows.reserveCapacity(512)
        for line in text.split(separator: "\n") {
            // pid ppid tty comm...
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            rows.append(PsRow(pid: pid, ppid: ppid, tty: String(parts[2]), comm: String(parts[3])))
        }
        return rows
    }

    /// O(n) map build + O(depth) walk per agent, cycle-guarded at 16 hops.
    public static func resolve(agentPids: Set<Int32>, rows: [PsRow]) -> [Int32: TerminalLink] {
        var byPid: [Int32: PsRow] = [:]
        byPid.reserveCapacity(rows.count)
        for r in rows { byPid[r.pid] = r }
        var out: [Int32: TerminalLink] = [:]
        for pid in agentPids {
            guard let agent = byPid[pid] else { continue }
            var seen: Set<Int32> = [pid]
            var cursor: PsRow? = agent
            var hops = 0
            var link: TerminalLink?
            while let cur = cursor, hops < 16 {
                hops += 1
                let comm = cur.comm.lowercased()
                if terminalComms.contains(where: { comm.contains($0) }) {
                    link = TerminalLink(agentPid: pid, terminalPid: cur.pid,
                                        terminalName: friendlyName(for: cur.comm),
                                        tty: agent.tty)
                    break
                }
                guard let parent = byPid[cur.ppid], seen.insert(parent.pid).inserted else { break }
                cursor = parent
            }
            if let link { out[pid] = link }
        }
        return out
    }

    public static func friendlyName(for comm: String) -> String {
        let c = comm.lowercased()
        if c.contains("iterm") { return "iTerm" }
        if c.contains("ghostty") { return "Ghostty" }
        if c.contains("warp") { return "Warp" }
        if c.contains("wezterm") { return "WezTerm" }
        if c.contains("kitty") { return "Kitty" }
        if c.contains("tmux") { return "tmux" }
        if c.contains("cursor") { return "Cursor" }
        if c.contains("zed") { return "Zed" }
        if c.contains("alacritty") { return "Alacritty" }
        if c.contains("code") { return "VS Code" }
        return "Terminal"
    }
}

public enum Tmux: Sendable {
    /// Parse `tmux list-panes -a -F '#{pane_pid} #{session_name}:#{window_index}.#{pane_index} #{pane_current_path}'`.
    public static func parsePanes(_ text: String) -> [TmuxPane] {
        var panes: [TmuxPane] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]) else { continue }
            panes.append(TmuxPane(pid: pid, target: String(parts[1]), path: String(parts[2])))
        }
        return panes
    }

    /// The pane running this pid (or its ancestor chain, for wrappers like zsh→claude).
    public static func match(panes: [TmuxPane], pid: Int32, ancestors: Set<Int32> = []) -> TmuxPane? {
        panes.first { $0.pid == pid || ancestors.contains($0.pid) }
    }

    /// Focus argv: select window+pane, then attach/switch-client best-effort.
    public static func focusArguments(target: String) -> [[String]] {
        [["select-window", "-t", target], ["select-pane", "-t", target]]
    }
}

public enum ItermJump: Sendable {
    /// AppleScript selecting the iTerm session whose tty matches. Pure builder.
    public static func script(tty: String) -> String {
        let t = tty.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "iTerm" to activate
        tell application "iTerm"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                try
                  if (tty of s) ends with "\(t)" then
                    select t
                    select s
                    return
                  end if
                end try
              end repeat
            end repeat
          end repeat
        end tell
        """
    }
}
