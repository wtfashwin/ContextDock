import Foundation

// MARK: - Markdown / frontmatter parsing

public struct ObsidianNote: Codable, Sendable, Hashable {
    public var path: String
    public var frontmatter: [String: String]
    public var frontmatterLists: [String: [String]]
    public var body: String
    public var wikilinks: [String]
    public var title: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
    public init(path: String, frontmatter: [String: String] = [:], frontmatterLists: [String: [String]] = [:], body: String = "", wikilinks: [String] = []) {
        self.path = path
        self.frontmatter = frontmatter
        self.frontmatterLists = frontmatterLists
        self.body = body
        self.wikilinks = wikilinks
    }
}

public enum MarkdownParser {
    /// Parses YAML-ish frontmatter (scalar `key: value` and simple `- item` lists) plus body.
    /// Full YAML is intentionally out of scope: Obsidian frontmatter in practice is this subset.
    public static func parse(path: String, content: String) -> ObsidianNote {
        var frontmatter: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var body = content

        if content.hasPrefix("---\n") {
            let rest = content.dropFirst(4)
            if let end = rest.range(of: "\n---") {
                let block = String(rest[..<end.lowerBound])
                body = String(rest[end.upperBound...]).trimmingCharacters(in: .newlines)
                var currentListKey: String?
                for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("- "), let key = currentListKey {
                        lists[key, default: []].append(String(trimmed.dropFirst(2)))
                    } else if let colon = trimmed.firstIndex(of: ":") {
                        let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                        let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        if value.isEmpty {
                            currentListKey = key
                            lists[key] = []
                        } else {
                            currentListKey = nil
                            frontmatter[key] = value
                        }
                    }
                }
            }
        }
        return ObsidianNote(
            path: path, frontmatter: frontmatter, frontmatterLists: lists,
            body: body, wikilinks: wikilinks(in: body)
        )
    }

    /// Extracts `[[Wiki Link]]` and `[[Target|Alias]]` targets.
    public static func wikilinks(in text: String) -> [String] {
        var links: [String] = []
        var search = text[...]
        while let open = search.range(of: "[[") {
            guard let close = search[open.upperBound...].range(of: "]]") else { break }
            var inner = String(search[open.upperBound..<close.lowerBound])
            if let pipe = inner.firstIndex(of: "|") { inner = String(inner[..<pipe]) }
            if let hash = inner.firstIndex(of: "#") { inner = String(inner[..<hash]) }
            let trimmed = inner.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { links.append(trimmed) }
            search = search[close.upperBound...]
        }
        return links
    }
}

// MARK: - Vault access

public enum VaultError: Error, Equatable {
    case pathOutsideVault(String)
    case symlinkEscape(String)
    case writeFailed(String)
}

/// All reads/writes go through here. Enforces vault containment, rejects
/// symlink escapes and path traversal. Writes are atomic with a revision backup.
public struct ObsidianVault: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Resolves a vault-relative path, refusing anything that escapes the vault.
    public func resolve(_ relativePath: String) throws -> URL {
        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(rootURL.path + "/") || candidate.path == rootURL.path else {
            throw VaultError.pathOutsideVault(relativePath)
        }
        // Reject escapes through symlinked intermediate directories.
        let resolved = candidate.resolvingSymlinksInPath()
        let parentResolved = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
        guard parentResolved.path.hasPrefix(rootURL.path) else {
            throw VaultError.symlinkEscape(relativePath)
        }
        _ = resolved
        return candidate
    }

    public func readNote(at relativePath: String) throws -> ObsidianNote {
        let url = try resolve(relativePath)
        let content = try String(contentsOf: url, encoding: .utf8)
        return MarkdownParser.parse(path: relativePath, content: content)
    }

    public func listMarkdownFiles(under relativeFolder: String = "") throws -> [String] {
        let base = try resolve(relativeFolder.isEmpty ? "." : relativeFolder)
        guard let enumerator = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let full = url.standardizedFileURL.path
            if full.hasPrefix(rootURL.path + "/") {
                out.append(String(full.dropFirst(rootURL.path.count + 1)))
            }
        }
        return out.sorted()
    }

    /// Atomic write with revision backup of previous content.
    @discardableResult
    public func writeNote(at relativePath: String, content: String) throws -> URL {
        let url = try resolve(relativePath)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let revisions = rootURL.appendingPathComponent(".contextdock-revisions")
            try fm.createDirectory(at: revisions, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = revisions.appendingPathComponent("\(url.lastPathComponent).\(stamp).bak")
            try? fm.copyItem(at: url, to: backup)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Appends under a `## Heading` section; creates the section (or note) when missing.
    /// Prefer this over whole-note replacement — never clobbers user-written content.
    public func appendToSection(notePath: String, heading: String, lines: [String]) throws {
        let url = try resolve(notePath)
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let marker = "## \(heading)"
        let addition = lines.joined(separator: "\n")
        if let headingRange = content.range(of: marker) {
            // Insert before the next "## " heading, or at end.
            let after = content[headingRange.upperBound...]
            if let next = after.range(of: "\n## ") {
                content.insert(contentsOf: "\n" + addition, at: next.lowerBound)
            } else {
                content += "\n" + addition
            }
        } else {
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
            content += "\n\(marker)\n\n\(addition)"
        }
        try writeNote(at: notePath, content: content)
    }
}

// MARK: - Obsidian URI

public enum ObsidianURI {
    public static func open(vault: String, file: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "obsidian"
        comps.host = "open"
        comps.queryItems = [
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "file", value: file),
        ]
        return comps.url
    }

    public static func search(vault: String, query: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "obsidian"
        comps.host = "search"
        comps.queryItems = [
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "query", value: query),
        ]
        return comps.url
    }
}
