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

    /// Whether it opens folded to its top line (the two stations, the
    /// distance and the time): on a short screen (a phone on its side) the
    /// bars under it left the map's ✓ no room above or beside it. A tap
    /// opens them.
    public static func startsFolded(compactHeight: Bool) -> Bool {
        compactHeight
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
