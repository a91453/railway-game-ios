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

/// Decision 300: the map's bottom-trailing buttons (coverage, 3D, zoom) on
/// a phone on its side, beside a panel. Beside it they stood in the middle
/// of the map, over the stations being picked (the panel is a little under
/// a third of the screen, so decision 123 did not move them away). Under a
/// panel they are as tall as the map's credit button and stand at the
/// screen's edge: in the credits' band at the bottom where it has room
/// beside them (the panel keeps its height), otherwise just above it,
/// where the panel ends a little higher.
public enum MapCornerRow {
    /// How tall the buttons look under a panel: as tall as the credit
    /// button in the band (decision 120's `attributionHeight`, 30 points,
    /// less a point above and below).
    public static let height: Double = 28
    /// How tall a finger's target is where the screen has room under the
    /// buttons (the home indicator's safe area): Apple's 44 points.
    public static let reach: Double = 44
    /// Between the buttons and what stands beside them.
    public static let gap: Double = 8

    /// Where a row `width` points wide ends (its trailing x) in the credits'
    /// band of a view `viewportWidth` wide: left of the trailing-most credit
    /// (`credits`, the logo, the legal link and the credit button, in the
    /// view's points), or of the safe area's `trailingInset` without one,
    /// and clear of the other credits; `nil` where it does not fit.
    public static func bandEnd(rowWidth: Double, viewportWidth: Double, trailingInset: Double, credits: [ScreenFrame]) -> Double? {
        let trailing = credits.filter { $0.x + $0.width / 2 > viewportWidth / 2 }.max { $0.x < $1.x }
        let end = (trailing.map { $0.x } ?? viewportWidth - trailingInset) - gap
        let start = end - rowWidth
        let blocked = credits.contains { $0 != trailing && $0.x < end && $0.x + $0.width > start - gap }
        return blocked || start < 0 ? nil : end
    }

    /// How much higher than the screen's `margin` a panel beside the map
    /// ends: nothing where the row is in the credits' band (or not under
    /// the panel), otherwise the row's height and a gap.
    public static func panelRaise(underPanel: Bool, inBand: Bool) -> Double {
        underPanel && !inBand ? height + gap : 0
    }
}

/// Decision 350: where the map's bottom-trailing buttons (coverage, 3D,
/// zoom) stand, one rule however the device is held. On a phone on its
/// side (a compact height; an iPhone is never held upright) they stand in
/// a row of their own under whatever covers the map's trailing side, the
/// building card as a panel (``MapCornerRow``); otherwise in the map's
/// corner, beside it. They give way (decision 123) only where the map
/// left beside it is too narrow for them, an iPad's narrowest split view,
/// and never in the tutorial, which points at the zoom buttons.
public enum MapCornerButtons: Equatable, Sendable {
    /// In the map's bottom-trailing corner, beside a card or panel.
    case corner
    /// In a row at the screen's bottom edge, under the card or panel.
    case underPanel
    /// Not shown; a pinch still zooms.
    case givesWay

    /// How wide the map beside a card or panel must stay for the buttons
    /// in its corner: the coverage, 3D and zoom buttons (44, 44 and 88
    /// points), their paddings and a little of the map.
    public static let cornerWidth: Double = 240

    /// `coverWidth`: how much of the view's width the card or panel at the
    /// trailing side takes (with its margin), 0 without one;
    /// `besideCover`: whether the corner's buttons would stand beside it
    /// rather than below a short card.
    public static func place(compactHeight: Bool, coverWidth: Double, viewportWidth: Double,
                             besideCover: Bool, tutorialRuns: Bool) -> MapCornerButtons {
        guard coverWidth > 0 else { return .corner }
        if compactHeight { return .underPanel }
        if besideCover, !tutorialRuns, viewportWidth - coverWidth < cornerWidth { return .givesWay }
        return .corner
    }

    /// Whether the zoom buttons show.
    public var showsZoom: Bool { self != .givesWay }

