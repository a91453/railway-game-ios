import Foundation
@testable import GameCore
import XCTest

/// Decision 801: with traffic control off, a train leaving its platform
/// lets a faster train behind it pass first (decision 228) only when that
/// one is coming: not when it stands held by a third train. On the Taoyuan
/// Airport MRT bought before decision 605, the simple rules, traffic
/// control turned off after a day (HEALTH-134 §3), three empty runs in
/// Luzhu depot waited in a ring from the second day's 05:46: train 6,
/// leaving its siding, for train 13 behind it on the depot's ladder; train
/// 13 for train 12 coming in; train 12 for train 6, the nearer of the two
/// to the ladder. Decision 228 keeps two trains from waiting for each
/// other, not three. Every train behind them stayed in the depot and 318
/// of the day's 333 runs were not sent out.
///
/// `SaveFixtures/v107-depot-ladder-ring.json` is that world at 05:40, six
/// minutes before, as the build before this decision played it there.
final class DepotLadderSpacingTests: XCTestCase {
    private static func world() throws -> GameWorld {
        let data = try Data(contentsOf: SavedGameTests.fixtures.appendingPathComponent("v107-depot-ladder-ring.json"))
        return try JSONDecoder().decode(SavedGame.self, from: data).world
    }

    /// The trains on their way that wait in a ring: each held, with no way
    /// on at all, by the next (``GameWorld/heldUp(_:within:near:)``).
    private static func ring(in world: GameWorld) -> [TrainID] {
        var holder: [TrainID: TrainID] = [:]
        for train in world.trains {
            guard case .travellingToStop? = train.execution, let held = world.heldUp(train, within: 1_000 * WorldCoordinate.unitsPerMetre), held.clear == 0 else { continue }
            holder[train.id] = held.by
        }
        for start in holder.keys.sorted() {
            var seen: [TrainID] = [start]
            var at = start
            while let next = holder[at] {
                if next == start { return seen }
                if seen.contains(next) { break }
                seen.append(next)
                at = next
            }
        }
        return []
    }

    /// Half an hour on, minute by minute: no three trains wait in a ring,
    /// and no train on its way stands ten minutes where it stood.
    func testTheEmptyRunsInTheDepotDoNotWaitInARing() throws {
        var world = try Self.world()
        XCTAssertFalse(world.isTrafficControlEnabled)
        world.setSpeed(.normal)
        var stood: [TrainID: (position: TrainPosition, minutes: Int)] = [:]
        var longest = 0
        for _ in 0..<30 {
            try world.advance(ticks: 1)
            let minute = world.clock.now.seconds % GameTime.secondsPerDay / 60
            XCTAssertEqual(Self.ring(in: world).map(\.rawValue), [], "waiting in a ring at \(minute / 60):\(minute % 60)")
            for train in world.trains {
                guard case .travellingToStop? = train.execution, let position = train.position else {
                    stood[train.id] = nil
                    continue
                }
                let minutes = stood[train.id].flatMap { $0.position == position ? $0.minutes + 1 : nil } ?? 0
                stood[train.id] = (position, minutes)
                longest = max(longest, minutes)
            }
        }
        XCTAssertLessThan(longest, 10, "a train on its way stood \(longest) minutes")
    }

    /// The morning's runs leave: by 08:00 none of the day's runs has been
    /// given up (318 of 333 were, the first the 05:56 from Chang Gung).
    func testTheMorningsRunsAreSentOut() throws {
        var world = try Self.world()
        world.setSpeed(.normal)
        try world.advance(ticks: 140)
        let line = try XCTUnwrap(world.lines.first { $0.hasRuns })
        let day = world.clock.now.seconds / GameTime.secondsPerDay
        let now = world.clock.now.seconds
        let missed = line.runs.indices.count { index in
            let run = line.runs[index]
            return run.runs(onDay: day) && run.start(onDay: day) + LineRun.latestDispatch < now && (line.runDays[index] ?? -1) < day
        }
        XCTAssertEqual(missed, 0, "runs not sent out by 08:00")
    }
}
