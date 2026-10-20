import Foundation
@testable import GameCore
import XCTest

/// The real network's transfers (ARCHITECTURE decision 298). Every
/// expectation is worked out by hand from the rules.
final class TransferDemandTests: XCTestCase {
    private let town = StationID(rawValue: 1)
    private let hub = StationID(rawValue: 2)
    private let yard = StationID(rawValue: 3)

    private static let middle: Int64 = 524_288

    /// A managed world of the standard bounds with demand from land: a cell
    /// of 1,000 residents in the middle with the station Town on it (400
    /// trips a day), and the stations Hub and Yard on no land, far from the
    /// edge.
    private func world() throws -> GameWorld {
        var world = GameWorld(bounds: .standard, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        world.setEconomyMode(.management)
        try world.setLand([LandCell(row: 128, column: 128, use: .residential, residents: 1_000, jobs: 0)])
        world.setLandDemand(true)
        try world.buildStation(named: "Town", at: PlanPoint(x: Self.middle + 2_048, y: Self.middle + 2_048))
        try world.buildStation(named: "Hub", at: PlanPoint(x: Self.middle + 200_000, y: Self.middle))
        try world.buildStation(named: "Yard", at: PlanPoint(x: Self.middle - 200_000, y: Self.middle))
        return world
    }

    func testTransferPointsAddTheirTripsToTheStationsRidership() throws {
        var world = try world()
        XCTAssertFalse(world.realTransfers)
        XCTAssertThrowsGameError(try world.setTransfers([hub: 5]), .invalidStationDemand)

        world.setRealTransfers(true)
        try world.setTransfers([hub: 5, town: 2])
        XCTAssertEqual(world.station(id: hub)?.transferPoints, 5)
        XCTAssertEqual(world.transferTrips(of: hub), 500)
        // Hub has no land: its 500 trips are all transfers, of homes.
        XCTAssertEqual(world.stationDemand(of: hub), StationDemand(kind: .residential, dailyTrips: 500))
        // Town's land gives 400; its 2 points add 200.
        XCTAssertEqual(world.stationDemand(of: town), StationDemand(kind: .residential, dailyTrips: 600))
        XCTAssertNil(world.stationDemand(of: yard))

        // The whole set each time: Town left out has none again.
        try world.setTransfers([hub: 5])
        XCTAssertEqual(world.station(id: town)?.transferPoints, 0)
        XCTAssertEqual(world.stationDemand(of: town), StationDemand(kind: .residential, dailyTrips: 400))

        // A closed station brings none.
        try world.setStationOperationMode(hub, to: .closed)
        XCTAssertEqual(world.transferTrips(of: hub), 0)
        XCTAssertNil(world.stationDemand(of: hub))
        try world.setStationOperationMode(hub, to: .normalFlow)
        XCTAssertEqual(world.stationDemand(of: hub)?.dailyTrips, 500)

        // Off, every station's points go.
        world.setRealTransfers(false)
        XCTAssertEqual(world.station(id: hub)?.transferPoints, 0)
        XCTAssertNil(world.stationDemand(of: hub))
    }

    func testABadSetChangesNothing() throws {
        var world = try world()
        world.setRealTransfers(true)
        try world.setTransfers([hub: 5])
        let before = world
        let ghost = StationID(rawValue: 99)
        XCTAssertThrowsGameError(try world.setTransfers([town: 1, ghost: 1]), .unknownStation(ghost))
        XCTAssertThrowsGameError(try world.setTransfers([town: TransferDemand.maximumPoints + 1]), .invalidStationDemand)
        XCTAssertThrowsGameError(try world.setTransfers([town: -1]), .invalidStationDemand)
        XCTAssertEqual(world, before)
        XCTAssertNoThrow(try world.setTransfers([town: TransferDemand.maximumPoints]))
    }

    func testADepotBringsNoTransfers() throws {
        var world = try world()
        world.setRealTransfers(true)
        try world.setTransfers([yard: 3])
        try world.setStationDepot(yard, to: true)
        XCTAssertEqual(world.station(id: yard)?.transferPoints, 0)
        XCTAssertNil(world.stationDemand(of: yard))
        XCTAssertThrowsGameError(try world.setTransfers([yard: 3]), .invalidStationDemand)
        XCTAssertNoThrow(try world.setTransfers([yard: 0]))
    }

    func testTheStationsByRealOnesSaveTheirPoints() throws {
        var world = try world()
        let plain = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertFalse(plain.contains("realTransfers"))
        XCTAssertFalse(plain.contains("transferPoints"))

        world.setRealTransfers(true)
        try world.setTransfers([hub: 7])
        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)

        func decodes(_ edit: (inout [String: Any]) -> Void) -> Bool {
            var object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            edit(&object)
            guard let edited = try? JSONSerialization.data(withJSONObject: object) else { return false }
            return (try? JSONDecoder().decode(GameWorld.self, from: edited)) != nil
        }
        func setHubPoints(_ value: Any?, in object: inout [String: Any]) {
            var stations = object["stations"] as? [[String: Any]] ?? []
            stations[1]["transferPoints"] = value
            object["stations"] = stations
        }
        XCTAssertTrue(decodes { _ in })
        XCTAssertFalse(decodes { $0["realTransfers"] = nil }, "points while real transfers are off")
        XCTAssertFalse(decodes { $0["realTransfers"] = false }, "written only when on")
        XCTAssertFalse(decodes { setHubPoints(0, in: &$0) }, "none is left out")
        XCTAssertFalse(decodes { setHubPoints(TransferDemand.maximumPoints + 1, in: &$0) })
        XCTAssertTrue(decodes { setHubPoints(nil, in: &$0) })
    }

    func testVersionSixtyFourKeepsTheTransfers() throws {
        var world = try world()
        world.setRealTransfers(true)
        try world.setTransfers([hub: 7, town: 2])
        try world.advance(ticks: 10)

        let url = SavedGameTests.fixtures.appendingPathComponent("v64-real-transfers.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["REAL_TRANSFERS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 64)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertTrue(loaded.realTransfers)
        XCTAssertEqual(loaded.stations.map(\.transferPoints), [2, 7, 0])
        XCTAssertEqual(loaded.stationDemand(of: hub)?.dailyTrips, 700)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 64,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