    /// Whether the 3D button shows (``Map3DShortcut``), and the coverage
    /// button always with it.
    public func shows3DAndCoverage(tutorialRuns: Bool) -> Bool {
        Map3DShortcut.isShown(zoomButtonsShow: showsZoom, tutorialRuns: tutorialRuns)
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
    /// These insets with the controls in the map's corners kept clear too
    /// (the layer buttons, the legend, the zoom buttons): each frame pushes
    /// in the edge, beside it or below it, that leaves more of the view,
    /// and only as far as it reaches past what these insets cover already;
    /// an empty frame (not laid out yet) pushes nothing. For the camera's
    /// own framing (opening a game,
    /// jumping to a place), not for the player's pans and zooms.
    public func clearing(_ corners: [ScreenFrame], viewport: ScreenSize) -> ScreenInsets {
        var insets = self
        for frame in corners where frame.standsInCorner(of: viewport) {
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

extension ScreenFrame {
    /// Whether this frame is a control standing in a corner of `viewport`:
    /// a frame not wholly in the view, or one past half of it, is a layout
    /// still settling (a column moving in), not a corner; an empty one is
    /// not laid out yet.
    func standsInCorner(of viewport: ScreenSize) -> Bool {
        width > 0 && height > 0
            && x >= 0 && y >= 0 && x + width <= viewport.width && y + height <= viewport.height
            && width <= viewport.width / 2 && height <= viewport.height / 2
    }

    /// Whether `point` is inside this frame.
    func contains(_ point: ScreenPoint) -> Bool {
        point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }
}

/// What covers the map view (decision 106, #593): the panels, the screen's
/// controls and the column at the top along its edges (`edges`), and the
/// controls standing in its corners (`corners`: the layer buttons, the
/// legend, the zoom buttons).
public struct MapCover: Hashable, Sendable {
    public var edges: ScreenInsets
    public var corners: [ScreenFrame]

    public init(edges: ScreenInsets = ScreenInsets(), corners: [ScreenFrame] = []) {
        self.edges = edges
        self.corners = corners
    }

    /// The insets the camera's own framing keeps clear of: the edges, each
    /// corner's control pushing in one of them
    /// (``ScreenInsets/clearing(_:viewport:)``).
    public func framing(in viewport: ScreenSize) -> ScreenInsets {
        edges.clearing(corners, viewport: viewport)
    }

    /// ``framing(in:)`` with the band under `row`'s top kept clear too, all
    /// along the bottom: for the tiles for sale, shown when the map
    /// expansion's pill, in `row`, starts to grow along the bottom (the PR
    /// #627–#646 review: the tile below the land lay under its Done). A
    /// row not standing in a corner (not laid out yet) adds nothing.
    public func framing(above row: ScreenFrame, in viewport: ScreenSize) -> ScreenInsets {
        var insets = framing(in: viewport)
        if row.standsInCorner(of: viewport) { insets.bottom = max(insets.bottom, viewport.height - row.y) }
        return insets
    }
}

extension PlanCamera {
    /// The least room, across or down, that the camera's framing must
    /// leave for a selection to be moved into its middle along that axis:
    /// a fingertip's width. Less, and the selection keeps its place along
    /// that axis.
    public static let smallestClearSpan = 44.0

    /// Whether `point` is out of the view or under what covers it
    /// (`cover`): under a panel or control along an edge, along an axis
    /// where the framing leaves room (``smallestClearSpan``), or under a
    /// corner's control itself; not merely beside a corner's control, in
    /// the band of the view the framing gives up to it (the PR #526–#626 review: a selected
    /// station moved every time the details card opened or closed).
    public func hides(_ point: WorldCoordinate, under cover: MapCover) -> Bool {
        let screen = screenPoint(of: point)
        guard screen.x >= 0, screen.x <= viewport.width, screen.y >= 0, screen.y <= viewport.height else { return true }
        let room = clearRoom(cover.framing(in: viewport))
        if room.across, screen.x < cover.edges.leading || screen.x > viewport.width - cover.edges.trailing { return true }
        if room.down, screen.y < cover.edges.top || screen.y > viewport.height - cover.edges.bottom { return true }
        return cover.corners.contains { $0.standsInCorner(of: viewport) && $0.contains(screen) }
    }

    /// Decision 106, later, and the PR #526–#626 review: the camera that brings `point` (the
    /// selected station) out from under `cover` into the middle of the
    /// part of the view its framing leaves, as near as the map's edges
    /// allow; `nil` when it is not hidden (``hides(_:under:)``), or when
    /// moving would not change the camera. Along an axis where the framing
    /// leaves less than ``smallestClearSpan``, `point` keeps its place (in
    /// the view's middle when it is out of the view that way).
    public func keepingClear(_ point: WorldCoordinate, of cover: MapCover) -> PlanCamera? {
        guard hides(point, under: cover) else { return nil }
        let framing = cover.framing(in: viewport)
        let room = clearRoom(framing)
        let screen = screenPoint(of: point)
        func target(room: Bool, near: Double, far: Double, at current: Double, size: Double) -> Double? {
            if room { return near + (size - near - far) / 2 }
            return current >= 0 && current <= size ? nil : size / 2
        }
        let x = target(room: room.across, near: framing.leading, far: framing.trailing, at: screen.x, size: viewport.width)
            .map { Double(point.x) - ($0 - viewport.width / 2) / pointsPerUnit } ?? centerX
        let y = target(room: room.down, near: framing.top, far: framing.bottom, at: screen.y, size: viewport.height)
            .map { Double(point.y) - ($0 - viewport.height / 2) / pointsPerUnit } ?? centerY
        let moved = centered(atX: x, y: y)
        return moved == self ? nil : moved
    }

    /// Whether `framing` leaves at least ``smallestClearSpan`` of the view
    /// across and down.
    private func clearRoom(_ framing: ScreenInsets) -> (across: Bool, down: Bool) {
        (
            across: viewport.width - framing.leading - framing.trailing >= Self.smallestClearSpan,
            down: viewport.height - framing.top - framing.bottom >= Self.smallestClearSpan
        )
    }

    /// The camera a game opens on (#593): as it always opened
    /// (``init(bounds:viewport:showing:clearOf:)`` with no insets) when
    /// none of `stations` it shows is under the screen's controls
    /// (`insets`); otherwise farther out about the same middle, `focus`
    /// fitted inside the larger inset of each pair of opposite edges, but
    /// never below ``openingZoomOutLimit`` of the usual scale.
    public static func opening(
        bounds: WorldBounds, viewport: ScreenSize, showing focus: WorldRegion?,
        keeping stations: [WorldCoordinate], clearOf insets: ScreenInsets
    ) -> PlanCamera {
        let plain = PlanCamera(bounds: bounds, viewport: viewport, showing: focus)
        let shown = plain.visibleRegion
        let covered = stations.contains { shown.contains($0) && !plain.showsClear($0, of: insets) }
        guard covered else { return plain }
        // The same on opposite edges, so what it opens on stays in the
        // middle of the view (the demo's Central under a tap there).
        let across = max(insets.leading, insets.trailing), down = max(insets.top, insets.bottom)
        let balanced = ScreenInsets(top: down, leading: across, bottom: down, trailing: across)
        let fitted = PlanCamera(bounds: bounds, viewport: viewport, showing: focus, clearOf: balanced)
        // Never much farther out than the usual opening: insets that leave
        // a small box would shrink the network to a corner of the map
        // (main's full lane on #603: the demo opened zoomed far out).
        return fitted.pointsPerUnit >= plain.pointsPerUnit * Self.openingZoomOutLimit ? fitted : plain
    }

    /// How far out the opening may go to keep the stations clear of the
    /// controls: no smaller than this share of the usual opening's scale.
    public static let openingZoomOutLimit = 0.6

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
