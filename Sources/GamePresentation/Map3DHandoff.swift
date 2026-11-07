import Foundation
import GameCore

/// ARCHITECTURE decision 269: the main map tilts as it comes closer.
/// Decision 313 (the owner, 2026-10-21: "2d常常跟3d搶畫面"): the 2D map
/// does the building, planning and running, the 3D map the watching,
/// exploring and riding along; the player goes back and forth quickly, but
/// neither takes the screen while the player is doing something. So a
/// pinch never switches while the fingers move: the 2D map pinches all
/// the way to its closest zoom (``MapScale/largestSize``), and only a pinch
/// that goes on past it (``opensOnRelease(referenceSize:asked:)``), let go
/// there, hands it over to the 3D map at the same middle and scale, which
/// starts straight down from that distance (``Map3DCamera/tiltsFrom``) so
/// nothing jumps. Pinched back out and let go far enough
/// (``handsBack(handedOverAt:from:to:)``), the 3D map hands it back. Not
/// while a building tool is out (the 3D map only shows), nor while the
/// tutorial runs (its steps would be left under the 3D map), nor with the
/// setting ``pinchOpensKey`` off.
public enum Map3DHandoff {
    /// The 2D map's view handed over or back: its middle (world units)
    /// and zoom (points per 16 m).
    public struct Plan: Hashable, Sendable {
        public let x: Double
        public let y: Double
        public let referenceSize: Double

        public init(x: Double, y: Double, referenceSize: Double) {
            self.x = x
            self.y = y
            self.referenceSize = referenceSize
        }
    }

    /// Metres of the world in ``MapScale/referenceLength`` (16 m).
    static let referenceMetres = Double(MapScale.referenceLength) / Double(WorldCoordinate.unitsPerMetre)

    /// How far a straight-down 3D camera stands to show as much ground
    /// from top to bottom as the 2D map at `referenceSize` points per
    /// 16 m in a view `viewportHeight` points tall.
    public static func distance(referenceSize: Double, viewportHeight: Double) -> Float {
        let shown = max(viewportHeight, 1) / max(referenceSize, 1e-6) * referenceMetres
        return Float(shown / (2 * tan(Double(Map3DCamera.fieldOfView) / 2)))
    }

    /// The 2D map's points per 16 m that show as much ground as a
    /// straight-down 3D camera `distance` metres up.
    public static func referenceSize(distance: Float, viewportHeight: Double) -> Double {
        let shown = 2 * Double(max(distance, 1)) * tan(Double(Map3DCamera.fieldOfView) / 2)
        return max(viewportHeight, 1) / shown * referenceMetres
    }

    /// How far past the 2D map's closest zoom a pinch must ask to go,
    /// as a share of it, for its release to open the 3D map: the size the
    /// fingers asked for (the zoom when it began times the pinch's scale,
    /// which the closest zoom stops) over ``MapScale/largestSize``. A third
    /// more is a deliberate pinch on, not a pinch that just reached the end.
    public static let pastClosest = 1.3

    /// Whether a pinch let go with the 2D map at `referenceSize` points per
    /// 16 m, its fingers having asked for `asked`, opens the 3D map: the 2D
    /// map is at its closest and the pinch went on a third past it.
    /// Decided only as the fingers lift (decision 313); a pinch that comes
    /// back out before it lifts stays 2D.
    public static func opensOnRelease(referenceSize: Double, asked: Double) -> Bool {
        referenceSize >= MapScale.largestSize * 0.999 && asked >= MapScale.largestSize * pastClosest
    }

    /// How many times farther out than it opened a 3D map a pinch handed
    /// over must be pinched, and let go, to hand the 2D map back.
    public static let closesPast: Float = 1.5

    /// Whether a pinch that moved the 3D camera from `before` metres (as it
    /// began) to `after` (as it was let go) hands the 2D map back. Only on
    /// a 3D map a pinch handed over (`start`, the distance it opened at;
    /// `nil` when the 3D button opened it, kilometres out), only pinched
    /// out, and only past ``closesPast`` times where it opened. Decided as
    /// the fingers lift (decision 313); 71.1 handed every pinch back, even
    /// closer, on a 3D map the button had opened (decision 269's fix).
    public static func handsBack(handedOverAt start: Float?, from before: Float, to after: Float) -> Bool {
        guard let start else { return false }
        return after > before && after > start * closesPast
    }

    /// How long, in seconds, a pinch rests near the 2D map's closest zoom
    /// (``buildsAhead(referenceSize:)``) before the 3D scene starts
    /// building. Decision 269, later: it started as soon as a pinch
    /// passed half the line, so a player who only zoomed the 2D map in
    /// built a 3D city (seconds of work, tens of MB) they never opened.
    public static let buildsAfterResting: Double = 0.4

    /// Whether the 2D map at `referenceSize` points per 16 m is near enough
    /// its closest zoom to build the 3D scene ahead, once the pinch rests
    /// there: from three quarters of ``MapScale/largestSize`` in.
    public static func buildsAhead(referenceSize: Double) -> Bool {
        referenceSize >= MapScale.largestSize * 0.75
    }

    /// Where the setting "Pinch closer for 3D" is kept (decision 313; on
    /// unless the player turns it off, Google Earth's "tilt when zooming").
    /// Off, only the 3D button opens the 3D map.
    public static let pinchOpensKey = "map3D.pinchOpens"

