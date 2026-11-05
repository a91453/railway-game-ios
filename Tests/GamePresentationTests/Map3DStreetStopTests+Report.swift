import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 596's numbers on the real-world Taipei map
/// (``Map3DFrameCostReportTests/taipeiScene(bands:)``): the stop lines and
/// crossings found, the trips, and a frame's street life without the
/// signals and with them. Only on request: `MAP3D_FRAME_REPORT=1`.
final class Map3DStreetStopReportTests: XCTestCase {
    func testTheTaipeiStreets() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        var start = Date()
        let scene = try Map3DFrameCostReportTests.taipeiScene()
        print("scene built in \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
        let life = scene.streetLife
        let stopped = life.lanes.filter { !$0.stops.isEmpty }
        let mostStops = life.lanes.map(\.stops.count).max() ?? 0
        let crossed = life.spots.filter { !$0.crossings.isEmpty }
        print("lanes: \(life.lanes.count), with stop lines: \(stopped.count), stop lines: \(life.lanes.reduce(0) { $0 + $1.stops.count }), most on one lane: \(mostStops)")
        print("pavements: \(life.spots.filter { $0.kind == .sidewalk }.count), crossing a road at signals: \(crossed.count), crossings: \(crossed.reduce(0) { $0 + $1.crossings.count })")
        // The trips (worked out with the scene): how long, how many
        // vehicles, any that would not end within its lap (it would
        // vanish where it stands), and what they hold.
        var slots = 0, overruns = 0, laps: [Double] = [], bytes = 0
        for schedule in life.lanes.flatMap(\.schedules) {
            slots += schedule.count
            laps.append(schedule.way.lap)
            overruns += zip(schedule.ends, schedule.entries).filter { $0.0 - $0.1 > schedule.way.lap }.count
            bytes += schedule.count * 16 + schedule.first.count * 4 + schedule.stood.count * MemoryLayout<Map3DStreetStops.Stood>.stride
                + schedule.way.stops.count * 40
        }
        let waits = life.spots.compactMap(\.route).reduce(0) { $0 + $1.waits.count }
        bytes += waits * 40
        let walks = life.spots.reduce(0) { $0 + $1.walks.count }
        bytes += walks * MemoryLayout<Map3DStreetStops.Walk>.stride
        start = Date()
        for lane in stopped { _ = Map3DStreetLife.schedules(of: lane) }
        for spot in life.spots where spot.route != nil { _ = Map3DStreetLife.walks(on: spot) }
        print("working the trips out again: \(String(format: "%.2f", Date().timeIntervalSince(start))) s, walkers with a trip: \(walks)")
        laps.sort()
        print("vehicle places on lanes with stops: \(slots), whose trip outruns its lap: \(overruns); laps median \(laps.isEmpty ? 0 : laps[laps.count / 2]) s, longest \(laps.last ?? 0) s; walker waits: \(waits); schedules and routes about \(bytes / 1_024) KB")
        print("| camera | vehicles, people (without) | a frame without | vehicles, people (with) | a frame with |")
        print("| --: | --: | --: | --: | --: |")
        for distance in [120, 280, 500, 900] as [Float] {
            let frames = 200
            start = Date()
            var plain = Map3DStreetLife.Frame()
            for frame in 0..<frames {
                plain = life.frame(target: .zero, distance: distance, time: Double(frame) / 10, detail: .full, activity: .init())
            }
            let without = Date().timeIntervalSince(start) / Double(frames)
            start = Date()
            var timed = Map3DStreetLife.Frame()
            for frame in 0..<frames {
                timed = life.frame(target: .zero, distance: distance, time: Double(frame) / 10, detail: .full, activity: .init(),
                                   signals: 8 * 3_600 + Double(frame) / 10)
            }
            let with = Date().timeIntervalSince(start) / Double(frames)
            print(String(format: "| %.0f m | %d, %d | %.3f ms | %d, %d | %.3f ms |", distance, plain.vehicles, plain.people, without * 1_000,
                         timed.vehicles, timed.people, with * 1_000))
        }
    }
}
