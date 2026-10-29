import GameCore
@testable import GamePresentation
import XCTest

/// Decision 485: following a train in the 3D map at 10×, the trains'
/// glide and body heights are worked out with the tick off the main actor,
/// and the 2D map under the 3D one shares the glide, so a tick no longer
/// costs the main thread tens of ms for each.
@MainActor
final class Map3DFollowTickTests: XCTestCase {
    private func session() throws -> GameSession {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .x10)
        let track = TestLine(tiles: 7, row: 1)
        try track.build(in: &world)
        let alpha = try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let gamma = try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let main = try world.createLine(named: "Main", stops: [alpha, gamma]).id
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: track.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.assignTrain(train.id, to: main)
        return GameSession(world: world)
    }

    private func assertSame(_ heights: Map3DTrains.Heights, _ expected: Map3DTrains.Heights, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(heights.bodies, expected.bodies, message, file: file, line: line)
        XCTAssertEqual(heights.types, expected.types, message, file: file, line: line)
    }

    func testTheTickWorksOutTheHeightsWhileThe3DMapShows() async throws {
        let session = try session()
        session.setMap3DOpen(true)
        var moved = 0
        for tick in 1...100 {
            let before = session.world.trains
            let loop = try XCTUnwrap(session.beginLoopTick())
            let outcome = await loop.work()
            XCTAssertTrue(session.finish(loop, with: outcome))
            guard session.world.trains != before else { continue }
            moved += 1
            let memo = try XCTUnwrap(session.trainHeightsMemo, "tick \(tick)")
            XCTAssertEqual(memo.revision, session.worldRevision)
            assertSame(session.map3DTrainHeights(), Map3DTrains.Heights(world: session.world), "tick \(tick)")
        }
        XCTAssertGreaterThan(moved, 50)
    }

    func testTheTickLeavesTheHeightsAloneWithoutThe3DMap() async throws {
        let session = try session()
        for _ in 1...20 {
            let loop = try XCTUnwrap(session.beginLoopTick())
            let outcome = await loop.work()
            XCTAssertTrue(session.finish(loop, with: outcome))
        }
        XCTAssertNil(session.trainHeightsMemo)
        // Asked for, worked out here once for the world as it is.
        assertSame(session.map3DTrainHeights(), Map3DTrains.Heights(world: session.world), "")
        XCTAssertEqual(session.trainHeightsMemo?.revision, session.worldRevision)
    }

    /// Both maps take the glide after a tick: the second gets the first's.
    func testTheSecondMapTakesTheGlideTheFirstTook() async throws {
        let session = try session()
        session.setMap3DOpen(true)
        var underneath = session.trainMotion(after: TrainMotion(), at: 1)
        var followed = session.trainMotion(after: TrainMotion(), at: 1)
        for tick in 1...50 {
            let loop = try XCTUnwrap(session.beginLoopTick())
            XCTAssertNotNil(loop.glide)
            let outcome = await loop.work()
            XCTAssertTrue(session.finish(loop, with: outcome))
            let time = 1 + Double(tick) / 10
            underneath = session.trainMotion(after: underneath, at: time)
            XCTAssertNil(session.glideMemo)
            followed = session.trainMotion(after: followed, at: time)
            XCTAssertEqual(followed.source, session.worldRevision)
            XCTAssertEqual(followed.time, underneath.time)
            XCTAssertEqual(followed.runs.map(\.lag), underneath.runs.map(\.lag), "tick \(tick)")
            for progress in [0, 0.5, 1.0] {
                XCTAssertEqual(followed.runs.first?.head(at: progress)?.point, underneath.runs.first?.head(at: progress)?.point)
            }
        }
    }
}
