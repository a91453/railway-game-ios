@testable import GameCore
import XCTest

/// The passing-loop tool's probe (NEXT_PRIORITIES §0 item 10): a station
/// closed to passengers, with two tracks, between the two ends of a single
/// line works as a signal station (號誌站). A line that does not call
/// there still has its trains meet on its two tracks.
final class ClosedStationMeetTests: XCTestCase {
    /// SingleTrackMeet with M closed and a line from W to E that does not
    /// call at M, two trains, one at each end.
    static func world() throws -> (world: GameWorld, line: LineID, trains: [TrainID]) {
        var world = try SingleTrackMeet.world()
        try world.setStationOperationMode(SingleTrackMeet.middle, to: .closed)
        let line = try world.createLine(named: "Single", stops: [SingleTrackMeet.west, SingleTrackMeet.east]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        let first = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let second = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072)
        try world.assignTrain(first, to: line)
        try world.assignTrain(second, to: line)
        try world.setTrafficControl(true)
        world.setSpeed(.x1)
        return (world, line, [first, second])
    }

    func testTheClosedStationsTwoTracksLetTwoTrainsRun() throws {
        let (world, line, _) = try Self.world()
        let layout = world.capacityLayout(of: try XCTUnwrap(world.line(id: line)))
        XCTAssertEqual(world.lineTrainsInService(line, at: .peak), 2, "layout: \(layout.blocks), passing \(layout.passing)")
    }

    func testTrainsMeetAtTheClosedStation() throws {
        var (world, _, trains) = try Self.world()
        var metAtMiddle = false
        var calls: [TrainID: Int] = [:]
        var last: [TrainID: TimetableExecution?] = [:]
        for _ in 0..<(3 * 3_600) {
            try world.advance(ticks: 10)
            if world.scheduledTrafficWaits().contains(where: { $0.station == SingleTrackMeet.middle && $0.kind == .meet }) { metAtMiddle = true }
            for id in trains {
                let execution = world.train(id: id)?.execution
                if execution != last[id] ?? nil, case .waitingAtStop? = execution { calls[id, default: 0] += 1 }
                last[id] = execution
            }
        }
        XCTAssertTrue(metAtMiddle, "a meet is planned at the closed station")
        XCTAssertEqual(world.deadlockedTrains(), [], "no deadlock")
        for id in trains { XCTAssertGreaterThan(calls[id] ?? 0, 10, "train \(id) keeps running: \(calls)") }
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }
}
