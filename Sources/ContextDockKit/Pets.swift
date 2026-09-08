import Foundation

// MARK: - Agent pets: the left wing
//
// Each engine gets a cute resident. Pickable style packs, persisted.
// Pure data — SwiftUI renders emoji + gradient ring, no assets needed.

public enum PetStyle: String, Codable, CaseIterable, Sendable {
    case ember, mono, pixel, aqua, war, abyss, shadow, retro
    public var displayName: String {
        switch self {
        case .ember: return "Ember"
        case .mono: return "Mono"
        case .pixel: return "Pixel Pals"
        case .aqua: return "Aqua"
        case .war: return "Warbound"
        case .abyss: return "Abyss"
        case .shadow: return "Shadow"
        case .retro: return "Retro"
        }
    }
    /// What choosing it means — shown under the picker, no mystery.
    public var meaning: String {
        switch self {
        case .ember: return "Warm + expressive. The classic islanders."
        case .mono: return "Quiet glyphs. For focus purists and light menus."
        case .pixel: return "Arcade energy. 8-bit sounds pair well."
        case .aqua: return "Cool sea tones. Calm during red builds."
        case .war: return "Decorated veterans. Every scar is a shipped postmortem."
        case .abyss: return "What stares back from the terminal at 2am. Beautiful down here."
        case .shadow: return "Stealth mode residents. They were never here."
        case .retro: return "Macintosh garden party. Lanyards required."
        }
    }
}

public struct AgentPet: Hashable, Sendable {
    public var emoji: String
    public var name: String
    public var trait: String
    public init(emoji: String, name: String, trait: String = "") {
        self.emoji = emoji; self.name = name; self.trait = trait
    }
}

public enum PetStore: Sendable {
    /// Exhaustive matrix: outer style × inner agent, NO `default:` anywhere.
    /// The compiler rejects any missing or overlapping cell, so packs cannot
    /// drift apart again. (codexCLI is the same CLI as codex: shared cells.)
    public static func pet(for agent: AgentKind, style: PetStyle) -> AgentPet {
        switch style {
        case .ember: return emberPet(agent)
        case .mono: return monoPet(agent)
        case .pixel: return pixelPet(agent)
        case .aqua: return aquaPet(agent)
        case .war: return warPet(agent)
        case .abyss: return abyssPet(agent)
        case .shadow: return shadowPet(agent)
        case .retro: return retroPet(agent)
        }
    }

    private static func emberPet(_ agent: AgentKind) -> AgentPet {
        switch agent {
        case .claudeCode: return AgentPet(emoji: "🦉", name: "Hoot", trait: "Reads the whole file first.")
        case .codex, .codexCLI: return AgentPet(emoji: "🐙", name: "Ink", trait: "Diffs before coffee.")
        case .gemini: return AgentPet(emoji: "🔥", name: "Twin", trait: "Two flames, one light.")
        case .cursor: return AgentPet(emoji: "🕯️", name: "Wick", trait: "Burns at the cursor.")
        case .opencode: return AgentPet(emoji: "🏮", name: "Lantern", trait: "Open light for dark code.")
        case .qwen: return AgentPet(emoji: "🎇", name: "Sparkler", trait: "Brief. Brilliant.")
        case .copilot: return AgentPet(emoji: "🔦", name: "Torch", trait: "Lights your thermal.")
        case .fake: return AgentPet(emoji: "🌰", name: "Seed", trait: "Every demo starts here.")
        }
    }

    private static func monoPet(_ agent: AgentKind) -> AgentPet {
        switch agent {
        case .claudeCode: return AgentPet(emoji: "○", name: "Scout", trait: "Silent, thorough.")
        case .codex, .codexCLI: return AgentPet(emoji: "◇", name: "Hex", trait: "Eight arms, zero conflicts.")
        case .gemini: return AgentPet(emoji: "☆", name: "Nova", trait: "Two answers, picks the good one.")
        case .cursor: return AgentPet(emoji: "◎", name: "Dot", trait: "Lands on the symbol.")
        case .opencode: return AgentPet(emoji: "□", name: "Shell", trait: "Open by name, open by nature.")
        case .qwen: return AgentPet(emoji: "△", name: "Q", trait: "Rare sighting. Good omen.")
        case .copilot: return AgentPet(emoji: "⬢", name: "Wing", trait: "Rides your thermal.")
        case .fake: return AgentPet(emoji: "·", name: "Sprout", trait: "Demo, but earnest.")
        }
    }

