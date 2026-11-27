import Foundation
import GameCore
import GamePresentation
import XCTest

/// TestFlight, 2026-11-27 (iPhone 17): "with many stops the line is not
/// drawn, and its trains do not run to the stops added." A station tapped
/// for a new line, or added to a line where it fits, goes where the track
/// has it, so the line can still be driven and is drawn.
@MainActor
final class LineStopPlacementTests: XCTestCase {
    private static let line = TestLine(tiles: 40, row: 1)

    /// Thirteen stations, S0 to S12, three tiles apart along one straight
    /// track, west to east.
    private func straightWorld() throws -> (world: GameWorld, stations: [StationID]) {
        var world = try makeWorld(width: 41 * 1_024, height: 4_096, balance: 100_000_000, speed: .normal)
        try Self.line.build(in: &world)
        let stations = try (0..<13).map { try Self.line.buildStation(named: "S\($0)", beside: 1 + $0 * 3, at: 0, in: &world) }
        return (world, stations)
    }

    private func tap(_ index: Int, in session: GameSession) {
        session.tapMap(at: TestLine.centre(1 + index * 3, 0), reach: 512)
    }

    /// Whether the map draws line `id` (``LineMap``).
    private func isDrawn(_ id: LineID, in world: GameWorld) -> Bool {
        LineMap(world: world).stretches.contains { $0.line == id }
    }

    /// The player's report: both ends picked (as the card from Build to a
    /// new line picks them, decision 1024), then more stations tapped. They
    /// used to go after the last end, so the line ran there, back and on
    /// again, and had no journey.
    func testStationsTappedAfterBothEndsGoWhereTheTrackPassesThem() throws {
        let (world, stations) = try straightWorld()
        let session = GameSession(world: world)
        session.startPickingLineStops()
        tap(0, in: session)
        tap(12, in: session)
        for index in [6, 3, 9, 1, 11] { tap(index, in: session) }
        XCTAssertEqual(session.lineDraft, [0, 1, 3, 6, 9, 11, 12].map { stations[$0] })
        XCTAssertEqual(session.lineDraftStops, stations, "every station along, each once, in order")

        session.lineDraftStopping = .pickedStations
        XCTAssertEqual(session.lineDraftStops, [0, 1, 3, 6, 9, 11, 12].map { stations[$0] })
        session.createLineFromDraft()
        let id = try XCTUnwrap(session.world.lines.first?.id)
        XCTAssertNotNil(session.world.lineJourney(id), "its trains can run it")
        XCTAssertTrue(isDrawn(id, in: session.world), "and the map draws it")
    }

    /// A station beyond the last picked still goes on the end, and one
    /// beyond the first, where the line could not otherwise reach it
    /// without turning back, before it.
    func testStationsBeyondTheEndsExtendTheLine() throws {
        let (world, stations) = try straightWorld()
        let session = GameSession(world: world)
        session.startPickingLineStops()
        tap(4, in: session)
        tap(8, in: session)
        tap(10, in: session)
        XCTAssertEqual(session.lineDraft, [4, 8, 10].map { stations[$0] })
        tap(2, in: session)
        XCTAssertEqual(session.lineDraft, [2, 4, 8, 10].map { stations[$0] })
        session.createLineFromDraft()
        let id = try XCTUnwrap(session.world.lines.first?.id)
        XCTAssertNotNil(session.world.lineJourney(id))
    }

    /// A station on another way between two picked (the passing loop of
    /// `LineDraftRouteTests`) chooses that way, as the draft's hint says.
    func testAStationTappedOnALoopAfterTheEndsChoosesTheLoop() throws {
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
        let session = GameSession(world: world)
        session.startPickingLineStops()
        for (x, y) in [(3_072, 2_048), (31_744, 2_048), (17_408, 8_192)] as [(Int64, Int64)] {
            session.tapMap(at: PlanPoint(x: x, y: y), reach: 512)
        }
        XCTAssertEqual(session.lineDraft, [stations[0], stations[2], stations[3]])
        XCTAssertEqual(session.lineDraftStops, [stations[0], stations[2], stations[3]], "by the loop, not the straight track")
    }

    /// A line round a hairpin: S0, S1 and S2 along the top track, which
    /// turns round to run back west below, where Bottom stands under S1.
    /// From where the stations stand Bottom fits between S1 and S2, which
    /// no train could drive; on the track it is after S2.
    func testAddingAStationWhereItFitsFollowsTheTrack() throws {
        var world = try makeWorld(width: 16_384, height: 8_192, balance: 100_000_000, speed: .normal)
        let top = TestLine(tiles: 11, row: 1)
        try top.build(in: &world)
        for x in (0...10).reversed() {
            let centre = TestLine.centre(x, 3)
            try world.buildTrackNode(at: WorldCoordinate(x: centre.x, y: centre.y))
        }
        try world.buildTrackEdge(from: .node(11), to: .node(12), curve: .cubic(TestLine.centre(12, 1), TestLine.centre(12, 3)))
        for k in 0..<10 { try world.buildTrackEdge(from: .node(12 + k), to: .node(13 + k)) }
        let stops = try [1, 5, 9].map { try top.buildStation(named: "S\($0)", beside: $0, at: 0, in: &world) }
        // Under S1, on the bottom track: edge 16 runs from column 6 to 5,
        // edge 17 from 5 to 4.
        let bottom = try world.buildStation(named: "Bottom", at: TestLine.centre(5, 4)).id
        try world.addTrackPlatform(bottom, on: .edge(16), from: TestLine.tile / 2, to: TestLine.tile)
        try world.addTrackPlatform(bottom, on: .edge(17), from: 0, to: TestLine.tile / 2)
        let id = try world.createLine(named: "Hairpin", stops: stops).id
        XCTAssertEqual(
            LineStopEditing.insertionIndex(of: TestLine.centre(5, 4), into: stops.compactMap { world.station(id: $0)?.point }), 2,
            "where the stations stand alone puts it between S1 and S2"
        )

        let session = GameSession(world: world)
        session.selectLine(id)
        session.addStationToSelectedLine(bottom)
        XCTAssertEqual(session.world.line(id: id)?.stops, stops + [bottom], session.message?.text ?? "")
        XCTAssertNotNil(session.world.lineJourney(id))
        XCTAssertTrue(isDrawn(id, in: session.world))
    }

    func testNoPlaceForFewerThanTwoStopsOrAStationAlreadyOnTheLine() throws {
        let (world, stations) = try straightWorld()
        XCTAssertNil(world.trackInsertionIndex(of: stations[3], into: [stations[0]], preferring: 1))
        XCTAssertNil(world.trackInsertionIndex(of: stations[0], into: [stations[0], stations[5]], preferring: 2))
        XCTAssertEqual(world.trackInsertionIndex(of: stations[3], into: [stations[0], stations[5]], preferring: 2), 1)
    }
}
