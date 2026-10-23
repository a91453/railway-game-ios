/// Which of the settings' three volumes a sound follows (decision 219,
/// stage 2): the music, the stations' arrival chimes, or the other sound
/// effects (building, tools, income, refusals, warnings, goals met).
public enum SoundCategory: String, CaseIterable, Hashable, Sendable {
    case music
    case chimes
    case effects
}

extension SoundCue {
    /// The volume the cue follows: every arrival chime and motif is a
    /// station chime, everything else an effect.
    public var category: SoundCategory {
        switch self {
        case .arrival: .chimes
        case .track, .transition, .built, .income, .refused, .warning, .goalMet, .lineAcquired, .ticketIssued: .effects
        }
    }
}

/// The player's three volumes (decision 219, stage 2: the research note's
/// §4, as the reference's OpenWorld `AudioSys` keeps one volume for the
/// music and one for the effects), each from 0 (silent) to 1 (as loud as
/// the game made it). Kept on the device, never in a save; the music and
/// sound switches still turn each off as a whole. Every level starts at 1,
/// so a player who never moves a slider hears what they heard before.
public struct SoundVolumes: Hashable, Sendable {
    public private(set) var music: Double
    public private(set) var chimes: Double
    public private(set) var effects: Double

    public init(music: Double = 1, chimes: Double = 1, effects: Double = 1) {
        self.music = Self.clamped(music)
        self.chimes = Self.clamped(chimes)
        self.effects = Self.clamped(effects)
    }

    /// The volumes kept on the device, read with `stored` by
    /// ``key(for:)``: a missing or unreadable value is 1.
    public init(stored: (String) -> Any?) {
        func level(_ category: SoundCategory) -> Double {
            (stored(Self.key(for: category)) as? Double) ?? 1
        }
        self.init(music: level(.music), chimes: level(.chimes), effects: level(.effects))
    }

    /// The device setting a category's volume is kept under.
    public static func key(for category: SoundCategory) -> String {
        "audio.volume.\(category.rawValue)"
    }

    /// The level of `category`, from 0 to 1.
    public func level(of category: SoundCategory) -> Double {
        switch category {
        case .music: music
        case .chimes: chimes
        case .effects: effects
        }
    }

    /// Sets `category`'s level, kept within 0 to 1.
    public mutating func setLevel(_ level: Double, of category: SoundCategory) {
        let level = Self.clamped(level)
        switch category {
        case .music: music = level
        case .chimes: chimes = level
        case .effects: effects = level
        }
    }

    /// What a sound the game plays at `base` (its own mix, from 0 to 1)
    /// plays at under the player's level for `category`.
    public func volume(_ base: Float, for category: SoundCategory) -> Float {
        base * Float(level(of: category))
    }

    /// 0 to 1; anything else (not a number included) is the nearer end,
    /// and not a number is 1, as a missing value is.
    private static func clamped(_ level: Double) -> Double {
        guard !level.isNaN else { return 1 }
        return min(max(level, 0), 1)
    }
}
