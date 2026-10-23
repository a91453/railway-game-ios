import GameCore

// Ways in that were there but hard to see (NEXT_PRIORITIES §22.2 rank 26,
// §22.9; decision 336, later): the sights from the status bar, what the
// lines panel's Advanced holds, and holding a line's track. Decision 383:
// what was folded too deep to find, brought up a level.

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
            "Service day, the tracks each leg takes and target headways.",
            "時段、各段股道與目標班距。"
        )
    }
}

/// The one-time line on the track's card (decision 276): holding a line's
/// track opens the line with its busiest trips, as the card's button does
/// (decision 383).
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
            "Tip: touching and holding a line's track opens the line too, without this card.",
            "提示：長按路線的軌道，不用這張卡也能直接打開路線。"
        )
    }

    /// Decision 383: the track card's button that opens line `name`, in
    /// words, so it is not found only by holding the track.
    public static func openTitle(_ name: String, in language: DisplayLanguage) -> String {
        language.text("Open \(name)", "打開\(name)")
    }
}

/// Decision 383: the switches for every line (traffic control and how
/// passengers route), in their own block at the top of the lines panel
/// rather than at the bottom of a line's Advanced.
public enum NetworkSwitches {
    public static func title(in language: DisplayLanguage) -> String {
        language.text("Whole network", "整個路網")
    }
}

/// Decision 383: adding an express (a stopping pattern) on the line's own
/// page, not behind Advanced.
public enum StoppingPatternEntry {
    public static func title(in language: DisplayLanguage) -> String {
        language.text("Add an express (stopping pattern)", "加快車（停車模式）")
    }
}

/// Decision 383: the build tool's folded options, named by what they
/// hold (the structure, the grade and the curves) rather than "Advanced";
/// snapping to track stands beside Double instead.
public enum NetworkOptionsEntry {
    public static func title(in language: DisplayLanguage) -> String {
        language.text("Elevated, grade, curves", "高架、坡度、曲線")
    }
}

/// Decision 383: what the card of a train tapped on the map does to it,
/// beside its timetable, rather than only under Build → Train. Taking it
/// off the track stays there.
public enum TrainCardAction: String, CaseIterable, Sendable {
    /// Stops it where it is (rate 0); ``resume`` once stopped.
    case hold, resume
    /// Turns it round, clearing its path.
    case reverse

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        // The train tool's words, never the clock's "Pause" or "Resume".
        case .hold: language.text("Hold train", "暫停列車")
        case .resume: language.text("Resume train", "恢復列車")
        case .reverse: language.text("Reverse", "折返")
        }
    }
}

extension GameSession {
    /// Decision 383: the actions the card of train `id` offers, in order:
    /// hold or resume, then reverse; none for a train off the track or one
    /// the world does not have.
    public func trainCardActions(of id: TrainID) -> [TrainCardAction] {
        guard let train = world.train(id: id), train.position != nil else { return [] }
        return [train.movement.rate > 0 ? .hold : .resume, .reverse]
    }

    /// Decision 383: does `action` to train `id` from its card, as the
    /// train tool's buttons do (``holdSelectedTrain()``,
    /// ``resumeSelectedTrain()``, ``reverseSelectedTrain()``): the train
    /// becomes the selected one first.
    public func runTrainCardAction(_ action: TrainCardAction, on id: TrainID) {
        guard world.train(id: id) != nil else { return }
        selectTrain(id)
        switch action {
        case .hold: holdSelectedTrain()
        case .resume: resumeSelectedTrain()
        case .reverse: reverseSelectedTrain()
        }
    }
}
