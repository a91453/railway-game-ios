import Foundation
@testable import GameCore
import XCTest

/// Decision 768: concerts and matches held at a real stadium or arena,
/// exhibitions at an exhibition hall, once a line reaches it.
final class EventVenueTests: XCTestCase {
    private let ids = (1...6).map { StationID(rawValue: $0) }

    private func world(venues: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 16_384, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 14)
        try track.build(in: &world)
        for (index, x) in [1, 3, 5, 7, 9, 11].enumerated() {
            try track.buildStation(named: "S\(index)", beside: x, at: 1, in: &world)
        }
        let line = try world.createLine(named: "L", stops: ids).id
        try world.setLineServiceWindow(line, to: .allDay)
        // A venue holds events once a line's trains call near it.
        try world.assignTrain(world.purchaseTrain(named: "T").id, to: line)
        for (index, id) in ids.enumerated() {
            try world.setStationDemand(id, to: StationDemand(kind: index % 2 == 0 ? .residential : .office, dailyTrips: Int64(500 * (index + 1))))
        }
        world.setDemandEvents(seed: 42)
        if venues {
            let arena = try XCTUnwrap(world.station(id: ids[1])).point, hall = try XCTUnwrap(world.station(id: ids[4])).point
            world.setEventVenues([
                EventVenue(id: "arena", kind: .arena, point: arena, seats: 15_000),
                EventVenue(id: "hall", kind: .exhibitionHall, point: hall, seats: 20_000),
            ])
        }
        world.setSpeed(.normal)
        return world
    }

    private func events(of world: GameWorld, days: Int) throws -> [DemandEvent] {
        var world = world
        var seen: [DemandEvent] = []
        for _ in 0..<days {
            try world.advance(ticks: 1_440)
            XCTAssertNil(world.demandEventProblem())
            for event in world.demandEvents!.events where !seen.contains(event) {
                seen.append(event)
            }
        }
        return seen
    }

    func testEventsAreHeldAtTheVenuesOfTheirKind() throws {
        let seen = try events(of: try world(), days: 90)
        XCTAssertTrue(seen.contains { $0.kind == .crowdSurge })
        XCTAssertTrue(seen.contains { $0.kind == .exhibition })
        for event in seen {
            switch event.kind {
            case .crowdSurge:
                XCTAssertEqual(event.station, ids[1], "\(event)")
                XCTAssertEqual(event.venue, "arena")
                XCTAssertNotNil(event.opens, "still in the evening (decision 730)")
            case .exhibition:
                XCTAssertEqual(event.station, ids[4], "\(event)")
                XCTAssertEqual(event.venue, "hall")
            case .festival:
                XCTFail("never drawn")
            }
        }
    }

    /// Without venues, the draws are the same as before decision 768: the
    /// same kinds, days and boosts, at stations drawn by traffic.
    func testWithoutVenuesTheDrawsAreAsBefore() throws {
        let plain = try events(of: try world(venues: false), days: 90)
        let held = try events(of: try world(), days: 90)
        XCTAssertTrue(plain.allSatisfy { $0.venue == nil })
        XCTAssertEqual(plain.map(\.kind), held.map(\.kind))
        XCTAssertEqual(plain.map(\.start), held.map(\.start))
        XCTAssertEqual(plain.map(\.boost), held.map(\.boost))
        XCTAssertNotEqual(plain.map(\.station), held.map(\.station))
    }

    /// The station nearest the venue that takes passengers holds it: on a
    /// map 256 m wide every station is in reach, and S0, with no demand,
    /// takes none.
    func testTheNearestStationThatTakesPassengersHoldsIt() throws {
        var world = try world(venues: false)
        world.setEventVenues([EventVenue(id: "far", kind: .stadium, point: PlanPoint(x: 16_000, y: 4_000), seats: 40_000)])
        let seen = try events(of: world, days: 60).filter { $0.kind == .crowdSurge }
        XCTAssertFalse(seen.isEmpty)
        XCTAssertTrue(seen.allSatisfy { $0.station == ids[5] && $0.venue == "far" }, "\(seen)")
    }

    func testVenuesAreKeptAsTheRulesSayAndBadOnesRefused() throws {
        var world = try world(venues: false)
        world.setEventVenues([
            EventVenue(id: "a", kind: .stadium, point: PlanPoint(x: 100, y: 100), seats: 10_000),
            EventVenue(id: "a", kind: .arena, point: PlanPoint(x: 200, y: 100), seats: 10_000),
            EventVenue(id: "out", kind: .arena, point: PlanPoint(x: -1, y: 100), seats: 10_000),
            EventVenue(id: "none", kind: .arena, point: PlanPoint(x: 300, y: 100), seats: 0),
            EventVenue(id: "", kind: .arena, point: PlanPoint(x: 300, y: 100), seats: 10),
        ])
        XCTAssertEqual(world.demandEvents?.venues.map(\.id), ["a"])
        XCTAssertEqual(world.demandEvents?.venues.first?.kind, .stadium)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
        // Kept across a new seed; none without events.
        world.setDemandEvents(seed: 7)
        XCTAssertEqual(world.demandEvents?.venues.map(\.id), ["a"])
        var off = try self.world(venues: false)
        off.setDemandEvents(seed: nil)
        off.setEventVenues([EventVenue(id: "a", kind: .stadium, point: PlanPoint(x: 100, y: 100), seats: 10)])
        XCTAssertNil(off.demandEvents)

        for bad in [
            EventVenue(id: "a", kind: .stadium, point: PlanPoint(x: 99_999, y: 100), seats: 10),
            EventVenue(id: "a", kind: .stadium, point: PlanPoint(x: 100, y: 100), seats: 300_000),
        ] {
            var broken = world
            broken.demandEvents!.venues = [bad]
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(broken)), "\(bad)")
        }
        var twice = world
        twice.demandEvents!.venues += twice.demandEvents!.venues
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(twice)))
        var named = world
        named.demandEvents!.events = [DemandEvent(kind: .crowdSurge, station: ids[0], announced: 0, start: 1, end: 2, boost: 600, venue: "")]
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(named)))
    }

    func testOnlyTheirKindsAreHeld() {
        XCTAssertTrue(EventVenueKind.stadium.holds(.crowdSurge))
        XCTAssertTrue(EventVenueKind.arena.holds(.crowdSurge))
        XCTAssertFalse(EventVenueKind.stadium.holds(.exhibition))
        XCTAssertTrue(EventVenueKind.exhibitionHall.holds(.exhibition))
        XCTAssertFalse(EventVenueKind.exhibitionHall.holds(.crowdSurge))
        XCTAssertFalse(EventVenueKind.allCases.contains { $0.holds(.festival) })
    }

    /// `v104-event-venues.json`: the six stations a day in, with an arena
    /// at S1 and an exhibition hall at S4, and a crowd surge at the arena.
    /// Written once by the version 104 build (`EVENT_VENUES_SAVE_NEW=1`); a
    /// save before has no venues and its events name none.
    func testVersionOneHundredFourKeepsTheVenues() throws {
        var world = try world()
        world.demandEvents!.events = [
            DemandEvent(kind: .crowdSurge, station: ids[1], announced: 0, start: 0, end: 2, boost: 700, opens: 1_140, closes: 1_320, venue: "arena"),
        ]
        try world.advance(ticks: 1)

        let url = SavedGameTests.fixtures.appendingPathComponent("v104-event-venues.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["EVENT_VENUES_SAVE_NEW"] != nil, SavedGame.currentVersion == 104 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 104)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.demandEvents?.venues.map(\.id), ["arena", "hall"])
        XCTAssertEqual(loaded.demandEvents?.events.map(\.venue), ["arena"])
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        try loaded.advance(ticks: 1_440 * 30)
        try world.advance(ticks: 1_440 * 30)
        XCTAssertEqual(loaded, world)

        // An event and a schedule with no venue are written without one.
        let plain = try JSONEncoder().encode(DemandEvent(kind: .crowdSurge, station: ids[2], announced: 0, start: 0, end: 1, boost: 700))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("venue"))
        let schedule = try JSONEncoder().encode(DemandEventSchedule(seed: 1, from: 0))
        XCTAssertFalse(String(decoding: schedule, as: UTF8.self).contains("venues"))
    }
}
