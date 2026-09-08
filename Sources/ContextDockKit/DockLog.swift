import Foundation
import os

// MARK: - DockLog: capped OSLog + rotating file log
//
// Privacy rule: never log user content. IDs, counts, timings only.
// Summaries pass through SecretRedactor before touching the file.

public enum DockLog {
    private static let log = OSLog(subsystem: "com.contextdock", category: "island")
    private static let queue = DispatchQueue(label: "contextdock.log", qos: .utility)
    private static let maxBytes = 512 * 1024

    public static func info(_ msg: String) {
        os_log("%{public}@", log: log, type: .info, msg)
        append("[I] \(msg)")
    }

    public static func fault(_ msg: String) {
        os_log("%{public}@", log: log, type: .fault, msg)
        append("[F] \(msg)")
    }

    public static func eventSummary(_ event: AgentEvent) {
        // Content-free: type + adapter + lengths, never the text itself.
        info("event \(event.type.rawValue) via \(event.adapter.rawValue) summaryLen=\(event.summary.count)")
    }

    private static func fileURL() -> URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ContextDock/dock.log")
        return base
    }

    private static func append(_ line: String) {
        queue.async {
            guard let url = fileURL() else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            rotateIfNeeded(url: url)
            let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
            if let data = stamped.data(using: .utf8), let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            }
        }
    }

    private static func rotateIfNeeded(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > maxBytes else { return }
        try? FileManager.default.removeItem(at: url.appendingPathExtension("old"))
        try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("old"))
    }
}