    private static func pixelPet(_ agent: AgentKind) -> AgentPet {
        switch agent {
        case .claudeCode: return AgentPet(emoji: "🐤", name: "Pip", trait: "Chirps at type errors.")
        case .codex, .codexCLI: return AgentPet(emoji: "👾", name: "Bit", trait: "Eats exit code 0.")
        case .gemini: return AgentPet(emoji: "🛸", name: "Saucer", trait: "Abducts bugs.")
        case .cursor: return AgentPet(emoji: "🧲", name: "Magnet", trait: "Snaps to the symbol.")
        case .opencode: return AgentPet(emoji: "🧪", name: "Flask", trait: "Brews in the open.")
        case .qwen: return AgentPet(emoji: "🎲", name: "Dice", trait: "Rare roll. Always crits.")
        case .copilot: return AgentPet(emoji: "🚀", name: "Boost", trait: "Pixel afterburner.")
        case .fake: return AgentPet(emoji: "🎮", name: "Continue", trait: "Insert coin to demo.")
        }
    }

    private static func aquaPet(_ agent: AgentKind) -> AgentPet {
        switch agent {
        case .claudeCode: return AgentPet(emoji: "🐬", name: "Sonar", trait: "Finds the bug underwater.")
        case .codex, .codexCLI: return AgentPet(emoji: "🦑", name: "Squirt", trait: "Inks the green build.")
        case .gemini: return AgentPet(emoji: "💧", name: "Drop", trait: "Ripple first, wave later.")
        case .cursor: return AgentPet(emoji: "🎣", name: "Angler", trait: "Hooks the right line.")
        case .opencode: return AgentPet(emoji: "🐚", name: "Shell", trait: "The ocean is open source.")
        case .qwen: return AgentPet(emoji: "🫧", name: "Bubble", trait: "Surfaces rarely. Pops brilliantly.")
        case .copilot: return AgentPet(emoji: "⛵", name: "Regatta", trait: "Catches every thermal wind.")
        case .fake: return AgentPet(emoji: "🪸", name: "Reef", trait: "A demo with depth.")
        }
    }

    private static func warPet(_ agent: AgentKind) -> AgentPet {
        switch agent {
        case .claudeCode: return AgentPet(emoji: "🪖", name: "Sarge", trait: "Held the line at the 3am deploy.")
        case .codex, .codexCLI: return AgentPet(emoji: "🎖️", name: "Valor", trait: "Cited for bravery under merge conflict.")
        case .gemini: return AgentPet(emoji: "💥", name: "Blast", trait: "Shock and awe, but for bugs.")
        case .cursor: return AgentPet(emoji: "🛡️", name: "Aegis", trait: "No diff gets through.")
        case .opencode: return AgentPet(emoji: "⚔️", name: "Sabre", trait: "Open steel. Open source.")
        case .qwen: return AgentPet(emoji: "🪂", name: "Drop", trait: "Behind enemy lines. Shipped anyway.")
        case .copilot: return AgentPet(emoji: "🚁", name: "Dustoff", trait: "Nobody left behind. Especially not you.")
        case .fake: return AgentPet(emoji: "🎗️", name: "Remembrance", trait: "A demo that served.")
        }
    }

