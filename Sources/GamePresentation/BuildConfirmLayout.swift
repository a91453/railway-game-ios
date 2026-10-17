// How wide the map's ✕ and ✓ pill may be, and where it goes across the
// map (decision 107). TestFlight 67.1, a phone held sideways with the track
// card open: a long refusal stood on one line, and the pill ran from the
// tools under the card, its words cut off there. The app measures the pill
// and the map's edges; this keeps the pill within the map's clear band, its
// words wrapping, so it is tested off Apple's platforms too.

/// How wide the map's build pill may be, and where its leading edge goes,
/// in the screen's points.
public enum BuildConfirmLayout {
    /// The gap the pill keeps from what floats over the map's sides.
    public static let margin = 8.0
    /// The narrowest the pill's words are given, so a squeezed map does not
    /// stand them a word to a line.
    public static let minimumWidth = 160.0

    /// The widest the pill may be: the map's width less what floats over
    /// its leading and trailing edges, and a margin beside each.
    public static func maximumWidth(viewportWidth: Double, leading: Double, trailing: Double) -> Double {
        max(minimumWidth, viewportWidth - leading - trailing - 2 * margin)
    }

    /// The pill's leading edge, for a pill `width` wide: centred on
    /// `anchorX`, kept within the clear band; at the band's leading side
    /// when it does not fit.
    public static func originX(anchorX: Double, width: Double, viewportWidth: Double, leading: Double, trailing: Double) -> Double {
        let minX = leading + margin
        let maxX = viewportWidth - trailing - width - margin
        return min(max(anchorX - width / 2, minX), max(minX, maxX))
    }
}
