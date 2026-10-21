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

    /// Where the 2D map comes back: the world point the 3D camera looked
    /// at, and the 2D zoom showing as much ground (the 2D map keeps it
    /// within its own zoom range). The 3D map's "2D" button too (decision
    /// 313), wherever it was opened from.
    public static func plan(from camera: Map3DCamera, in scene: Map3DScene) -> Plan {
        let middle = scene.worldPosition(of: camera.target)
        return Plan(x: middle.x, y: middle.y, referenceSize: referenceSize(distance: camera.distance, viewportHeight: Double(camera.viewport.height)))
    }
}
