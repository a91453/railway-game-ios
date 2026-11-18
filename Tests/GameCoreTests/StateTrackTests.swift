import Foundation
@testable import GameCore
import XCTest

/// A line bought on the state's track (decision 828): the state pays for
/// its track, the line pays an access charge of 1 % of keeping it, and its
/// riders pay the kilometre fare.
final class StateTrackTests: XCTestCase {
    private let track = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let blue = TrainID(rawValue: 1)
    private let kemijarvi = "vr:KJA"

    /// Alpha → Gamma leaving at 06:10, as `LineAcquisitionTests`' run.
    private let out = LineRun(from: 0, to: 2, times: [
        LineRunTime(arrival: 22_200, departure: 22_200), LineRunTime(arrival: 22_500, departure: 22_560), LineRunTime(arrival: 22_800, departure: 22_800),
    ])

    /// `LineAcquisitionTests`' world at 05:00 of day 0, a managed company
    /// with NT$100,000, its track laid on the state's track when `state`.
    private func world(state: Bool) throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: fixtureEconomy(balance: 10_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        world.setSpeed(.normal)
        try world.advance(ticks: 300)
        if state {
            // `TestLine.build(in:)`'s nodes and edges.
            try world.layStateTrack { (world: inout GameWorld) throws(GameError) in
                for x in 0..<7 {
                    let centre = TestLine.centre(x, 1)
                    try world.buildTrackNode(at: WorldCoordinate(x: centre.x, y: centre.y))
                }
                for x in 1..<7 {
                    try world.buildTrackEdge(from: .node(x), to: .node(x + 1))
                }
            }
        } else {
            try track.build(in: &world)
        }
        try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try track.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        _ = try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.setLineServiceWindow(main, to: .allDay)
        _ = try world.purchaseTrain(named: "Blue")
        try world.placeTrain(blue, at: track.at(1, facingEast: true))
        try world.setTrainMovementRate(blue, to: 1_024)
        try world.assignTrain(blue, to: main)
        try world.setLineRuns(main, to: [out])
        return world
    }

    /// What the company's own six edges cost, nothing on the state's
    /// track, and no record or capital spending for it; the stations and
    /// the train are paid as usual.
    func testTheStatePaysForItsTrack() throws {
        let own = try world(state: false)
        let state = try world(state: true)
        XCTAssertEqual(state.network, own.network)
        let laid = own.accounts.assets.filter { $0.kind == .track }
        XCTAssertEqual(laid.count, 6)
        let cost = laid.reduce(Money.zero) { $0 + $1.cost }
        XCTAssertGreaterThan(cost, .zero)
        XCTAssertEqual(state.economy.balance - own.economy.balance, cost)
        XCTAssertEqual(state.accounts.assets.filter { $0.kind == .track }.count, 0)
        XCTAssertEqual(state.accounts.assets.count, own.accounts.assets.count - 6)
        let spent = { (world: GameWorld) in world.accounts.capitalDays.reduce(Money.zero) { $0 + $1.capitalSpending } }
        XCTAssertEqual(spent(own) - spent(state), cost)
    }

