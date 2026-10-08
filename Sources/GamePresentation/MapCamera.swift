import GameCore

// The map's camera: where the world is drawn on the map view, which part of
// it is in view, and zooming and panning. Set ahead of Stage E1 (the large
// map, drawing only what is in view) so the map can be drawn against it
// while E1 and E2 are built; E2's real-world mode puts MapKit's camera
// behind the same ``MapProjection``. The references keep a web map's camera
// (MapLibre and AMap in `Ci/` and `Railway/`): a centre and a zoom, the
// bounds in view for drawing only what is on screen, and levels of detail
// by zoom.
//
// Presentation only: GameCore never sees the camera, and a camera's
// floating-point values reach it only as the whole world units of
// ``MapProjection/planPoint(at:)`` and ``MapProjection/worldDistance(_:)``.

/// A point on the map view, in points from its top-left corner: x to the
/// right, y down.
public struct ScreenPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The size of the map view, in points.
public struct ScreenSize: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// A rectangle of the world seen from above, in world units (x east, y
/// south, as ``WorldCoordinate``). Fractional, for drawing only.
public struct WorldRegion: Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// The smallest region holding every point of `points` seen from above;
    /// `nil` for no points. For drawing only what is in view: an edge's
    /// sampled centre line, a train's body.
    public init?(enclosing points: some Sequence<WorldCoordinate>) {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else { return nil }
        var region = WorldRegion(minX: Double(first.x), minY: Double(first.y), maxX: Double(first.x), maxY: Double(first.y))
        while let point = iterator.next() {
            region.minX = min(region.minX, Double(point.x))
            region.minY = min(region.minY, Double(point.y))
            region.maxX = max(region.maxX, Double(point.x))
            region.maxY = max(region.maxY, Double(point.y))
        }
        self = region
    }

    /// The whole world: its ``WorldBounds`` from the north-west corner.
    public init(bounds: WorldBounds) {
        self.init(minX: 0, minY: 0, maxX: Double(bounds.width), maxY: Double(bounds.height))
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }

    /// Whether `point`, seen from above, lies inside or on the edge.
    public func contains(_ point: WorldCoordinate) -> Bool {
        minX <= Double(point.x) && Double(point.x) <= maxX && minY <= Double(point.y) && Double(point.y) <= maxY
    }

    /// Whether the two overlap or touch.
    public func intersects(_ other: WorldRegion) -> Bool {
        minX <= other.maxX && other.minX <= maxX && minY <= other.maxY && other.minY <= maxY
    }

    /// The region grown by `margin` on every side (the references draw a
    /// margin beyond the bounds in view, so what is half in view is drawn).
    public func expanded(by margin: Double) -> WorldRegion {
        WorldRegion(minX: minX - margin, minY: minY - margin, maxX: maxX + margin, maxY: maxY + margin)
    }

    /// The part of `world` something is built on, seen from above: its
    /// track nodes, the points along its edges (a curve may bow out past
    /// its ends: a ring's arcs between nodes on its diagonals), and its
    /// stations; `nil` for a world with
    /// none. Where a game's map opens (``PlanCamera``'s `showing`): on a
    /// 16 km map (Stage E1), the built network may be anywhere.
    public static func built(in world: GameWorld) -> WorldRegion? {
        var points = world.network.nodes.map(\.position)
        for edge in world.network.edges {
            points += world.trackGeometry(of: edge.id)?.points ?? []
        }
        points += world.stations.map { WorldCoordinate(x: $0.location.x, y: $0.location.y) }
        return WorldRegion(enclosing: points)
    }

    /// Where `world`'s map opens: what is built on it (``built(in:)``),
    /// or, on a map whose land is read in as it is needed with nothing
    /// built yet (decision 89: the whole of Taiwan), the whole map, so the
    /// player starts seeing the island rather than a few hundred metres of
    /// it; `nil`, the camera's own opening, otherwise.
    public static func opening(in world: GameWorld) -> WorldRegion? {
        built(in: world) ?? (world.landBlocks != nil ? WorldRegion(bounds: world.bounds) : nil)
    }
}

