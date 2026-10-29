import Foundation
@testable import GameCore
import XCTest

/// Scratch probe (BH9): a long single track without passing loops, one
/// platform per station, a line over all of it with `trains` trains under
/// traffic control; the ticks' cost at the fastest speed.
final class HangProbeTests: XCTestCase {
    static func singleTrack(stations count: Int, trains: Int) throws -> GameWorld {
        let span: Int64 = 8_192
        var world = try GameWorld(bounds: WorldBounds(width: span * Int64(count + 2), height: 12_288), economy: GameEconomy(balance: 1_000_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal))
        for index in 0...count { _ = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + span * Int64(index), y: 4_096)) }
        for edge in 1...count { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        var stations: [StationID] = []
        for index in 0..<count {
            let station = try world.buildStation(named: "S\(index)", at: PlanPoint(x: 1_024 + span * Int64(index) + 4_096, y: 8_192))
            try world.addTrackPlatform(station.id, on: .edge(index + 1), from: 3_072, to: 5_120)
            stations.append(station.id)
        }
        let line = try world.createLine(named: "L", stops: stations).id
        for index in 0..<trains {
            let edge = 1 + index * count / trains
            let traversal = index % 2 == 0 ? SingleTrackMeet.forward(edge) : SingleTrackMeet.backward(edge)
            let id = try SingleTrackMeet.stand(&world, edge: traversal, offset: index % 2 == 0 ? 5_120 : 3_072)
            try world.assignTrain(id, to: line)
        }
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: trains, offPeak: trains, low: trains))
        try world.setTrafficControl(true)
        return world
    }

    func testProbe() throws {
        guard ProcessInfo.processInfo.environment["HANG_PROBE"] != nil else { throw XCTSkip("scratch") }
        let clock = ContinuousClock()
        let cases = (ProcessInfo.processInfo.environment["HANG_PROBE"] ?? "").split(separator: ",").map { $0.split(separator: "x").compactMap { Int($0) } }
        for pair in cases where pair.count == 2 {
            let (count, trains) = (pair[0], pair[1])
            var world = try Self.singleTrack(stations: count, trains: trains)
            world.setSpeed(.fast)
            var longest = 0.0, total = 0.0, deadlockTicks = 0
            for tick in 0..<144 {
                let spent = try clock.measure { try world.advance(ticks: 1) }
                let ms = Double(spent.components.seconds) * 1_000 + Double(spent.components.attoseconds) / 1e15
                longest = max(longest, ms)
                total += ms
                if !world.deadlockedTrains().isEmpty { deadlockTicks += 1 }
                if ms > 500 { print(String(format: "[HANG]   tick %d %@: %.0f ms", tick, "\(world.clock.now.seconds)", ms)) }
            }
            let alerts = clock.measure { _ = world.situationAlerts() }
            let alertsMs = Double(alerts.components.seconds) * 1_000 + Double(alerts.components.attoseconds) / 1e15
            print(String(format: "[HANG] stations %d trains %d: mean %.1f ms, longest %.1f ms, ticks in deadlock %d/144, deadlocked at end %d, situationAlerts %.1f ms", count, trains, total / 144, longest, deadlockTicks, world.deadlockedTrains().count, alertsMs))
        }
    }
}
