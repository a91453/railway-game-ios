import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 379 (continued, CABVIEW-2): 119.1, the bought Kaohsiung
/// light rail followed on the 3D map at 10×. A step of the game loop is
/// five ticks; four came within some 0.3 s and the last, which reads
/// traffic control, some 2 s later. Each tick's glide lasted the time
/// since the one before, so the cab view moved for 0.3 s and stood still
/// for 2.2 s. The map now takes a step's glide at its last tick, over
/// the whole step, and on the 3D map following a train traffic control
/// is read once a game minute.
@MainActor
final class CabViewStepGlideTests: XCTestCase {
    private func session() throws -> (GameSession, TrainID) {
        var world = try GamePresentationTests.makeWorld(width: 65_536, height: 4_096, balance: 1_000_000, speed: .x10)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 2_048))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 64_512, y: 2_048))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let train = try world.purchaseTrain(named: "T1").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: 1_024))
        try world.setTrainMovementRate(train, to: 600)
        return (GameSession(world: world, language: .traditionalChinese), train)
    }

    /// The followed head, drawn at 60 frames a second as the map would
    /// draw it, steps of five ticks timed as on the phone: 0.06 s for each
    /// of the first four, 2.2 s for the last, a rest of 0.1 s.
    func testTheFollowedHeadMovesThroughEveryFrameOfASlowStep() async throws {
        let (session, train) = try session()
        session.setMap3DOpen(true)
        session.followTrain(train)
        var now = 100.0
        // The map as it opens, then as it takes a glide (MapView,
        // Map3DPreviewScreen: on ``GameSession/glideKey``).
        var motion = session.trainMotion(after: TrainMotion(world: session.world, time: now), at: now)
        var key = session.glideKey
        var shown: [(time: Double, motion: TrainMotion)] = [(now, motion)]
        for _ in 0..<4 {
            var index = 0
            let stepped = await session.runLoopStep(ticks: 5) {
                now += index < 4 ? 0.06 : 2.2
                index += 1
                let next = session.glideKey
                guard next != key else { return }
                key = next
                guard !next.waits else { return }
                motion = session.trainMotion(after: motion, at: now)
                shown.append((now, motion))
            }
            XCTAssertTrue(stepped)
            XCTAssertFalse(session.glideWaitsForStepEnd, "the glide waits no more once the step is done")
            now += 0.1
        }
        shown.append((now, motion))
        // From the second step's glide (the first one's began as the map
        // opened, not a step before), frame by frame to the last step's end.
        var standing = 0, frames = 0
        var last = try XCTUnwrap(shown[2].motion.head(of: train, at: shown[2].time)).x
        for (glide, end) in zip(shown.dropFirst(2).dropLast(), shown.dropFirst(3)) {
            var at = glide.time + 1.0 / 60
            while at < end.time {
                let x = try XCTUnwrap(glide.motion.head(of: train, at: at)).x
                if x <= last { standing += 1}
                last = x
                frames += 1
                at += 1.0 / 60
            }
        }
        XCTAssertGreaterThan(frames, 300)
        XCTAssertEqual(standing, 0, "frames of \(frames) the followed head stood still within a step")
    }

    /// On the 3D map following a train, traffic control is read once a
    /// game minute rather than at every step, and nothing reads it on the
    /// main actor in between.
    func testFollowedOnThe3DMapTrafficIsReadOnceAGameMinute() async throws {
        let (session, train) = try session()
        session.setMap3DOpen(true)
        session.followTrain(train)
        session.selectTrain(train)
        XCTAssertTrue(session.readsTrafficSparsely)
        // The game as it opens is read here, once.
        _ = session.trafficOverlay
        XCTAssertEqual(session.trafficReadOnTheMainActor, 1)
        var readings = 0
        var lastRead = session.trafficTickRead.map { "\($0)" }
        // 24 steps of five ticks at 10×: two game minutes.
        for _ in 0..<24 {
            _ = await session.runLoopStep(ticks: 5) {
                let read = session.trafficTickRead.map { "\($0)" }
                if read != lastRead { readings += 1 }
                lastRead = read
                // What the follow bar reads in between.
                _ = session.routeWaitText(of: train)
                _ = session.trafficOverlay
            }
        }
        XCTAssertLessThanOrEqual(readings, 3, "once a game minute, not at each of 24 steps")
        XCTAssertGreaterThanOrEqual(readings, 2)
        XCTAssertEqual(session.trafficReadOnTheMainActor, 1)
        XCTAssertNil(session.trafficReadTask, "nor off the main actor between the ticks' readings")
        // On the 2D map, at every step.
        session.setMap3DOpen(false)
        XCTAssertFalse(session.readsTrafficSparsely)
        readings = 0
        for _ in 0..<4 {
            _ = await session.runLoopStep(ticks: 5) {
                let read = session.trafficMemo?.revision
                if read == session.worldRevision { readings += 1 }
            }
        }
        XCTAssertEqual(readings, 4)
    }
}
