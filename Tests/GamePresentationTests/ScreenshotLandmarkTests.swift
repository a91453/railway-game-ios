import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 555 續 (LANDMARK101): the screenshot scenes of Taipei open on
/// their landmark, standing: the line each lays to open the map there
/// runs beside it, not through it (where a landmark gives way to the
/// track, decision 370).
final class ScreenshotLandmarkTests: XCTestCase {
    /// The tallest the scene draws within `radius` metres of `place`.
    private func tallest(near place: (latitude: Double, longitude: Double), radius: Float, in scene: Map3DScene, of world: GameWorld) throws -> Float {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
        let middle = scene.point(worldX: at.x, worldY: at.y, height: 0)
        let metre = scene.point(worldX: at.x + Double(WorldCoordinate.unitsPerMetre), worldY: at.y, height: 0).x - middle.x
        return scene.chunks.flatMap(\.mesh.vertices).filter {
            let dx = ($0.x - middle.x) / metre, dz = ($0.z - middle.z) / metre
            return dx * dx + dz * dz < radius * radius
        }.map { ($0.y - middle.y) / metre }.max() ?? 0
    }

    /// Taipei 101's scene: the tower to its spire (508 m), where it stands.
    func testTaipei101Stands() throws {
        let world = ScreenshotScene.taipei101.make(in: .english)
        let scene = Map3DScene(world: world)
        let place = try XCTUnwrap(ScreenshotScene.taipei101.place)
        XCTAssertGreaterThan(try tallest(near: place, radius: 60, in: scene, of: world), 500)
    }

    /// Taipei Main Station's scene: the station's landmark and the Shin
    /// Kong Life Tower (244 m) south-west of it.
    func testTaipeiMainAndShinKongStand() throws {
        let world = ScreenshotScene.taipeiMain.make(in: .english)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        let built = builder.addTaipeiLandmarks(frame: frame)
        XCTAssertNotNil(built[.taipeiMainStation])
        XCTAssertNotNil(built[.shinKongLifeTower])
    }
}
