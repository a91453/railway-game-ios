// Decision 382 (TestFlight 85.1, the owner's screenshot of a phone on its
// side): everything that floats over the map keeps one inset inside the
// safe area, on every side. The status bar reached 10 points from the
// trailing edge, the overview map and the zoom buttons 24 (two paddings of
// 12), so the bar stood 14 points past them; and the zoom buttons' foot
// stood 14 points above the tools column's and the expansion button's.

/// The margins of the controls floating over the map, in points.
public enum HUDMargins {
    /// How far inside the safe area (and above the credits' band on a
    /// real-world map) every floating control keeps, on every side: the
    /// status bar, the layer strip, the tools column or dock, the map's
    /// buttons, the overview map and a layer's legend, the station master,
    /// and the map's credit and its attribution button.
    public static let edge: Double = 10
    /// Between the groups stacked in the map's bottom-trailing corner: the
    /// overview map or a layer's legend over the buttons.
    public static let cornerStackGap: Double = 10
    /// Between the 3D button and the zoom buttons beside it (as before).
    public static let zoomGap: Double = 12

    /// The four lines the floating controls keep to on a screen `screen`
    /// big, with the safe area `safeArea` and, on a real-world map, the
    /// credits' band `creditsBand` points tall above the safe area's foot.
    public static func lines(screen: ScreenSize, safeArea: ScreenInsets, creditsBand: Double = 0) -> HUDLines {
        HUDLines(
            leading: safeArea.leading + edge,
            trailing: screen.width - safeArea.trailing - edge,
            top: safeArea.top + edge,
            bottom: screen.height - safeArea.bottom - creditsBand - edge
        )
    }
}

/// Where the floating controls' edges are on the screen (``HUDMargins``),
/// in its points from its top-leading corner.
public struct HUDLines: Hashable, Sendable {
    /// The leading line: the status bar's, the layer strip's and the tools
    /// column's leading edge.
    public var leading: Double
    /// The trailing line: the status bar's, the card's, the overview map's
    /// and the map's buttons' trailing edge.
    public var trailing: Double
    /// The top line: the status bar's top.
    public var top: Double
    /// The bottom row's line: the foot of the tools column (or dock), the
    /// expansion button, the station master and the map's buttons.
    public var bottom: Double

    public init(leading: Double, trailing: Double, top: Double, bottom: Double) {
        self.leading = leading
        self.trailing = trailing
        self.top = top
        self.bottom = bottom
    }

    /// The widest the status bar may be: from the leading line to the
    /// trailing one.
    public var statusBarMaxWidth: Double { max(0, trailing - leading) }

    /// The status bar, `size` big as it measures itself, at the top
    /// leading corner and no wider than the lines allow.
    public func statusBar(_ size: ScreenSize) -> ScreenFrame {
        ScreenFrame(x: leading, y: top, width: min(size.width, statusBarMaxWidth), height: size.height)
    }

    /// Something `size` big standing on the bottom row at its leading
    /// end, `after` points from the leading line (beside the tools column).
    public func bottomLeading(_ size: ScreenSize, after: Double = 0) -> ScreenFrame {
        ScreenFrame(x: leading + after, y: bottom - size.height, width: size.width, height: size.height)
    }

    /// Something `size` big standing on the bottom row at its trailing end.
    public func bottomTrailing(_ size: ScreenSize) -> ScreenFrame {
        ScreenFrame(x: trailing - size.width, y: bottom - size.height, width: size.width, height: size.height)
    }

    /// Something `size` big against the trailing line, above `below` with
    /// the corner's gap between them (the overview map over the buttons).
    public func trailing(_ size: ScreenSize, above below: ScreenFrame) -> ScreenFrame {
        ScreenFrame(
            x: trailing - size.width, y: below.y - HUDMargins.cornerStackGap - size.height,
            width: size.width, height: size.height
        )
    }
}