/// Where the world is drawn on the map view, and back: everything the map's
/// drawing and its taps need from a camera.
///
/// The map is drawn against this, not against ``PlanCamera``, so the blank
/// map (our own camera, Stage E1) and the real-world map (MapKit's camera,
/// Stage E2) share one renderer. MapKit's camera can turn and tilt, so
/// nothing may assume one scale over the whole view: convert each point.
public protocol MapProjection {
    /// Where the world point (`x`, `y`) is drawn, in world units seen from
    /// above. Fractional, so a point between whole units can be drawn.
    func screenPoint(worldX x: Double, worldY y: Double) -> ScreenPoint

    /// The world point under `point`, in world units seen from above,
    /// unrounded. Commands take ``planPoint(at:)``.
    func worldPosition(at point: ScreenPoint) -> (x: Double, y: Double)

    /// The part of the world in view, or a region holding it: draw what
    /// intersects it, skip the rest.
    var visibleRegion: WorldRegion { get }

    /// Points on the screen per world unit at the middle of the view: sizes
    /// the drawing, picks the level of detail and turns a fingertip's reach
    /// into world units.
    var pointsPerUnit: Double { get }
}

extension MapProjection {
    /// Where `point` is drawn, seen from above: the height is not shown (a
    /// top-down projection of the track network, Stage S3).
    public func screenPoint(of point: WorldCoordinate) -> ScreenPoint {
        screenPoint(worldX: Double(point.x), worldY: Double(point.y))
    }

    public func screenPoint(of point: PlanPoint) -> ScreenPoint {
        screenPoint(worldX: Double(point.x), worldY: Double(point.y))
    }

    /// The world point under `point`, rounded to whole units, for a
    /// `GameWorld` command; kept within ``WorldCoordinate/limit`` (GameCore
    /// refuses what lies off the map).
    public func planPoint(at point: ScreenPoint) -> PlanPoint {
        let position = worldPosition(at: point)
        return PlanPoint(x: Self.wholeUnits(position.x), y: Self.wholeUnits(position.y))
    }

    /// `points` of the screen in world units at the middle of the view,
    /// rounded: how far a tap reaches (see `NetworkBuilding.touchRadius`).
    public func worldDistance(_ points: Double) -> Int64 {
        precondition(pointsPerUnit > 0, "worldDistance(_:) requires a positive scale")
        return Self.wholeUnits(points / pointsPerUnit)
    }

    /// Points on the screen per ``MapScale/referenceLength`` (16 m) of the
    /// world: the size the map's drawing is sized by.
    public var referenceSize: Double {
        pointsPerUnit * Double(MapScale.referenceLength)
    }

    /// How much of the map to draw at this zoom (see
    /// ``MapScale/detail(forReferenceSize:)``).
    public var detail: MapDetail {
        MapScale.detail(forReferenceSize: referenceSize)
    }

    private static func wholeUnits(_ value: Double) -> Int64 {
        // Not a number would trap in the conversion; the screen never sends
        // one, but no point may crash the game.
        guard !value.isNaN else { return 0 }
        let limit = Double(WorldCoordinate.limit)
        return Int64(min(max(value.rounded(), -limit), limit))
    }
}

/// The camera of the map seen from above, straight down and north up: the
/// blank map's camera (Stage E1).
///
/// 16 m of the world (``MapScale/referenceLength``) is
/// ``MapScale/largestSize`` points at most, and at least the size at which
/// the whole map fits the view (but never smaller than necessary,
/// ``MapScale/minimumSize(fitting:)``): a new game's 16 km world fits a phone
/// at well under a point per 16 m. The zoom buttons multiply or divide the
/// size by ``MapScale/zoomFactor``. Panning stops at the map's edges, and
/// along a side where the whole map fits it is centred, as the scrolling
/// map was.
///
/// A value: the map view keeps it as view state and replaces it as the
/// player zooms and pans. Nothing about it is saved.
public struct PlanCamera: MapProjection, Hashable, Sendable {
    /// The world point at the middle of the view, in world units.
    public private(set) var centerX: Double
    public private(set) var centerY: Double
    public private(set) var pointsPerUnit: Double
    /// The size of the map view, at least one point each way.
    public private(set) var viewport: ScreenSize
    /// The map: the part of the world the camera shows.
    public let mapRegion: WorldRegion

