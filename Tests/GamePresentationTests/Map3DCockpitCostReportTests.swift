import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// PERF_3D_COCKPIT (2026-10-30), on request: what the 3D map's screen
/// asks of the main actor at every tick while it follows a train from the
/// cab, on a save the owner sent (`COCKPIT_SAVE=<.alongtheline>`, with the
/// real-world data its command log names: `COCKPIT_LOG=<command-log.json>`;
/// the train whose name holds `COCKPIT_TRAIN`, the first moving one by
/// default; `COCKPIT_TICKS`, 300 by default). Each part is what
/// `Map3DPreviewScreen` and `Map3DTrainFeed` (in the app) work out when the
/// world changes, timed apart; the tick's own finish beside them.
@MainActor
final class Map3DCockpitCostReportTests: XCTestCase {
    func testWhatATickCostsTheCockpitOnTheOwnersSave() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["COCKPIT_SAVE"] else { throw XCTSkip("set COCKPIT_SAVE=<save file>") }
        let game = try HeadlessGame.load(Data(contentsOf: URL(fileURLWithPath: path)))
        if let log = environment["COCKPIT_LOG"] {
            let report = try JSONDecoder().decode(CommandLogReport.self, from: Data(contentsOf: URL(fileURLWithPath: log)))
            try game.install(report.startData, from: CommandLogReplay.realWorld)
        }
        let session = game.session
        let ticks = Int(environment["COCKPIT_TICKS"] ?? "") ?? 300
        let world = session.world
        print("stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count), speed \(world.clock.speed)")
        let named = environment["COCKPIT_TRAIN"]
        let train = try XCTUnwrap(world.trains.first { train in named.map { train.name.contains($0) } ?? false }
            ?? world.trains.first { $0.position != nil && $0.movement.rate > 0 } ?? world.trains.first { $0.position != nil })
        session.followTrain(train.id)
        session.setMap3DOpen(true)
        if session.world.clock.isPaused { session.togglePause() }
        session.setSpeed(.x10)
        print("following \(train.name), \(session.world.clock.speed), \(session.world.clock.speed.tenthsPerTick) tenths a tick")
        let clock = ContinuousClock()
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        var sums: [String: Double] = [:]
        var longest: [String: Double] = [:]
        func time(_ name: String, _ body: () -> Void) {
            let t = ms(clock.measure(body))
            sums[name, default: 0] += t
            longest[name] = max(longest[name] ?? 0, t)
        }
        var motion = TrainMotion()
        var realClock: RealTrainClock?
        var busClock: RealTrainClock?
        // What the app's scene key (`Map3DSceneKey`) and the buses' layer
        // are made of: each change starts the scene, or the buses, again.
        struct SceneParts: Equatable {
            let edges: Int, lastEdge: TrackEdgeID?, platforms: Int, buildings: Int, week: Int64
            let lines: Map3DLineBands.Signature, bought: Int, roads: Int
        }
        func parts(_ world: GameWorld) -> SceneParts {
            SceneParts(edges: world.network.edges.count, lastEdge: world.network.edges.last?.id, platforms: world.network.platforms.count,
                       buildings: world.placedBuildings.count, week: world.clock.now.seconds / (7 * GameTime.secondsPerDay),
                       lines: Map3DLineBands.Signature(world: world), bought: world.acquisitions.count { $0.kind == .railway },
                       roads: world.roads?.roadCellCount ?? 0)
        }
        var lastParts = parts(session.world)
        var lastBuses = Map3DBuses.Signature(world: session.world, palette: .standard, roads: session.busRoads)
        var changes: [String: Int] = [:]
        for index in 0..<ticks {
            guard let loop = session.beginLoopTick() else { break }
            let outcome = await loop.work()
            time("tick: finish (simulation, not the 3D map's)") { _ = session.finish(loop, with: outcome) }
            let world = session.world
            let at = Double(index) * 0.1
            let nowParts = parts(world)
            if nowParts != lastParts {
                for (name, changed) in [("edges", nowParts.edges != lastParts.edges), ("platforms", nowParts.platforms != lastParts.platforms),
                                        ("buildings", nowParts.buildings != lastParts.buildings), ("week", nowParts.week != lastParts.week),
                                        ("lines", nowParts.lines != lastParts.lines), ("bought", nowParts.bought != lastParts.bought),
                                        ("roads", nowParts.roads != lastParts.roads)] where changed {
                    changes["scene key: \(name)", default: 0] += 1
                }
                lastParts = nowParts
            }
            let nowBuses = Map3DBuses.Signature(world: world, palette: .standard, roads: session.busRoads)
            if nowBuses != lastBuses { changes["buses' signature", default: 0] += 1 }
            lastBuses = nowBuses
            // What the 2D map's screen (under the 3D one) and its HUD read
            // of the session at every change of the world: not the 3D
            // map's, timed to compare.
            time("2D/session: station master's advice") { _ = session.stationMasterAdvice }
            time("2D/session: situation alerts") { _ = session.situationAlerts }
            time("2D/session: next steps") { _ = session.nextSteps }
            time("2D/session: company rank") { _ = CompanyRank(world: world) }
            time("2D/session: traffic overlay") { _ = session.trafficOverlay }
            // Map3DPreviewScreen.body, at every change of the world.
            time("body: scene key, line bands' signature") { _ = Map3DLineBands.Signature(world: world) }
            time("body: scene key, roads counted (now)") { _ = world.roads?.roadCellCount ?? 0 }
            time("before: roads counted through allCells") { _ = world.roads?.allCells.count ?? 0 }
            time("body: scene key, the rest") {
                _ = world.network.edges.count
                _ = world.network.edges.last?.id
                _ = world.network.platforms.count
                _ = world.placedBuildings.count
                _ = world.acquisitions.count { $0.kind == .railway }
            }
            time("body: driver HUD") { _ = world.map3DDriverHUD(of: train.id, in: .traditionalChinese) }
            time("body: weather, light") {
                _ = Map3DWeather(MapWeather(world: world))
                _ = Map3DLighting(at: world.clock.now)
                _ = Map3DSignalTiming.Clock(world.clock)
            }
            // Map3DTrainFeed.update, when the trains change.
            time("feed: glide + heights") {
                motion = session.trainMotion(after: motion, at: at)
                _ = session.map3DTrainHeights()
            }
            time("feed: Activity") { _ = Map3DStreetLife.Activity(world: world) }
            time("feed: Labels") { _ = Map3DTrainLabels(world: world) }
            // At every change of the clock.
            time("feed: real trains' clock") { realClock = RealTrainClock(world: world, previous: realClock, time: at) }
            time("feed: buses' clock + signature") {
                busClock = RealTrainClock(world: world, previous: busClock, time: at)
                _ = Map3DBuses.Signature(world: world, palette: .standard, roads: session.busRoads)
            }
        }
        print("== \(ticks) ticks at \(session.world.clock.speed) ==")
        print("changes over the ticks: \(changes.isEmpty ? "none" : changes.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))")
        for (name, sum) in sums.sorted(by: { $0.value > $1.value }) {
            print("\(name): mean \(String(format: "%.3f", sum / Double(ticks))) ms, longest \(String(format: "%.3f", longest[name] ?? 0)) ms")
        }
    }
}
