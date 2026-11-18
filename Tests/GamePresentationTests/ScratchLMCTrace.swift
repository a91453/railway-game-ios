import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

@MainActor
final class ScratchLMCTrace: XCTestCase {
    func testTrace() throws {
        guard ProcessInfo.processInfo.environment["LMC_TRACE"] != nil else { return }
        let simple = ProcessInfo.processInfo.environment["LMC_REAL"] == nil
        var world = try ProcessInfo.processInfo.environment["LMC_TW"].map { try TimetableCheckupWorlds.taiwan($0, rules: simple ? .simple : .realistic) } ?? TimetableCheckupWorlds.hongKong([ProcessInfo.processInfo.environment["LMC_LINE"] ?? "EAL_LMC"], rules: simple ? .simple : .realistic)
        world.setSpeed(.normal)
        GameWorld.debugApproach = true
        let from = Int64(ProcessInfo.processInfo.environment["LMC_FROM"] ?? "0")!
        let to = Int64(ProcessInfo.processInfo.environment["LMC_TO"] ?? "200000")!
        func t(_ s: Int64) -> String { let d = s % 86400; return String(format: "d%d %02d:%02d:%02d", s / 86400, d / 3600, d % 3600 / 60, d % 60) }
        func name(_ s: StationID) -> String { world.station(id: s)?.name ?? "?" }
        var last: [TrainID: String] = [:]
        let line = world.lines.first { $0.hasRuns }!
        print("LINE stops \(line.stops.map(name)) trains \(line.assignedTrains.count)")
        for n in world.network.nodes { print("NODE \(n.id) \(n.position.x) \(n.position.y)") }
        for e in world.network.edges { print("EDGE \(e.id) \(e.from) \(e.to) \(e.length)") }
        for e in world.network.edges { for pl in world.network.platforms(on: e.id) { print("PLAT \(e.id) \(pl.station) \(pl.start) \(pl.end)") } }
        for st in world.stations { print("STATION \(st.id) \(st.name) depot=\(st.isDepot)") }
        while world.clock.now.seconds < to {
            try world.advance(ticks: 1)
            let now = world.clock.now.seconds
            guard now >= from else { continue }
            if ProcessInfo.processInfo.environment["LMC_WAITS"] != nil {
                for w in world.routeWaits() { print("\(t(now)) WAIT T\(w.train.rawValue) held by T\(w.holder.rawValue) contested \(w.contested.prefix(4))") }
            }
            for train in world.trains {
                let tt = train.timetable.map { "\(name($0.station)) \(t($0.arrival.seconds))-\(t($0.departure.seconds))" }.joined(separator: " > ")
                let ex = train.execution.map { "\($0)" } ?? "nil"
                let env = world.authorityEnvelopes(of: train)
                let auth = world.authority(of: train).map { "\($0.left)" } ?? "whole"
                let s = "len=\(env.length) lim=\(world.approachLimit(of: train, env).map { "\($0)" } ?? "-") auth=\(auth) rate=\(train.movement.rate) res=\(train.reservation.count) tt[\(tt)] ex=\(ex) dh=\(train.isDeadheading) aside=\(train.isStandingAside) edge=\(train.position.map { "\($0)" } ?? "-")"
                if ProcessInfo.processInfo.environment["LMC_LIM"] != nil {
                    if let l = world.approachLimit(of: train, env) { print("\(t(now)) LIM T\(train.id.rawValue) len=\(env.length) lim=\(l) to=\(train.execution.map { name(train.timetable[$0.stop].station) } ?? "") tt=\(train.timetable.map { name($0.station) })") }
                    continue
                }
                let pos = ProcessInfo.processInfo.environment["LMC_POS"] != nil
                if pos || last[train.id] != s.components(separatedBy: " edge=")[0] {
                    print("\(t(now)) T\(train.id.rawValue) \(s)")
                    last[train.id] = s.components(separatedBy: " edge=")[0]
                }
            }
        }
    }
}
