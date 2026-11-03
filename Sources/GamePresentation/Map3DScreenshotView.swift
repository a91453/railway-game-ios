import Foundation
import GameCore

/// Decision 555: the 3D map's camera a screenshot asks for (the Debug
/// app's `-screenshot-3d-view`, "distance,heading,tilt": metres, degrees
/// clockwise from north, degrees from straight down, 0 for the distance's
/// own), looking at the place a ``ScreenshotScene`` is set round.
public struct Map3DScreenshotView: Equatable, Sendable {
    public var distance: Float
    public var heading: Float
    public var tilt: Float

    public init?(_ text: String) {
        let parts = text.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3, parts[0] > 0, parts.allSatisfy(\.isFinite) else { return nil }
        distance = parts[0]
        heading = parts[1] * .pi / 180
        tilt = parts[2] * .pi / 180
    }

    /// The camera over `place` (degrees) in `scene` of `world`, for a view
    /// `viewport` points, leaned two fingers' way as far as ``tilt`` asks
    /// (``Map3DCamera/leaned(dy:)``).
    public func camera(at place: (latitude: Double, longitude: Double), in scene: Map3DScene, of world: GameWorld,
                       viewport: (width: Float, height: Float)) -> Map3DCamera? {
        guard let frame = RealWorldFrame(world: world) else { return nil }
        let at = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
        let camera = Map3DCamera(target: scene.point(worldX: at.x, worldY: at.y, height: 0), distance: distance, heading: heading, viewport: viewport)
        guard tilt > camera.tilt else { return camera }
        return camera.leaned(dy: -(tilt - camera.tilt) / Map3DCamera.leanPerPoint)
    }
}