    /// The camera on a new map view, at ``MapScale/automaticSize(fitting:)``
    /// (the whole map when it fits at a size comfortable to tap,
    /// ``MapScale/compactSize`` otherwise) in the middle of the map, or
    /// centred on `focus` and zoomed out until it fits with
    /// ``focusPadding`` to spare, when it does not at that size. The map is
    /// centred along a side where it fits.
    ///
    /// Stage E1: a game opens on what it has built (see
    /// ``WorldRegion/built(in:)``), as the references fit their map to the
    /// stations when a save or scene opens (`Ci/`
    /// `fitAnycityImportedSaveNetworkView`, `Railway/` `fitData`), never
    /// closer than a set zoom (`Ci/`'s `maxZoom: 12`, here the automatic
    /// size).
    public init(bounds: WorldBounds, viewport: ScreenSize, showing focus: WorldRegion? = nil) {
        mapRegion = WorldRegion(bounds: bounds)
        self.viewport = Self.usable(viewport)
        pointsPerUnit = 1
        centerX = 0
        centerY = 0
        var size = MapScale.automaticSize(fitting: fittingReferenceSize)
        if let focus {
            // Room inside the padding; a view too small for it uses all of
            // itself.
            let room = (
                width: self.viewport.width > 4 * Self.focusPadding ? self.viewport.width - 2 * Self.focusPadding : self.viewport.width,
                height: self.viewport.height > 4 * Self.focusPadding ? self.viewport.height - 2 * Self.focusPadding : self.viewport.height
            )
            let fitting = min(room.width / focus.width, room.height / focus.height) * Double(MapScale.referenceLength)
            size = MapScale.clamped(min(size, fitting), fitting: fittingReferenceSize)
        }
        pointsPerUnit = size / Double(MapScale.referenceLength)
        let middle = focus ?? mapRegion
        centerX = (middle.minX + middle.maxX) / 2
        centerY = (middle.minY + middle.maxY) / 2
        clampCenter()
    }

    /// Room left around what a camera opens on, in points on each side:
    /// `Railway/`'s `fitBounds` padding (`Ci/` leaves 72 on a desktop
    /// screen, too much on a phone).
    public static let focusPadding = 30.0

    // MARK: - Projection

    public func screenPoint(worldX x: Double, worldY y: Double) -> ScreenPoint {
        ScreenPoint(
            x: (x - centerX) * pointsPerUnit + viewport.width / 2,
            y: (y - centerY) * pointsPerUnit + viewport.height / 2
        )
    }

    public func worldPosition(at point: ScreenPoint) -> (x: Double, y: Double) {
        ((point.x - viewport.width / 2) / pointsPerUnit + centerX, (point.y - viewport.height / 2) / pointsPerUnit + centerY)
    }

    public var visibleRegion: WorldRegion {
        WorldRegion(
            minX: centerX - visibleWidth / 2,
            minY: centerY - visibleHeight / 2,
            maxX: centerX + visibleWidth / 2,
            maxY: centerY + visibleHeight / 2
        )
    }

    // MARK: - Zoom

    /// Whether the zoom-in button can zoom further.
    public var canZoomIn: Bool {
        referenceSize < MapScale.largestSize
    }

    /// Whether the zoom-out button can zoom further.
    public var canZoomOut: Bool {
        referenceSize > MapScale.minimumSize(fitting: fittingReferenceSize)
    }

    /// ``MapScale/zoomFactor`` times closer, about the middle of the view
    /// (the zoom-in button).
    public func zoomedIn() -> PlanCamera {
        zoomed(toReferenceSize: MapScale.zoomedIn(from: referenceSize, fitting: fittingReferenceSize), around: middle)
    }

    /// ``MapScale/zoomFactor`` times farther, about the middle of the view
    /// (the zoom-out button).
    public func zoomedOut() -> PlanCamera {
        zoomed(toReferenceSize: MapScale.zoomedOut(from: referenceSize, fitting: fittingReferenceSize), around: middle)
    }

