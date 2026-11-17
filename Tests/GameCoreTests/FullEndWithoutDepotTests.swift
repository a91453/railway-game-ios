import Foundation
@testable import GameCore
import XCTest

/// Decision 816: a line with runs and no depot, with more trains ending
/// the night at one end than it has tracks.
///
/// Both saves are Hong Kong's map with one line of the MTR bought as the
/// game opens, under the realistic rules, late on its first night. The
/// runs dropped for lateness that day were not as many each way, so the
/// trains do not end the night as the timetable leaves them.
///
/// `SaveFixtures/v107-full-end-south-island.json`, 00:20: seven of the
/// South Island Line's ten trains end at Admiralty, which has five
/// tracks, and three at South Horizons, which has five too. Before
/// decision 816 trains 2 and 7 stood at Ocean Park and Wong Chuk Hang
/// from 00:34 until the first runs of the morning.
///
/// `SaveFixtures/v107-full-end-tung-chung.json`, 00:30: six of the Tung
/// Chung Line's twelve trains end at Tung Chung, which has five tracks,
/// and two at Hong Kong. Before decision 816 train 2 stood at Sunny Bay
/// from 01:09 until morning, and the two trains bound for the night at
/// Sunny Bay and Tsing Yi behind it.
final class FullEndWithoutDepotTests: XCTestCase {
    private static func world(_ name: String) throws -> GameWorld {
        let data = try Data(contentsOf: SavedGameTests.fixtures.appendingPathComponent(name))
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        world.setSpeed(.normal)
        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertTrue(world.blockSections)
        XCTAssertEqual(world.lines.count, 1)
        XCTAssertEqual(world.lines.first?.depots, [])
        return world
    }

    /// `world` played for `minutes`: the most minutes running with a
    /// train in a deadlock, and the minutes with one in all.
    private static func play(_ world: inout GameWorld, minutes: Int) throws -> (longest: Int, total: Int) {
        var longest = 0, running = 0, total = 0
        for _ in 0..<minutes {
            try world.advance(ticks: 1)
            running = world.deadlockedTrains().isEmpty ? 0 : running + 1
            longest = max(longest, running)
            if running > 0 { total += 1 }
        }
        return (longest, total)
    }

    /// How many trains without a service stand at each station, by name.
    private static func standing(in world: GameWorld) -> [String: Int] {
        var count: [String: Int] = [:]
        for train in world.trains where train.execution == nil {
            for station in world.stationsStoppedAt(by: train.id).prefix(1) {
                count[world.station(id: station)?.name ?? "", default: 0] += 1
            }
        }
        return count
    }

    func testTheSouthIslandLinesTrainsEndTheNightFiveAtEachEnd() throws {
        var world = try Self.world("v107-full-end-south-island.json")
        // To 01:40. A train waits a minute or two for the one sent away
        // to clear the points; none waits longer.
        let waits = try Self.play(&world, minutes: 80)
        XCTAssertLessThanOrEqual(waits.longest, 2)
        XCTAssertLessThanOrEqual(waits.total, 4)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(Self.standing(in: world), ["金鐘": 5, "海怡半島": 5])
        // Nothing for the map to call stuck: no train waits for a route.
        XCTAssertEqual(world.routeWaits().map(\.train), [])
        XCTAssertEqual(world.heldDepartures().keys.sorted(), [])
    }

    func testTheTungChungLinesLastTrainsReachWhereTheyStandOvernight() throws {
        var world = try Self.world("v107-full-end-tung-chung.json")
        // To 02:30.
        let waits = try Self.play(&world, minutes: 120)
        XCTAssertLessThanOrEqual(waits.longest, 2)
        XCTAssertLessThanOrEqual(waits.total, 4)
        XCTAssertEqual(world.deadlockedTrains(), [])
        // One of Tung Chung's ran empty to Hong Kong; the trains between
        // stand where the first runs of the morning start.
        XCTAssertEqual(Self.standing(in: world), ["東涌": 5, "香港": 3, "九龍": 1, "奧運": 1, "欣澳": 1, "青衣": 1])
        // Nothing for the map to call stuck: no train waits for a route.
        XCTAssertEqual(world.routeWaits().map(\.train), [])
        XCTAssertEqual(world.heldDepartures().keys.sorted(), [])
    }

    /// The trains were sent to a free berth of the other end, not to the
    /// nearest one, where a train stood.
    func testAnEmptyRunBetweenEndsTakesAFreeBerth() throws {
        var world = try Self.world("v107-full-end-south-island.json")
        var sent: Train?
        for _ in 0..<40 where sent == nil {
            try world.advance(ticks: 1)
            sent = world.trains.first { $0.isDeadheading && $0.execution != nil }
        }
        let train = try XCTUnwrap(sent)
        XCTAssertEqual(train.timetable.count, 2)
        let end = try XCTUnwrap(train.timetable.last?.station)
        XCTAssertEqual(world.station(id: end)?.name, "海怡半島")
        XCTAssertEqual(world.pullOutBerths(of: train, leaving: 0, to: end).map { !$0.isEmpty }, true)
    }
}
