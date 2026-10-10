import Foundation
import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 100: a new line from its two ends. The stations
/// between are the ones whose platforms the track a line's journey would
/// take passes, never a guess from where the stations stand; a station
/// picked on the way chooses where the line goes; the player chooses which
/// stations along it the line calls at.
@MainActor
final class LineDraftRouteTests: XCTestCase {
    private static let line = TestLine(tiles: 9, row: 1)
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)
    private static let gamma = StationID(rawValue: 3)
    private static let delta = StationID(rawValue: 4)
    private static let lonely = StationID(rawValue: 5)

    /// Alpha, Beta, Gamma and Delta along one straight track, west to east;
    /// Lonely stands on no track.
    private func straightWorld() throws -> GameWorld {
        var world = try makeWorld(width: 9_216, height: 4_096, balance: 1_000_000, speed: .normal)
        try Self.line.build(in: &world)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            try Self.line.buildStation(named: name, beside: x, at: 0, in: &world)
        }
        try world.buildStation(named: "Lonely", at: PlanPoint(x: 4_608, y: 3_584))
        return world
    }

    /// West and East on a straight single track with a station, Straight,
    /// on it, and a loop beside it with a station, Loop, on the loop only
    /// (the passing loop of `TrafficOverlayTests`). The straight way is the
    /// shorter.
    private func loopWorld() throws -> (world: GameWorld, west: StationID, straight: StationID, loop: StationID, east: StationID) {
        var world = try makeWorld(width: 36_864, height: 12_288, balance: 100_000_000, speed: .normal)
        for (x, y) in [(1_024, 4_096), (9_216, 4_096), (25_600, 4_096), (33_792, 4_096), (13_312, 6_144), (21_504, 6_144)] as [(Int64, Int64)] {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        for edge in 1...3 { try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        try world.buildTrackEdge(from: .node(2), to: .node(5), curve: .cubic(PlanPoint(x: 11_264, y: 4_096), PlanPoint(x: 11_264, y: 6_144)))
        try world.buildTrackEdge(from: .node(5), to: .node(6))
        try world.buildTrackEdge(from: .node(6), to: .node(3), curve: .cubic(PlanPoint(x: 23_552, y: 6_144), PlanPoint(x: 23_552, y: 4_096)))
        var stations: [StationID] = []
        for (name, x, y) in [("West", Int64(3_072), Int64(2_048)), ("Straight", 17_408, 2_048), ("Loop", 17_408, 8_192), ("East", 31_744, 2_048)] {
            stations.append(try world.buildStation(named: name, at: PlanPoint(x: x, y: y)).id)
        }
        for (station, edge, start) in [(0, 1, Int64(1_024)), (1, 2, 7_168), (2, 5, 3_072), (3, 3, 5_120)] {
            try world.addTrackPlatform(stations[station], on: .edge(edge), from: start, to: start + 2_048)
        }
        return (world, stations[0], stations[1], stations[2], stations[3])
    }

    func testTheStationsBetweenAreTheOnesTheTrackPasses() throws {
        let world = try straightWorld()
        XCTAssertEqual(world.stationsAlongTrack(from: Self.alpha, to: Self.delta), [Self.beta, Self.gamma])
        XCTAssertEqual(world.stationsAlongTrack(from: Self.delta, to: Self.alpha), [Self.gamma, Self.beta], "in the order the train passes them")
        XCTAssertEqual(world.stationsAlongTrack(from: Self.beta, to: Self.gamma), [])
        XCTAssertNil(world.stationsAlongTrack(from: Self.alpha, to: Self.alpha))
        XCTAssertNil(world.stationsAlongTrack(from: Self.alpha, to: Self.lonely), "no track reaches it")
        XCTAssertNil(world.stationsAlongTrack(from: Self.alpha, to: StationID(rawValue: 99)))
        XCTAssertEqual(world.stationsAlongTrack(through: [Self.alpha, Self.gamma, Self.beta]), [Self.alpha, Self.beta, Self.gamma, Self.beta])
        XCTAssertNil(world.stationsAlongTrack(through: [Self.alpha]))
    }

    func testAStationPickedOnTheWayChoosesWhichWayTheLineGoes() throws {
        let (world, west, straight, loop, east) = try loopWorld()
        XCTAssertEqual(world.stationsAlongTrack(from: west, to: east), [straight], "the shorter way, by the straight track")
        XCTAssertEqual(world.stationsAlongTrack(through: [west, loop, east]), [west, loop, east], "by the loop, which passes no other station")
    }

    func testPickingTheEndsOnTheMapFindsTheStationsBetween() throws {
        let start = try straightWorld()
        let session = GameSession(world: start)
        session.startPickingLineStops()
        XCTAssertTrue(session.isPickingLineStops)

        session.tapMap(at: TestLine.centre(1, 0), reach: 512)
        XCTAssertEqual(session.lineDraft, [Self.alpha])
        XCTAssertNil(session.lineDraftRoute)
        // A little off the first tap, as a finger lands.
        let first = TestLine.centre(1, 0)
        session.tapMap(at: PlanPoint(x: first.x + 40, y: first.y), reach: 512)
        XCTAssertEqual(session.lineDraft, [Self.alpha], "the same station twice in a row is not added")
        XCTAssertEqual(session.message?.kind, .failure, "and the player is told why")
        session.tapMap(at: TestLine.centre(7, 0), reach: 512)
        XCTAssertEqual(session.lineDraft, [Self.alpha, Self.delta])
        XCTAssertEqual(session.lineDraftRoute, [Self.alpha, Self.beta, Self.gamma, Self.delta])

        XCTAssertEqual(session.lineDraftStops, [Self.alpha, Self.beta, Self.gamma, Self.delta], "every station by default")
        session.lineDraftStopping = .pickedStations
        XCTAssertEqual(session.lineDraftStops, [Self.alpha, Self.delta])
        session.toggleLineDraftStop(Self.gamma)
        XCTAssertEqual(session.lineDraftStopping, .custom)
        XCTAssertEqual(session.lineDraftStops, [Self.alpha, Self.beta, Self.delta])
        session.toggleLineDraftStop(Self.alpha)
        XCTAssertEqual(session.lineDraftStops, [Self.alpha, Self.beta, Self.delta], "the ends are always called at")
        XCTAssertEqual(session.world, start, "a draft changes nothing in the world")

        session.createLineFromDraft()
        var expected = start
        try expected.createLine(named: "Line 1", stops: [Self.alpha, Self.beta, Self.delta])
        XCTAssertEqual(session.world, expected)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.lineDraft, [])
        XCTAssertNil(session.lineDraftRoute)
        XCTAssertEqual(session.lineDraftStopping, .everyStation)
        XCTAssertFalse(session.isPickingLineStops, "the line is made: picking ends")

        session.tapMap(at: TestLine.centre(3, 0), reach: 512)
        XCTAssertEqual(session.lineDraft, [], "taps select again")
    }

    func testStationsWithNoTrackBetweenMakeTheLineThePlayerPicked() throws {
        let session = GameSession(world: try straightWorld())
        session.selectStation(Self.alpha)
        session.addSelectedStationToLineDraft()
        session.selectStation(Self.lonely)
        session.addSelectedStationToLineDraft()
        XCTAssertNil(session.lineDraftRoute)
        XCTAssertEqual(session.lineDraftStops, [Self.alpha, Self.lonely])
    }

    func testTheRouteFollowsTrackBuiltAndUndoneWhileDrafting() throws {
        var world = try makeWorld(width: 9_216, height: 4_096, balance: 1_000_000, speed: .paused)
        for x in 0..<3 {
            let centre = TestLine.centre(x, 1)
            try world.buildTrackNode(at: WorldCoordinate(x: centre.x, y: centre.y))
        }
        try world.buildTrackEdge(from: .node(1), to: .node(2))
        let west = try world.buildStation(named: "West", at: TestLine.centre(0, 0)).id
        let middle = try world.buildStation(named: "Middle", at: TestLine.centre(1, 0)).id
        let east = try world.buildStation(named: "East", at: TestLine.centre(2, 0)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 0, to: 256)
        try world.addTrackPlatform(middle, on: .edge(1), from: 768, to: 1_024)

        let session = GameSession(world: world)
        session.selectStation(west)
        session.addSelectedStationToLineDraft()
        session.selectStation(east)
        session.addSelectedStationToLineDraft()
        XCTAssertNil(session.lineDraftRoute, "East has no platform yet")

        _ = try session.performEdit { world throws(GameError) in
            try world.buildTrackEdge(from: .node(2), to: .node(3))
            try world.addTrackPlatform(east, on: .edge(2), from: 768, to: 1_024)
        }
        XCTAssertEqual(session.lineDraftRoute, [west, middle, east])
        session.undo()
        XCTAssertNil(session.lineDraftRoute)
    }

    /// Decision 112: a selected station's card starts a new line there;
    /// the next station tapped is its other end.
    func testALineStartedAtTheSelectedStationEndsAtTheNextTapped() throws {
        let start = try straightWorld()
        let session = GameSession(world: start)
        session.selectStation(Self.gamma)
        session.addSelectedStationToLineDraft()
        session.selectStation(Self.beta)

        session.startLineFromSelectedStation()
        XCTAssertEqual(session.lineDraft, [Self.beta], "the draft begun before is dropped")
        XCTAssertTrue(session.isPickingLineStops)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world, start)

        session.tapMap(at: TestLine.centre(7, 0), reach: 512)
        XCTAssertEqual(session.lineDraft, [Self.beta, Self.delta])
        XCTAssertEqual(session.lineDraftRoute, [Self.beta, Self.gamma, Self.delta])
    }

    func testALineCannotStartWithNoStationSelected() throws {
        let session = GameSession(world: try straightWorld())
        session.startLineFromSelectedStation()
        XCTAssertEqual(session.lineDraft, [])
        XCTAssertFalse(session.isPickingLineStops)
        XCTAssertEqual(session.message?.kind, .failure)
    }
}