    /// `factor` times as close, within the zoom range, keeping the world
    /// point under `anchor` where it is when the map's edges allow (a
    /// pinch: the camera when it began, its magnification and where the
    /// fingers began).
    public func zoomed(by factor: Double, around anchor: ScreenPoint) -> PlanCamera {
        guard factor.isFinite, factor > 0 else { return self }
        return zoomed(toReferenceSize: MapScale.clamped(referenceSize * factor, fitting: fittingReferenceSize), around: anchor)
    }

    // MARK: - Pan

    /// The map moved `dx` right and `dy` down on the screen, stopping at its
    /// edges (a drag: the camera when it began and the drag's translation,
    /// so the world point under the finger stays under it).
    public func panned(byX dx: Double, y dy: Double) -> PlanCamera {
        guard dx.isFinite, dy.isFinite else { return self }
        var camera = self
        camera.centerX -= dx / pointsPerUnit
        camera.centerY -= dy / pointsPerUnit
        camera.clampCenter()
        return camera
    }

    /// `point` in the middle of the view, as near as the map's edges allow.
    public func centered(on point: WorldCoordinate) -> PlanCamera {
        centered(atX: Double(point.x), y: Double(point.y))
    }

    /// The world point (`x`, `y`) in the middle of the view, as near as the
    /// map's edges allow: for a centre between whole units, such as the
    /// eased centre of a followed train (``FollowCamera``).
    public func centered(atX x: Double, y: Double) -> PlanCamera {
        guard x.isFinite, y.isFinite else { return self }
        var camera = self
        camera.centerX = x
        camera.centerY = y
        camera.clampCenter()
        return camera
    }

    // MARK: - The view

    /// The camera for a map view now `viewport` in size (a rotation, a
    /// split screen): the same middle and zoom, as far as the new zoom
    /// range and the map's edges allow.
    public func resized(to viewport: ScreenSize) -> PlanCamera {
        var camera = self
        camera.viewport = Self.usable(viewport)
        camera.pointsPerUnit = MapScale.clamped(referenceSize, fitting: camera.fittingReferenceSize) / Double(MapScale.referenceLength)
        camera.clampCenter()
        return camera
    }

    // MARK: - Private

    /// The size at which the whole map fits the view
    /// (``MapScale/fittingSize(width:height:worldWidth:worldHeight:)``).
    private var fittingReferenceSize: Double {
        MapScale.fittingSize(width: viewport.width, height: viewport.height, worldWidth: mapRegion.width, worldHeight: mapRegion.height)
    }

    private var visibleWidth: Double { viewport.width / pointsPerUnit }
    private var visibleHeight: Double { viewport.height / pointsPerUnit }
    private var middle: ScreenPoint { ScreenPoint(x: viewport.width / 2, y: viewport.height / 2) }

    private func zoomed(toReferenceSize size: Double, around anchor: ScreenPoint) -> PlanCamera {
        let fixed = worldPosition(at: anchor)
        var camera = self
        camera.pointsPerUnit = size / Double(MapScale.referenceLength)
        camera.centerX = fixed.x - (anchor.x - viewport.width / 2) / camera.pointsPerUnit
        camera.centerY = fixed.y - (anchor.y - viewport.height / 2) / camera.pointsPerUnit
        camera.clampCenter()
        return camera
    }

    /// Keeps the view on the map: along a side where the whole map fits,
    /// the map is centred; otherwise the view stops at the map's edges.
    private mutating func clampCenter() {
        centerX = Self.clamped(centerX, from: mapRegion.minX, to: mapRegion.maxX, visible: visibleWidth)
        centerY = Self.clamped(centerY, from: mapRegion.minY, to: mapRegion.maxY, visible: visibleHeight)
    }

    private static func clamped(_ center: Double, from low: Double, to high: Double, visible: Double) -> Double {
        guard high - low > visible else { return (low + high) / 2 }
        return min(max(center, low + visible / 2), high - visible / 2)
    }

    /// A view of no size (before its first layout) is taken as one point
    /// each way, so the scale stays positive.
    private static func usable(_ size: ScreenSize) -> ScreenSize {
        ScreenSize(
            width: size.width.isFinite ? max(size.width, 1) : 1,
            height: size.height.isFinite ? max(size.height, 1) : 1
        )
    }
}
