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

    /// Decision 575 續 (CABLEMAP): the camera over the ground under the
    /// first cable car's span `leg`, `permille` along it (the app's
    /// `-screenshot-3d-cableway` "leg,permille"), so a screenshot looks at
    /// its towers and cabins.
    public func camera(cableway text: String, in scene: Map3DScene, of world: GameWorld,
                       viewport: (width: Float, height: Float)) -> Map3DCamera? {
        let parts = text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let cableway = world.cableways.first, cableway.legMetres.indices.contains(parts[0]) else { return nil }
        let plan = CablewayCabins.planPoint(of: .span(leg: parts[0], permille: min(max(parts[1], 0), 1_000), outbound: true), in: cableway)
        let flat = scene.point(worldX: Double(plan.x), worldY: Double(plan.y), height: 0)
        let target = Map3DPoint(flat.x, scene.drawnGround.height(x: flat.x, z: flat.z, world: world), flat.z)
        var camera = Map3DCamera(target: target, distance: distance, heading: heading, viewport: viewport)
        // Past what two fingers lean, set outright: a view from just over
        // the ground, up at the cabins' floors.
        if tilt > Map3DCamera.mostLean {
            camera.pitch = tilt
            return camera
        }
        guard tilt > camera.tilt else { return camera }
        return camera.leaned(dy: -(tilt - camera.tilt) / Map3DCamera.leanPerPoint)
    }

    /// Decision 585 PR-3 (FERRY3): the camera over the first ferry
    /// route's first boat at the world's moment (the app's
    /// `-screenshot-3d-ferry`), so a screenshot looks at a boat and its
    /// pier; over the scene's place when there is none.
    public func camera(ferryIn scene: Map3DScene, of world: GameWorld, viewport: (width: Float, height: Float)) -> Map3DCamera? {
        let laid = Map3DFerries(world: world, scene: scene)
        guard let boat = laid.firstBoat(second: Double(world.clock.now.seconds)) else { return nil }
        let camera = Map3DCamera(target: boat, distance: distance, heading: heading, viewport: viewport)
        guard tilt > camera.tilt else { return camera }
        return camera.leaned(dy: -(tilt - camera.tilt) / Map3DCamera.leanPerPoint)
    }
}
