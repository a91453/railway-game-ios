import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

// TEMPORARY probe (TYMC-REBUILD-4), not committed.
final class ZZProbeTests: XCTestCase {
    func testProbe() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["PROBE_FROM"] else { throw XCTSkip("PROBE_FROM") }
        var world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: URL(fileURLWithPath: path))).world
        world.setSpeed(.fast)
        GameWorld.followProbe = Int(env["FOLLOW_PROBE"] ?? "") ?? 0
        let until = Int64(env["PROBE_UNTIL"] ?? "0") ?? 0
        let every = Int64(env["PROBE_EVERY"] ?? "0") ?? 0
        func name(_ id: StationID) -> String { world.station(id: id)?.name ?? "?" }
        func hm(_ s: Int64) -> String { String(format: "%d %02d:%02d", s / 86_400, s % 86_400 / 3_600, s % 3_600 / 60) }
        func dump() {
            var memo = GameWorld.DirectionMemo()
            let stuck = world.deadlock(memo: &memo)
            var text = "PROBE \(hm(world.clock.now.seconds)) stuck \(stuck.count)\n"
            let ids = env["PROBE_ALL"] != nil ? world.trains.map(\.id) : stuck.keys.sorted()
            for id in ids {
                guard let train = world.train(id: id) else { continue }
                let edge: String = if case .onEdge(let t, let o)? = train.position { "\(t.edge)\(t.direction == .forward ? "+" : "-")@\(o)" } else { "-" }
                let at = world.stationsStoppedAt(by: id).map(name).joined(separator: "/")
                let wait = world.awaitedRoute(of: id, memo: &memo)
                let res = Set(train.reservation.compactMap { r -> String? in if case .span(let s) = r { "\(s.edge)" } else { nil } }).sorted().joined(separator: ",")
                text += "  \(train.name) \(edge) [\(at)] dead \(train.isDeadheading) exec \(String(describing: train.execution).prefix(45)) waitsFor \(wait.map { world.train(id: $0.holder)?.name ?? "?" } ?? "-")\n    move \(train.movement.cursor)/\(train.movement.edges.count): \(train.movement.edges.map { "\($0)" }.joined(separator: ",").replacingOccurrences(of: "edge", with: ""))\n    res \(res.replacingOccurrences(of: "edge", with: ""))\n    tt \(train.timetable.map { "\(name($0.station))@\(hm($0.departure.seconds))" }.joined(separator: " ").prefix(160))\n"
            }
            print(text)
        }
        if env["PROBE_NET"] != nil {
            for s in world.stations where ["環北站", "老街溪站", "高鐵桃園站", "青埔機廠", "興南站", "領航站", "桃園體育園區站"].contains(s.name) {
                print("PROBE station \(s.name) \(s.id) platforms \(world.network.platforms(of: s.id).map { "\($0.edge)[\($0.start)-\($0.end)]" })")
            }
            for raw in (Int(env["PROBE_E0"] ?? "0") ?? 0)...(Int(env["PROBE_E1"] ?? "0") ?? 0) {
                if let e = world.network.edge(.edge(raw)) { print("PROBE edge \(raw): \(e.from) -> \(e.to) len \(e.length)") }
            }
            for line in world.lines { print("PROBE line \(line.name) stops \(line.stops.map(name)) depots \(line.depots.map(name)) routes \(line.routePreferences.map { "\(name(line.stops[$0.from]))>\(name(line.stops[$0.to])):\($0.platform.edge)" })") }
        }
        while world.clock.now.seconds < until {
            try world.advance(ticks: 1)
            if every > 0, world.clock.now.seconds % every == 0 { dump() }
        }
        dump()
    }
}
