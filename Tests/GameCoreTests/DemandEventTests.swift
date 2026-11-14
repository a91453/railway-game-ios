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
                // Decision 730: in the evening, opening at 17:00 to 19:00
                // and lasting 2 to 3½ hours, on the half hour.
                let opens = try XCTUnwrap(event.opens), closes = try XCTUnwrap(event.closes)
                XCTAssertTrue(stride(from: 1_020, through: 1_140, by: 30).contains(opens), "\(event)")
                XCTAssertTrue(stride(from: 120, through: 210, by: 30).contains(closes - opens), "\(event)")
            case .festival:
                XCTFail("Festivals are a scenario's (decision 90), never drawn")
            }
            if event.kind == .exhibition {
                XCTAssertNil(event.opens, "an exhibition runs all day")
                XCTAssertNil(event.closes)
            }
        }
        XCTAssertTrue(seen.contains { $0.kind == .crowdSurge }, "the seed draws a crowd surge in 60 days")
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

    /// Decision 730: an event with hours keeps the day's trips to and
    /// from its station, but the travellers it brings come in a wave half
    /// an hour before it opens and leave in one half an hour after it
    /// closes.
    func testAnEventsCrowdComesBeforeItOpensAndLeavesAfterItCloses() throws {
        for tidal in [false, true] {
            var allDay = try world()
            allDay.setTidalDemand(tidal)
            let station = ids[2], other = ids[0]
            allDay.demandEvents!.events = [DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 0, end: 1, boost: 800)]
            var timed = allDay
            // 19:00 to 22:00: the crowd comes around 18:30 and leaves
            // around 22:30.
            timed.demandEvents!.events = [DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 0, end: 1, boost: 800,
                                                      opens: 1_140, closes: 1_320)]
            XCTAssertEqual(timed.demandMultiplier(at: station), 1_800, "the day's boost is the same")
            // With tidal demand an hour is released most at its middle,
            // otherwise at its start.
            let coming = tidal ? [18] : [18, 19], leaving = tidal ? [22] : [22, 23]
            for (from, to, wave) in [(station, other, leaving), (other, station, coming)] {
                let before = allDay.hourlyDemand(from: from, to: to)
                let after = timed.hourlyDemand(from: from, to: to)
                XCTAssertEqual(timed.dailyDemand(from: from, to: to), allDay.dailyDemand(from: from, to: to))
                XCTAssertEqual(after.reduce(0, +), before.reduce(0, +), "the day's trips are the same")
                let trips = after.reduce(0, +)
                let share = GameWorld.eventShare(of: trips, boost: 800)
                XCTAssertEqual(share, trips - (trips * 1_000 + 900) / 1_800)
                XCTAssertGreaterThan(share, 0)
                let inWave = wave.reduce(0) { $0 + after[$1] }
                let wasInWave = wave.reduce(0) { $0 + before[$1] }
                XCTAssertGreaterThan(inWave, wasInWave + share / 2, "tidal \(tidal), \(from) to \(to): \(before) → \(after)")
                let elsewhere = (0..<24).filter { !wave.contains($0) }
                XCTAssertLessThan(elsewhere.reduce(0) { $0 + after[$1] }, elsewhere.reduce(0) { $0 + before[$1] })
            }
            // Between two stations without it, nothing moves.
            XCTAssertEqual(timed.hourlyDemand(from: ids[1], to: ids[3]), allDay.hourlyDemand(from: ids[1], to: ids[3]))
        }
    }

    /// Decision 730: over the day the passengers released from the event's
    /// station are as many as before, more of them in the hour after it
    /// closes.
    func testTheCrowdIsReleasedInTheHourAfterItCloses() throws {
        var allDay = try world()
        let station = ids[2]
        allDay.demandEvents!.events = [DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 0, end: 1, boost: 1_000)]
        var timed = allDay
        timed.demandEvents!.events = [DemandEvent(kind: .crowdSurge, station: station, announced: 0, start: 0, end: 1, boost: 1_000,
                                                  opens: 1_140, closes: 1_320)]
        // Up to 22:00, then the hour to 23:00, then the rest of the day.
        var released: [[Int64]] = [[], []]
        for (index, world) in [allDay, timed].enumerated() {
            var running = world
            for minutes: Int64 in [1_320, 60, 60] {
                try running.advance(ticks: Int(minutes))
                released[index].append(running.passengerLedger(of: station).released)
            }
        }
        XCTAssertEqual(released[1][2], released[0][2], "the same over the day")
        XCTAssertGreaterThan(released[1][1] - released[1][0], 2 * (released[0][1] - released[0][0]), "\(released)")
        XCTAssertLessThan(released[1][0], released[0][0], "fewer before it closes")
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
            // Decision 730: hours come both or neither, on the half hour,
            // opening by 02:00 and closing by 22:30.
            DemandEvent(kind: .crowdSurge, station: ids[0], announced: 0, start: 1, end: 2, boost: 600, opens: 1_140),
            DemandEvent(kind: .crowdSurge, station: ids[0], announced: 0, start: 1, end: 2, boost: 600, closes: 1_320),
            DemandEvent(kind: .crowdSurge, station: ids[0], announced: 0, start: 1, end: 2, boost: 600, opens: 1_150, closes: 1_320),
            DemandEvent(kind: .crowdSurge, station: ids[0], announced: 0, start: 1, end: 2, boost: 600, opens: 1_140, closes: 1_140),
            DemandEvent(kind: .crowdSurge, station: ids[0], announced: 0, start: 1, end: 2, boost: 600, opens: 90, closes: 300),
            DemandEvent(kind: .crowdSurge, station: ids[0], announced: 0, start: 1, end: 2, boost: 600, opens: 1_200, closes: 1_380),
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

    /// `v96-demand-hours.json`: the six stations a minute in, a crowd
    /// surge at S2 from 19:00 to 22:00 today and tomorrow and an
    /// exhibition at S4 all day: the event's `"opens"` and `"closes"`.
    /// Written once by the version 96 build (`DEMAND_HOURS_SAVE_NEW=1`);
    /// an event of an earlier save has neither and runs all day.
    func testVersionNinetySixKeepsTheEventsHours() throws {
        var world = try world()
        world.demandEvents!.events = [
            DemandEvent(kind: .crowdSurge, station: ids[2], announced: 0, start: 0, end: 2, boost: 700, opens: 1_140, closes: 1_320),
            DemandEvent(kind: .exhibition, station: ids[4], announced: 0, start: 0, end: 4, boost: 300),
        ]
        try world.advance(ticks: 1)

        let url = SavedGameTests.fixtures.appendingPathComponent("v96-demand-hours.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["DEMAND_HOURS_SAVE_NEW"] != nil, SavedGame.currentVersion == 96 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 96)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.demandEvents?.events.map(\.opens), [1_140, nil])
        XCTAssertEqual(loaded.demandEvents?.events.map(\.closes), [1_320, nil])
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        // Run on through the evening, as the world does.
        try loaded.advance(ticks: 1_440)
        try world.advance(ticks: 1_440)
        XCTAssertEqual(loaded, world)

        // An event without hours, as every save before 96 wrote it, runs
        // all day, and is written without them.
        let plain = try JSONEncoder().encode(DemandEvent(kind: .crowdSurge, station: ids[2], announced: 0, start: 0, end: 1, boost: 700))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("opens"))
        let read = try JSONDecoder().decode(DemandEvent.self, from: plain)
        XCTAssertNil(read.opens)
        XCTAssertNil(read.closes)
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
