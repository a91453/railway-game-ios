import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 238: the city in full near the camera and
/// simplified afar.
final class Map3DDetailTests: XCTestCase {
    func testTheCameraWantsDetailOnlyCloseToWhatItLooksAt() {
        let near = Map3DCamera(target: .zero, distance: 300)
        XCTAssertTrue(near.wantsDetail(minimum: Map3DPoint(-256, 0, -256), maximum: Map3DPoint(256, 30, 256)), "the chunk it looks at")
        XCTAssertTrue(near.wantsDetail(minimum: Map3DPoint(256, 0, -256), maximum: Map3DPoint(768, 30, 256)), "the next chunk")
        XCTAssertFalse(near.wantsDetail(minimum: Map3DPoint(2048, 0, 2048), maximum: Map3DPoint(2560, 30, 2560)), "two kilometres off")
        // From high up, nothing is drawn in full.
        let far = Map3DCamera(target: .zero, distance: Map3DCamera.detailDistance + 1)
        XCTAssertFalse(far.wantsDetail(minimum: Map3DPoint(-256, 0, -256), maximum: Map3DPoint(256, 30, 256)))
        // A margin either side of the line, as the street scene's: a chunk
        // just past the reach keeps its detail if it had it, and one just
        // within it waits to come a little closer.
        let edge = max(Map3DCamera.detailReach, near.distance * 1.2)
        let past = (Map3DPoint(edge * 1.05, 0, 0), Map3DPoint(edge * 1.05 + 512, 30, 512))
        XCTAssertFalse(near.wantsDetail(minimum: past.0, maximum: past.1, wasDetailed: false))
        XCTAssertTrue(near.wantsDetail(minimum: past.0, maximum: past.1, wasDetailed: true))
        let within = (Map3DPoint(edge * 0.95, 0, 0), Map3DPoint(edge * 0.95 + 512, 30, 512))
        XCTAssertFalse(near.wantsDetail(minimum: within.0, maximum: within.1, wasDetailed: false))
        XCTAssertTrue(near.wantsDetail(minimum: within.0, maximum: within.1, wasDetailed: true))
        // The ground under a tilted eye counts as much as the target.
        let tilted = Map3DCamera(target: .zero, distance: 1_200, heading: 0)
        let under = tilted.eye
        XCTAssertTrue(tilted.wantsDetail(minimum: Map3DPoint(under.x - 10, 0, under.z - 10), maximum: Map3DPoint(under.x + 10, 10, under.z + 10)))
    }

    func testTheSimplifiedCityIsTheSameCityWithLess() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let scene = Map3DScene(world: world)
        var near = 0, far = 0
        var nearColors = Set<UInt32>(), farColors = Set<UInt32>()
        for chunk in scene.chunks {
            let city = chunk.mesh.indices.count - chunk.baseIndexCount
            XCTAssertGreaterThanOrEqual(city, 0)
            XCTAssertLessThanOrEqual(chunk.far.indices.count, city, "chunk \(chunk.column), \(chunk.row): afar is never more")
            XCTAssertEqual(chunk.far.isEmpty, city == 0, "a city near is a city afar")
            near += city / 3
            far += chunk.far.triangleCount
            nearColors.formUnion(chunk.mesh.indices.dropFirst(chunk.baseIndexCount).map { chunk.mesh.vertices[Int($0)].color })
            farColors.formUnion(chunk.far.vertices.map(\.color))
        }
        // Afar, the city is a good part lighter; near, it has its
        // balconies' air conditioners and signs, afar none.
        XCTAssertLessThan(Double(far), Double(near) * 0.8, "near \(near), far \(far)")
        XCTAssertTrue(nearColors.contains(Map3DPalette.acUnit))
        XCTAssertFalse(farColors.contains(Map3DPalette.acUnit))
        // The shadows are made once.
        let again = Map3DScene(world: world)
        XCTAssertEqual(again.chunks.map(\.shadows.vertices), scene.chunks.map(\.shadows.vertices))
        XCTAssertEqual(again.chunks.map(\.far.vertices), scene.chunks.map(\.far.vertices))
    }

    /// Decision 267: the closest detail only near the target, close up.
    func testTheClosestDetailOnlyCloseUp() {
        let box = (Map3DPoint(-256, 0, -256), Map3DPoint(256, 30, 256))
        let close = Map3DCamera(target: .zero, distance: 200)
        XCTAssertTrue(close.wantsClose(minimum: box.0, maximum: box.1))
        XCTAssertFalse(close.wantsClose(minimum: Map3DPoint(1024, 0, 1024), maximum: Map3DPoint(1536, 30, 1536)), "a kilometre off")
        let higher = Map3DCamera(target: .zero, distance: 800)
        XCTAssertFalse(higher.wantsClose(minimum: box.0, maximum: box.1), "too high")
        XCTAssertTrue(higher.wantsDetail(minimum: box.0, maximum: box.1), "though still in full")
        // The margin: once drawn, kept a little farther.
        let edge = Map3DCamera(target: .zero, distance: Map3DCamera.closeDistance)
        XCTAssertFalse(edge.wantsClose(minimum: box.0, maximum: box.1))
        XCTAssertTrue(edge.wantsClose(minimum: box.0, maximum: box.1, wasClose: true))
    }
}
