// Decision 384 (TestFlight 85.1, the owner's screenshot of a phone on its
// side): while a new line's stations were picked, the drawer comparing the
// last two (decision 224, 3B) stood across the middle of the map, over the
// map's ✕ and ✓ beside the last station and over the small map and the
// zoom buttons: the line could not be opened. It made room only for a
// panel beside the map.

/// Where the new line's station pair drawer goes, in the screen's points.
public enum StationPairDrawerLayout {
    /// The widest it is (decision 224, 3B).
    public static let maximumWidth = 460.0

    /// How much of the screen's trailing side it leaves: the widest of a
    /// panel beside the map, the details card beside the tools (each with
    /// its margin) and the map's bottom-trailing column (the small map, a
    /// layer's key, the coverage, 3D and zoom buttons), 0 for what is not
    /// there.
    public static func trailingInset(panel: Double, card: Double, corner: Double) -> Double {
        max(panel, card, corner, 0)
    }

    /// Whether it rides in the map's ✕ ↶ ✓ pill, beside its words, rather
    /// than across the bottom of the map: on a short screen (a phone on its
    /// side) there was no room for the pill above or beside it, its bars
    /// open, so one covered the other. In the pill they move together and
    /// cannot; it opens folded to its top line (the two stations, the
    /// distance and the time), and a tap opens the bars.
    public static func ridesInPill(compactHeight: Bool) -> Bool {
        compactHeight
    }

    /// How tall it is folded: its top line (the 32-point fold button) and
    /// its padding above and below.
    public static let foldedHeight = 52.0
    /// How wide it is in the pill.
    public static let widthInPill = 300.0
    /// The gap between it and the pill's words beside it.
    public static let pillSpacing = 6.0
    /// The pill's padding around them.
    public static let pillPadding = 6.0

    /// The tallest it may be in the pill: `available` (the map's clear
    /// height the pill may stand in) less the pill's padding; its bars
    /// scroll in what is left under its top line. `nil` when the pill,
    /// at most `pillWidth` wide, has no room for it beside the narrowest
    /// words (``BuildConfirmLayout/minimumWidth``) or not even its top
    /// line fits: the pill shows without it, its words still giving the
    /// line's length and time.
    public static func maximumHeightInPill(available: Double, pillWidth: Double) -> Double? {
        let room = available - 2 * pillPadding
        let fits = 2 * pillPadding + widthInPill + pillSpacing + BuildConfirmLayout.minimumWidth <= pillWidth
        return fits && room >= foldedHeight ? room : nil
    }

    /// How tall its bars may be under its top line when it is at most
    /// `maximumHeight` tall (6 points between them and the top line); 0
    /// shows the top line only.
    public static func barsRoom(maximumHeight: Double) -> Double {
        max(0, maximumHeight - foldedHeight - 6)
    }

    /// Its frame, `size` as it measures itself (no wider than
    /// ``maximumWidth``), in the middle of the band between `leading` and
    /// `trailing` (with `margin` inside each) on a screen `screenWidth`
    /// wide, its foot `bottom` points above the screen's.
    public static func frame(
        size: ScreenSize, screenWidth: Double, screenHeight: Double,
        leading: Double, trailing: Double, bottom: Double, margin: Double
    ) -> ScreenFrame {
        let band = max(0, screenWidth - leading - trailing - 2 * margin)
        let width = min(size.width, maximumWidth, band)
        let x = leading + margin + (band - width) / 2
        return ScreenFrame(x: x, y: screenHeight - bottom - size.height, width: width, height: size.height)
    }
}
