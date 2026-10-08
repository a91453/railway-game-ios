import Foundation
@testable import GameCore
import XCTest

/// Demand events (item 4): exhibitions and crowd surges drawn from the
/// world's seed, announced ahead, raising a station's demand while they run.
final class DemandEventTests: XCTestCase {
    private let ids = (1...6).map { StationID(rawValue: $0) }

    private func world(seed: UInt32? = 42) throws -> GameWorld {
        var world = try makeWorld(width: 16_384, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 14)
        try track.build(in: &world)
        for (index, x) in [1, 3, 5, 7, 9, 11].enumerated() {
            try track.buildStation(named: "S\(index)", beside: x, at: 1, in: &world)
        }
        let line = try world.createLine(named: "L", stops: ids).id
        try world.setLineServiceWindow(line, to: .allDay)
        for (index, id) in ids.enumerated() {
            try world.setStationDemand(id, to: StationDemand(kind: index % 2 == 0 ? .residential : .office, dailyTrips: Int64(500 * (index + 1))))
        }
        world.setDemandEvents(seed: seed)
        world.setSpeed(.normal)
        return world
    }

    func testTheHashIsTheReferencesFNV1a() {
        XCTAssertEqual(DemandEventSchedule(seed: 42, from: 0).hash("first"), 1_130_935_913)
        XCTAssertEqual(DemandEventSchedule(seed: 0, from: 0).hash(""), 1_441_645_609)
        XCTAssertEqual(DemandEventSchedule(seed: 7, from: 0).hash("event.0.kind"), 1_078_441_504)
        // The first draw comes 3 to 7 days in.
        let first = DemandEventSchedule(seed: 42, from: 10).nextDraw
        XCTAssertTrue((13...17).contains(first))
    }

    func testEventsAreDrawnAnnouncedAndEndOnTheirDays() throws {
        var world = try world()
        var seen: [DemandEvent] = []
        for _ in 0..<60 {
            try world.advance(ticks: 1_440)
            for event in world.demandEvents!.events where !seen.contains(event) {
                seen.append(event)
            }
            let today = world.clock.now.seconds / GameTime.secondsPerDay
            XCTAssertTrue(world.demandEvents!.events.allSatisfy { $0.announced <= today && today <= $0.end })
            XCTAssertNil(world.demandEventProblem())
        }
        XCTAssertGreaterThanOrEqual(seen.count, 4, "About one every 8 to 12 days")
        for event in seen {
            XCTAssertTrue(event.isValid)
            XCTAssertTrue((2...5).contains(event.start - event.announced))
            switch event.kind {
            case .exhibition:
                XCTAssertTrue((3...7).contains(event.end - event.start))
                XCTAssertTrue((200...500).contains(event.boost))
            case .crowdSurge:
                XCTAssertTrue((1...2).contains(event.end - event.start))
                XCTAssertTrue((500...1_000).contains(event.boost))
            case .festival:
                XCTFail("Festivals are a scenario's (decision 90), never drawn")
            }
        }
        // The same seed gives the same events; another seed others.
        var again = try self.world()
        try again.advance(ticks: 1_440 * 60)
        XCTAssertEqual(again, world)
        var other = try self.world(seed: 43)
        try other.advance(ticks: 1_440 * 60)
        XCTAssertNotEqual(other.demandEvents?.events, world.demandEvents?.events)
    }

    func testARunningEventRaisesItsStationsDemand() throws {
        var world = try world()
        let station = ids[2]
        let before = world.dailyDemand(from: station)
        let base = world.dailyDemand(from: ids[0]).first { $0.destination == station }!.trips
        world.demandEvents!.events = [DemandEvent(kind: .exhibition, station: station, announced: 0, start: 0, end: 3, boost: 500)]
        XCTAssertEqual(world.demandMultiplier(at: station), 1_500)
        XCTAssertEqual(world.demandMultiplier(at: ids[0]), 1_000)
        XCTAssertEqual(world.activeDemandEvents(at: station).count, 1)
        // Its own trips are 1.5 times as many...
        XCTAssertEqual(world.dailyDemand(from: station).reduce(0) { $0 + $1.trips },
                       (before.reduce(0) { $0 + $1.trips } * 1_500 + 500) / 1_000)
        // ...and it draws more of the others'.
        XCTAssertGreaterThan(world.dailyDemand(from: ids[0]).first { $0.destination == station }!.trips, base)
        // An event yet to start changes nothing.
        world.demandEvents!.events = [DemandEvent(kind: .exhibition, station: station, announced: 0, start: 1, end: 3, boost: 500)]
        XCTAssertEqual(world.demandMultiplier(at: station), 1_000)
    }

    func testBatchesMatchMinuteStepsAndSavesContinue() throws {
        var batched = try world()
        try batched.advance(ticks: 1_440 * 12)
        var stepped = batched
        try batched.advance(ticks: 1_440 * 3 + 7)
        for _ in 0..<(1_440 * 3 + 7) { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched))
        XCTAssertEqual(loaded, batched)
        try loaded.advance(ticks: 1_440 * 10)
        try batched.advance(ticks: 1_440 * 10)
        XCTAssertEqual(loaded, batched)
        for station in batched.stations {
            let ledger = batched.passengerLedger(of: station.id)
            XCTAssertEqual(ledger.released, ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned)
        }
    }

    func testOffByDefaultAndBadEventsAreRefused() throws {
        var world = try world(seed: nil)
        XCTAssertNil(world.demandEvents)
        let plain = try JSONEncoder().encode(world)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("demandEvents"))
        world.setDemandEvents(seed: 9)
        XCTAssertEqual(world.demandEvents?.seed, 9)
        world.demandEvents!.events = [DemandEvent(kind: .crowdSurge, station: ids[0], announced: 0, start: 1, end: 2, boost: 600)]
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
        for bad in [
            DemandEvent(kind: .crowdSurge, station: StationID(rawValue: 99), announced: 0, start: 1, end: 2, boost: 600),
            DemandEvent(kind: .crowdSurge, station: ids[0], announced: 0, start: 2, end: 2, boost: 600),
            DemandEvent(kind: .crowdSurge, station: ids[0], announced: 0, start: 1, end: 2, boost: 0),
            DemandEvent(kind: .crowdSurge, station: ids[0], announced: 5, start: 6, end: 7, boost: 600),
            DemandEvent(kind: .crowdSurge, station: ids[0], announced: .min, start: .min, end: .max, boost: 600),
        ] {
            var broken = world
            broken.demandEvents!.events = [bad]
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(broken)), "\(bad)")
        }
        // A count of draws no game reaches, which the next draw would
        // overflow.
        var counted = world
        counted.demandEvents!.draws = .max
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(counted)))
        world.setDemandEvents(seed: nil)
        XCTAssertNil(world.demandEvents)
    }

    /// A save at the most draws a save may count loads, and so does every
    /// save after it: the draws stop there rather than count one more than
    /// a save may hold.
    func testTheLastDrawASaveMayCountIsTheLast() throws {
        var world = try world()
        world.demandEvents!.draws = 1 << 40
        world.demandEvents!.nextDraw = 0
        world = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        try world.advance(ticks: 1_440 * 2)
        XCTAssertEqual(world.demandEvents?.draws, 1 << 40)
        XCTAssertNil(world.demandEventProblem())
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }
}
