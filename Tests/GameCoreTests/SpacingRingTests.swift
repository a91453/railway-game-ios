import Foundation
@testable import GameCore
import XCTest

/// Decision 805: with traffic control off, trains of real runs that wait
/// for each other in a ring are found, named as a deadlock, and as each
/// minute begins one of each ring goes first.
///
/// The ring is decision 801's: `SaveFixtures/v107-depot-ladder-ring.json`
/// is the Taoyuan Airport MRT six minutes before three empty runs in Luzhu
/// depot waited for each other, as the rule before that decision had it
/// (``GameWorld/passesHeldTrains`` plays that rule here).
final class SpacingRingTests: XCTestCase {
    private static func world(before801: Bool = true) throws -> GameWorld {
        let data = try Data(contentsOf: SavedGameTests.fixtures.appendingPathComponent("v107-depot-ladder-ring.json"))
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        world.passesHeldTrains = before801
        world.setSpeed(.normal)
        return world
    }

    private static func rings(in world: GameWorld) -> [[TrainID]] {
        var ways: [TrainID: SpacingWay] = [:]
        return GameWorld.spacingRings(in: world.spacingStands(near: world.spacingIndex(), ways: &ways))
    }

    private static func stand(_ holds: [(Int, Int)], why: SpacingHold = .behind) -> [TrainID: (by: TrainID, why: SpacingHold)] {
        Dictionary(uniqueKeysWithValues: holds.map { (TrainID(rawValue: $0.0), (by: TrainID(rawValue: $0.1), why: why)) })
    }

    // MARK: - Finding rings

    func testARingIsEachHeldByTheNext() {
        // 6 for 13, 13 for 12, 12 for 6; 5 behind 6, and 8 behind 5; 20
        // behind 21, which is held by nobody.
        let rings = GameWorld.spacingRings(in: Self.stand([(6, 13), (13, 12), (12, 6), (5, 6), (8, 5), (20, 21)]))
        XCTAssertEqual(rings.map { $0.map(\.rawValue) }, [[6, 13, 12]])
    }

    func testTwoRingsComeInOrderOfTheirLowestTrain() {
        let rings = GameWorld.spacingRings(in: Self.stand([(9, 7), (7, 9), (3, 4), (4, 5), (5, 3), (2, 3)]))
        XCTAssertEqual(rings.map { $0.map(\.rawValue) }, [[3, 4, 5], [7, 9]])
    }

    func testTrainsBehindEachOtherInALineAreNoRing() {
        XCTAssertEqual(GameWorld.spacingRings(in: Self.stand([(1, 2), (2, 3), (3, 4)])).count, 0)
        XCTAssertEqual(GameWorld.spacingRings(in: [:]).count, 0)
    }

    // MARK: - The depot's ladder, by the rule before decision 801

    /// The ring forms as it did, is named as a deadlock while it stands,
    /// and is gone a minute later: no ring is seen two minutes running.
    /// (By the old rule trains still let held trains pass one after the
    /// other, in no ring, for up to 13 minutes: decision 801's to mend,
    /// not this one's.)
    func testOneOfARingGoesFirstWithinAMinute() throws {
        var world = try Self.world()
        XCTAssertFalse(world.isTrafficControlEnabled)
        var seen: [[TrainID]] = []
        var last: [[TrainID]] = []
        for _ in 0..<40 {
            try world.advance(ticks: 1)
            let minute = world.clock.now.seconds % GameTime.secondsPerDay / 60
            let rings = Self.rings(in: world)
            if !rings.isEmpty {
                seen.append(contentsOf: rings)
                // While it stands the map is told: every train of it, each
                // with the train that holds it.
                let named = Set(world.deadlockedTrains())
                XCTAssertTrue(named.isSuperset(of: rings.joined()), "at \(minute / 60):\(minute % 60)")
                let waits = world.routeWaits()
                XCTAssertEqual(Set(waits.map(\.train)), named)
                XCTAssertTrue(waits.allSatisfy { $0.isDeadlocked && named.contains($0.holder) })
            } else {
                XCTAssertEqual(world.deadlockedTrains(), [])
            }
            for ring in rings {
                XCTAssertFalse(last.contains(ring), "\(ring.map(\.rawValue)) still waits in a ring at \(minute / 60):\(minute % 60)")
            }
            last = rings
        }
        // The ring of decision 801: trains 6, 13 and 12, from 05:46.
        XCTAssertTrue(seen.contains([6, 13, 12].map(TrainID.init(rawValue:))), "rings seen: \(seen.map { $0.map(\.rawValue) })")
    }

    /// The morning's runs leave by the old rule too: by 08:00 none of the
    /// day's runs has been given up (26 were without this decision).
    func testTheMorningsRunsAreSentOutThroughTheRing() throws {
        var world = try Self.world()
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

    /// Moving the trains ten minutes at once leaves them where a minute at
    /// a time does, through the ring and its release.
    func testABatchEndsWhereMinutesDo() throws {
        var minutes = try Self.world()
        var batch = minutes
        try minutes.advance(ticks: 30)
        batch.setSpeed(.fast)
        try batch.advance(ticks: 3)
        batch.setSpeed(.normal)
        XCTAssertEqual(batch.clock.now, minutes.clock.now)
        XCTAssertEqual(batch.trains, minutes.trains)
    }

    /// Saved and loaded in the minute the ring stands, the world plays on
    /// as it would have: nothing of the ring or its release is kept.
    func testASaveInTheRingPlaysOnTheSame() throws {
        var world = try Self.world()
        var loadedInRing = false
        for _ in 0..<40 {
            try world.advance(ticks: 1)
            guard !Self.rings(in: world).isEmpty else { continue }
            loadedInRing = true
            var loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
            loaded.passesHeldTrains = true
            XCTAssertEqual(loaded, world)
            var on = world
            try on.advance(ticks: 5)
            try loaded.advance(ticks: 5)
            XCTAssertEqual(loaded.trains, on.trains)
            break
        }
        XCTAssertTrue(loadedInRing)
    }

    /// By the rule as it is (decision 801) the same morning has no ring,
    /// so nothing here changes it: no train's turn is waived.
    func testNoTurnIsWaivedWithoutARing() throws {
        var world = try Self.world(before801: false)
        for _ in 0..<40 {
            try world.advance(ticks: 1)
            XCTAssertEqual(Self.rings(in: world).count, 0)
            XCTAssertEqual(world.deadlockedTrains(), [])
            XCTAssertEqual(world.routeWaits().count, 0)
        }
    }
}
