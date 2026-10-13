import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 201, later: the one-time card about track numbers
/// and routes comes when a line first gets a second track, or when the
/// route menus first come into view; never in the tutorial, never for the
/// double track a game was opened with.
@MainActor
final class RouteHintTests: XCTestCase {
    private static let main = LineID(rawValue: 1)

    /// West and East on one straight track (edges 1, 2 and 3), a line
    /// between them; `double` lays a second track 8 m beside it with a
    /// platform of each station on it.
    private func world(double: Bool) throws -> GameWorld {
        var world = try makeWorld(width: 36_864, height: 12_288, balance: 100_000_000, speed: .normal)
        for x in [1_024, 9_216, 25_600, 33_792] as [Int64] {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: 4_096))
        }
        for edge in 1...3 { try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 2_048)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 31_744, y: 2_048)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(east, on: .edge(3), from: 5_120, to: 7_168)
        try world.createLine(named: "Main", stops: [west, east])
        if double { try addSecondTrack(to: &world) }
        return world
    }

    private func addSecondTrack(to world: inout GameWorld) throws(GameError) {
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 4_608))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 33_792, y: 4_608))
        let edge = try world.buildTrackEdge(from: a, to: b)
        try world.addTrackPlatform(StationID(rawValue: 1), on: edge, from: 1_024, to: 3_072)
        try world.addTrackPlatform(StationID(rawValue: 2), on: edge, from: 29_696, to: 31_744)
    }

    func testTheLegsOnTwoTracksAreFound() throws {
        XCTAssertEqual(RouteHint.parallelLegs(in: try world(double: false)), [])
        XCTAssertEqual(RouteHint.parallelLegs(in: try world(double: true)), [RouteHint.Leg(line: Self.main, stop: 0)])
    }

    func testASecondTrackBuiltBringsTheCardUpOnce() throws {
        let single = try world(double: false)
        let session = GameSession(world: single, language: .english)
        session.watchRouteHint()
        XCTAssertNil(session.routeHint, "single track: nothing to choose")

        XCTAssertTrue(session.perform { world throws(GameError) in
            try self.addSecondTrack(to: &world)
            return "a second track"
        })
        session.watchRouteHint()
        XCTAssertEqual(session.routeHint, .parallelTrack(Self.main))
        let text = RouteHint.message(.parallelTrack(Self.main), in: session.world, language: .english, advancedShown: false)
        XCTAssertTrue(text.hasPrefix("Main now has two tracks"), text)
        XCTAssertTrue(text.contains("under Advanced"), "folded, the card says where the menus are")
        XCTAssertFalse(
            RouteHint.message(.parallelTrack(Self.main), in: session.world, language: .english, advancedShown: true).contains("Advanced")
        )
        XCTAssertEqual(RouteHint.showButton(.parallelTrack(Self.main), in: .traditionalChinese), "看進路設定")

        session.dismissRouteHint()
        session.watchRouteHint()
        XCTAssertNil(session.routeHint, "the same second track does not bring it up again")
    }

    func testAGameOpenedWithDoubleTrackWaitsForANewOne() throws {
        let session = GameSession(world: try world(double: true), language: .traditionalChinese)
        session.watchRouteHint()
        XCTAssertNil(session.routeHint, "the double track the game was opened with")
    }

    func testTheRouteMenusBringItUpButNotInTheTutorial() throws {
        let session = GameSession(world: try world(double: false), language: .traditionalChinese)
        session.routeMenusDidAppear()
        XCTAssertEqual(session.routeHint, .routeMenus)
        XCTAssertNil(RouteHint.showButton(.routeMenus, in: .english), "the menus are already beside the player")
        let text = RouteHint.message(.routeMenus, in: session.world, language: .traditionalChinese, advancedShown: true)
        XCTAssertTrue(text.contains("軌段 #7"), text)
        XCTAssertTrue(text.contains("箭頭"), text)
        session.dismissRouteHint()
        XCTAssertNil(session.routeHint)

        session.startTutorial()
        XCTAssertNotNil(session.tutorial)
        session.routeMenusDidAppear()
        XCTAssertNil(session.routeHint, "not over the tutorial's cards")
    }
}