    /// REVIEW-L28: the state's track through two of the company's houses.
    /// They come down for their fees, paid from the cash as the ledger
    /// books them (decision 95), and no record of the track stays, though
    /// the houses' records came out from before it in the list (that
    /// stopped the app: the records were taken from where the list had
    /// ended, now past its end).
    func testTheStatesTrackThroughTheCompanysBuildingsLeavesNoTrackRecord() throws {
        let bounds = try WorldBounds(width: 131_072, height: 98_304)
        var world = GameWorld(bounds: bounds, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .paused))
        world.setEconomyMode(.management)
        let west = try world.placeBuilding(.house, at: PlanPoint(x: 8_000, y: 10_000))
        let east = try world.placeBuilding(.house, at: PlanPoint(x: 12_000, y: 10_000))
        let fees = world.demolitionCost(of: west) + world.demolitionCost(of: east)
        XCTAssertGreaterThan(fees, .zero)
        XCTAssertEqual(world.accounts.assets.count, 2)
        let balance = world.economy.balance
        let spent = { (world: GameWorld) in world.accounts.capitalDays.reduce(Money.zero) { $0 + $1.capitalSpending } }
        let before = spent(world)
        try world.layStateTrack { (world: inout GameWorld) throws(GameError) in
            let a = try world.buildTrackNode(at: WorldCoordinate(x: 4_000, y: 10_000))
            let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_000, y: 10_000))
            try world.buildTrackEdge(from: a, to: b)
        }
        XCTAssertTrue(world.placedBuildings.isEmpty)
        XCTAssertEqual(world.network.edges.count, 1)
        XCTAssertEqual(world.accounts.assets, [], "the houses' records are written off and the track has none")
        XCTAssertEqual(world.economy.balance, balance - fees)
        XCTAssertEqual(spent(world), before)
        XCTAssertEqual(world.financeReport(.day).current.netCashFlow, world.economy.balance - 1_000_000_000)
    }

    /// The line's route counts 1 % of its length in the upkeep and route
    /// energy once it is bought on the state's track.
    func testALineOnTheStatesTrackPaysOnePercentOfItsRoute() throws {
        var world = try world(state: true)
        var memo = GameWorld.DispatchMemo()
        let full = world.fixedAssets(memo: &memo).routeLength
        XCTAssertGreaterThan(full, 0)
        try world.recordLineAcquisition(line: main, realLine: kemijarvi, dailyRiders: 0, stateTrack: true)
        XCTAssertEqual(world.acquisition(of: kemijarvi)?.stateTrack, true)
        memo = GameWorld.DispatchMemo()
        let assets = world.fixedAssets(memo: &memo)
        XCTAssertEqual(assets.routeLength, full * 10 / 1_000)
        XCTAssertEqual(assets.lines.first?.routeLength, full * 10 / 1_000)
    }

    /// NT$5 a kilometre of the straight line: 79 km is NT$395, more than
    /// the city's fare; 1 km's NT$5 is less, and the city's fare stands.
    func testItsRidersPayTheKilometreFare() throws {
        let metre = WorldCoordinate.unitsPerMetre
        var world = try makeWorld(width: 5_300_000, height: 40_000, balance: 100_000)
        for east in [0, 79_000, 1_000] as [Int64] {
            try world.buildStation(named: "S\(east)", at: PlanPoint(x: 100_000 + east * metre, y: 20_000))
        }
        XCTAssertEqual(LineAcquisition.stateTrackFare(squaredDistance: (79_000 * metre) * (79_000 * metre)), Money(39_500))
        let city = try XCTUnwrap(world.tripFare(from: alpha, to: beta))
        XCTAssertLessThan(city, Money(39_500))
        XCTAssertEqual(world.tripFare(from: alpha, to: beta, stateTrack: true), Money(39_500))
        XCTAssertEqual(world.tripFare(from: alpha, to: gamma, stateTrack: true), world.tripFare(from: alpha, to: gamma))
    }

    /// A purchase saves `"stateTrack"` only when on, and a bus route's
    /// never has it.
    func testTheFlagSavesOnlyWhenOn() throws {
        var world = try world(state: true)
        try world.recordLineAcquisition(line: main, realLine: kemijarvi, dailyRiders: 0)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(world.acquisitions), as: UTF8.self).contains("stateTrack"))
        world = try self.world(state: true)
        try world.recordLineAcquisition(line: main, realLine: kemijarvi, dailyRiders: 0, stateTrack: true)
        let data = try JSONEncoder().encode(world)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""stateTrack":true"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        // A bus route is never on the state's track.
        let bus = #"{"kind":"bus","realLine":"bus:1","busRoute":1,"day":0,"value":0,"stateTrack":true}"#
        XCTAssertThrowsError(try JSONDecoder().decode(LineAcquisition.self, from: Data(bus.utf8)))
    }

    /// The version 108 save: the line bought on the state's track at 05:00
    /// with far demand on, run to 06:30, the train under way; it loads as
    /// the same world and runs on the same. Written with
    /// `STATE_TRACK_SAVE_NEW=1` by the build that first made it.
    func testTheVersion108SaveKeepsTheStatesTrackAndFarDemand() throws {
        var world = try world(state: true)
        world.setFarDemand(true)
        try world.recordLineAcquisition(line: main, realLine: kemijarvi, dailyRiders: 0, stateTrack: true)
        try world.advance(ticks: 24 * 60 + 90)
        let url = SavedGameTests.fixtures.appendingPathComponent("v108-state-track.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["STATE_TRACK_SAVE_NEW"] != nil, SavedGame.currentVersion == 108 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 108)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertTrue(loaded.farDemand)
        XCTAssertEqual(loaded.acquisition(of: kemijarvi)?.stateTrack, true)
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 600)
        try running.advance(ticks: 600)
        XCTAssertEqual(loaded, running)
    }
}
