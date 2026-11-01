import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 521's fourth sequel: how long a long traced stretch's preview
/// takes on a large network (the frame-time bench's Taipei, decision 421,
/// with its lines laid), a trace that joins track already laid and a
/// double one. Only on request: `TRACE_COST_REPORT=<lines>` (20 for the
/// decision's numbers), in a release build.
@MainActor
final class TraceCostReportTests: XCTestCase {
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre

    func testReportTheTracedPreviewsCost() async throws {
        guard let lines = ProcessInfo.processInfo.environment["TRACE_COST_REPORT"].flatMap(Int.init) else {
            throw XCTSkip("Set TRACE_COST_REPORT=<lines>.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TraceCostReport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.loadRealWorldData { Map3DOpenEveryStartTests.data }.value
        let opened = await launcher.openFrameTimeBench(lines: lines)
        let session = try XCTUnwrap(opened)
        print("TRACE_COST world: \(session.world.network.nodes.count) nodes, \(session.world.network.edges.count) edges, \(session.world.lines.count) lines")

        if ProcessInfo.processInfo.environment["TRACE_COST_PROBE"] != nil {
            print("TRACE_COST bounds \(session.world.bounds)")
            for name in ["基隆", "七堵", "汐科", "汐止", "南港", "松山", "臺北", "萬華", "板橋", "浮洲", "樹林", "山佳", "鶯歌"] {
                guard let station = try? BundledRealData.station(name, in: "tra_sched"),
                      let point = try? BundledRealData.point(station.coordinate, in: session.world) else { continue }
                let near = session.world.network.nodes.contains { abs($0.position.x - point.x) < 300 * Int64(WorldCoordinate.unitsPerMetre) && abs($0.position.y - point.y) < 300 * Int64(WorldCoordinate.unitsPerMetre) }
                print("TRACE_COST \(name) \(point) inside=\(session.world.bounds.contains(point)) track=\(near)")
            }
            return
        }
        // Pairs of stations along the real lines, from one to the other.
        let pairs: [(String, String, String, Bool)] = [
            ("tra_sched", "松山", "浮洲", false),
            ("tra_sched", "浮洲", "松山", false),
            ("tra_sched", "松山", "臺北", false),
            ("tra_sched", "松山", "臺北", true),
            ("tra_sched", "板橋", "浮洲", true),
            ("tra_sched", "萬華", "浮洲", true),
        ]
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        for (system, a, b, double) in pairs {
            guard let first = try? BundledRealData.station(a, in: system), let second = try? BundledRealData.station(b, in: system),
                  let from = try? BundledRealData.point(first.coordinate, in: session.world),
                  let to = try? BundledRealData.point(second.coordinate, in: session.world)
            else { print("TRACE_COST \(a)→\(b): no station"); continue }
            session.clearNetworkDraft()
            session.networkBuildsDouble = double
            session.networkDoubleChosen = true
            session.tapNetwork(at: from, reach: reach)
            session.tapNetwork(at: to, reach: reach)
            guard let start = session.networkStart, let end = session.networkEnd else {
                print("TRACE_COST \(a)→\(b): no ends start=\(String(describing: session.networkStart)) end=\(String(describing: session.networkEnd)) tool=\(session.tool) msg=\(session.message?.text ?? "")")
                continue
            }
            var times: [Double] = []
            var preview: NetworkPreview?
            for _ in 0..<5 {
                let clock = ContinuousClock.now
                preview = session.tracePreview(from: start, to: end)?.0
                let elapsed = ContinuousClock.now - clock
                times.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1_000)
            }
            times.sort()
            let planClock = ContinuousClock.now
            let plan = session.traceAlong(from: start, to: end)
            let planTime = ContinuousClock.now - planClock
            print("TRACE_COST   traceAlong alone \(planTime)")
            if ProcessInfo.processInfo.environment["TRACE_COST_PARTS"] != nil,
               let a = session.world.position(of: start, height: 0), let b = session.world.position(of: end, height: 0) {
                var clock = ContinuousClock.now
                let way = session.tracedWay(from: a, to: b, reach: GameSession.traceReach(NetworkBuilding.minimumSpacing * 2))
                print("TRACE_COST   tracedWay \(ContinuousClock.now - clock) \(way?.count ?? -1) points")
                if let way {
                    let smooth = WorldPath(way).smoothed()
                    clock = ContinuousClock.now
                    let near = TraceOverlap.Edge.near(smooth, in: session.world)
                    print("TRACE_COST   Edge.near \(ContinuousClock.now - clock) \(near.count) edges")
                    clock = ContinuousClock.now
                    let runs = TraceOverlap.runs(along: smooth, edges: near)
                    print("TRACE_COST   runs \(ContinuousClock.now - clock) \(runs.count) runs")
                }
                clock = ContinuousClock.now
                _ = session.tracePlan(from: start, to: end)
                print("TRACE_COST   tracePlan \(ContinuousClock.now - clock)")
                if let plan {
                    let built = Array(plan.stretches.prefix(plan.buildable))
                    clock = ContinuousClock.now
                    let decided = session.tracedDouble(built)
                    print("TRACE_COST   tracedDouble \(ContinuousClock.now - clock) \(decided)")
                    clock = ContinuousClock.now
                    _ = session.tracedSaleLine(from: start, to: end)
                    print("TRACE_COST   tracedSaleLine \(ContinuousClock.now - clock)")
                    if let traced = plan.built {
                        clock = ContinuousClock.now
                        let cleared = session.world.placedBuildings(clearedIn: traced)
                        print("TRACE_COST   placedBuildings(clearedIn:) \(ContinuousClock.now - clock) \(cleared.count)")
                    }
                    if decided.double, plan.existing.isEmpty, !built.isEmpty {
                        clock = ContinuousClock.now
                        let reused = session.tracedDoublePlan(built, from: start, to: end, reachesEnd: !plan.stopped, traced: plan)
                        print("TRACE_COST   tracedDoublePlan reusing \(ContinuousClock.now - clock) \((try? reused.get()) != nil)")
                        clock = ContinuousClock.now
                        _ = session.tracedDoublePlan(built, from: start, to: end, reachesEnd: !plan.stopped)
                        print("TRACE_COST   tracedDoublePlan afresh \(ContinuousClock.now - clock)")
                    }
                }
            }
            print(String(
                format: "TRACE_COST %@→%@ double=%@: median %.0f ms (min %.0f, max %.0f); %d stretches, %d buildable, %d existing runs, %d m, cost %@, problem %@",
                a, b, "\(preview?.tracedDouble ?? false || !(preview?.crossovers.isEmpty ?? true))", times[2], times[0], times[4],
                plan?.stretches.count ?? 0, plan?.buildable ?? 0, plan?.existing.count ?? 0,
                Int((preview?.length ?? 0) / Int64(WorldCoordinate.unitsPerMetre)),
                "\(preview?.cost.map { "\($0.amount)" } ?? "nil")", preview?.problem ?? preview?.traceNote ?? "nil"
            ))
        }
    }
}
