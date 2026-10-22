@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 331: the commercial kit's scenes before the big city stations,
/// close up only.
final class Map3DStationCommerceTests: XCTestCase {
    /// A builder with a track along x at z 0 and a big station's building
    /// beside it, 30 m deep and 80 m wide, its middle at z 25, its front
    /// (+z) away from the track.
    private func builder() -> Map3DScene.Builder {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                                         world: GameWorld.newGame())
        builder.trackLines = [(stride(from: Float(-300), through: 300, by: 2).map { Map3DPoint($0, Map3DScene.railLift, 0) }, .surface)]
        let centre = Map3DPoint(0, 0, 25), forward = Map3DPoint(0, 0, 1)
        builder.houseFootprints = [[Map3DPoint(-40, 0, 10), Map3DPoint(40, 0, 10), Map3DPoint(40, 0, 40), Map3DPoint(-40, 0, 40)]]
        builder.bigStations = [(centre, forward, 30)]
        return builder
    }

    private func vertices(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> [Map3DVertex] {
        meshes.values.flatMap(\.vertices)
    }

    private func triangles(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Int {
        meshes.values.reduce(0) { $0 + $1.indices.count / 3 }
    }

    /// Each scene is the commercial kit's, its ground the size it says.
    func testTheModels() throws {
        let models = Map3DScene.Builder.commerceModels
        XCTAssertEqual(models.map(\.example), [.stationTransitHub, .commercialAvenue, .neighborhoodRetailCorner, .nightMarketAlley])
        for (example, model) in models {
            XCTAssertEqual(model.triangles, Map3DCommercialKit.model(for: example).triangleCount, "\(example)")
            let bounds = try XCTUnwrap(model.mesh.bounds)
            // Its ground holds it, signs and awnings too.
            XCTAssertGreaterThanOrEqual(bounds.min.x, -model.length / 2, "\(example)")
            XCTAssertLessThanOrEqual(bounds.max.x, model.length / 2, "\(example)")
            XCTAssertGreaterThanOrEqual(bounds.min.z, -model.width / 2, "\(example)")
            XCTAssertLessThanOrEqual(bounds.max.z, model.width / 2, "\(example)")
            XCTAssertLessThan(model.width, 52 - 2, "\(example): two side by side leave a gap")
        }
    }

    /// Only the city and high-speed rail stations are big.
    func testOnlyTheCityStationsAreBig() throws {
        let big = Map3DStationKit.stations.filter(Map3DScene.Builder.isBig)
        XCTAssertTrue(big.contains { $0.profile == .taipei })
        XCTAssertTrue(big.contains { $0.profile == .hsrTaichung })
        XCTAssertLessThan(big.count, Map3DStationKit.stations.count)
        // The demo's regional station keeps its shop street, and no scene.
        var regional = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                                          world: GameWorld.newGame())
        _ = regional.addStations(GameWorld.newGame().railwaySnapshot(), frame: nil)
        XCTAssertTrue(regional.bigStations.isEmpty)
        XCTAssertTrue(regional.addStationCommerce(clearOf: []).isEmpty)
    }

    /// Before the building, across its forecourt, off the building and
    /// facing it; within the station's triangles; close up only.
    func testTheScenesStandBeforeTheStation() throws {
        var b = builder()
        let cells = b.addStationCommerce(clearOf: [])
        XCTAssertFalse(cells.isEmpty)
        let placed = triangles(b.closeMeshes)
        let fit = Map3DScene.Builder.commerceModels.reduce(into: 0) { sum, scene in
            if sum + scene.model.triangles <= Map3DScene.Builder.commerceTriangles { sum += scene.model.triangles }
        }
        XCTAssertEqual(placed, fit)
        XCTAssertGreaterThan(placed, Map3DScene.Builder.commerceModels[0].model.triangles)
        XCTAssertGreaterThan(try XCTUnwrap(vertices(b.closeMeshes).map(\.z).min()), 40 + Map3DScene.Builder.commerceGap - 1)
        XCTAssertTrue(b.nearMeshes.isEmpty)
        XCTAssertTrue(b.farMeshes.isEmpty)
        XCTAssertTrue(b.meshes.isEmpty, "nothing drawn at every distance")
    }

    /// Not on a cell another thing holds, nor over a road or the track.
    func testNotOnACellTakenNorARoad() throws {
        var plain = builder()
        let all = plain.addStationCommerce(clearOf: [])
        var taken = builder()
        XCTAssertTrue(taken.addStationCommerce(clearOf: all).isEmpty)
        XCTAssertTrue(taken.closeMeshes.isEmpty)

        // A road across the forecourt: the scenes stand clear of it.
        var road = builder()
        road.roadLines = [([Map3DPoint(-400, 0, 70), Map3DPoint(400, 0, 70)], 6)]
        _ = road.addStationCommerce(clearOf: [])
        let points = vertices(road.closeMeshes)
        XCTAssertFalse(points.isEmpty)
        XCTAssertTrue(points.allSatisfy { abs($0.z - 70) > 3 }, "the road stays clear")

        // A second track before the building: none on it.
        var track = builder()
        track.trackLines.append((stride(from: Float(-300), through: 300, by: 2).map { Map3DPoint($0, Map3DScene.railLift, 75) }, .surface))
        _ = track.addStationCommerce(clearOf: [])
        XCTAssertTrue(vertices(track.closeMeshes).allSatisfy { abs($0.z - 75) > 4 }, "4 m from the track")
    }

    /// The same station gets the same scenes every time.
    func testTheSameEveryTime() {
        var one = builder(), two = builder()
        XCTAssertEqual(one.addStationCommerce(clearOf: []), two.addStationCommerce(clearOf: []))
        XCTAssertEqual(vertices(one.closeMeshes).map(\.z).sorted(), vertices(two.closeMeshes).map(\.z).sorted())
    }
}
