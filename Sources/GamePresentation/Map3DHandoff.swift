import Foundation
import GameCore

/// ARCHITECTURE decision 269: the main map tilts as it comes closer. A
/// pinch on the 2D map past ``opensAt(viewportHeight:)`` hands it over to
/// the 3D map at the same middle and the same scale: from that close
/// the 3D camera still looks straight down (``Map3DCamera/flatFrom``),
/// so nothing jumps, and it leans over as the pinch goes on. Pinched back
/// out past ``closesAt``, the 3D map hands the 2D one back the same way.
/// Not while a building tool is out (the 3D map only shows) nor while the
/// tutorial runs (its steps would be left under the 3D map).
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

    /// The 2D zoom (points per 16 m) from which a pinch closer opens the
    /// 3D map: the scale of a 3D camera at ``Map3DCamera/flatFrom``.
    public static func opensAt(viewportHeight: Double) -> Double {
        referenceSize(distance: Map3DCamera.flatFrom, viewportHeight: viewportHeight)
    }

    /// From this far out a 3D map the 2D one handed over hands it back:
    /// a fifth past where it opened, so a pinch that stops at the line
    /// does not flick between the two.
    public static let closesAt: Float = Map3DCamera.flatFrom * 1.2

    /// Whether a pinch that moved the 3D camera from `before` to `after`
    /// metres hands the 2D map back. Only on a 3D map a pinch handed over
    /// (`start`, the distance it opened at; `nil` when the 3D button opened
    /// it, which opens kilometres out), only as it is pinched out, and only
    /// past ``closesAt`` or a fifth past where it opened, whichever is
    /// farther (a 3D view taller than the 2D map's opens farther out at the
    /// same scale). Decision 269, later fix: 71.1 handed every pinch back,
    /// even closer, on a 3D map the button had opened.
    public static func handsBack(handedOverAt start: Float?, from before: Float, to after: Float) -> Bool {
        guard let start else { return false }
        return after > before && after > max(closesAt, start * 1.2)
    }

    /// How long, in seconds, a pinch rests near the line
    /// (``buildsAhead(referenceSize:viewportHeight:)``) before the 3D scene
    /// starts building. Decision 269, later: it started as soon as a pinch
    /// passed half the line, so a player who only zoomed the 2D map in
    /// built a 3D city (seconds of work, tens of MB) they never opened.
    public static let buildsAfterResting: Double = 0.4

    /// Whether the 2D map at `referenceSize` points per 16 m is near enough
    /// the line to build the 3D scene ahead, once the pinch rests there:
    /// from three quarters of ``opensAt(viewportHeight:)`` to it. Past the
    /// line the 3D map opens and builds its scene anyway.
    public static func buildsAhead(referenceSize: Double, viewportHeight: Double) -> Bool {
        let opens = opensAt(viewportHeight: viewportHeight)
        return referenceSize >= opens * 0.75 && referenceSize < opens
    }

    /// Whether the 2D map hands over when pinched close: not with a
    /// building tool out, nor while the tutorial runs.
    public static func hands(building: Bool, tutorialRuns: Bool) -> Bool {
        !building && !tutorialRuns
    }

    /// The 3D camera the 2D map's view `plan` hands over to, in `scene`,
    /// for a view `viewport` points.
    public static func camera(from plan: Plan, in scene: Map3DScene, viewport: (width: Float, height: Float)) -> Map3DCamera {
        Map3DCamera(target: scene.point(worldX: plan.x, worldY: plan.y, height: 0),
                    distance: distance(referenceSize: plan.referenceSize, viewportHeight: Double(viewport.height)), viewport: viewport)
    }

    /// Where the 2D map comes back: the world point the 3D camera looked
    /// at, and the 2D zoom showing as much ground.
    public static func plan(from camera: Map3DCamera, in scene: Map3DScene) -> Plan {
        let middle = scene.worldPosition(of: camera.target)
        return Plan(x: middle.x, y: middle.y, referenceSize: referenceSize(distance: camera.distance, viewportHeight: Double(camera.viewport.height)))
    }
}
