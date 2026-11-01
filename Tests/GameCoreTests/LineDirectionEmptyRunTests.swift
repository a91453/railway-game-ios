@testable import GameCore
import XCTest

/// Decision 527: with traffic control off, an empty run of a line with
/// real runs keeps off track its line takes only the other way. On the
/// Sanying line (the author's 97.1 save) empty runs out of the depot
/// crossed onto the track the line's trains take towards Dingpu, met them
/// head on, and with decision 228's spacing each waited for the other for
/// good: twelve trains stood two days and nine stations filled up.
///
/// The double track of ``KeepLeftTests``, keeping left off: the line Main
/// from West to East takes the north track east (the shortest way) and,
/// by its chosen route, the south track west, so the north track is the
/// eastbound one and the south the westbound one.
final class LineDirectionEmptyRunTests: XCTestCase {
    private static let northWest = [6, 4, 2, 1].map { TrackTraversal(edge: .edge($0), direction: .backward) }
    private static let southWest = [7, 5, 3, 1].map { TrackTraversal(edge: .edge($0), direction: .backward) }

    /// The world, traffic control `trafficControl`, Main with a run each
    /// way and its westbound route by the south track, and a train of
    /// Main's at East's berth facing west.
    private func makeWorld(trafficControl: Bool = false) throws -> (world: GameWorld, train: TrainID, west: StationID, east: StationID) {
        var (world, west, east) = try KeepLeftTests.world(keepLeft: false)
        try world.setTrafficControl(trafficControl)
        let line = try world.createLine(named: "Main", stops: [west, east]).id
        let times = [LineRunTime(arrival: 21_600, departure: 21_600), LineRunTime(arrival: 22_200, departure: 22_200)]
        try world.setLineRuns(line, to: [LineRun(from: 0, to: 1, times: times), LineRun(from: 1, to: 0, times: times)])
        let platform = try XCTUnwrap(world.trackPlatforms(of: west).first)
        try world.setLineRoutePreferences(line, to: [
            LineRoutePreference(from: 1, to: 0, tracks: [TrackTraversal(edge: .edge(8), direction: .backward)] + Self.southWest, platform: platform),
        ])
        let train = try world.purchaseTrain(named: "T").id
        try world.placeTrain(train, at: KeepLeftTests.fromEast)
        try world.assignTrain(train, to: line)
        return (world, train, west, east)
    }

    /// The edges the train takes leaving East for West, as an empty run
    /// when `empty`.
    private func leavingEast(_ world: GameWorld, _ id: TrainID, west: StationID, east: StationID, empty: Bool) throws -> [Int] {
        var train = try XCTUnwrap(world.trains.first { $0.id == id })
        train.timetable = [
            ScheduledStop(station: east, arrival: GameTime(seconds: 21_600), departure: GameTime(seconds: 21_600)),
            ScheduledStop(station: west, arrival: GameTime(seconds: 22_200), departure: GameTime(seconds: 22_200)),
        ]
        train.isDeadheading = empty
        train.execution = .waitingAtStop(0, cycle: 0)
        let left = try XCTUnwrap(world.leaving(train, stop: 0, cycle: 0).train)
        return left.movement.remainingEdges.compactMap(\.networkNumber)
    }

    func testTheNorthTrackIsTheEastboundOne() throws {
        let (world, train, _, _) = try makeWorld()
        let line = try XCTUnwrap(world.lines.first)
        let length = try XCTUnwrap(world.trains.first { $0.id == train }).length
        let against = world.oneWayAgainst(line, length: length)
        XCTAssertTrue(Self.northWest.dropLast().allSatisfy(against.contains), "westward along the north track goes against the line")
        XCTAssertTrue(Self.southWest.allSatisfy { !against.contains($0) }, "westward along the south track goes with it")
    }

    /// The shortest way west is the north track; an empty run takes the
    /// south track, the line's westbound one.
    func testAnEmptyRunKeepsToTheLinesWestboundTrack() throws {
        let (world, train, west, east) = try makeWorld()
        XCTAssertEqual(try leavingEast(world, train, west: west, east: east, empty: true).filter { $0 != 8 }, Self.southWest.map { $0.edge.networkNumber! })
    }

    /// A train in service takes its way as before (the line's chosen
    /// routes and decision 228's platforms decide that), and so does an
    /// empty run under traffic control, whose movement authority keeps
    /// trains apart and undoes a deadlock.
    func testOnlyEmptyRunsWithoutTrafficControl() throws {
        let off = try makeWorld()
        XCTAssertEqual(try leavingEast(off.world, off.train, west: off.west, east: off.east, empty: false).filter { $0 != 8 }, Self.northWest.map { $0.edge.networkNumber! })
        let on = try makeWorld(trafficControl: true)
        XCTAssertEqual(try leavingEast(on.world, on.train, west: on.west, east: on.east, empty: true).filter { $0 != 8 }, Self.northWest.map { $0.edge.networkNumber! })
    }
}
