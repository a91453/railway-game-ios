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

/// A control floating in a corner of the map view, in the view's points:
/// its leading and top edges and its size.
public struct ScreenFrame: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

extension ScreenInsets {
    /// The same on opposite edges, the larger of the two: what the camera
    /// opens clear of keeps what it opens on in the middle of the view
    /// (#593: the demo's middle station stays in the middle of the map).
    public var balanced: ScreenInsets {
        let across = max(leading, trailing), down = max(top, bottom)
        return ScreenInsets(top: down, leading: across, bottom: down, trailing: across)
    }

    /// These insets with the controls in the map's corners kept clear too
    /// (the layer buttons, the legend, the zoom buttons): each frame pushes
    /// in the edge, beside it or below it, that leaves more of the view,
    /// and only as far as it reaches past what these insets cover already;
    /// an empty frame (not laid out yet) pushes nothing. For the camera's
    /// own framing (opening a game,
    /// jumping to a place), not for the player's pans and zooms.
    public func clearing(_ corners: [ScreenFrame], viewport: ScreenSize) -> ScreenInsets {
        var insets = self
        for frame in corners where frame.width > 0 && frame.height > 0 {
            let atTrailing = frame.x + frame.width / 2 > viewport.width / 2
            let atBottom = frame.y + frame.height / 2 > viewport.height / 2
            let side = atTrailing ? viewport.width - frame.x : frame.x + frame.width
            let edge = atBottom ? viewport.height - frame.y : frame.y + frame.height
            // The share of the view each way would leave out.
            if side / max(viewport.width, 1) <= edge / max(viewport.height, 1) {
                if atTrailing { insets.trailing = max(insets.trailing, side) } else { insets.leading = max(insets.leading, side) }
            } else {
                if atBottom { insets.bottom = max(insets.bottom, edge) } else { insets.top = max(insets.top, edge) }
            }
        }
        return insets
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
        centered(atX: Double(point.x), y: Double(point.y), clearOf: insets)
    }

    /// The world point (`x`, `y`) in the middle of the part of the view
    /// `insets` leave clear, as near as the map's edges allow: for a centre
    /// between whole units (a region's middle, a followed train's eased
    /// centre).
    public func centered(atX x: Double, y: Double, clearOf insets: ScreenInsets) -> PlanCamera {
        let middle = clearMiddle(insets)
        return centered(
            atX: x - (middle.x - viewport.width / 2) / pointsPerUnit,
            y: y - (middle.y - viewport.height / 2) / pointsPerUnit
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
    func clearArea(_ insets: ScreenInsets) -> (leading: Double, top: Double, width: Double, height: Double) {
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
