import AppKit

// MARK: - 8-bit style alerts (cached players; silent when toggled off upstream)
enum SoundEffects {
    enum Kind { case needsAttention, done, failed }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSSound] = [:]

    static func play(_ kind: Kind) {
        let name: String
        switch kind {
        case .needsAttention: name = "Glass"
        case .done: name = "Hero"
        case .failed: name = "Basso"
        }
        lock.lock()
        let sound = cache[name] ?? NSSound(named: name).map { cache[name] = $0; return $0 }
        lock.unlock()
        sound?.play()
    }
}