    /// Whether the 2D map hands over when pinched close: the setting on,
    /// and not with a building tool out, nor while the tutorial runs.
    public static func hands(building: Bool, tutorialRuns: Bool, pinchOpens: Bool = true) -> Bool {
        pinchOpens && !building && !tutorialRuns
    }

    /// The 3D camera the 2D map's view `plan` hands over to, in `scene`,
    /// for a view `viewport` points.
    /// It looks straight down from there and leans as it comes closer
    /// (decision 313: flat from where it opened, not from
    /// ``Map3DCamera/flatFrom``, as the 2D map's closest zoom is nearer).
    public static func camera(from plan: Plan, in scene: Map3DScene, viewport: (width: Float, height: Float)) -> Map3DCamera {
        var camera = Map3DCamera(target: scene.point(worldX: plan.x, worldY: plan.y, height: 0),
                                 distance: distance(referenceSize: plan.referenceSize, viewportHeight: Double(viewport.height)), viewport: viewport)
        camera.tiltsFrom = min(camera.distance, Map3DCamera.flatFrom)
        return camera
    }

    // MARK: Decision 635 (D5): where the 3D button opens

    /// The most ground, in metres across, the 2D map may show for the 3D
    /// button to open over its middle: as much as a 3D scene holds
    /// (``Map3DScene/reach`` each way). Further out (the whole island) the
    /// middle is mostly mountain with no track near, and the 3D map
    /// cannot be pulled out to find the line (the Mac playtest of
    /// 2026-11-08, D5).
    public static let opensOverTheMiddleUpTo: Double = 2 * Map3DScene.reach

    /// The ground, in metres from top to bottom, a 3D map opened over a
    /// station, a train or the nearest track (``opening(from:in:station:train:)``)
    /// shows: a town and its station.
    public static let groundShownOverTarget: Double = 3_000

    /// What the 3D button opens over, from the 2D map's `camera`: its
    /// middle and zoom while it shows no more than
    /// ``opensOverTheMiddleUpTo``; further out, the selected station
    /// (`station`), else the selected or followed train (`train`), else the
    /// track nearest the middle, shown ``groundShownOverTarget`` tall; with
    /// none of those (nothing built), still the middle.
    public static func opening(from camera: PlanCamera, in world: GameWorld, station: StationID? = nil, train: TrainID? = nil) -> Plan {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let shown = camera.visibleRegion
        let middle = Plan(x: camera.centerX, y: camera.centerY, referenceSize: camera.referenceSize)
        guard max(shown.width, shown.height) / metre > opensOverTheMiddleUpTo else { return middle }
        let target = station.flatMap { world.station(id: $0) }.map { (x: Double($0.location.x), y: Double($0.location.y)) }
            ?? train.flatMap { world.train(id: $0)?.position }.flatMap { world.location(of: $0) }
                .map { (x: Double($0.position.x), y: Double($0.position.y)) }
            ?? nearestTrack(to: (x: middle.x, y: middle.y), in: world)
        guard let target else { return middle }
        let size = max(camera.viewport.height, 1) / groundShownOverTarget * referenceMetres
        return Plan(x: target.x, y: target.y, referenceSize: size)
    }

    /// The point of `world`'s track (its nodes and the points along its
    /// edges) or of a station nearest `point`, seen from above; `nil` with
    /// none built.
    static func nearestTrack(to point: (x: Double, y: Double), in world: GameWorld) -> (x: Double, y: Double)? {
        var best: (x: Double, y: Double)?
        var bestDistance = Double.infinity
        func consider(_ x: Int64, _ y: Int64) {
            let dx = Double(x) - point.x, dy = Double(y) - point.y
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = (Double(x), Double(y))
            }
        }
        for node in world.network.nodes { consider(node.position.x, node.position.y) }
        for edge in world.network.edges {
            for p in world.trackGeometry(of: edge.id)?.points ?? [] { consider(p.x, p.y) }
        }
        for station in world.stations { consider(station.location.x, station.location.y) }
        return best
    }

    /// How far out the 3D camera opens over the plan the 3D button handed
    /// over (`plan`), in a scene `sceneSpan` metres across, for a view
    /// `viewportHeight` points tall: as close as the 2D map was
    /// (``distance(referenceSize:viewportHeight:)``), and never further than
    /// the whole scene in view, as it opened before decision 635 (D5: "2D
    /// 拉得很近時按 3D，3D 也是開在遠景"). From the settings, with no plan,
    /// the whole scene.
    public static func openingDistance(of plan: Plan?, sceneSpan: Float, viewportHeight: Double) -> Float {
        let whole = sceneSpan * 0.9
        guard let plan else { return whole }
        return min(whole, distance(referenceSize: plan.referenceSize, viewportHeight: viewportHeight))
    }

    /// Where the 2D map comes back: the world point the 3D camera looked
    /// at, and the 2D zoom showing as much ground (the 2D map keeps it
    /// within its own zoom range). The 3D map's "2D" button too (decision
    /// 313), wherever it was opened from.
    public static func plan(from camera: Map3DCamera, in scene: Map3DScene) -> Plan {
        let middle = scene.worldPosition(of: camera.target)
        return Plan(x: middle.x, y: middle.y, referenceSize: referenceSize(distance: camera.distance, viewportHeight: Double(camera.viewport.height)))
    }
}
