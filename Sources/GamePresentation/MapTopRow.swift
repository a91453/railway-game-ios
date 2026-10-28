// Decision 469 (UI review D, 2-3 and 2-20; players: "the phone is too
// crowded"): the row under the status pill (the night skip, the layer
// strip, a free game's next step and the follow bar) took its pieces at
// their full widths, about 300 points for the strip and 190 for the night
// skip, and on a phone held upright with the details card open, or at night,
// ran past the screen or under the card. Now each piece gives way in turn,
// the least pressing first, until the row fits the room it has.

/// How the row under the status pill is laid out in `width` points.
public enum MapTopRow {
    /// The layer strip: every quick layer and More, or one button that
    /// opens the full layer list.
    public enum Layers: Hashable, Sendable {
        case strip
        case button
    }

    /// The night skip (decision 305): its name and the time, or its icon
    /// alone (the time is in the status pill above it).
    public enum NightSkipForm: Hashable, Sendable {
        case full
        case icon
    }

    public struct Arrangement: Hashable, Sendable {
        public let layers: Layers
        /// Whether a free game's next step shows; where it does, the chip
        /// still chooses between its line and its flag alone.
        public let showsNextStep: Bool
        public let nightSkip: NightSkipForm
    }

    /// Between the pieces: the screen's edge gap (``HUDMargins/edge``).
    public static let gap: Double = HUDMargins.edge
    /// A quick layer's button: 46 wide, an icon over its name.
    public static let cellWidth: Double = 46
    /// The whole strip (``MapQuickLayer``'s five layers and More), 299
    /// points: the buttons and the line before More, 2 points apart, the
    /// line 1 point with 2 either side, and the glass's 3 each side.
    public static var stripWidth: Double {
        let buttons = Double(MapQuickLayer.allCases.count + 1)
        let gaps = buttons
        return buttons * cellWidth + gaps * 2 + (1 + 2 * 2) + 2 * 3
    }

    /// The strip put away: More alone in its glass.
    public static var layersButtonWidth: Double { cellWidth + 2 * 3 }
    /// The night skip with its icon alone: a finger's 44 points.
    public static let nightSkipIconWidth: Double = 44
    /// The next step's flag and count, the narrowest the chip draws.
    public static let nextStepLeast: Double = 64
    /// The follow bar's narrowest (``FollowBar``'s last layout): the
    /// line's badge and the stop button.
    public static let followBarLeast: Double = 110

    /// The row in `width` points. `nightSkipWidth` is the night skip's full
    /// width, `0` where it does not show; the follow bar, when `follows`,
    /// takes what is left and lays itself out to it.
    ///
    /// What gives way, in turn: the strip folds to one button (the list
    /// it opens has every layer), then the next step goes (the goals list
    /// it), then the night skip keeps only its icon. The follow bar and
    /// the night skip stay: one is what the camera is doing, the other
    /// ends with the night.
    public static func arrange(
        width: Double, showsLayers: Bool, nightSkipWidth: Double, nextStep: Bool, follows: Bool
    ) -> Arrangement {
        let tries: [Arrangement] = [
            Arrangement(layers: .strip, showsNextStep: nextStep, nightSkip: .full),
            Arrangement(layers: .button, showsNextStep: nextStep, nightSkip: .full),
            Arrangement(layers: .button, showsNextStep: false, nightSkip: .full),
            Arrangement(layers: .button, showsNextStep: false, nightSkip: .icon),
        ]
        let fitting = tries.first {
            self.width(of: $0, showsLayers: showsLayers, nightSkipWidth: nightSkipWidth, follows: follows) <= width
        }
        return fitting ?? tries[tries.count - 1]
    }

    /// The least width `arrangement` takes.
    static func width(of arrangement: Arrangement, showsLayers: Bool, nightSkipWidth: Double, follows: Bool) -> Double {
        var pieces: [Double] = []
        if showsLayers {
            if nightSkipWidth > 0 {
                pieces.append(arrangement.nightSkip == .full ? nightSkipWidth : nightSkipIconWidth)
            }
            pieces.append(arrangement.layers == .strip ? stripWidth : layersButtonWidth)
            if arrangement.showsNextStep { pieces.append(nextStepLeast) }
        }
        if follows { pieces.append(followBarLeast) }
        guard !pieces.isEmpty else { return 0 }
        return pieces.reduce(0, +) + Double(pieces.count - 1) * gap
    }
}
