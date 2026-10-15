import Foundation
import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 201: a leg of a line shown on the map as its trains
/// would drive it, with the way they go and each track's number; the
/// lines' colours with arrows where a line runs one way only; the route
/// menu in the words the map uses.
@MainActor
final class RoutePreviewTests: XCTestCase {
    private static let main = LineID(rawValue: 1)

    /// West and East on a straight single track (edges 1, 2 and 3) with a
    /// passing loop beside the middle edge (edges 4, 5 and 6; the passing
    /// loop of `LineDraftRouteTests`), and a line from West to East.
    private func loopWorld() throws -> GameWorld {
        var world = try makeWorld(width: 36_864, height: 12_288, balance: 100_000_000, speed: .normal)
        for (x, y) in [(1_024, 4_096), (9_216, 4_096), (25_600, 4_096), (33_792, 4_096), (13_312, 6_144), (21_504, 6_144)] as [(Int64, Int64)] {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        for edge in 1...3 { try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        try world.buildTrackEdge(from: .node(2), to: .node(5), curve: .cubic(PlanPoint(x: 11_264, y: 4_096), PlanPoint(x: 11_264, y: 6_144)))
        try world.buildTrackEdge(from: .node(5), to: .node(6))
        try world.buildTrackEdge(from: .node(6), to: .node(3), curve: .cubic(PlanPoint(x: 23_552, y: 6_144), PlanPoint(x: 23_552, y: 4_096)))
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 2_048)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 31_744, y: 2_048)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(east, on: .edge(3), from: 5_120, to: 7_168)
        try world.createLine(named: "Main", stops: [west, east])
        return world
    }

    /// A walk for the leg from `from` to `to` by the loop (`true`) or the
    /// straight track, to the platform at its end. The route menu offers
    /// only each berth's shortest walk, the straight one.
    private func choice(_ world: GameWorld, from: Int, to: Int, byLoop: Bool) throws -> LineRoutePreference {
        let stop = try XCTUnwrap(world.line(id: Self.main)?.stops[to])
        let platform = try XCTUnwrap(world.network.platforms(of: stop).first)
        let east = to == 1
        let edges = byLoop ? [1, 4, 5, 6, 3] : [1, 2, 3]
        let walk = (east ? edges : edges.reversed()).map {
            TrackTraversal(edge: .edge($0), direction: east ? .forward : .backward)
        }
        return LineRoutePreference(from: from, to: to, tracks: walk, platform: platform)
    }

    func testALegIsShownTheWayItsTrainsDriveIt() throws {
        let world = try loopWorld()
        let out = try XCTUnwrap(RoutePreview(.init(line: Self.main, pattern: nil, from: 0, to: 1), in: world))
        XCTAssertEqual(out.trackNumbers, [1, 2, 3], "the shorter way, on the straight track")
        XCTAssertTrue(out.pieces.allSatisfy(\.isForward), "out east, the way every edge is built")
        XCTAssertTrue(out.pieces.allSatisfy { $0.start < $0.end })
        XCTAssertTrue(out.followsChoice)
        XCTAssertNotNil(out.focus)
        XCTAssertEqual(out.text(in: .english), "Tracks #1 → #2 → #3, stopping on #3")
        XCTAssertEqual(out.text(in: .traditionalChinese), "經由軌段 #1 → #2 → #3，停在 #3")

        let back = try XCTUnwrap(RoutePreview(.init(line: Self.main, pattern: nil, from: 1, to: 0), in: world))
        XCTAssertEqual(back.trackNumbers, [3, 2, 1])
        XCTAssertTrue(back.pieces.allSatisfy { !$0.isForward }, "back west, against the way the edges are built")

        XCTAssertNil(RoutePreview(.init(line: Self.main, pattern: nil, from: 0, to: 0), in: world), "no such leg")
        XCTAssertNil(RoutePreview(.init(line: Self.main, pattern: 3, from: 0, to: 1), in: world), "no such pattern")
        XCTAssertNil(RoutePreview(.init(line: LineID(rawValue: 9), pattern: nil, from: 0, to: 1), in: world), "no such line")
    }

