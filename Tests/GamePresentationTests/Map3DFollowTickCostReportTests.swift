import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 485, on request (`FOLLOW_REPORT=<ticks>`, `FOLLOW_LINE=HSR`
/// or a bought network's code, Jiji's by default): what each tick costs
/// the main actor while the 3D map follows a train, at 1× and 10×, as the
/// 3D feed worked it out before (its own glide and heights) and as it does
/// now (taken from the tick, worked out off the main actor).
@MainActor
final class Map3DFollowTickCostReportTests: XCTestCase {
    func testWhatATickCostsTheFollowedMapAtEachSpeed() async throws {
        guard let value = ProcessInfo.processInfo.environment["FOLLOW_REPORT"] else {
            throw XCTSkip("set FOLLOW_REPORT=<ticks>")
        }
        let ticks = Int(value) ?? 100
        let network = ProcessInfo.processInfo.environment["FOLLOW_LINE"] ?? "JIJI"
        let session: GameSession
        if network == "HSR" {
            session = try MapFrameCostReportTests.highSpeedSession()
        } else {
            session = try RealLineAcquisitionTests.game(round: network, side: 1 << 21)
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == network })
            XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)))
        }
        session.setSpeed(.fast)
        // To 08:00 of the next day.
        while session.world.clock.now.seconds % GameTime.secondsPerDay < 8 * 3600 || session.world.clock.now.seconds < GameTime.secondsPerDay {
            session.advance(ticks: 1)
        }
        let moving = try XCTUnwrap(session.world.trains.first { $0.position != nil && $0.movement.rate > 0 } ?? session.world.trains.first { $0.position != nil })
        session.followTrain(moving.id)
        session.setMap3DOpen(true)
        print("trains: \(session.world.trains.count), following \(moving.name)")
        let clock = ContinuousClock()
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        for speed in [GameSpeed.x1, .x10] {
            session.setSpeed(speed)
            var before = TrainMotion(world: session.world, time: 0)
            var underneath = session.trainMotion(after: TrainMotion(), at: 0)
            var followed = underneath
            var sums: [String: Double] = [:]
            var longest: [String: Double] = [:]
            func time(_ name: String, _ body: () -> Void) {
                let t = ms(clock.measure(body))
                sums[name, default: 0] += t
                longest[name] = max(longest[name] ?? 0, t)
            }
            for index in 0..<ticks {
                let loop = try XCTUnwrap(session.beginLoopTick())
                let outcome = await loop.work()
                time("finish") { _ = session.finish(loop, with: outcome) }
                let world = session.world
                let at = Double(index) * 0.1
                time("before: glide + heights") {
                    before = TrainMotion(world: world, previous: before, time: at)
                    _ = Map3DTrains.Heights(world: world)
                }
                time("now: 2D glide") { underneath = session.trainMotion(after: underneath, at: at) }
                time("now: 3D glide + heights") {
                    followed = session.trainMotion(after: followed, at: at)
                    _ = session.map3DTrainHeights()
                }
                time("Activity") { _ = Map3DStreetLife.Activity(world: world) }
                time("Labels") { _ = Map3DTrainLabels(world: world) }
            }
            print("== \(speed) ==")
            for (name, sum) in sums.sorted(by: { $0.value > $1.value }) {
                print(String(format: "%@: mean %.3f ms, longest %.3f ms", name, sum / Double(ticks), longest[name] ?? 0))
            }
        }
    }
}
