import GameCore

/// How wide the panels beside the map are (decision 106, later): a panel
/// (the lines, the station, ...) and the details card. On a phone on its
/// side (a compact height) they are narrower, so the map keeps about two
/// thirds of the screen (TestFlight 54.1: on an iPhone 14 Pro the lines
/// panel covered 49 % of it).
public enum SidePanelWidth {
    /// A panel beside the map: 420 points, at most half the width; on a
    /// compact height 300 points, at most 36 %.
    public static func panel(screenWidth: Double, compactHeight: Bool) -> Double {
        compactHeight ? min(300, (screenWidth * 0.36).rounded()) : min(420, (screenWidth * 0.5).rounded())
    }

    /// The details card: 340 points, at most 40 % of the width; on a
    /// compact height 300 points, at most 35 %.
    public static func card(screenWidth: Double, compactHeight: Bool) -> Double {
        compactHeight ? min(300, (screenWidth * 0.35).rounded()) : min(340, (screenWidth * 0.4).rounded())
    }
}

/// What floats over each edge of the map view, in points: the part of the
/// view inside them is the map the player sees.
public struct ScreenInsets: Hashable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

extension PlanCamera {
    /// The middle of the part of the view `insets` leave clear; the view's
    /// middle when they leave none.
    public func clearMiddle(_ insets: ScreenInsets) -> ScreenPoint {
        let clear = clearArea(insets)
        return ScreenPoint(x: clear.leading + clear.width / 2, y: clear.top + clear.height / 2)
    }

    /// Whether `point` shows in the part of the view `insets` leave clear.
    public func showsClear(_ point: WorldCoordinate, of insets: ScreenInsets) -> Bool {
        let screen = screenPoint(of: point)
        let clear = clearArea(insets)
        return screen.x >= clear.leading && screen.x <= clear.leading + clear.width
            && screen.y >= clear.top && screen.y <= clear.top + clear.height
    }

    /// `point` in the middle of the part of the view `insets` leave clear,
    /// as near as the map's edges allow (decision 106, later: a station
    /// selected beside a panel moves into the map left beside it).
    public func centered(on point: WorldCoordinate, clearOf insets: ScreenInsets) -> PlanCamera {
        let middle = clearMiddle(insets)
        return centered(
            atX: Double(point.x) - (middle.x - viewport.width / 2) / pointsPerUnit,
            y: Double(point.y) - (middle.y - viewport.height / 2) / pointsPerUnit
        )
    }

    /// `region` in the middle of the part of the view `insets` leave clear,
    /// zoomed out as far as it takes to fit there with
    /// ``focusPadding`` to spare and the zoom range allows, never in (a
    /// line selected beside a panel).
    public func showing(_ region: WorldRegion, clearOf insets: ScreenInsets) -> PlanCamera {
        let clear = clearArea(insets)
        let width = max(clear.width - 2 * Self.focusPadding, 1)
        let height = max(clear.height - 2 * Self.focusPadding, 1)
        let fits = min(
            region.width > 0 ? width / region.width : .infinity,
            region.height > 0 ? height / region.height : .infinity
        )
        let zoomed = fits < pointsPerUnit ? self.zoomed(by: fits / pointsPerUnit, around: ScreenPoint(x: viewport.width / 2, y: viewport.height / 2)) : self
        let middle = WorldCoordinate(x: Int64(((region.minX + region.maxX) / 2).rounded()), y: Int64(((region.minY + region.maxY) / 2).rounded()))
        return zoomed.centered(on: middle, clearOf: insets)
    }

    /// The part of the view `insets` leave clear: its leading and top
    /// edges and its size; the whole view along a side where they would
    /// leave less than a point.
    private func clearArea(_ insets: ScreenInsets) -> (leading: Double, top: Double, width: Double, height: Double) {
        let width = viewport.width - insets.leading - insets.trailing
        let height = viewport.height - insets.top - insets.bottom
        return (
            leading: width >= 1 ? insets.leading : 0,
            top: height >= 1 ? insets.top : 0,
            width: width >= 1 ? width : viewport.width,
            height: height >= 1 ? height : viewport.height
        )
    }
}
