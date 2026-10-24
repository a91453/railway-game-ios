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

extension BuildConfirmLayout {
    /// The pill at `x`, `y`, `width` by `height`, moved off what it covers
    /// of `obstacles`: up over the one it covers where there is room (no
    /// higher than `highest`), else beside it, within `minX`…`maxX`; left
    /// where it is when neither has room. Decision 384: the new line's
    /// station pair drawer is one of them, which covered its ✓
    /// (TestFlight 85.1).
    public static func keepingOff(
        _ obstacles: [ScreenFrame], x: Double, y: Double, width: Double, height: Double,
        minX: Double, maxX: Double, highest: Double
    ) -> (x: Double, y: Double) {
        var x = x, y = y
        for obstacle in obstacles where obstacle.width > 0 && obstacle.height > 0 {
            guard overlaps(x: x, y: y, width: width, height: height, obstacle, by: margin / 2) else { continue }
            let above = obstacle.y - margin - height
            if above >= highest {
                y = above
                continue
            }
            let after = obstacle.x + obstacle.width + margin, before = obstacle.x - margin - width
            if after <= maxX, after >= minX {
                x = after
            } else if before >= minX, before <= maxX {
                x = before
            }
        }
        return (x, y)
    }

    /// Whether the pill at `x`, `y` comes within `gap` of `frame`.
    public static func overlaps(x: Double, y: Double, width: Double, height: Double, _ frame: ScreenFrame, by gap: Double = 0) -> Bool {
        x < frame.x + frame.width + gap && x + width > frame.x - gap
            && y < frame.y + frame.height + gap && y + height > frame.y - gap
    }
}
