import GameCore
@testable import GamePresentation
import XCTest

/// Decision 840: the studio's reindeer decode, near and far, stand on the
/// ground, and only the sleigh's lamps glow.
final class Map3DReindeerTests: XCTestCase {
    func testEveryUnitDecodesNearAndFarWithinItsBudget() throws {
        let budget: [Map3DReindeer.Unit: (near: Int, far: Int)] = [
            .sleigh: (8_000, 2_000), .standing: (1_000, 250), .grazing: (1_000, 250), .sledRide: (2_500, 600),
        ]
        for unit in Map3DReindeer.Unit.allCases {
            let near = try XCTUnwrap(Map3DReindeer.model(unit), "\(unit)")
            let far = try XCTUnwrap(Map3DReindeer.model(unit, far: true), "\(unit) far")
            let limit = try XCTUnwrap(budget[unit])
            XCTAssertLessThanOrEqual(near.triangleCount, limit.near, "\(unit)")
            XCTAssertLessThanOrEqual(far.triangleCount, limit.far, "\(unit)")
            XCTAssertLessThan(far.triangleCount, near.triangleCount, "\(unit)")
        }
    }

    func testTheGroundReindeerStandOnTheGroundFacingPlusX() throws {
        for unit in [Map3DReindeer.Unit.standing, .grazing, .sledRide] {
            let model = try XCTUnwrap(Map3DReindeer.model(unit))
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.05, "\(unit)")
            XCTAssertGreaterThan(model.maximum.x - model.minimum.x, model.maximum.y - model.minimum.y, "\(unit)")
            XCTAssertFalse(model.vertices.contains { $0.layer == Map3DVertex.glowing }, "\(unit)")
        }
    }

    func testTheSleighIsTheSantaFlightModel() throws {
        let model = try XCTUnwrap(Map3DReindeer.model(.sleigh))
        XCTAssertEqual(model.name, SantaFlight.Model.name)
        XCTAssertEqual(model.maximum.x - model.minimum.x, SantaFlight.Model.length, accuracy: 0.05)
        XCTAssertEqual(model.maximum.z - model.minimum.z, SantaFlight.Model.height, accuracy: 0.05)
        XCTAssertTrue(model.vertices.contains { $0.layer == Map3DVertex.glowing && $0.color == Map3DPalette.lantern })
    }

    /// A scene builder 1.5 km round `plaza` on `world`, its winter
    /// decorations and herd laid.
    private func laid(_ world: GameWorld, round plaza: String) throws -> Map3DScene.Builder {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let spot = try XCTUnwrap(Map3DWinterLights.plazas.first { $0.name == plaza })
        let place = frame.worldPosition(latitude: spot.latitude, longitude: spot.longitude)
        let metre = Double(WorldCoordinate.unitsPerMetre), reach = 1_500 * metre
        let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
        var builder = Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: nil)
        builder.addWinterDecor(frame: frame)
        builder.addReindeerHerd(frame: frame)
        return builder
    }

    /// On Rovaniemi's map the herd stands by the Santa Claus village's
    /// plaza, clear of its tree, no landmark or station building under
    /// it; by Banqiao's plaza there is none.
    func testTheHerdStandsByTheSantaClausVillage() throws {
        let builder = try laid(GameWorld.newOverseasGame(try RovaniemiRailwaysTests.ground()), round: "santa-claus-village")
        let herd = builder.reindeerHerd
        XCTAssertEqual(herd.map(\.unit), Map3DReindeerHerd.members.map(\.unit))
        let tree = try XCTUnwrap(builder.winterDecor.first { $0.decor == .treeLarge })
        for reindeer in herd {
            let flat = Map3DPoint(reindeer.point.x, 0, reindeer.point.z)
            XCTAssertLessThanOrEqual(flat.length, Map3DReindeerHerd.farthest + Map3DReindeerHerd.foot)
            XCTAssertGreaterThan((flat - Map3DPoint(tree.point.x, 0, tree.point.z)).length, 8)
            XCTAssertFalse(builder.underLandmark(reindeer.point))
            XCTAssertTrue(builder.isClearOfBuildings(reindeer.point, radius: 2))
        }
        let banqiao = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0141, longitudeDegrees: 121.4637))
        XCTAssertTrue(try laid(GameWorld.newGame(anchor: banqiao), round: "banqiao").reindeerHerd.isEmpty)
    }

    /// Near the camera the near models, past ``Map3DReindeerHerd/nearReach``
    /// the far ones, past ``Map3DReindeerHerd/farReach`` none; all year.
    func testTheHerdIsDrawnByReach() throws {
        let pack = Map3DModelPack.standard
        let herd = Map3DReindeerHerd(placements: Map3DReindeerHerd.members.map {
            .init(unit: $0.unit, point: Map3DPoint($0.x, 0, $0.z), forward: Map3DPoint(1, 0, 0))
        })
        func drawn(from eye: Map3DPoint) -> [String] {
            var frame = Map3DTrains.Frame()
            herd.add(to: &frame, pack: pack, eye: eye)
            return frame.instances.map { pack.models[$0.model].name }
        }
        XCTAssertEqual(drawn(from: Map3DPoint(0, 40, 60)), Map3DReindeerHerd.members.map(\.unit.rawValue))
        XCTAssertEqual(drawn(from: Map3DPoint(0, 400, 1_000)), Map3DReindeerHerd.members.map { $0.unit.rawValue + "-far" })
        XCTAssertEqual(drawn(from: Map3DPoint(0, 400, 4_000)), [])
    }

    /// Decision 840's later amendment: every reindeer's antlers dark
    /// brown, as in the photographs; Santa's team brown, the farms' grey.
    func testTheColours() throws {
        func colours(_ unit: Map3DReindeer.Unit) throws -> Set<UInt32> { Set(try XCTUnwrap(Map3DReindeer.model(unit)).vertices.map(\.color)) }
        for unit in Map3DReindeer.Unit.allCases {
            let used = try colours(unit)
            XCTAssertTrue(used.contains(Map3DReindeer.antler), "\(unit)")
            XCTAssertFalse(used.contains(Map3DPalette.concrete), "\(unit): no pale antlers")
        }
        XCTAssertTrue(try colours(.sleigh).contains(Map3DPalette.trunk))
        XCTAssertFalse(try colours(.sleigh).contains(Map3DPalette.arcade))
        XCTAssertTrue(try colours(.standing).contains(Map3DPalette.arcade))
    }
}
