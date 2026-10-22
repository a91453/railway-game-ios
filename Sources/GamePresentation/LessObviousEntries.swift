import GameCore

// Ways in that were there but hard to see (NEXT_PRIORITIES §22.2 rank 26,
// §22.9; decision 336, later): the sights from the status bar, what the
// lines panel's Advanced holds, and holding a line's track.

extension GameSession {
    /// Whether the status bar shows the sights' button: a game with
    /// sights (decision 174), not in the tutorial or a lesson. The game
    /// menu's More keeps its row too.
    public var showsSightsButton: Bool {
        world.hasTourism && tutorial == nil && lesson == nil
    }
}

extension AdvancedDetails {
    /// What the lines panel's Advanced switch shows, under the switch
    /// itself, folded or not.
    public static func contentsText(in language: DisplayLanguage) -> String {
        language.text(
            "Service day, stopping patterns, the tracks each leg takes, target headways and traffic control.",
            "時段、停靠模式、各段股道、目標班距與行車控制。"
        )
    }
}

/// The one-time line on the track's card (decision 276): holding a line's
/// track opens the line with its busiest trips.
public enum TrackHoldHint {
    /// The device's setting that says the hint has been seen
    /// (`@AppStorage`).
    public static let seenKey = "hints.holdTrack.seen"

    /// Whether the card of a track with `lines` on it shows the hint: not
    /// seen yet, a track some line runs over, and not in the tutorial.
    public static func shows(lines: [LineID], seen: Bool, tutorialRuns: Bool) -> Bool {
        !seen && !lines.isEmpty && !tutorialRuns
    }

    public static func text(in language: DisplayLanguage) -> String {
        language.text(
            "Tip: touch and hold a line's track to open the line and its busiest trips.",
            "提示：長按路線的軌道，可以打開這條路線和它最熱門的旅程。"
        )
    }
}
