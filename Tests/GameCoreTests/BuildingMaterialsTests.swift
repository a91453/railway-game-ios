import Foundation
@testable import GameCore
import XCTest

/// Building materials (ARCHITECTURE decision 156): a freight yard can send
/// them instead of goods; let off at a yard they stay at its station, and
/// every station gets some by road each midnight, an outside connection
/// its imports besides.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class BuildingMaterialsTests: XCTestCase {
    private let track = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let gamma = StationID(rawValue: 2)
    private let main = LineID(rawValue: 1)
    private let blue = TrainID(rawValue: 1)
    private let crawl = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1)

    /// `FreightTests`' world: Alpha and Gamma 64 m apart, 40,000 industrial
    /// jobs by Alpha, a managed company, a yard at each, the freight line
    /// Goods and one one-car train on it; building materials on, and
    /// Alpha's yard sending them.
    private func world(trains: Int = 1, materials: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts)
        )
        try track.build(in: &world)
        try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        try world.setLand([LandCell(row: 0, column: 0, use: .industrial, residents: 0, jobs: 40_000)])
        world.setEconomyMode(.management)
        if materials { world.enableBuildingMaterials() } else { world.enableFreight() }
        try world.buildFreightFacility(at: alpha)
        try world.buildFreightFacility(at: gamma)
        if materials { try world.setFreightProduct(at: alpha, to: .materials) }
        try world.createLine(named: "Goods", stops: [alpha, gamma])
        try world.setLinePerformance(main, to: crawl)
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineFreight(main, to: true)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: trains, offPeak: trains, low: trains))
        for index in 0..<trains {
            let train = try world.purchaseTrain(named: "T\(index)")
            try world.placeTrain(train.id, at: track.at(1, facingEast: true))
            try world.setTrainMovementRate(train.id, to: 1_024)
            try world.assignTrain(train.id, to: main)
        }
        world.setSpeed(.normal)
        return world
    }

    func testCommandsAreCheckedInOrder() throws {
        var world = try world(materials: false)
        XCTAssertThrowsGameError(try world.setFreightProduct(at: StationID(rawValue: 9), to: .goods), .noFreightFacility(StationID(rawValue: 9)))
        XCTAssertThrowsGameError(try world.setFreightProduct(at: alpha, to: .materials), .buildingMaterialsNotEnabled)
        try world.setFreightProduct(at: alpha, to: .goods)
        XCTAssertEqual(world.materialsSuppliedPerDay(at: alpha), 0)
        world.enableBuildingMaterials()
        try world.setFreightProduct(at: alpha, to: .materials)
        XCTAssertEqual(world.freightFacility(at: alpha)?.product, .materials)
        XCTAssertEqual(world.materialsSuppliedPerDay(at: alpha), 60)

        var off = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000, costs: testCosts))
        XCTAssertThrowsGameError(try off.setFreightProduct(at: alpha, to: .goods), .freightNotEnabled)
        off.enableBuildingMaterials()
        XCTAssertNotNil(off.freight, "building materials turn freight on")
    }

    /// Every station gets 60 t at each midnight, the first at the start; an
    /// outside connection 600 t more. A station holds at most 5,000 t.
    func testEveryStationGetsMaterialsByRoadEachMidnight() throws {
        var world = try world(trains: 0)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.materialsStock(at: alpha), 60)
        XCTAssertEqual(world.materialsStock(at: gamma), 60)
        try world.advance(ticks: 2 * 1_440)
        XCTAssertEqual(world.materialsStock(at: alpha), 180, "midnights 0, 1 and 2")
        var port = try self.world(trains: 0)
        port.setOutsideConnections(true)
        XCTAssertEqual(port.materialsSuppliedPerDay(at: alpha), 660)
        try port.advance(ticks: 8 * 1_440 + 1)
        // Nine midnights of 660 t is 5,940 t: 5,000 kept, 940 lost.
        XCTAssertEqual(port.materialsStock(at: alpha), 5_000)
        let state = try XCTUnwrap(port.freight)
        XCTAssertEqual(state.materialsSupplied, 2 * 9 * 660)
        XCTAssertEqual(state.materialsLost, 2 * 940)
        XCTAssertTrue(state.isConserved)
    }

    /// Alpha's yard sends building materials: the train carries them as
    /// materials, is paid at Gamma as for goods, and they stay at Gamma.
    func testMaterialsAreCarriedPaidForAndKept() throws {
        var world = try world()
        var sawMaterials = false
        for _ in 0..<(6 * 60) {
            try world.advance(ticks: 1)
            let state = try XCTUnwrap(world.freight)
            XCTAssertTrue(state.isConserved, "at \(world.clock.now)")
            if let group = state.loads.first?.groups.first {
                XCTAssertEqual(group.kind, .materials)
                sawMaterials = true
            }
        }
        XCTAssertTrue(sawMaterials)
        let state = try XCTUnwrap(world.freight)
        XCTAssertGreaterThan(state.materialsReceived, 0)
        XCTAssertEqual(state.materialsReceived, state.delivered, "everything let off was materials")
        XCTAssertEqual(world.materialsStock(at: gamma), 60 + state.materialsReceived)
        XCTAssertEqual(world.materialsStock(at: alpha), 60)
        XCTAssertGreaterThan(world.financeReport(.day).current.freightRevenue, .zero)
    }

    /// A station removed loses the materials it held.
    func testRemovingAStationLosesItsMaterials() throws {
        var world = try world(trains: 0)
        try world.advance(ticks: 1)
        try world.removeStation(gamma)
        let state = try XCTUnwrap(world.freight)
        XCTAssertEqual(state.materials.map(\.station), [alpha])
        XCTAssertEqual(state.materialsLost, 60)
        XCTAssertTrue(state.isConserved)
    }

    func testLongBatchesMatchSingleTicks() throws {
        var once = try world()
        var stepped = once
        try once.advance(ticks: 26 * 60 + 7)
        for _ in 0..<(26 * 60 + 7) { try stepped.advance(ticks: 1) }
        XCTAssertEqual(once, stepped)
    }

    // MARK: - Saving

    func testAWorldWithoutMaterialsWritesNoneAndAWorldWithThemKeepsThem() throws {
        var goods = try world(materials: false)
        try goods.advance(ticks: 3 * 60)
        let plain = String(decoding: try JSONEncoder().encode(SavedGame(world: goods)), as: UTF8.self)
        XCTAssertFalse(plain.contains("materials") || plain.contains("product") || plain.contains("kind\":\"goods"))

        var world = try world()
        try world.advance(ticks: 5 * 60)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
    }

    func testMaterialsWithoutTheSwitchAreRefused() throws {
        var world = try world()
        try world.advance(ticks: 1)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: world))) as? [String: Any])
        var inner = try XCTUnwrap(json["world"] as? [String: Any])
        var freight = try XCTUnwrap(inner["freight"] as? [String: Any])
        freight.removeValue(forKey: "buildingMaterials")
        inner["freight"] = freight
        json["world"] = inner
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: json)))
    }

    /// Version 39 (decision 156): `world()` run five hours and on to a
    /// minute when its train carries materials. It saves byte for byte and
    /// is the world this build makes.
    func testVersionThirtyNineKeepsItsBuildingMaterials() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v39-materials.json")
        var made = try world()
        try made.advance(ticks: 5 * 60)
        while made.freight?.loads.isEmpty ?? true { try made.advance(ticks: 1) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["MATERIALS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 39)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        let state = try XCTUnwrap(world.freight)
        XCTAssertTrue(state.buildingMaterials)
        XCTAssertEqual(state.loads.first?.groups.first?.kind, .materials)
        XCTAssertEqual(state.facilities.first?.product, .materials)
        XCTAssertTrue(state.isConserved)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 39,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
