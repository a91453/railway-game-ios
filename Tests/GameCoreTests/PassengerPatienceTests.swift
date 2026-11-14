import Foundation
@testable import GameCore
import XCTest

/// Decision 731: passengers who wait too long leave. The lines here have no
/// train, so everyone released waits until they give up.
final class PassengerPatienceTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)

    /// Two stations `apart` world units apart on one line, with no train;
    /// A sends its trips to B.
    private func makeLine(apart: Int64 = 8_192, width: Int64 = 20_480) throws -> GameWorld {
        var world = try makeWorld(width: width, height: 5_120, balance: 100_000)
        try world.buildStation(named: "A", at: PlanPoint(x: 2_048, y: 2_048))
        try world.buildStation(named: "B", at: PlanPoint(x: 2_048 + apart, y: 2_048))
        try world.createLine(named: "Line", stops: [a, b])
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: 100_000))
        world.setSpeed(.normal)
        return world
    }

    private func assertConserved(_ world: GameWorld, file: StaticString = #filePath, line: UInt = #line) {
        for station in [a, b] {
            let ledger = world.passengerLedger(of: station)
            XCTAssertEqual(ledger.released, ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned + ledger.gaveUp,
                           "station \(station.rawValue)", file: file, line: line)
        }
    }

    func testWithPatienceOffPassengersWaitAsLongAsItTakes() throws {
        var world = try makeLine()
        XCTAssertFalse(world.passengerPatience)
        try world.advance(ticks: 100)
        XCTAssertEqual(world.passengerLedger(of: a).gaveUp, 0)
        XCTAssertEqual(world.waitingPassengers(at: a).first?.since, GameTime(minutes: 0))
    }

    /// On, a group still waiting 40 minutes after it came leaves at that
    /// minute, before the minute's release, counted as given up.
    func testPassengersOnAnOrdinaryTripGiveUpAfterFortyMinutes() throws {
        var world = try makeLine()
        world.setPassengerPatience(true)
        try world.advance(ticks: 40)
        XCTAssertEqual(world.passengerLedger(of: a).gaveUp, 0, "at 00:39 the first has waited 39 minutes")
        XCTAssertEqual(world.waitingPassengers(at: a).first?.since, GameTime(minutes: 0))
        let first = world.waitingPassengers(at: a).filter { $0.since == GameTime(minutes: 0) }.reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(first, 0)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.passengerLedger(of: a).gaveUp, first)
        XCTAssertTrue(world.waitingPassengers(at: a).allSatisfy { $0.since >= GameTime(minutes: 1) })
        try world.advance(ticks: 59)
        XCTAssertTrue(world.waitingPassengers(at: a).allSatisfy { $0.since >= GameTime(minutes: 60) })
        XCTAssertEqual(world.passengerLedger(of: a).abandoned, 0)
        assertConserved(world)
    }

    /// A trip of 20 km or more waits 90 minutes.
    func testPassengersOnALongTripWaitNinetyMinutes() throws {
        let far = PassengerPatience.longDistance
        var world = try makeLine(apart: far, width: far + 8_192)
        world.setPassengerPatience(true)
        try world.advance(ticks: 1)
        let group = try XCTUnwrap(world.waitingPassengers(at: a).first)
        XCTAssertTrue(world.isLongTrip(group, at: a))
        try world.advance(ticks: 89)
        XCTAssertEqual(world.passengerLedger(of: a).gaveUp, 0, "at 01:29 the first has waited 89 minutes")
        try world.advance(ticks: 1)
        XCTAssertGreaterThan(world.passengerLedger(of: a).gaveUp, 0)
        XCTAssertTrue(world.waitingPassengers(at: a).allSatisfy { $0.since >= GameTime(minutes: 1) })
        assertConserved(world)

        // A metre short of 20 km is an ordinary trip.
        let near = try makeLine(apart: far - WorldCoordinate.unitsPerMetre, width: far + 8_192)
        XCTAssertFalse(near.isLongTrip(group, at: a))
    }

    /// A passenger changing trains waits from when they can board, not
    /// from when they set out.
    func testATransferWaitsFromWhenItCanBoard() throws {
        var world = try makeLine()
        world.setPassengerPatience(true)
        try world.advance(ticks: 1)
        let group = try XCTUnwrap(world.waitingPassengers(at: a).first)
        let leg = PassengerRouteLeg(line: group.line, pattern: nil, direction: group.direction, from: a, to: b, rideSeconds: 60)
        let route = PassengerRoute(legs: [leg], rideMinutes: 1, waitMinutes: 0, transferSeconds: 0, walkSeconds: 0)
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: route))
        let index = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        let ready = GameTime(minutes: 30)
        XCTAssertEqual(world.passengers[index].enqueueTransfer(5, along: journey, at: GameTime(minutes: 1), readyAt: ready), 5)
        world.sendImpatientPassengersAway(at: GameTime(minutes: 69))
        XCTAssertTrue(world.waitingPassengers(at: a).contains { $0.readyAt == ready }, "39 minutes after it could board")
        world.sendImpatientPassengersAway(at: GameTime(minutes: 70))
        XCTAssertFalse(world.waitingPassengers(at: a).contains { $0.readyAt == ready })
    }

    /// One call or minute by minute leave the same groups.
    func testOneCallOrMinuteByMinuteIsTheSame() throws {
        var world = try makeLine()
        world.setPassengerPatience(true)
        var stepped = world
        try world.advance(ticks: 1_500)
        for _ in 0..<1_500 {
            try stepped.advance(ticks: 1)
        }
        XCTAssertEqual(world, stepped)
        XCTAssertGreaterThan(world.passengerLedger(of: a).gaveUp, 0)
        assertConserved(world)
    }

    /// The rule and those who gave up are saved; a save without them waits
    /// as before.
    func testTheSaveKeepsTheRuleAndThoseWhoGaveUp() throws {
        var world = try makeLine()
        let plain = String(decoding: try JSONEncoder().encode(SavedGame(world: world)), as: UTF8.self)
        XCTAssertFalse(plain.contains("passengerPatience"))
        world.setPassengerPatience(true)
        try world.advance(ticks: 60)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"passengerPatience\":true"))
        XCTAssertTrue(text.contains("\"gaveUp\""))
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        try loaded.advance(ticks: 60)
        try world.advance(ticks: 60)
        XCTAssertEqual(loaded, world)
    }

    /// A station whose counts, with those who gave up, are more than it
    /// released is refused.
    func testASaveThatCountsTooManyWhoGaveUpIsRefused() throws {
        var world = try makeLine()
        world.setPassengerPatience(true)
        try world.advance(ticks: 60)
        let released = world.passengerLedger(of: a).released
        let text = String(decoding: try JSONEncoder().encode(SavedGame(world: world)), as: UTF8.self)
        let gaveUp = world.passengerLedger(of: a).gaveUp
        let broken = text.replacingOccurrences(of: "\"gaveUp\":\(gaveUp)", with: "\"gaveUp\":\(released + 1)")
        XCTAssertNotEqual(broken, text)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(broken.utf8)))
    }

    /// `v97-passenger-patience.json`: the line above with the rule on, saved
    /// at 01:00. Written with `PATIENCE_SAVE_NEW=1`, as the save was first
    /// made.
    func testTheVersion97SaveLoadsAndRunsOn() throws {
        var world = try makeLine()
        world.setPassengerPatience(true)
        try world.advance(ticks: 60)

        // The file is version 97's, whatever this build writes: never
        // written again under a later version's name.
        let url = SavedGameTests.fixtures.appendingPathComponent("v97-passenger-patience.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["PATIENCE_SAVE_NEW"] != nil, SavedGame.currentVersion == 97 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"saveVersion\" : 97"), "the fixture is a version 97 save")
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertTrue(loaded.passengerPatience)
        XCTAssertGreaterThan(loaded.passengerLedger(of: a).gaveUp, 0)
        XCTAssertEqual(loaded.passengerLedger(of: a), world.passengerLedger(of: a))
        try loaded.advance(ticks: 60)
        try world.advance(ticks: 60)
        XCTAssertEqual(loaded, world)
    }
}
