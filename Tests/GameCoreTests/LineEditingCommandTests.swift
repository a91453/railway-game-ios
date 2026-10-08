import Foundation
@testable import GameCore
import XCTest

/// ARCHITECTURE decision 80: reversing a line's stops
/// (`reverseLineStops`, MapBuilder's `handleReverseStationOrder`) and
/// copying a line (`duplicateLine`, its `handleLineDuplicate`).
final class LineEditingCommandTests: XCTestCase {
    /// Three stations and a line through them; no track (a line is plan
    /// data, `createLine`).
    private func makeLineWorld() throws -> (GameWorld, LineID, [StationID]) {
        var world = GameWorld(bounds: try WorldBounds(width: 8_192, height: 8_192), economy: GameEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 0, station: 0, train: 0, car: 0)))
        let stations = try ["A", "B", "C", "D"].enumerated().map { index, name in
            try world.buildStation(named: name, at: PlanPoint(x: 1_024 + Int64(index) * 1_024, y: 1_024)).id
        }
        let line = try world.createLine(named: "Line", stops: stations).id
        return (world, line, stations)
    }

    /// `world` with line `index`'s dispatch times set, through a save (the
    /// world only sets them when it sends trains out).
    private func settingDispatch(_ world: GameWorld, line index: Int, inner: Int64?, outer: Int64?) throws -> GameWorld {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var lines = try XCTUnwrap(json["lines"] as? [[String: Any]])
        lines[index]["lastDispatch"] = inner
        lines[index]["outerLastDispatch"] = outer
        json["lines"] = lines
        return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - Reversing

    /// The stops go the other way; a pattern keeps calling at the same
    /// stations and a route preference stays on the same two stations.
    func testReversingKeepsPatternsAndRoutesOnTheirStations() throws {
        var (world, _, line, _) = try LineRoutePreferenceTests.setup(traffic: false, patterns: true)
        let route = LineRoutePreferenceTests.loop(world)
        try world.setLineRoutePreferences(line, to: [route])
        let before = try XCTUnwrap(world.line(id: line))

        try world.reverseLineStops(line)

        let after = try XCTUnwrap(world.line(id: line))
        XCTAssertEqual(after.stops, before.stops.reversed())
        XCTAssertEqual(after.patterns.map(\.calls), [[0, 2]], "west and east, as before")
        XCTAssertEqual(
            after.patterns.map { $0.calls.map { after.stops[$0] } },
            before.patterns.map { $0.calls.map { before.stops[$0] }.reversed() },
            "the same stations, called the other way"
        )
        XCTAssertEqual(after.routePreferences.map(\.from), [2])
        XCTAssertEqual(after.routePreferences.map(\.to), [1])
        XCTAssertEqual(after.routePreferences.map { after.stops[$0.from] }, [before.stops[route.from]])
        XCTAssertEqual(after.routePreferences.map { after.stops[$0.to] }, [before.stops[route.to]])
        XCTAssertEqual(after.routePreferences.map(\.platform), [route.platform])
        XCTAssertTrue(after.validRoutePreferences)
        XCTAssertEqual(after.trains, before.trains)
        XCTAssertEqual(after.patterns.map(\.trains), before.patterns.map(\.trains))
        XCTAssertNotNil(world.lineJourney(line))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "saves and loads")

        try world.reverseLineStops(line)
        XCTAssertEqual(world.line(id: line), before, "twice is the line as it was")
    }

    /// A pattern that is not symmetric maps to the mirrored indices.
    func testReversingMirrorsAnExpressPattern() throws {
        var (world, line, stations) = try makeLineWorld()
        try world.addLinePattern(line, calling: [0, 1, 3])
        try world.reverseLineStops(line)
        let reversed = try XCTUnwrap(world.line(id: line))
        XCTAssertEqual(reversed.stops, stations.reversed())
        XCTAssertEqual(reversed.patterns.map(\.calls), [[0, 2, 3]])
        XCTAssertEqual(reversed.patterns[0].calls.map { reversed.stops[$0] }, [stations[3], stations[1], stations[0]])
    }

    /// A ring goes round the other way, so the times its two streams last
    /// sent a train out swap with them.
    func testReversingARingSwapsItsDispatchTimes() throws {
        var (world, line, _) = try makeLineWorld()
        try world.setLineRing(line, to: true)
        world.setSpeed(.normal)
        try world.advance(ticks: 3)
        let index = try XCTUnwrap(world.lines.firstIndex { $0.id == line })
        world = try settingDispatch(world, line: index, inner: 60, outer: 120)
        XCTAssertEqual(world.lines[index].lastDispatch, GameTime(seconds: 60))

        try world.reverseLineStops(line)

        XCTAssertEqual(world.lines[index].lastDispatch, GameTime(seconds: 120))
        XCTAssertEqual(world.lines[index].outerLastDispatch, GameTime(seconds: 60))
        XCTAssertTrue(world.lines[index].isRing)
    }

    func testReversingAnUnknownLineIsRefused() throws {
        var (world, _, _) = try makeLineWorld()
        let before = world
        XCTAssertThrowsError(try world.reverseLineStops(LineID(rawValue: 99))) {
            XCTAssertEqual($0 as? GameError, .unknownLine(LineID(rawValue: 99)))
        }
        XCTAssertEqual(world, before)
    }

    // MARK: - Copying

    /// The copy has everything but the trains and when they were sent out;
    /// its ID is the next line ID; the original is unchanged.
    func testACopyHasTheLineButNotItsTrains() throws {
        var (world, _, line, _) = try LineRoutePreferenceTests.setup(traffic: false, patterns: true)
        try world.setLineRoutePreferences(line, to: [LineRoutePreferenceTests.loop(world)])
        try world.setLineColor(line, to: LineColor.presets[2])
        try world.setLineTargetHeadways(line, to: TargetHeadways(peak: 6, offPeak: nil, low: nil))
        let index = try XCTUnwrap(world.lines.firstIndex { $0.id == line })
        if world.lines[index].lastDispatch == nil {
            world.setSpeed(.normal)
            try world.advance(ticks: 1)
            world = try settingDispatch(world, line: index, inner: 30, outer: nil)
        }
        XCTAssertNotNil(world.lines[index].lastDispatch)
        let original = world.lines[index]
        XCTAssertFalse(original.trains.isEmpty && original.patterns.allSatisfy(\.trains.isEmpty), "the setup assigns a train")

        let copy = try world.duplicateLine(line, named: "Route - Fork")

        XCTAssertEqual(copy.id, LineID(rawValue: line.rawValue + 1))
        XCTAssertEqual(copy.name, "Route - Fork")
        XCTAssertEqual(copy.stops, original.stops)
        XCTAssertEqual(copy.routePreferences, original.routePreferences)
        XCTAssertEqual(copy.performance, original.performance)
        XCTAssertEqual(copy.window, original.window)
        XCTAssertEqual(copy.trainsInService, original.trainsInService)
        XCTAssertEqual(copy.targetHeadways, original.targetHeadways)
        XCTAssertEqual(copy.color, original.color)
        XCTAssertEqual(copy.isRing, original.isRing)
        XCTAssertEqual(copy.patterns.map(\.calls), original.patterns.map(\.calls))
        XCTAssertEqual(copy.patterns.map(\.routePreferences), original.patterns.map(\.routePreferences))
        XCTAssertEqual(copy.patterns.map(\.trainsInService), original.patterns.map(\.trainsInService))
        XCTAssertEqual(copy.trains, [])
        XCTAssertTrue(copy.patterns.allSatisfy { $0.trains.isEmpty && $0.lastDispatch == nil })
        XCTAssertNil(copy.lastDispatch)
        XCTAssertEqual(world.lines.last, copy)
        XCTAssertEqual(world.lines[index], original)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "saves and loads")
        XCTAssertEqual(try world.createLine(named: "Next", stops: original.stops).id, LineID(rawValue: copy.id.rawValue + 1))
    }

    func testACopyOfARingIsARing() throws {
        var (world, line, _) = try makeLineWorld()
        try world.setLineRing(line, to: true)
        let copy = try world.duplicateLine(line, named: "Loop")
        XCTAssertTrue(copy.isRing)
        XCTAssertNil(copy.outerLastDispatch)
    }

    func testABadCopyIsRefusedAndChangesNothing() throws {
        var (world, line, _) = try makeLineWorld()
        let before = world
        XCTAssertThrowsError(try world.duplicateLine(line, named: "  ")) {
            XCTAssertEqual($0 as? GameError, .invalidName)
        }
        XCTAssertThrowsError(try world.duplicateLine(LineID(rawValue: 99), named: "Copy")) {
            XCTAssertEqual($0 as? GameError, .unknownLine(LineID(rawValue: 99)))
        }
        XCTAssertEqual(world, before)
    }
}