    func testAChoiceIsShownBeforeItIsPickedAndLeavesTheWorldAlone() throws {
        let world = try loopWorld()
        let loop = try choice(world, from: 0, to: 1, byLoop: true)
        let preview = try XCTUnwrap(RoutePreview(.init(line: Self.main, pattern: nil, from: 0, to: 1, choice: .preference(loop)), in: world))
        XCTAssertEqual(preview.trackNumbers, [1, 4, 5, 6, 3], "by the loop")
        XCTAssertTrue(preview.followsChoice)
        XCTAssertEqual(world.line(id: Self.main)?.routePreferences, [], "the preview changed nothing")

        // Picked, the line runs it; automatic goes back to the straight way.
        var picked = world
        try picked.setLineRoutePreferences(Self.main, to: [loop])
        XCTAssertEqual(RoutePreview(.init(line: Self.main, pattern: nil, from: 0, to: 1), in: picked)?.trackNumbers, [1, 4, 5, 6, 3])
        XCTAssertEqual(RoutePreview(.init(line: Self.main, pattern: nil, from: 0, to: 1, choice: .automatic), in: picked)?.trackNumbers, [1, 2, 3])

        let other = try choice(world, from: 1, to: 0, byLoop: true)
        XCTAssertNil(RoutePreview(.init(line: Self.main, pattern: nil, from: 0, to: 1, choice: .preference(other)), in: world), "another leg's choice")
    }

    /// A double line: out by the loop, back by the straight track. The
    /// line's colour has arrows on each, the way it is ridden; where the
    /// line runs both ways, and in a platform where trains turn round,
    /// none.
    func testTheLinesColourSaysWhichWayEachTrackIsRidden() throws {
        var world = try loopWorld()
        XCTAssertTrue(LineMap(world: world).stretches.allSatisfy { $0.way == .both }, "out and back on the same track")

        let out = try choice(world, from: 0, to: 1, byLoop: true)
        let back = try choice(world, from: 1, to: 0, byLoop: false)
        try world.setLineRoutePreferences(Self.main, to: [out, back])
        let stretches = LineMap(world: world).stretches
        func ways(_ edge: Int) -> Set<LineMap.Way> { Set(stretches.filter { $0.edge == .edge(edge) }.map(\.way)) }
        XCTAssertEqual(ways(5), [.forward], "out east on the loop")
        XCTAssertEqual(ways(2), [.backward], "back west on the straight track")
        XCTAssertEqual(ways(1), [.both], "both ways to West")
        XCTAssertEqual(ways(3), [.both], "both ways from East")
    }

    /// A pattern's own route is drawn too, not only the line's own service.
    func testAPatternsRouteIsDrawn() throws {
        var world = try loopWorld()
        _ = try world.addLinePattern(Self.main, calling: [0, 1])
        XCTAssertFalse(LineMap(world: world).stretches.contains { $0.edge == .edge(5) })
        try world.setLineRoutePreferences(Self.main, to: [try choice(world, from: 0, to: 1, byLoop: true)], pattern: 0)
        let stretches = LineMap(world: world).stretches
        XCTAssertEqual(Set(stretches.filter { $0.edge == .edge(5) }.map(\.way)), [.forward], "the pattern runs out by the loop")
        XCTAssertEqual(
            RoutePreview(.init(line: Self.main, pattern: 0, from: 0, to: 1), in: world)?.trackNumbers, [1, 4, 5, 6, 3]
        )
        XCTAssertEqual(RoutePreview(.init(line: Self.main, pattern: nil, from: 0, to: 1), in: world)?.trackNumbers, [1, 2, 3])
    }

    func testTheRouteMenuUsesTheMapsWords() throws {
        let world = try loopWorld()
        let choices = world.lineRouteChoices(Self.main, from: 0, to: 1)
        let platform = try XCTUnwrap(choices.first { $0.tracks.isEmpty })
        XCTAssertEqual(RoutePreview.choiceText(platform, in: .english), "Platform on track #3 · route chosen automatically")
        XCTAssertEqual(RoutePreview.choiceText(platform, in: .traditionalChinese), "月台在軌段 #3・自動選路")
        let loop = try choice(world, from: 0, to: 1, byLoop: true)
        XCTAssertEqual(RoutePreview.choiceText(loop, in: .english), "Tracks #1 → #4 → #5 → #6 → #3 (platform)")
        XCTAssertEqual(RoutePreview.choiceText(loop, in: .traditionalChinese), "軌段 #1 → #4 → #5 → #6 → #3（月台）")
        XCTAssertEqual(RoutePreview.choiceTexts([loop, loop, platform], in: .english), [
            "Tracks #1 → #4 → #5 → #6 → #3 (platform)",
            "Tracks #1 → #4 → #5 → #6 → #3 (platform) (2)",
            "Platform on track #3 · route chosen automatically",
        ])
        XCTAssertEqual(RoutePreview.label(of: .edge(12)), "#12")
        XCTAssertEqual(TrackEdgeID.edge(12).displayText(in: .english), "Track #12")
        XCTAssertEqual(TrackEdgeID.edge(12).displayText(in: .traditionalChinese), "軌段 #12")
    }

