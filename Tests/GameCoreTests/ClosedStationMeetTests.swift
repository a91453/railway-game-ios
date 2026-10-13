@testable import GameCore
import XCTest

/// The passing-loop tool's probe (NEXT_PRIORITIES §0 item 10): a station
/// closed to passengers with two tracks between the ends of a single line,
/// a signal station (號誌站). SingleTrackMeet with M closed.
final class ClosedStationMeetTests: XCTestCase {
    /// Timetabled services east and west, the westbound calling at M or
    /// running through it.
    static func services(westCallsAtMiddle: Bool) throws -> (world: GameWorld, east: TrainID, west: TrainID) {
        var world = try SingleTrackMeet.world()
        try world.setStationOperationMode(SingleTrackMeet.middle, to: .closed)
        let east = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let west = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072)
        try world.setTrainTimetable(east, to: [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 0), departure: .init(seconds: 60)),
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 660), departure: .init(seconds: 720)),
        ])
        let middle: [ScheduledStop] = westCallsAtMiddle
            ? [.init(station: SingleTrackMeet.middle, arrival: .init(seconds: 400), departure: .init(seconds: 460))] : []
        try world.setTrainTimetable(west, to: [
            .init(station: SingleTrackMeet.east, arrival: .init(seconds: 0), departure: .init(seconds: 120)),
        ] + middle + [
            .init(station: SingleTrackMeet.west, arrival: .init(seconds: 760), departure: .init(seconds: 820)),
        ])
        try world.startTrainService(east)
        try world.startTrainService(west)
        try world.setTrafficControl(true)
        return (world, east, west)
    }

    /// A service calling at the closed station has the meet planned there
    /// (the eastbound train waits on its other track), and both run through.
    func testAMeetIsPlannedAtAClosedStationCalledAt() throws {
        var (world, east, west) = try Self.services(westCallsAtMiddle: true)
        let wait = try XCTUnwrap(world.scheduledTrafficWaits().first)
        XCTAssertEqual(wait.station, SingleTrackMeet.middle)
        XCTAssertEqual(wait.kind, .meet)
        try world.advance(ticks: 20_000)
        XCTAssertNil(world.train(id: east)?.execution)
        XCTAssertNil(world.train(id: west)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.east])
        XCTAssertEqual(world.stationsStoppedAt(by: west), [SingleTrackMeet.west])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// Through a closed station neither calls at, no meet is planned, but
    /// traffic control still passes the trains on its two tracks.
    func testTrainsPassAtAClosedStationNeitherCallsAt() throws {
        var (world, east, west) = try Self.services(westCallsAtMiddle: false)
        XCTAssertEqual(world.scheduledTrafficWaits(), [])
        try world.advance(ticks: 20_000)
        XCTAssertNil(world.train(id: east)?.execution)
        XCTAssertNil(world.train(id: west)?.execution)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// A line's capacity (decision 61) counts a passing place only at a
    /// stop: a line that runs through the closed station keeps one train on
    /// the single track; one that calls there can run two.
    func testALineCountsTheClosedStationOnlyWhenItCallsThere() throws {
        for calls in [false, true] {
            var world = try SingleTrackMeet.world()
            try world.setStationOperationMode(SingleTrackMeet.middle, to: .closed)
            let stops = calls ? [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east] : [SingleTrackMeet.west, SingleTrackMeet.east]
            let line = try world.createLine(named: "Single", stops: stops).id
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
            try world.setTrafficControl(true)
            XCTAssertEqual(world.lineTrainsInService(line, at: .peak), calls ? 2 : 1, "calls at M: \(calls)")
        }
    }
}
