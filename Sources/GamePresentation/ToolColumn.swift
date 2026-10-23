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
    /// Every button's width in the building tools beside the map, on an
    /// iPad (a phone is only held sideways, where the tools are in the
    /// column): 66.1's rail, 72 points, less its glass.
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

// Decision 382, later (TestFlight 85.1, the planner): while building, the
// phone's column (the card's toggle, the track, train and building tools,
// Done, and Build lit) scrolled past its height on a phone on its side with
// a real-world map's credits under it, and Build at its foot was cut in
// half. Build now stands at the foot, outside what scrolls, and what
// scrolls is cut between two buttons.
extension ToolColumn {
    /// A button's height with its icon alone: 32 and the button style's 4
    /// above and below.
    public static let compactButtonHeight: Double = 40
    /// The space between the column's groups.
    public static let tileGap: Double = 6

    /// A group of `buttons` icon-alone buttons in its glass.
    public static func tileHeight(buttons: Int) -> Double {
        guard buttons > 0 else { return 0 }
        return Double(buttons) * compactButtonHeight + Double(buttons - 1) * buttonSpacing + 2 * tilePadding
    }

    /// The building column's height with its icons alone: the card's
    /// toggle when it shows (`toggle`), the `tools` building tools and
    /// Done in one group, and Build.
    public static func buildingHeight(tools: Int, toggle: Bool) -> Double {
        scrollingContent(tools: tools, toggle: toggle).height + tileGap + tileHeight(buttons: 1)
    }

    /// How tall the part over Done and Build is shown where the whole
    /// column does not fit in `maxHeight`: the tools, then the card's
    /// toggle, all of them when they fit, else cut midway between two
    /// buttons (or two groups), the rest scrolling, so no button shows in
    /// part. Done and Build stand under it, each a gap below, so Done is
    /// never scrolled out of reach, and the tools come before the toggle,
    /// so building needs no scrolling.
    public static func buildingScrollHeight(maxHeight: Double, tools: Int, toggle: Bool) -> Double {
        let content = scrollingContent(tools: tools, toggle: toggle, done: false)
        let room = maxHeight - 2 * (tileGap + tileHeight(buttons: 1))
        guard content.height > room else { return content.height }
        return content.cuts.last { $0 <= room } ?? content.cuts.first ?? 0
    }

    /// The part over Build, Done in the tools' group (`done`) or not, and
    /// the card's toggle under them: its height and where it may be cut,
    /// midway between each two buttons.
    private static func scrollingContent(tools: Int, toggle: Bool, done: Bool = true) -> (height: Double, cuts: [Double]) {
        var cuts: [Double] = []
        let buttons = tools + (done ? 1 : 0)
        for index in 0..<buttons {
            let foot = tilePadding + Double(index + 1) * compactButtonHeight + Double(index) * buttonSpacing
            if index < buttons - 1 { cuts.append(foot + buttonSpacing / 2) }
        }
        var y = tileHeight(buttons: buttons)
        if toggle {
            if buttons > 0 {
                cuts.append(y + tileGap / 2)
                y += tileGap
            }
            y += tileHeight(buttons: 1)
        }
        return (y, cuts)
    }
}
