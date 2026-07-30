import Foundation

/// Local-only Unix domain socket listener for normalized agent events.
/// Newline-delimited JSON, one AgentEvent per line. No network listener.
/// Socket file is created with owner-only permissions.
public final class EventSocketServer: @unchecked Sendable {
    public let socketPath: String
    private var serverFD: Int32 = -1
    private let queue = DispatchQueue(label: "contextdock.eventsocket")
    private var deduplicator = EventDeduplicator()
    private let dedupLock = NSLock()
    private let onEvent: @Sendable (AgentEvent) -> Void
    private let onAudit: @Sendable (AuditEvent) -> Void
    private var running = false

    public init(
        socketPath: String,
        onEvent: @escaping @Sendable (AgentEvent) -> Void,
        onAudit: @escaping @Sendable (AuditEvent) -> Void = { _ in }
    ) {
        self.socketPath = socketPath
        self.onEvent = onEvent
        self.onAudit = onAudit
    }

    public func start() throws {
        unlink(socketPath)
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { throw SocketError.createFailed }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { throw SocketError.pathTooLong }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBytes { src in
                dest.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(dest.count)))
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(serverFD, $0, size) }
        }
        guard bindResult == 0 else { throw SocketError.bindFailed(errno) }
        // Owner-only: local protection against other users on the machine.
        chmod(socketPath, 0o600)
        guard listen(serverFD, 8) == 0 else { throw SocketError.listenFailed(errno) }
        running = true
        queue.async { [weak self] in self?.acceptLoop() }
        onAudit(AuditEvent(action: "socket.start", detail: socketPath))
    }

    private func acceptLoop() {
        while running {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { continue }
            handleClient(fd: clientFD)
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { break }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > EventValidation.maxMessageBytes * 4 {
                onAudit(AuditEvent(action: "socket.reject", detail: "client stream exceeded size bound"))
                return
            }
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                process(lineData)
            }
        }
    }

    private func process(_ data: Data) {
        switch EventValidation.decodeEvent(from: data) {
        case .success(let event):
            dedupLock.lock()
            let isNew = deduplicator.admit(event)
            dedupLock.unlock()
            if isNew {
                onAudit(AuditEvent(action: "socket.event", detail: "\(event.type.rawValue) \(event.eventID.raw)"))
                onEvent(event)
            } else {
                onAudit(AuditEvent(action: "socket.duplicate", detail: event.eventID.raw))
            }
        case .failure(let failure):
            onAudit(AuditEvent(action: "socket.reject", detail: "\(failure)"))
        }
    }

    public func stop() {
        running = false
        if serverFD >= 0 { close(serverFD) }
        unlink(socketPath)
        onAudit(AuditEvent(action: "socket.stop", detail: socketPath))
    }

    public enum SocketError: Error {
        case createFailed, pathTooLong
        case bindFailed(Int32), listenFailed(Int32)
    }
}

/// Test/demo client that writes newline-delimited AgentEvent JSON to the socket.
public enum EventSocketClient {
    public static func send(_ event: AgentEvent, to socketPath: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw EventSocketServer.SocketError.createFailed }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            pathBytes.withUnsafeBytes { src in
                dest.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(dest.count)))
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) }
        }
        guard result == 0 else { throw EventSocketServer.SocketError.bindFailed(errno) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(event)
        data.append(0x0A)
        data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
    }
}
