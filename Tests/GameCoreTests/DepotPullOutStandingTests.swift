@testable import GameCore
import XCTest

/// Decision 547: with traffic control off, an empty run of a line with real
/// runs out of a depot keeps off track where another train stands, as
/// decision 228 has the way into one. On Danhai's Green Mountain Line with
/// the simple rules the runs out of the depot past Kanding to Hongshulin
/// for the 00:14 and 00:31 took Kanding's platform where a train stood for
/// the 00:57 empty run, waited behind it fifty minutes, and both runs were
/// dropped.
///
/// The double track of ``KeepLeftTests``, keeping left off, and a depot,
/// Yard, past East: the shortest way from it to West is the north track,
/// where another train of the line stands.
final class DepotPullOutStandingTests: XCTestCase {
    private static let north = [6, 4, 2, 1]
    private static let south = [7, 5, 3, 1]

    /// The world, traffic control `trafficControl`, Main from West to East
    /// with real runs, a train of Main's in East's depot facing west and,
    /// with `standing`, another stood on the north track.
    private func makeWorld(trafficControl: Bool = false, standing: Bool = true, keepLeft: Bool = false, standingOn edge: Int = 4) throws -> (world: GameWorld, train: TrainID, west: StationID, yard: StationID) {
        var (world, west, east) = try KeepLeftTests.world(keepLeft: keepLeft)
        try world.setTrafficControl(trafficControl)
        try world.buildTrackNode(at: WorldCoordinate(x: 40_896, y: 5_120)) // node 9
        try world.buildTrackEdge(from: .node(8), to: .node(9)) // e9, 1,984 long
        let yard = try world.buildStation(named: "Yard", at: PlanPoint(x: 39_936, y: 7_168)).id
        try world.addTrackPlatform(yard, on: .edge(9), from: 0, to: 1_984)
        try world.setStationDepot(yard, to: true)
        let line = try world.createLine(named: "Main", stops: [west, east]).id
        let times = [LineRunTime(arrival: 21_600, departure: 21_600), LineRunTime(arrival: 22_200, departure: 22_200)]
        try world.setLineRuns(line, to: [LineRun(from: 0, to: 1, times: times), LineRun(from: 1, to: 0, times: times)])
        let train = try world.purchaseTrain(named: "T").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: .edge(9), direction: .backward), offset: 1_984))
        try world.assignTrain(train, to: line)
        if standing {
            let other = try world.purchaseTrain(named: "U").id
            try world.placeTrain(other, at: .onEdge(TrackTraversal(edge: .edge(edge), direction: .backward), offset: 10_240))
            try world.assignTrain(other, to: line)
        }
        return (world, train, west, yard)
    }

    /// The edges the train takes out of the depot to West, empty, from
    /// East on.
    private func leavingTheDepot(_ world: GameWorld, _ id: TrainID, west: StationID, yard: StationID) throws -> [Int] {
        var train = try XCTUnwrap(world.trains.first { $0.id == id })
        train.timetable = [
            ScheduledStop(station: yard, arrival: GameTime(seconds: 21_000), departure: GameTime(seconds: 21_000)),
            ScheduledStop(station: west, arrival: GameTime(seconds: 21_600), departure: GameTime(seconds: 21_600)),
        ]
        train.isDeadheading = true
        train.execution = .waitingAtStop(0, cycle: 0)
        let left = try XCTUnwrap(world.leaving(train, stop: 0, cycle: 0).train)
        return left.movement.remainingEdges.compactMap(\.networkNumber).filter { $0 != 8 && $0 != 9 }
    }

    func testTheRunOutKeepsOffTheTrackWhereATrainStands() throws {
        let (world, train, west, yard) = try makeWorld()
        XCTAssertEqual(try leavingTheDepot(world, train, west: west, yard: yard), Self.south)
    }

    /// With the track free it takes the shortest way, as before; under
    /// traffic control, whose movement authority routes it, too.
    func testOnlyPastAStandingTrainWithoutTrafficControl() throws {
        let free = try makeWorld(standing: false)
        XCTAssertEqual(try leavingTheDepot(free.world, free.train, west: free.west, yard: free.yard), Self.north)
        let on = try makeWorld(trafficControl: true)
        XCTAssertEqual(try leavingTheDepot(on.world, on.train, west: on.west, yard: on.yard), Self.north)
    }

    /// Decision 547 (L6-4): keeping left, Main's trains run west on the
    /// south track (e7, e5, e3), so the north one taken west is track Main
    /// takes only the other way (decision 527). A third track between the
    /// two, a little longer than either, runs from the south track's
    /// turnouts (e10, e11, e12). With a train standing on the south track,
    /// the way kept off it is the north track; before the way kept off
    /// that was worked out keeping off the standing train too, it went
    /// back to the south track, past the train standing there.
    func testTheRunOutKeptOffTheOtherWaysTrackStillKeepsOffTheStandingTrain() throws {
        func run(standing: Bool) throws -> [Int] {
            var (world, train, west, yard) = try makeWorld(standing: standing, keepLeft: true, standingOn: 5)
            try world.buildTrackNode(at: WorldCoordinate(x: 13_312, y: 5_120)) // node 10
            try world.buildTrackNode(at: WorldCoordinate(x: 26_624, y: 5_120)) // node 11
            try world.buildTrackEdge(from: .node(4), to: .node(10), curve: .cubic(PlanPoint(x: 11_264, y: 6_144), PlanPoint(x: 11_264, y: 5_120))) // e10
            try world.buildTrackEdge(from: .node(10), to: .node(11)) // e11
            try world.buildTrackEdge(from: .node(11), to: .node(6), curve: .cubic(PlanPoint(x: 28_672, y: 5_120), PlanPoint(x: 28_672, y: 6_144))) // e12
            return try leavingTheDepot(world, train, west: west, yard: yard)
        }
        XCTAssertEqual(try run(standing: false), [7, 5, 3, 1], "keeping left, the south track")
        XCTAssertEqual(try run(standing: true), [7, 12, 11, 10, 3, 1], "the third track, neither past the standing train nor on the north one")
    }
}
