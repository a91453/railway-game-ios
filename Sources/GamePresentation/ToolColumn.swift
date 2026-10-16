// Decision 226, later (TestFlight, 2026-10-16): the tools column down the
// leading edge of a phone held sideways, and the building tools beside the
// map, keep one size for every button, chosen or not, and one width for
// every group of them, so the column lines up; and the column keeps the
// screen's gap below the layer strip over it rather than reaching up to it.
// Later the same day (TestFlight 67.1 beside 66.1): the phone's column back
// to 66.1's width, so the map has the room it had; the building tools
// beside the map, where the map has room to spare, keep 66.1's 72 points.

/// The sizes of the tools column, in points.
public enum ToolColumn {
    /// Every button's width in the column, chosen or not: a chosen button's
    /// bolder name made it wider than the others, and the card's toggle
    /// was as wide as its icon. 48, the narrowest a named button was on
    /// 66.1, when each took its name's width: at 64 the column took a
    /// quarter more of the map (TestFlight 67.1).
    public static let buttonWidth: Double = 48
    /// The glass round each group of buttons, on every side.
    public static let tilePadding: Double = 4
    /// The space between the buttons of a group.
    public static let buttonSpacing: Double = 4
    /// The column's width: a button and the glass either side of it.
    public static var width: Double { buttonWidth + 2 * tilePadding }
    /// Every button's width in the building tools beside the map (an iPad,
    /// or a phone held upright): 66.1's rail, 72 points, less its glass.
    /// The map has room to spare there, and the longest English names fit.
    public static let railButtonWidth: Double = 64
    /// The width of the building tools beside the map.
    public static var railWidth: Double { railButtonWidth + 2 * tilePadding }

    /// The most height the column may take, anchored `bottom` points above
    /// the screen's foot: up to `gap` below `top`, the lower edge of what
    /// floats over the top of the screen (the board, and the layer strip
    /// under it when it shows), on a screen `screenHeight` high. Never
    /// less than `least`, where the column scrolls.
    public static func maxHeight(screenHeight: Double, top: Double, gap: Double, bottom: Double, least: Double = 60) -> Double {
        max(least, screenHeight - top - gap - bottom)
    }
}
