import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// LANDMARK-PLINTH: a landmark with a ``Map3DLandmarkRegistration/plinth``
/// stands on the highest drawn ground under its foot, so no part of its
/// foot is sunk into the ground (Dazaifu's hall's porch and railing were,
/// the ground under it rising 2.6 m), on a base that reaches down below
/// the lowest ground under it, so it floats nowhere either.
final class Map3DLandmarkPlinthTests: XCTestCase {
    static var plinthed: [Map3DLandmarkRegistration] { Map3DLandmarkRegistry.landmarks.filter { $0.plinth != nil } }

    func testDazaifusHallAndGateStandOnABase() {
        let ids = Set(Self.plinthed.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["jp-dazaifu-honden", "jp-dazaifu-romon"]), "\(ids)")
        XCTAssertTrue(Self.plinthed.allSatisfy { $0.map == "fukuoka" && $0.sink == 0 && $0.deck == nil })
    }

    func testNoFootIsSunkAndNoneFloats() throws {
        let ground = try FukuokaRailwaysTests.ground()
        var world = GameWorld.newOverseasGame(ground)
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        for landmark in Self.plinthed {
            let at = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
            let region = WorldRegion(minX: at.x - 200 * metre, minY: at.y - 200 * metre, maxX: at.x + 200 * metre, maxY: at.y + 200 * metre)
            var builder = Map3DScene.Builder(originX: at.x, originY: at.y, region: region, world: world, heights: ground.heights)
            XCTAssertTrue(builder.addHongKongLandmarks(frame: frame).contains(landmark.id), landmark.id)
            let model = landmark.model(full: true)
            let foot = try XCTUnwrap(model.footOutline(), landmark.id)
            let top = try XCTUnwrap(model.vertices.map(\.z).max())
            var built: [Map3DVertex] = []
            for mesh in builder.nearMeshes.values {
                for vertex in mesh.vertices where LandmarkMesh.contains(foot.ring, (x: vertex.x, y: -vertex.z)) { built.append(vertex) }
            }
            // Where its model's foot was set: its top's height less the model's.
            let placed = try XCTUnwrap(built.map(\.y).max()) - top
            let heights = LandmarkMesh.plinthSamples(foot.ring, step: 1).map { builder.drawnGround(x: $0.x, z: -$0.y) }
            let high = try XCTUnwrap(heights.max()), low = try XCTUnwrap(heights.min())
            XCTAssertEqual(placed + foot.z, high, accuracy: 0.05, "\(landmark.id): its foot on the highest ground under it")
            XCTAssertLessThanOrEqual(try XCTUnwrap(built.map(\.y).min()), low - LandmarkMesh.plinthTuck + 0.01,
                                     "\(landmark.id): its base down below the lowest ground under it")
        }
    }

    /// The outline round a model's foot is its convex hull, counter-clockwise.
    func testFootOutline() {
        let ring = LandmarkMesh.convexHull([(x: 0, y: 0), (x: 2, y: 0), (x: 1, y: 1), (x: 2, y: 2), (x: 0, y: 2), (x: 1, y: 0)])
        XCTAssertEqual(ring.map(\.x), [0, 2, 2, 0])
        XCTAssertEqual(ring.map(\.y), [0, 0, 2, 2])
        XCTAssertTrue(LandmarkMesh.contains(ring, (x: 1, y: 1)))
        XCTAssertFalse(LandmarkMesh.contains(ring, (x: 3, y: 1)))
        XCTAssertEqual(LandmarkMesh.plinthSamples(ring, step: 1).count, 4 + 9)
    }
}
