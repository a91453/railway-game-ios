// HEALTH-146: the two performance questions REVIEW-L34 left (P3-3, P3-4).
// Not part of the package: copy it into Tests/GamePresentationTests/,
// build in release with -enable-testing, and run
//   HEALTH146_PROBE=heights .build/release/GamePresentationTests-test-runner GamePresentationTests.Health146ProbeTests
//   HEALTH146_PROBE=dawn [DEPOT_RETURN_SIMPLE=1] .build/release/GamePresentationTests-test-runner GamePresentationTests.Health146ProbeTests
import Foundation
import XCTest
@testable import GameCore
@testable import GamePresentation

@MainActor
final class Health146ProbeTests: XCTestCase {
    private func ms(_ since: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - since.uptimeNanoseconds) / 1_000_000
    }

    private func say(_ text: String) {
        FileHandle.standardError.write(Data("HEALTH146 \(text)\n".utf8))
    }

    /// P3-3: what `GameSession.heights`' didSet costs (decision 943's
    /// `groundJoining`, which reads every block beside the world's ground
    /// from the file twice).
    func testHeights() throws {
        guard ProcessInfo.processInfo.environment["HEALTH146_PROBE"] == "heights" else { throw XCTSkip("HEALTH146_PROBE=heights") }
        let resources = BundledRealData.directory.deletingLastPathComponent()
        var start = DispatchTime.now()
        let heights = try HeightGrid(data: Data(contentsOf: resources.appendingPathComponent("RealWorld/taiwan_heights.dat")))
        say("heights file read: \(String(format: "%.1f", ms(start))) ms")
        for (name, id, side) in [("tymc", "tymc:A", Int64(1) << 22), ("wenhu", "trtc:BR", Int64(1) << 21)] {
            start = DispatchTime.now()
            guard let world = try? DepotReturnReportTests.bought(id, side: side) else { say("\(name): not bought"); continue }
            say("\(name): bought in \(String(format: "%.0f", ms(start))) ms, ground blocks \(world.ground.blocks.count)")
            var times: [Double] = []
            var joined = 0
            for _ in 0..<5 {
                start = DispatchTime.now()
                joined = world.groundJoining(heights).count
                times.append(ms(start))
            }
            // A world that kept ground from an earlier heights file
            // (decision 943): every block 6 m higher, so every block
            // beside it is joined and set.
            var raised = world
            var ground = Ground()
            ground.add(world.ground.sortedBlocks.compactMap { GroundBlock(block: $0.block, heights: $0.heights.map { $0 &+ 96 }) })
            raised.ground = ground
            start = DispatchTime.now()
            let raisedJoining = raised.groundJoining(heights)
            let joinTime = ms(start)
            start = DispatchTime.now()
            try raised.setGround(raisedJoining)
            let setTime = ms(start)
            say("\(name): groundJoining \(times.map { String(format: "%.1f", $0) }.joined(separator: " / ")) ms, \(joined) joined; earlier-file ground: \(String(format: "%.1f", joinTime)) ms, \(raisedJoining.count) joined, setGround \(String(format: "%.1f", setTime)) ms")
        }
    }

    /// P3-4: what decision 954's `dawnRunsKept` (and the empty-run search
    /// it makes when no train of the line is in a depot) costs a tick on
    /// the Taoyuan Airport MRT, against the whole tick, hour by hour.
    func testDawn() throws {
        guard ProcessInfo.processInfo.environment["HEALTH146_PROBE"] == "dawn" else { throw XCTSkip("HEALTH146_PROBE=dawn") }
        var world = try DepotReturnReportTests.bought("tymc:A", side: 1 << 22)
        world.setSpeed(.normal)
        let begin = world.clock.now.seconds
        let end = begin + 51 * 3_600
        var tickMs: [Int64: (count: Int, total: Double, most: Double)] = [:]
        var dawnMs: [Int64: (calls: Int, kept: Int, total: Double, most: Double)] = [:]
        var candidatesMs: [Int64: Double] = [:]
        let lines = world.lines.filter { $0.hasRuns && !$0.depots.isEmpty }
        while world.clock.now.seconds < end {
            let hour = world.clock.now.seconds / 3_600
            var start = DispatchTime.now()
            try world.advance(ticks: 1)
            let tick = ms(start)
            tickMs[hour, default: (0, 0, 0)].count += 1
            tickMs[hour]!.total += tick
            tickMs[hour]!.most = max(tickMs[hour]!.most, tick)
            for line in lines {
                guard let first = line.stops.first, let last = line.stops.last else { continue }
                var memo = GameWorld.DispatchMemo()
                start = DispatchTime.now()
                _ = world.runDepotEntryCandidates(of: line, memo: &memo)
                candidatesMs[hour, default: 0] += ms(start)
                for end in [first, last] {
                    guard let index = world.trains.firstIndex(where: { train in
                        line.trains.contains(train.id) && train.execution == nil && train.placement != nil
                            && world.stationsStoppedAt(by: train.id).first == end
                    }) else { continue }
                    var fresh = GameWorld.DispatchMemo()
                    start = DispatchTime.now()
                    let kept = world.dawnRunsKept(of: line, at: end, for: world.trains[index], memo: &fresh)
                    let took = ms(start)
                    dawnMs[hour, default: (0, 0, 0, 0)].calls += 1
                    if kept > 0 { dawnMs[hour]!.kept += 1 }
                    dawnMs[hour]!.total += took
                    dawnMs[hour]!.most = max(dawnMs[hour]!.most, took)
                }
            }
        }
        for hour in tickMs.keys.sorted() {
            let t = tickMs[hour]!, d = dawnMs[hour] ?? (0, 0, 0, 0)
            say(String(
                format: "day %lld %02lld:00 ticks %d tick avg %.2f ms max %.1f ms | candidates %.2f ms/tick | dawnRunsKept calls %d kept>0 %d avg %.3f ms max %.2f ms",
                hour / 24, hour % 24, t.count, t.total / Double(t.count), t.most, (candidatesMs[hour] ?? 0) / Double(t.count),
                d.calls, d.kept, d.calls == 0 ? 0 : d.total / Double(d.calls), d.most
            ))
        }
    }
}
