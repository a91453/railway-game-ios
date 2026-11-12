// The owner (2026-11-13): 「鐵軌上下滑動好像沒有教學」. The construction
// HUD's height cell (decision 646: held and slid up or down a metre at a
// time, a tap for − and +) was only ever told in What's New. A small line
// under the HUD says it the first times a stretch is previewed, until the
// player has changed a height once or put the line away: the device keeps
// that, not the save (as ``RouteHint`` and ``PassingLoopHint``).

/// The one-time line under the construction HUD about its height cell.
public enum HeightSlideHint {
    /// The device's setting that says the line is done with
    /// (`@AppStorage`).
    public static let seenKey = "hints.trackHeightSlide.seen"

    /// Whether the line shows: not yet done with, the HUD has a height
    /// cell that slides (`card` with a label; a stretch between two
    /// existing ends has none), and no tutorial runs, whose own card says
    /// what to do next.
    public static func shows(seen: Bool, card: NetworkHeightCard?, tutorialRuns: Bool) -> Bool {
        guard !seen, !tutorialRuns, let card, !card.label.isEmpty else { return false }
        return card.canRaise || card.canLower
    }

    /// Whether raising the end by `steps` metres (a slide let go, − or +,
    /// VoiceOver's adjustment) is the player having used the cell: any
    /// change is; a hold let go where it began is not.
    public static func isUse(raisingBy steps: Int) -> Bool {
        steps != 0
    }

    public static func text(in language: DisplayLanguage) -> String {
        language.text(
            "Hold the height above and slide up or down to raise this end or take it underground.",
            "按住上面的高度上下滑，可以把這一端架高或挖到地下。"
        )
    }

    public static func dismissLabel(in language: DisplayLanguage) -> String {
        language.text("Close tip", "關掉提示")
    }
}
