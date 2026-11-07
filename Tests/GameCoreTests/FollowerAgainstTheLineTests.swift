@testable import GameCore
import XCTest

/// Decision 636: without block sections, a train following another (Stage
/// U2) is never given an authority that could leave it standing on track
/// its line runs only the other way (decision 527's
/// ``GameWorld/oneWayAgainst(_:length:)``). On the Taoyuan Airport MRT
/// rebuilt after the real line, the Qingpu depot's track joins only the
/// eastbound line: an empty run out of it to Huanbei followed a westbound
/// train along the eastbound track, its authority ending there; the train
/// ahead stopped at Xingnan, and the empty run stood head on with an
/// eastbound service at THSR Taoyuan. Neither moved again, and eight trains
/// stood (TYMC-REBUILD-4).
///
/// The double track of ``KeepLeftTests``, keeping left off: the line Main
/// takes the north track east and, by its chosen route, the south track
/// west, so westward along the north track goes against the line.
final class FollowerAgainstTheLineTests: XCTestCase {
    private static let northWest = [6, 4, 2, 1].map { TrackTraversal(edge: .edge($0), direction: .backward) }
    private static let southWest = [7, 5, 3, 1].map { TrackTraversal(edge: .edge($0), direction: .backward) }

    /// The world with traffic control on: L, travelling to West's berth
    /// on e1 and on to East after it, and F, an empty run of Main at
    /// East's berth facing west, its route to West along `way`.
    private func makeWorld(way: [TrackTraversal]) throws -> (world: GameWorld, f: Train) {
        var (world, west, east) = try KeepLeftTests.world(keepLeft: false)
        let line = try world.createLine(named: "Main", stops: [west, east]).id
        let times = [LineRunTime(arrival: 21_600, departure: 21_600), LineRunTime(arrival: 22_200, departure: 22_200)]
        try world.setLineRuns(line, to: [LineRun(from: 0, to: 1, times: times), LineRun(from: 1, to: 0, times: times)])
        let platform = try XCTUnwrap(world.trackPlatforms(of: west).first)
        try world.setLineRoutePreferences(line, to: [
            LineRoutePreference(from: 1, to: 0, tracks: [TrackTraversal(edge: .edge(8), direction: .backward)] + Self.southWest, platform: platform),
        ])
        let f = try world.purchaseTrain(named: "F").id
        try world.placeTrain(f, at: KeepLeftTests.fromEast)
        try world.assignTrain(f, to: line)
        try world.setTrainContinuation(f, along: [], stoppingAt: 3_072)
        try world.setTrainMovementRate(f, to: 16_384)
        let l = try world.purchaseTrain(named: "L").id
        try world.placeTrain(l, at: .onEdge(TrackTraversal(edge: .edge(1), direction: .backward), offset: 1_024))
        try world.setTrainContinuation(l, along: [], stoppingAt: 3_072)
        try world.setTrainMovementRate(l, to: 16_384)
        try world.setTrafficControl(true)

        var leader = try XCTUnwrap(world.train(id: l))
        leader.timetable = [
            ScheduledStop(station: west, arrival: GameTime(seconds: 21_600), departure: GameTime(seconds: 21_600)),
            ScheduledStop(station: east, arrival: GameTime(seconds: 22_200), departure: GameTime(seconds: 22_200)),
        ]
        leader.execution = .travellingToStop(0, cycle: 0)
        guard case .granted(let granted) = world.reserving(leader) else { throw XCTSkip("L's route is free") }
        world = world.replacing(granted)

        var follower = try XCTUnwrap(world.train(id: f))
        follower.timetable = [
            ScheduledStop(station: east, arrival: GameTime(seconds: 21_600), departure: GameTime(seconds: 21_600)),
            ScheduledStop(station: west, arrival: GameTime(seconds: 22_200), departure: GameTime(seconds: 22_200)),
        ]
        follower.isDeadheading = true
        follower.execution = .travellingToStop(1, cycle: 0)
        // Its way to West, set as a departure's is.
        follower.movement.edges = way.map(\.edge)
        follower.movement.cursor = 0
        follower.movement.end = 3_072
        follower.reservation = []
        return (world, follower)
    }

    func testTheNorthTrackGoesAgainstTheLine() throws {
        let (world, f) = try makeWorld(way: Self.northWest)
        let line = try XCTUnwrap(world.lines.first)
        let against = world.oneWayAgainst(line, length: f.length)
        XCTAssertTrue(Self.northWest.dropLast().allSatisfy(against.contains))
        XCTAssertTrue(Self.southWest.allSatisfy { !against.contains($0) })
    }

    /// Along the north track it waits: its authority would end on it,
    /// short of L. Before, it set off along the north track that far.
    func testAFollowerWaitsRatherThanStopOnTrackAgainstTheLine() throws {
        let (world, f) = try makeWorld(way: Self.northWest)
        guard case .held = world.reserving(f, following: true) else {
            return XCTFail("F is let onto the north track only part of the way")
        }
    }

    /// Along the south track, the line's own way west, it follows L as
    /// before, part of the way.
    func testAFollowerWithTheLineFollowsAsBefore() throws {
        let (world, f) = try makeWorld(way: Self.southWest)
        guard case .granted(let granted) = world.reserving(f, following: true) else {
            return XCTFail("F follows L along the south track")
        }
        XCTAssertFalse(granted.reservation.isEmpty)
        XCTAssertTrue(world.replacing(granted).isFollowing(granted))
    }
}
