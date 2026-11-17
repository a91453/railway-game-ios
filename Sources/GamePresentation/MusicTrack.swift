import Foundation

// Decision 815: the game's music has two tunes. The theme plays all year;
// from 1 December to 6 January, the winter event's days by the device's
// own date (`WinterEvent`), the winter tune, an arrangement of Jingle
// Bells (public domain) made by the same synth (tools/audio). The music
// switch, the three volumes and the follow duck act on whichever plays.

/// Which tune the game's music plays.
public enum MusicTrack: String, CaseIterable, Sendable {
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

    /// The tune for `date`: the winter one while the winter event is on,
    /// the theme otherwise.
    public static func playing(at date: Date, calendar: Calendar = WinterEvent.calendar()) -> MusicTrack {
        WinterEvent.isOn(at: date, calendar: calendar) ? .winter : .theme
    }
}