    func testTheSessionShowsTheLegJustPickedAndOnlyForTheSelectedLine() throws {
        let world = try loopWorld()
        let session = GameSession(world: world)
        XCTAssertNil(session.routePreview)
        session.selectLine(Self.main)
        session.previewRoute(from: 0, to: 1, pattern: nil)
        XCTAssertEqual(session.routePreview?.trackNumbers, [1, 2, 3])
        XCTAssertTrue(session.isPreviewingRoute(from: 0, to: 1, pattern: nil))
        XCTAssertFalse(session.isPreviewingRoute(from: 1, to: 0, pattern: nil))

        let loop = try choice(world, from: 0, to: 1, byLoop: true)
        session.previewRoute(from: 0, to: 1, pattern: nil, choice: .preference(loop))
        XCTAssertEqual(session.routePreview?.trackNumbers, [1, 4, 5, 6, 3])
        XCTAssertEqual(session.world.line(id: Self.main)?.routePreferences, [])

        session.previewRoute(from: 1, to: 0, pattern: nil)
        session.setSelectedLineRoute(from: 0, to: 1, preference: loop)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        // Words the player knows, not "physical path" (the PR #526–#626
        // review).
        XCTAssertEqual(session.message?.text, "Updated the tracks the line takes between these stops.")
        XCTAssertEqual(session.routePreviewRequest, .init(line: Self.main, pattern: nil, from: 0, to: 1), "the leg just picked")
        XCTAssertEqual(session.routePreview?.trackNumbers, [1, 4, 5, 6, 3], "as the line now runs it")

        session.endRoutePreview(from: 1, to: 0, pattern: nil)
        XCTAssertNotNil(session.routePreview, "another leg's end leaves it")
        session.endRoutePreview(from: 0, to: 1, pattern: nil)
        XCTAssertNil(session.routePreview)
        session.previewRoute(from: 1, to: 0, pattern: nil)
        session.endRoutePreviews()
        XCTAssertNil(session.routePreview, "the panel closed")
    }

    func testMarksAlongAPolyline() {
        let straight = [ScreenPoint(x: 0, y: 0), ScreenPoint(x: 100, y: 0)]
        let marks = PolylineMarks.marks(along: straight, spacing: 40)
        XCTAssertEqual(marks.map(\.point), [ScreenPoint(x: 25, y: 0), ScreenPoint(x: 75, y: 0)])
        XCTAssertTrue(marks.allSatisfy { $0.angle == 0 })
        XCTAssertEqual(PolylineMarks.marks(along: straight, spacing: 400).map(\.point), [ScreenPoint(x: 50, y: 0)], "a short line has one")
        XCTAssertEqual(PolylineMarks.marks(along: straight, spacing: 1, limit: 3).count, 3)
        XCTAssertEqual(PolylineMarks.marks(along: [ScreenPoint(x: 5, y: 5)], spacing: 10), [])

        // Round a corner: down the screen after the first 10 points.
        let corner = [ScreenPoint(x: 0, y: 0), ScreenPoint(x: 10, y: 0), ScreenPoint(x: 10, y: 30)]
        let middle = try? XCTUnwrap(PolylineMarks.middle(of: corner))
        XCTAssertEqual(middle?.point, ScreenPoint(x: 10, y: 10))
        XCTAssertEqual(middle?.angle ?? 0, Double.pi / 2, accuracy: 1e-9)

        // Left of a mark pointing right is up the screen.
        let left = PolylineMarks.shifted(PolylineMarks.Mark(point: ScreenPoint(x: 0, y: 0), angle: 0), by: 5)
        XCTAssertEqual(left.point.x, 0, accuracy: 1e-9)
        XCTAssertEqual(left.point.y, -5, accuracy: 1e-9)
    }

    func testTheHelpGuideSaysWhereTheNumbersAre() throws {
        let entry = try XCTUnwrap(HelpGuide.entries.first { $0.id == "trackNumbers" })
        XCTAssertTrue(HelpGuide.entries(matching: "股道").contains(entry))
        XCTAssertTrue(HelpGuide.entries(matching: "track number").contains(entry))
        XCTAssertTrue(entry.answer(in: .traditionalChinese).contains("軌段 #7"))
    }
}
