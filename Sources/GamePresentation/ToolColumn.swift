// Decision 226, later (TestFlight, 2026-10-16): the tools column down the
// leading edge of a phone held sideways, and the building tools beside the
// map, keep one size for every button, chosen or not, and one width for
// every group of them, so the column lines up; and the column keeps the
// screen's gap below the layer strip over it rather than reaching up to it.

/// The sizes of the tools column, in points.
public enum ToolColumn {
    /// Every button's width in the column, chosen or not: a chosen button's
    /// bolder name made it wider than the others, and the card's toggle
    /// was as wide as its icon.
    public static let buttonWidth: Double = 64
    /// The glass round each group of buttons, on every side.
    public static let tilePadding: Double = 4
    /// The space between the buttons of a group.
    public static let buttonSpacing: Double = 4
    /// The column's width, and the building tools' beside the map: a
    /// button and the glass either side of it.
    public static var width: Double { buttonWidth + 2 * tilePadding }

    /// The most height the column may take, anchored `bottom` points above
    /// the screen's foot: up to `gap` below `top`, the lower edge of what
    /// floats over the top of the screen (the board, and the layer strip
    /// under it when it shows), on a screen `screenHeight` high. Never
    /// less than `least`, where the column scrolls.
    public static func maxHeight(screenHeight: Double, top: Double, gap: Double, bottom: Double, least: Double = 60) -> Double {
        max(least, screenHeight - top - gap - bottom)
    }
}
