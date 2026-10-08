import Foundation
@testable import GameCore
import XCTest

/// ARCHITECTURE decision 83: demolishing a station (`removeStation`,
/// MapBuilder's `handleStationDelete` and the `Ci/` metro game's
/// `confirmDeleteStationAllLines`). Lines, patterns and route preferences
/// lose it; trains running a service through it refuse it; passengers
/// waiting there leave as when it closes; its own go with its ledger.
final class StationRemovalTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)
    private let one = TrainID(rawValue: 1)
    private let two = TrainID(rawValue: 2)

    /// `PassengerTransferTests`' world: A, B and C along a straight track,
    /// First (A–B) with train One and Second (B–C) with train Two, network
    /// routing. Nothing has been sent out yet.
    private func world() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3), ("C", 5)] {
            try track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [b, c]).id
        for line in [first, second] {
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        }
        try world.purchaseTrain(named: "One")
        try world.purchaseTrain(named: "Two")
        try world.placeTrain(one, at: track.at(1, facingEast: true))
        try world.placeTrain(two, at: track.at(3, facingEast: true))
        try world.setTrainMovementRate(one, to: 1024)
        try world.setTrainMovementRate(two, to: 1024)
        try world.assignTrain(one, to: first)
        try world.assignTrain(two, to: second)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 0))
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    /// Four stations and no track: lines are plan data.
    private func planWorld() throws -> (GameWorld, [StationID]) {
        var world = GameWorld(bounds: try WorldBounds(width: 8_192, height: 8_192), economy: GameEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 0, station: 0, train: 0, car: 0)))
        let stations = try ["A", "B", "C", "D"].enumerated().map { index, name in
            try world.buildStation(named: name, at: PlanPoint(x: 1_024 + Int64(index) * 1_024, y: 1_024)).id
        }
        return (world, stations)
    }

    /// Every remaining station's ledger balances, and the world saves and
    /// loads as it is.
    private func assertConservedAndSaveable(_ world: GameWorld, file: StaticString = #filePath, line: UInt = #line) throws {
        for station in world.stations {
            let ledger = world.passengerLedger(of: station.id)
            XCTAssertEqual(ledger.released,
                ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned,
                file: file, line: line)
        }
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world,
                       file: file, line: line)
    }

    /// Stops every service: each line's train is taken off its line, then
    /// stopped if it is still on a round trip.
    private func stopEveryService(_ world: inout GameWorld) throws {
        for train in world.trains {
            if world.assignedLine(of: train.id) != nil { try world.unassignTrain(train.id) }
            if world.train(id: train.id)?.execution != nil { try world.stopTrainService(train.id) }
        }
    }

    // MARK: - The station and its lines

    /// The station, its platforms and its stops go; a line left with one
    /// stop goes (the `Ci/` game's "deleted too short"), with its train
    /// taken off it; a longer line just loses the stop. Free, and the ID is
    /// never handed out again.
    func testTheStationGoesFromItsTrackAndLines() throws {
        var world = try world()
        let through = try world.createLine(named: "Through", stops: [a, b, c]).id
        XCTAssertFalse(world.trackPlatforms(of: b).isEmpty)
        let balance = world.economy.balance

        try world.removeStation(b)

        XCTAssertEqual(world.stations.map(\.id), [a, c])
        XCTAssertEqual(world.trackPlatforms(of: b), [])
        XCTAssertFalse(world.network.platforms.contains { $0.station == b })
        XCTAssertEqual(world.lines.map(\.id), [through], "First and Second had one stop left")
        XCTAssertEqual(world.line(id: through)?.stops, [a, c])
        XCTAssertNil(world.assignedLine(of: one))
        XCTAssertNil(world.assignedLine(of: two))
        XCTAssertEqual(world.economy.balance, balance, "free, and nothing refunded")
        try assertConservedAndSaveable(world)
        XCTAssertEqual(try world.buildStation(named: "D", at: TestLine.centre(3, 2)).id, StationID(rawValue: 4))
    }

    func testAnUnknownStationIsRefused() throws {
        var world = try world()
        let before = world
        XCTAssertThrowsGameError(try world.removeStation(StationID(rawValue: 9)), .unknownStation(StationID(rawValue: 9)))
        XCTAssertEqual(world, before)
    }

    // MARK: - Trains

    /// A running service that calls at the station refuses it, naming the
    /// lowest numbered such train, and the world does not change; once
    /// every such service is stopped, the station can go.
    func testARunningServiceThroughTheStationRefusesIt() throws {
        var world = try world()
        try world.advance(ticks: 1)
        XCTAssertNotNil(world.train(id: one)?.execution)
        XCTAssertNotNil(world.train(id: two)?.execution)
        let before = world

        XCTAssertThrowsGameError(try world.removeStation(b), .trainServiceActive(one))
        XCTAssertThrowsGameError(try world.removeStation(c), .trainServiceActive(two)) // One never calls at C
        XCTAssertEqual(world, before)

        try world.unassignTrain(one)
        try world.stopTrainService(one)
        XCTAssertThrowsGameError(try world.removeStation(b), .trainServiceActive(two))
        try world.unassignTrain(two)
        try world.stopTrainService(two)
        try world.removeStation(b)
        XCTAssertNil(world.station(id: b))
        try assertConservedAndSaveable(world)
    }

    /// A train not running a service loses the station from its timetable
    /// and forgets its visits; a repeating timetable left with no stop no
    /// longer repeats.
    func testAnIdleTrainsTimetableLosesTheStation() throws {
        var world = try world()
        try world.unassignTrain(one)
        try world.unassignTrain(two)
        try world.setTrainTimetable(one, to: [
            ScheduledStop(station: a, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: b, arrival: GameTime(minutes: 3), departure: GameTime(minutes: 4)),
            ScheduledStop(station: c, arrival: GameTime(minutes: 6), departure: GameTime(minutes: 7)),
        ], repeatingEvery: 600)
        try world.setTrainTimetable(two, to: [
            ScheduledStop(station: b, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
        ], repeatingEvery: 60)

        try world.removeStation(b)

        XCTAssertEqual(world.train(id: one)?.timetable.map(\.station), [a, c])
        XCTAssertEqual(world.train(id: one)?.timetablePeriod, 600)
        XCTAssertEqual(world.train(id: two)?.timetable, [])
        XCTAssertNil(world.train(id: two)?.timetablePeriod)
        try assertConservedAndSaveable(world)
    }

    // MARK: - Passengers

    /// Passengers from A waiting at B to change to Second leave, counted as
    /// abandoned at A (as when B closes, `clearStationWaitingPassengers`);
    /// so do those at A whose journey changes at B.
    func testThoseWaitingThereLeaveCountedAtTheirOrigin() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        XCTAssertEqual(journey.legs.map(\.from), [a, b])
        let origin = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        world.passengers[origin].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.waitingPassengers(at: b).map(\.count), [5], "changing at B")
        world.passengers[origin].release(3, along: journey, at: GameTime(minutes: 1))
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 8)
        try stopEveryService(&world)

        try world.removeStation(b)

        XCTAssertNil(world.passengers.first { $0.station == b })
        let ledger = world.passengerLedger(of: a)
        XCTAssertEqual(ledger.released, 8)
        XCTAssertEqual(ledger.waiting, 0)
        XCTAssertEqual(ledger.abandoned, 8)
        try assertConservedAndSaveable(world)
    }

    /// Passengers who set out from the station go with its ledger wherever
    /// they wait: A's passengers changing at B are gone with A, and B's
    /// ledger is untouched.
    func testThoseFromTheStationGoWithItsLedger() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        let origin = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        world.passengers[origin].release(5, along: journey, at: world.clock.now)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.waitingPassengers(at: b).map(\.journey?.origin), [a])
        try stopEveryService(&world)
        let ledgerB = world.passengerLedger(of: b)

        try world.removeStation(a)

        XCTAssertEqual(world.waitingPassengers(at: b), [])
        XCTAssertNil(world.passengers.first { $0.station == a })
        XCTAssertEqual(world.passengerLedger(of: b), ledgerB)
        XCTAssertEqual(world.lines.map(\.name), ["Second"])
        try assertConservedAndSaveable(world)
    }

    /// Passengers on board for the station refuse it even on a train whose
    /// own calls do not include it: Two carries A's passengers to C.
    func testRidersFromTheStationRefuseIt() throws {
        var world = try world()
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: XCTUnwrap(world.passengerRoutes(from: a, to: c).first)))
        let origin = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        world.passengers[origin].release(5, along: journey, at: world.clock.now)
        for _ in 0..<30 where world.riders(of: two).isEmpty {
            try world.advance(ticks: 1)
        }
        XCTAssertEqual(world.riders(of: two).map(\.count), [5])
        try world.unassignTrain(one)
        try world.stopTrainService(one)
        let before = world
        XCTAssertThrowsGameError(try world.removeStation(a), .trainServiceActive(two))
        XCTAssertEqual(world, before)
    }

    // MARK: - Patterns, route preferences, rings and groups

    /// A pattern keeps calling at its stations; a route preference stays on
    /// its leg; a preference to the station goes; a pattern left with one
    /// call goes, and its train is taken off the line.
    func testPatternsAndRoutePreferencesFollowTheirStations() throws {
        var (world, _, line, train) = try LineRoutePreferenceTests.setup(traffic: false, patterns: true)
        let route = LineRoutePreferenceTests.loop(world)
        try world.setLineRoutePreferences(line, to: [route])
        XCTAssertEqual(world.assignedPattern(of: train), 0)
        var withoutMiddle = world

        try world.removeStation(SingleTrackMeet.east)
        let short = try XCTUnwrap(world.line(id: line))
        XCTAssertEqual(short.stops, [SingleTrackMeet.west, SingleTrackMeet.middle])
        XCTAssertEqual(short.routePreferences, [route], "West to Middle")
        XCTAssertEqual(short.patterns, [], "West–East called at West alone")
        XCTAssertNil(world.assignedLine(of: train))
        try assertConservedAndSaveable(world)

        try withoutMiddle.removeStation(SingleTrackMeet.middle)
        let express = try XCTUnwrap(withoutMiddle.line(id: line))
        XCTAssertEqual(express.stops, [SingleTrackMeet.west, SingleTrackMeet.east])
        XCTAssertEqual(express.routePreferences, [], "the leg to Middle is gone")
        XCTAssertEqual(express.patterns.map(\.calls), [[0, 1]])
        XCTAssertEqual(withoutMiddle.assignedPattern(of: train), 0)
        try assertConservedAndSaveable(withoutMiddle)
    }

    /// Where the station stood between two stops of one station they
    /// become one stop; a pattern's calls follow their stations and run
    /// together the same way.
    func testNeighboursOfOneStationBecomeOneStop() throws {
        var (world, s) = try planWorld()
        let loop = try world.createLine(named: "Loop", stops: [s[0], s[1], s[0], s[2]]).id
        try world.addLinePattern(loop, calling: [0, 2, 3])
        try world.addLinePattern(loop, calling: [1, 3])
        let express = try world.createLine(named: "Express", stops: s).id
        try world.addLinePattern(express, calling: [0, 1, 3])

        try world.removeStation(s[1])

        XCTAssertEqual(world.line(id: loop)?.stops, [s[0], s[2]])
        XCTAssertEqual(world.line(id: loop)?.patterns.map(\.calls), [[0, 1]], "B–C had only C left")
        XCTAssertEqual(world.line(id: express)?.stops, [s[0], s[2], s[3]])
        XCTAssertEqual(world.line(id: express)?.patterns.map(\.calls), [[0, 2]])
        try assertConservedAndSaveable(world)
    }

    /// A ring keeps going round with three stops or more, and goes with
    /// fewer.
    func testARingNeedsThreeStopsLeft() throws {
        var (world, s) = try planWorld()
        let big = try world.createLine(named: "Big", stops: s).id
        try world.setLineRing(big, to: true)
        let small = try world.createLine(named: "Small", stops: [s[0], s[1], s[3]]).id
        try world.setLineRing(small, to: true)

        try world.removeStation(s[3])

        XCTAssertEqual(world.lines.map(\.id), [big])
        XCTAssertEqual(world.line(id: big)?.stops, Array(s.prefix(3)))
        XCTAssertEqual(world.line(id: big)?.isRing, true)
        try assertConservedAndSaveable(world)
    }

    /// The station leaves its transfer group; a group left with one
    /// station goes, and its ID is not handed out again.
    func testTheStationLeavesItsTransferGroup() throws {
        var (world, s) = try planWorld()
        try world.linkTransfer(s[0], s[1])
        try world.linkTransfer(s[0], s[2])

        try world.removeStation(s[1])
        XCTAssertEqual(world.transferGroups, [TransferGroup(id: TransferGroupID(rawValue: 1), stations: [s[0], s[2]])])
        try world.removeStation(s[2])
        XCTAssertEqual(world.transferGroups, [])
        try assertConservedAndSaveable(world)
        XCTAssertEqual(try world.linkTransfer(s[0], s[3]), TransferGroupID(rawValue: 2))
    }

    // MARK: - Demand, growth and events

    /// After a day of a managed company's traffic between A and C, with
    /// town growth and demand events: C's growth, its events and A's
    /// remainders for it go with it, and every ledger still balances.
    func testItsGrowthEventsAndRemaindersGoWithIt() throws {
        var world = try world()
        try world.removeStation(b)
        let line = try world.createLine(named: "Direct", stops: [a, c]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(one, to: line)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 2_000))
        try world.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 2_000))
        world.setEconomyMode(.management)
        world.setTownGrowth(true)
        world.setDemandEvents(seed: 7)
        try world.advance(ticks: 1_500)
        XCTAssertNotNil(world.townGrowth(of: c))
        XCTAssertGreaterThan(world.passengerLedger(of: a).released, 0)
        try stopEveryService(&world)

        try world.removeStation(c)

        XCTAssertNil(world.townGrowth(of: c))
        XCTAssertNotNil(world.townGrowth(of: a))
        XCTAssertFalse(world.demandEvents?.events.contains { $0.station == c } ?? false)
        XCTAssertFalse(world.passengers.contains { $0.remainders.contains { $0.destination == c } })
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 0, "nowhere left to go")
        try assertConservedAndSaveable(world)
    }
}
