import GameCore
@testable import GamePresentation
import XCTest

/// Decision 277, later: the shop street by a station, after
/// `town-scene-reference-clean`'s `main.js`: striped cloth awnings in each
/// shop's own colour, and on some tall shops a board on the roof and a
/// canopy with a warm light over the door.
final class Map3DStationStreetTests: XCTestCase {
    private func scene() throws -> (Map3DScene, stations: [Map3DPoint]) {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let scene = Map3DScene(world: world)
        let stations = world.stations.filter { !$0.isDepot }.map { scene.point(worldX: Double($0.point.x), worldY: Double($0.point.y), height: 0) }
        XCTAssertFalse(stations.isEmpty)
        return (scene, stations)
    }

    /// Striped awnings stand by the stations and nowhere else, cream
    /// stripes between stripes of the station shops' colours.
    func testStripedAwningsStandOnlyByTheStations() throws {
        let (scene, stations) = try scene()
        let cream = scene.chunks.flatMap(\.close.vertices).filter { $0.color == Map3DPalette.awningCream }
        XCTAssertFalse(cream.isEmpty, "a shop street by a town's station")
        // Within the reach of a station, give or take a house's depth.
        let reach = Map3DScene.Builder.stationStreetReach + 20
        for vertex in cream {
            XCTAssertTrue(stations.contains { hypotf($0.x - vertex.x, $0.z - vertex.z) <= reach }, "(\(vertex.x), \(vertex.z))")
        }
        let colours = Set(scene.chunks.flatMap(\.close.vertices).map(\.color))
        XCTAssertFalse(colours.isDisjoint(with: Map3DPalette.stationShops))
    }

    /// Within 400 m of a station, and with no station nowhere: a new
    /// game's towns keep their plain awnings.
    func testTheShopStreetReachesFourHundredMetres() {
        let world = GameWorld.newGame()
        let builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        XCTAssertEqual(builder.stations, [])
        XCTAssertFalse(Map3DScene.Builder.isStationStreet(.zero, stations: []))
        XCTAssertTrue(Map3DScene.Builder.isStationStreet(Map3DPoint(100, 0, 100), stations: [.zero]))
        XCTAssertTrue(Map3DScene.Builder.isStationStreet(Map3DPoint(280, 0, 280), stations: [.zero]))
        XCTAssertFalse(Map3DScene.Builder.isStationStreet(Map3DPoint(290, 0, 290), stations: [.zero]))
        let plain = Map3DScene(world: world)
        XCTAssertFalse(plain.chunks.flatMap(\.close.vertices).contains { $0.color == Map3DPalette.awningCream })
    }

    /// A tall shop's board and door light glow at night; the awning is
    /// the reference's seven stripes and valance.
    func testTheShopsPieces() {
        var mesh = Map3DMesh()
        Map3DScene.Builder.addStripedAwning(&mesh, from: Map3DPoint(0, 3, 0), facing: Map3DPoint(0, 0, 1), width: 4.2, color: Map3DPalette.stationShops[0])
        XCTAssertEqual(mesh.triangleCount, 7 * 2 * 2, "seven stripes, each a slope and a valance")
        XCTAssertEqual(mesh.vertices.filter { $0.color == Map3DPalette.awningCream }.count, 3 * 2 * 4)
        let lowest = mesh.vertices.map(\.y).min() ?? 0
        XCTAssertEqual(lowest, 3 - 1.2 * sinf(0.42) - 0.25, accuracy: 0.001)

        var board = Map3DMesh()
        Map3DScene.Builder.addRoofBoard(&board, front: .zero, facing: Map3DPoint(0, 0, 1), width: 6, roof: 14, color: Map3DPalette.stationShops[1])
        XCTAssertTrue(board.vertices.filter { $0.color == Map3DPalette.stationShops[1] }.allSatisfy { $0.layer == Map3DVertex.glowing })
        XCTAssertTrue(board.vertices.filter { $0.color == Map3DPalette.signPost }.allSatisfy { $0.layer != Map3DVertex.glowing })

        var canopy = Map3DMesh()
        Map3DScene.Builder.addEntranceCanopy(&canopy, front: .zero, facing: Map3DPoint(0, 0, 1), width: 6, height: 3.2)
        XCTAssertTrue(canopy.vertices.contains { $0.color == Map3DPalette.downlight && $0.layer == Map3DVertex.glowing })
    }
}