    private static func abyssPet(_ agent: AgentKind) -> AgentPet {
        switch agent {
        case .claudeCode: return AgentPet(emoji: "🕳️", name: "Undertow", trait: "It read your code. All of it.")
        case .codex, .codexCLI: return AgentPet(emoji: "👁️", name: "Watcher", trait: "Eight eyes. All on the diff.")
        case .gemini: return AgentPet(emoji: "🌒", name: "Tidelock", trait: "One face always toward the bug.")
        case .cursor: return AgentPet(emoji: "🕸️", name: "Web", trait: "You already clicked. It knew.")
        case .opencode: return AgentPet(emoji: "🧿", name: "Hadal", trait: "Pressure-tested at 10,000 meters.")
        case .qwen: return AgentPet(emoji: "👻", name: "Wisp", trait: "A rare sighting. Don't blink.")
        case .copilot: return AgentPet(emoji: "🌪️", name: "Vortex", trait: "Your thermal, but haunted.")
        case .fake: return AgentPet(emoji: "🥀", name: "Pressed", trait: "A demo that dreamed too deep.")
        }
    }

    private static func shadowPet(_ agent: AgentKind) -> AgentPet {
        switch agent {
        case .claudeCode: return AgentPet(emoji: "🦇", name: "Echo", trait: "Works nights. You sleep.")
        case .codex, .codexCLI: return AgentPet(emoji: "🕷️", name: "Weave", trait: "Spins the web of deps.")
        case .gemini: return AgentPet(emoji: "🌑", name: "Umbra", trait: "Twin minds, one quiet.")
        case .cursor: return AgentPet(emoji: "🎱", name: "Eight", trait: "Called the shot.")
        case .opencode: return AgentPet(emoji: "🕶️", name: "Shade", trait: "Open source. Closed curtains.")
        case .qwen: return AgentPet(emoji: "🌫️", name: "Mist", trait: "There, then gone.")
        case .copilot: return AgentPet(emoji: "🦅", name: "Soar", trait: "Ridge lift included.")
        case .fake: return AgentPet(emoji: "🌱", name: "Sprout", trait: "Demo, but earnest.")
        }
    }

    private static func retroPet(_ agent: AgentKind) -> AgentPet {
        switch agent {
        case .claudeCode: return AgentPet(emoji: "📎", name: "Clip", trait: "It looks like you're shipping.")
        case .codex, .codexCLI: return AgentPet(emoji: "💾", name: "Floppy", trait: "Saves. Always saves.")
        case .gemini: return AgentPet(emoji: "🔮", name: "Oracle", trait: "The future is 256 colors.")
        case .cursor: return AgentPet(emoji: "🕹️", name: "Stick", trait: "Up up down down ship it.")
        case .opencode: return AgentPet(emoji: "📼", name: "Rewind", trait: "Be kind, rebase.")
        case .qwen: return AgentPet(emoji: "📻", name: "Dial", trait: "Broadcasting on all frequencies.")
        case .copilot: return AgentPet(emoji: "✈️", name: "Clipper", trait: "Pan Am. Pan all.")
        case .fake: return AgentPet(emoji: "👾", name: "Invader", trait: "High score: demo.")
        }
    }

    /// Locked styles explain themselves: requirement + progress.
    /// NOTE: locks never block selection — every pack is pickable from day
    /// one. Locks only drive the earned banner + progress copy below.
    public static func unlocked(_ style: PetStyle, settings: IslandSettings) -> (open: Bool, hint: String) {
        switch style {
        case .ember, .mono, .pixel, .aqua: return (true, "Yours from day one.")
        case .war: return settings.failuresSeen >= 3
            ? (true, "Unlocked — decorated across \(settings.failuresSeen) glorious failures.")
            : (false, "Survive \(3 - settings.failuresSeen) more failed sessions to earn your scars. (\(settings.failuresSeen)/3)")
        case .abyss: return settings.jumpsMade >= 15
            ? (true, "Unlocked — you've descended \(settings.jumpsMade) times.")
            : (false, "Jump into terminals \(15 - settings.jumpsMade) more times to descend. (\(settings.jumpsMade)/15)")
        case .shadow:
            if settings.questionsAnswered >= 5 {
                return (true, "Unlocked — you faced 5 questions.")
            }
            return (false, "Answer \(5 - settings.questionsAnswered) more agent questions to wake them. (\(settings.questionsAnswered)/5)")
        case .retro: return settings.partyUnlocked
            ? (true, "Unlocked — the parade marched.")
            : (false, "Type “party” in Capture to throw the parade.")
        }
    }

