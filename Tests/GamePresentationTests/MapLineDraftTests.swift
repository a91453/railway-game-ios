import GameCore
import GamePresentation
import XCTest

/// Decision 100, later: a new line picked and created on the map, and a
/// station added to the selected line from the map (decision 196, later).
@MainActor
final class MapLineDraftTests: XCTestCase {
    private let track = TestLine(tiles: 7, row: 1)

    private func makeStations() throws -> (world: GameWorld, stations: [StationID]) {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        try track.build(in: &world)
        let alpha = try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let beta = try track.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        let gamma = try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        return (world, [alpha, beta, gamma])
    }

    func testNothingIsDrawnUntilALineIsPicked() throws {
        let (world, _) = try makeStations()
        let session = GameSession(world: world, language: .english)
        XCTAssertNil(session.mapLineDraft)
        session.startPickingLineStops(announces: false)
        XCTAssertNil(session.mapLineDraft, "no station picked yet")
    }

    func testTheDraftAsksForTheNextStationThenCreatesTheLine() throws {
        let (world, stations) = try makeStations()
        let session = GameSession(world: world, language: .english)
        session.selectStation(stations[0])
        session.startLineFromSelectedStation()
        let first = try XCTUnwrap(session.mapLineDraft)
        XCTAssertFalse(first.canCreate)
        XCTAssertEqual(first.caption, "Tap the line's next station")
        XCTAssertEqual(first.anchor, world.station(id: stations[0])?.point)

        session.selectStation(stations[2])
        session.addSelectedStationToLineDraft()
        let draft = try XCTUnwrap(session.mapLineDraft)
        XCTAssertTrue(draft.canCreate)
        // The track passes Beta, which the line calls at too.
        XCTAssertEqual(draft.calls.count, 3)
        XCTAssertEqual(draft.picked.count, 2)
        XCTAssertEqual(draft.anchor, world.station(id: stations[2])?.point)
        // The draft's one line (CTM study 4.2): stops, length, time.
        XCTAssertEqual(draft.caption, "3 stops · 56 m · about 2 min")

        let chinese = GameSession(world: world, language: .traditionalChinese)
        chinese.selectStation(stations[0])
        chinese.startLineFromSelectedStation()
        chinese.selectStation(stations[2])
        chinese.addSelectedStationToLineDraft()
        XCTAssertEqual(chinese.mapLineDraft?.caption, "3 站 · 56 m · 約 2 分")

        session.createLineFromDraft()
        XCTAssertEqual(session.world.lines.count, 1)
        XCTAssertNil(session.mapLineDraft, "the draft is gone once the line is made")
    }

    func testASelectedStationOffTheSelectedLineCanJoinIt() throws {
        var (world, stations) = try makeStations()
        let main = try world.createLine(named: "Main", stops: [stations[0], stations[1]]).id
        let session = GameSession(world: world, language: .english)
        session.selectLine(main)
        session.selectStation(stations[1])
        XCTAssertNil(session.mapStopSuggestion, "the line already calls there")
        session.selectStation(stations[2])
        let suggestion = try XCTUnwrap(session.mapStopSuggestion)
        XCTAssertEqual(suggestion.caption, "Add Gamma to Main")
        XCTAssertEqual(suggestion.line, main)

        session.addStationToSelectedLine(suggestion.station)
        XCTAssertEqual(session.world.line(id: main)?.stops, stations)
        XCTAssertNil(session.mapStopSuggestion)

        // Not while a new line is picked.
        session.selectStation(stations[0])
        session.startLineFromSelectedStation()
        XCTAssertNil(session.mapStopSuggestion)
    }
}
