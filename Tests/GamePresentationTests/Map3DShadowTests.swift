import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 232: the soft shadows on the ground under what
/// stands on the 3D map, worked out without a GPU.
final class Map3DShadowTests: XCTestCase {
    func testAShadowFadesFromItsFootprintToNothing() {
        var mesh = Map3DMesh()
        let inner = Map3DMesh.footprint(centre: Map3DPoint(0, 1, 0), length: 10, width: 4)
        let outer = Map3DMesh.footprint(centre: Map3DPoint(0, 1, 0), length: 14, width: 8)
        mesh.addShadow(inner: inner, outer: outer, darkness: 0.3)
        // The footprint and the four sides fading out: ten triangles.
        XCTAssertEqual(mesh.triangleCount, 10)
        XCTAssertTrue(mesh.vertices[0..<4].allSatisfy { $0.color == Map3DShadow.color(0.3) })
        XCTAssertTrue(mesh.vertices[4..<8].allSatisfy { $0.color == Map3DShadow.color(0) })
        XCTAssertTrue(mesh.vertices.allSatisfy { $0.color & 0x00FF_FFFF == 0 && $0.surface == nil }, "black, untextured")
        XCTAssertEqual(Map3DShadow.color(0.3) >> 24, 77)
        // Every triangle lies flat, and none is a sliver.
        for start in stride(from: 0, to: mesh.indices.count, by: 3) {
            let p = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])].position }
            XCTAssertGreaterThan((p[1] - p[0]).cross(p[2] - p[0]).length, 1)
        }
    }

    func testShadowsAreFainterAtNight() {
        XCTAssertEqual(Map3DShadow.strength(Map3DLighting(minute: 12 * 60)), 1, accuracy: 0.01)
        XCTAssertLessThan(Map3DShadow.strength(Map3DLighting(minute: 2 * 60)), 0.5)
    }

    private func lineBetweenTwoTowns() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        return try newGameLine(through: [towns[0], towns[1]])
    }

    func testTheTownsCastShadowsOnTheGroundTheSceneDraws() throws {
        let world = try lineBetweenTwoTowns()
        let scene = Map3DScene(world: world)
        let shadows = scene.chunks.flatMap(\.shadows.vertices)
        XCTAssertGreaterThan(shadows.count, 1_000)
        // Each shadow lies on the ground quad under it, the lift over it:
        // the ground's own vertices are where the drawn ground passes.
        var builder = Map3DScene.Builder(originX: scene.originX, originY: scene.originY, region: scene.region, world: world)
        for vertex in shadows.prefix(2_000) {
            XCTAssertEqual(vertex.y, builder.drawnGround(x: vertex.x, z: vertex.z) + Map3DShadow.lift, accuracy: 0.001)
        }
        // The drawn ground meets the ground mesh at its corners.
        let groundVertices = scene.chunks.flatMap(\.mesh.vertices).filter { $0.color == Map3DPalette.ground }
        for vertex in groundVertices.prefix(500) {
            XCTAssertEqual(builder.drawnGround(x: vertex.x, z: vertex.z), vertex.y, accuracy: 0.01)
        }
        // A chunk's box holds its shadows, so they are not culled early.
        for chunk in scene.chunks {
            for vertex in chunk.shadows.vertices {
                XCTAssertTrue(vertex.x >= chunk.minimum.x && vertex.x <= chunk.maximum.x && vertex.z >= chunk.minimum.z && vertex.z <= chunk.maximum.z)
            }
        }
    }

    func testAViaductCastsAStripOnTheGroundBelowIt() {
        let world = GameWorld.newGame()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        let ground = builder.drawnGround(x: 0, z: 0)
        builder.addTrackPiece([Map3DPoint(0, ground + 8, 0), Map3DPoint(0, ground + 8, -64)], kind: .viaduct)
        let shadows = builder.chunks().flatMap(\.shadows.vertices)
        XCTAssertFalse(shadows.isEmpty)
        XCTAssertTrue(shadows.allSatisfy { $0.y < ground + 1 }, "on the ground, not on the deck")
        // Wider than the 5 m deck.
        XCTAssertGreaterThan((shadows.map(\.x).max() ?? 0) - (shadows.map(\.x).min() ?? 0), 5)
        // Track on the ground casts none.
        var low = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        low.addTrackPiece([Map3DPoint(0, ground, 0), Map3DPoint(0, ground, -64)], kind: .viaduct)
        XCTAssertTrue(low.chunks().allSatisfy { $0.shadows.isEmpty })
    }

    func testEveryCarCastsAShadowOnItsBed() throws {
        var world = try lineBetweenTwoTowns()
        try world.advance(ticks: 30)
        let scene = Map3DScene(world: world)
        let motion = TrainMotion(world: world, time: 0)
        let frame = Map3DTrains.frame(motion, progress: 1, heights: Map3DTrains.Heights(world.railwaySnapshot()), in: scene, models: nil, eye: nil)
        let cars = motion.runs.reduce(0) { $0 + TrainCars.count(length: $1.length, carPitch: $1.carPitch) }
        XCTAssertEqual(frame.shadows.triangleCount, cars * 10)
        // Under the cars, just over the bed's top: the rail less 0.3 m,
        // where the cars' boxes start 0.3 m over the rail.
        let floor = try XCTUnwrap(frame.boxes.bounds).min.y, lowest = try XCTUnwrap(frame.shadows.bounds).min.y
        XCTAssertEqual(lowest, floor - 0.6, accuracy: 0.01)
    }
}