    // MARK: Earned banners (pure: diff two settings, get newly opened styles)

    /// Styles open in `after` but not `before`, excluding already-celebrated.
    /// Pure so tests pin the exact moment each pack is earned.
    public static func newlyUnlocked(before: IslandSettings, after: IslandSettings) -> [PetStyle] {
        [.war, .abyss, .shadow, .retro].filter { style in
            !unlocked(style, settings: before).open
                && unlocked(style, settings: after).open
                && !after.celebratedStyles.contains(style.rawValue)
        }
    }

    public static func celebrationLine(for style: PetStyle) -> String {
        switch style {
        case .war: return "🎖️ Warbound earned — your scars are showing in Pets"
        case .abyss: return "🕳️ Abyss opened — the deep residents await in Pets"
        case .shadow: return "🌑 Shadow woke — check Pets, quietly"
        case .retro: return "📼 Retro unlocked — the parade left souvenirs in Pets"
        default: return "✨ New residents in Pets"
        }
    }

    // MARK: Easter eggs (tap the notch 5x / type "party")

    public static let quotes: [String] = [
        "Ship it. 🚢", "No merge conflicts in the island.",
        "The notch is honest now. Move.", "Touch grass after this deploy.",
        "I eat exit code 0 for breakfast.", "psst… try typing “party”.",
    ]
    public static func quote(for agent: AgentKind) -> String {
        let idx = abs(agent.rawValue.hashValue) % quotes.count
        return quotes[idx]
    }
}

// MARK: - Island settings (persisted as JSON in StoreDocument.settings["island"])

public struct IslandSettings: Codable, Hashable, Sendable {
    public var petStyle: PetStyle
    public var soundsEnabled: Bool
    public var launchAtLogin: Bool
    public var showSnippets: Bool
    public var onboarded: Bool
    public var tapCount: Int
    public var partyUnlocked: Bool
    // Earned stats drive unlocks + pattern copy. Counters only, no content.
    public var approvalsGiven: Int
    public var questionsAnswered: Int
    public var jumpsMade: Int
    public var failuresSeen: Int
    public var seenInsightIDs: [String]
    public var glassVivid: Bool
    /// Styles already celebrated, so earned banners fire exactly once.
    public var celebratedStyles: [String]
    public init(
        petStyle: PetStyle = .ember, soundsEnabled: Bool = true,
        launchAtLogin: Bool = false, showSnippets: Bool = true,
        onboarded: Bool = false, tapCount: Int = 0, partyUnlocked: Bool = false,
        approvalsGiven: Int = 0, questionsAnswered: Int = 0, jumpsMade: Int = 0,
        failuresSeen: Int = 0, seenInsightIDs: [String] = [], glassVivid: Bool = true,
        celebratedStyles: [String] = []
    ) {
        self.petStyle = petStyle; self.soundsEnabled = soundsEnabled
        self.launchAtLogin = launchAtLogin; self.showSnippets = showSnippets
        self.onboarded = onboarded; self.tapCount = tapCount
        self.partyUnlocked = partyUnlocked
        self.approvalsGiven = approvalsGiven; self.questionsAnswered = questionsAnswered
        self.jumpsMade = jumpsMade; self.failuresSeen = failuresSeen
        self.seenInsightIDs = seenInsightIDs; self.glassVivid = glassVivid
        self.celebratedStyles = celebratedStyles
    }

    public static func decode(from string: String?) -> IslandSettings {
        guard let string, let data = string.data(using: .utf8),
              let s = try? JSONDecoder().decode(IslandSettings.self, from: data) else { return IslandSettings() }
        return s
    }
    public func encode() -> String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
