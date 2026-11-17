import Foundation
@testable import GameCore
import XCTest

/// Decision 808's second part: the last service of the night reaches the
/// airport terminals.
///
/// `SaveFixtures/v107-night-terminal-berths.json` is the Taoyuan Airport
/// MRT bought as it was before decision 605 under the realistic rules, at
/// 00:10 of its second day. Train 5, the last service (Taipei 23:38), is
/// on its way to Kengkou, Airport Terminal 1 and Terminal 2. Two trains
/// between runs stand on berths of Terminal 1 and train 20 ends its run
/// on the third at 00:24; Luzhu depot is full, and the way to Qingpu's
/// sidings is by the berth of Terminal 2 where train 1 stands between
/// runs. Before decision 808 only train 20 was in a service's way, train
/// 1 waited for Luzhu, and train 5 stood at Kengkou until the first
/// trains of the morning, 05:38. Now, with nothing else to do for train
/// 5, train 1 runs empty to Qingpu, train 20 after it, and train 5 goes
/// on two minutes late.
final class NightTerminalBerthTests: XCTestCase {
    override func setUp() { // PROBE-D2 (temporary)
        GameWorld.probeNoA2 = ProcessInfo.processInfo.environment["PROBE_NO_A2"] != nil // PROBE-D2 (temporary)
        GameWorld.probeNoB = ProcessInfo.processInfo.environment["PROBE_NO_B"] != nil // PROBE-D2 (temporary)
        GameWorld.probeNoC = ProcessInfo.processInfo.environment["PROBE_NO_C"] != nil // PROBE-D2 (temporary)
        GameWorld.probeLog = true // PROBE-D2 (temporary)
    } // PROBE-D2 (temporary)
    private static func world() throws -> GameWorld {
        let data = try Data(contentsOf: SavedGameTests.fixtures.appendingPathComponent("v107-night-terminal-berths.json"))
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        world.setSpeed(.normal)
        return world
    }

    func testTheLastServiceReachesBothTerminals() throws {
        var world = try Self.world()
        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertTrue(world.blockSections)
        let last = TrainID(rawValue: 5)
        let calls = try XCTUnwrap(world.train(id: last)).timetable.map(\.station)
        XCTAssertEqual(world.train(id: last)?.execution, .travellingToStop(calls.count - 4, cycle: 0))
        var waited = 0
        var longest = 0
        var running = 0
        var minutes: [GameTime] = []
        for _ in 0..<40 {
            try world.advance(ticks: 1)
            let stuck = world.deadlockedTrains()
            if stuck.contains(last) { waited += 1 }
            if !stuck.isEmpty { minutes.append(world.clock.now) }
            // The waits of a minute as a train comes in on one that has
            // just ended its run are still there (decision 805's fourth
            // case), and the one here is two: none lasts longer.
            running = stuck.isEmpty ? 0 : running + 1
            longest = max(longest, running)
        }
        XCTAssertLessThanOrEqual(waited, 2)
        XCTAssertLessThanOrEqual(longest, 2)
        print("PROBE-D2 minutes \(minutes.map { "\($0.seconds % 86_400 / 60)" })") // PROBE-D2 (temporary)
        // 00:50: its run has ended at Terminal 2, and the two that stood
        // in its way are in Qingpu depot.
        XCTAssertNil(world.train(id: last)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: last), [try XCTUnwrap(calls.last)])
        let line = try XCTUnwrap(world.lines.first { $0.trains.contains(last) })
        for id in [1, 20] {
            let train = try XCTUnwrap(world.train(id: TrainID(rawValue: id)))
            XCTAssertTrue(world.isInDepot(train, of: line), "train \(id)")
        }
        XCTAssertEqual(world.deadlockedTrains(), [])
    }
}
