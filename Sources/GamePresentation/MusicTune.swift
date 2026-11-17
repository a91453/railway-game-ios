import Foundation

// Decision 815: the game's music has two tunes. The theme plays all year;
// from 1 December to 6 January, the winter event's days by the device's
// own date (`WinterEvent`), the winter tune, an arrangement of Jingle
// Bells (public domain) made by the same synth (tools/audio), takes turns
// with the theme: the winter tune once, the theme once, and again, so a
// tune everyone knows is not heard round and round for 37 days. The music
// switch, the three volumes and the follow duck act on whichever plays.

/// Which tune the game's music plays.
public enum MusicTune: String, CaseIterable, Sendable {
    /// The game's own theme (decision 79).
    case theme
    /// The winter tune, during the winter event (decision 815).
    case winter

    /// The bundled file (`Resources/Audio/`): a seamless IMA4 loop.
    public var resource: (name: String, extension: String) {
        switch self {
        case .theme: ("music-loop", "caf")
        case .winter: ("music-winter", "caf")
        }
    }

    /// The tune the music starts with on `date`: the winter one while the
    /// winter event is on, the theme otherwise.
    public static func playing(at date: Date, calendar: Calendar = WinterEvent.calendar()) -> MusicTune {
        WinterEvent.isOn(at: date, calendar: calendar) ? .winter : .theme
    }

    /// What the music plays when it starts or the app comes back to the
    /// foreground on `date`, `current` having played before (`nil`: none
    /// yet). Outside the winter event the theme loops. During it the two
    /// tunes take turns, each played once: a turn already under way goes
    /// on, and the theme looping from before the event gives way to the
    /// winter tune at once.
    public static func play(at date: Date, continuing current: MusicPlay?, calendar: Calendar = WinterEvent.calendar()) -> MusicPlay {
        let tune = playing(at: date, calendar: calendar)
        guard tune == .winter else { return MusicPlay(tune: .theme, loops: true) }
        if let current, !current.loops { return current }
        return MusicPlay(tune: .winter, loops: false)
    }

    /// What follows `finished` when it has played to its end on `date`
    /// (only a turn that does not loop ends): the other tune while the
    /// winter event is on, the theme looping once it is over.
    public static func play(after finished: MusicTune, at date: Date, calendar: Calendar = WinterEvent.calendar()) -> MusicPlay {
        guard playing(at: date, calendar: calendar) == .winter else { return MusicPlay(tune: .theme, loops: true) }
        return MusicPlay(tune: finished == .winter ? .theme : .winter, loops: false)
    }
}

/// What the game's music plays (decision 815): a tune, and whether it
/// loops on its own or, played once, gives way to the next
/// (``MusicTune/play(after:at:calendar:)``).
public struct MusicPlay: Equatable, Sendable {
    public var tune: MusicTune
    public var loops: Bool

    public init(tune: MusicTune, loops: Bool) {
        self.tune = tune
        self.loops = loops
    }
}
