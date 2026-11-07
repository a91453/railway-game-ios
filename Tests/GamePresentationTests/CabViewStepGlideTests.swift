import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 379 (continued four, CABVIEW-3): the game loop's step driven
/// as the loop drives it (``GameSession/runLoopStep(ticks:taken:)``), the
/// map taking a glide as MapView and Map3DPreviewScreen do, on
/// ``GameSession/glideKey`` (review P3 a and b of 379 續三), and the loop's
/// stop ending a step's glide (P3 d).
@MainActor
final class CabViewStepGlideTests: XCTestCase {
    private func session(rate: Int64 = 600, offset: Int64 = 1_024, east: Int64 = 64_512) throws -> (GameSession, TrainID) {
        var world = try GamePresentationTests.makeWorld(width: 65_536, height: 4_096, balance: 1_000_000, speed: .x10)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 2_048))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: east, y: 2_048))
        let edge = try world.buildTrackEdge(from: west, to: end)
        let train = try world.purchaseTrain(named: "T1").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: offset))
        try world.setTrainMovementRate(train, to: rate)
        return (GameSession(world: world, language: .traditionalChinese), train)
    }

    /// The map as the app has it: a glide taken whenever ``GameSession/glideKey``
    /// changes and the step's glide does not go on.
    @MainActor private struct Map {
        var key: GameSession.GlideKey
        var motion: TrainMotion
        var shown: [(time: Double, motion: TrainMotion)] = []

        init(_ session: GameSession, at time: Double) {
            key = session.glideKey
            motion = session.trainMotion(after: TrainMotion(world: session.world, time: time), at: time)
            shown = [(time, motion)]
        }

        mutating func look(_ session: GameSession, at time: Double) {
            let next = session.glideKey
            guard next != key else { return }
            key = next
            guard !next.goesOn else { return }
            motion = session.trainMotion(after: motion, at: time)
            shown.append((time, motion))
        }
    }

    /// 119.1, the bought Kaohsiung light rail followed on the 3D map at
    /// 10×: a step's first four ticks within some 0.3 s, its last 2.2 s
    /// later (traffic control read), a rest of 0.1 s. Driven through the
    /// loop's own step, the followed head moves at every frame at 60 a
    /// second.
    func testTheFollowedHeadMovesThroughEveryFrameOfTheLoopsSlowStep() async throws {
        let (session, train) = try session()
        session.setMap3DOpen(true)
        session.followTrain(train)
        var now = 100.0
        var map = Map(session, at: now)
        for _ in 0..<4 {
            var index = 0
            let stepped = await session.runLoopStep(ticks: 5) {
                now += index < 4 ? 0.06 : 2.2
                index += 1
                map.look(session, at: now)
            }
            XCTAssertTrue(stepped)
            XCTAssertFalse(session.glidesOnThroughTheStep, "nothing goes on once the step is done")
            now += 0.1
        }
        XCTAssertEqual(map.shown.count, 5, "one glide as the map opened, then one a step")
        // From the second step's glide (the first began as the map opened,
        // not a step before), frame by frame to the last step's end.
        var standing = 0, frames = 0
        let glides = Array(map.shown.dropFirst(2)) + [(now, map.motion)]
        var last = try XCTUnwrap(glides[0].motion.head(of: train, at: glides[0].time)).x
        for (glide, end) in zip(glides.dropLast(), glides.dropFirst()) {
            var at = glide.time + 1.0 / 60
            while at < end.time {
                let x = try XCTUnwrap(glide.motion.head(of: train, at: at)).x
                if x <= last { standing += 1 }
                last = x
                frames += 1
                at += 1.0 / 60
            }
        }
        XCTAssertGreaterThan(frames, 300)
        XCTAssertEqual(standing, 0, "frames of \(frames) the followed head stood still within a step")
    }

    /// Review P3 b: a train that comes to its track's end within a step
    /// moves at the first ticks and not at the last. The map taking a
    /// glide on the trains alone kept the step before's glide; on
    /// ``GameSession/glideKey`` it glides to where the train stopped.
    func testAStepWhoseLastTickMovesNoTrainIsStillGlidedTo() async throws {
        // 4 units a tick at 10×, 10 units short of the track's end.
        let (session, train) = try session(rate: 250, offset: 8_182, east: 9_216)
        var now = 10.0
        var map = Map(session, at: now)
        var onTheTrains = map.motion
        var trains = session.world.trains
        var movedAt: [Int] = []
        var index = 0
        _ = await session.runLoopStep(ticks: 5) {
            now += 0.1
            if session.world.trains != trains {
                movedAt.append(index)
                trains = session.world.trains
                onTheTrains = session.trainMotion(after: onTheTrains, at: now)
            }
            index += 1
            map.look(session, at: now)
        }
        XCTAssertFalse(movedAt.isEmpty)
        XCTAssertFalse(movedAt.contains(4), "the last tick moved no train: \(movedAt)")
        let end = try XCTUnwrap(session.world.train(id: train)?.position)
        XCTAssertEqual(map.motion.samples[train]?.position, end, "glided to where it stopped")
        XCTAssertNotEqual(onTheTrains.samples[train]?.position, end, "on the trains alone, the step before's glide stayed")
    }

    /// Review P3 d: a loop stopped within a step leaves no step going on.
    func testStoppingTheLoopEndsTheStepsGlide() async throws {
        let (session, _) = try session()
        let tick = try XCTUnwrap(session.beginLoopTick().map { begun in
            var tick = begun
            tick.goesOnInTheStep()
            return tick
        })
        let outcome = await tick.work()
        XCTAssertTrue(session.finish(tick, with: outcome))
        XCTAssertTrue(session.glidesOnThroughTheStep)
        XCTAssertTrue(session.glideKey.goesOn)
        session.stopGameLoop()
        XCTAssertFalse(session.glidesOnThroughTheStep)
    }
}
