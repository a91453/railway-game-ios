import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 80: adding a station to a line where it fits
/// (MapBuilder's `handleAddStationToLine` and `ef`), reversing a line's
/// stops and copying a line. Expected indices are worked out by hand from
/// the reference's score: the turn over 180° plus the new leg over the
/// typical distance, the lowest up to 2 winning, the later of equals.
@MainActor
final class RouteEditingSessionTests: XCTestCase {
    private static func points(_ xs: [Int64]) -> [PlanPoint] {
        xs.map { PlanPoint(x: $0, y: 1_024) }
    }

    // MARK: - Where a station joins

    /// Stops at 0, 1000 and 2000 along a straight line; the typical
    /// distance is the second smallest of the three.
    func testAStationBetweenTwoStopsGoesBetweenThem() {
        // From 1500: distances 1500, 500, 500, typical 500. Before the first:
        // a U-turn, 1 + 1500/500. Between 0 and 1000: a U-turn, 1 + 500/500
        // = 2. Between 1000 and 2000: straight on, 0 + 500/500 = 1. After
        // the last: a U-turn, 1 + 500/500 = 2, not below 1.
        XCTAssertEqual(LineStopEditing.insertionIndex(of: PlanPoint(x: 1_500, y: 1_024), into: Self.points([0, 1_000, 2_000])), 2)
    }

    func testAStationBeyondAnEndGoesAtThatEnd() {
        // From 3000: typical 2000. After the last: straight on, 1000/2000 =
        // 0.5; between 1000 and 2000: a U-turn, 1 + 1000/2000.
        XCTAssertEqual(LineStopEditing.insertionIndex(of: PlanPoint(x: 3_000, y: 1_024), into: Self.points([0, 1_000, 2_000])), 3)
        // From −1000: typical 2000. Before the first: straight on, 0.5.
        XCTAssertEqual(LineStopEditing.insertionIndex(of: PlanPoint(x: -1_000, y: 1_024), into: Self.points([0, 1_000, 2_000])), 0)
    }

    /// A station off to the side of a leg: the turn there is the larger
    /// angle, so it joins the leg it is beside.
    func testAStationBesideALegJoinsThatLeg() {
        let stops = [PlanPoint(x: 0, y: 0), PlanPoint(x: 4_000, y: 0), PlanPoint(x: 8_000, y: 0)]
        XCTAssertEqual(LineStopEditing.insertionIndex(of: PlanPoint(x: 6_000, y: 500), into: stops), 2)
        XCTAssertEqual(LineStopEditing.insertionIndex(of: PlanPoint(x: 2_000, y: -500), into: stops), 1)
    }

    /// Fewer than two stops: first, as the reference's `ef`.
    func testAShortListTakesItFirst() {
        XCTAssertEqual(LineStopEditing.insertionIndex(of: PlanPoint(x: 5, y: 5), into: []), 0)
        XCTAssertEqual(LineStopEditing.insertionIndex(of: PlanPoint(x: 5, y: 5), into: Self.points([0])), 0)
    }

    // MARK: - The session

    /// Three stations in a row and a line calling at the two ends.
    private func makeSession(language: DisplayLanguage = .english) throws -> (GameSession, [StationID], LineID) {
        var world = try makeWorld(width: 16_384, height: 8_192, balance: 100_000)
        let stations = try [("West", 1_024), ("Middle", 4_096), ("East", 8_192)].map { name, x in
            try world.buildStation(named: name, at: PlanPoint(x: Int64(x), y: 2_048)).id
        }
        let line = try world.createLine(named: "Line 1", stops: [stations[0], stations[2]]).id
        let session = GameSession(world: world, language: language)
        session.selectLine(line)
        return (session, stations, line)
    }

    func testAStationIsAddedWhereItFits() throws {
        let (session, stations, line) = try makeSession()
        session.addStationToSelectedLine(stations[1])
        XCTAssertEqual(session.world.line(id: line)?.stops, stations, "between the two ends")
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Line 1 now calls at West – Middle – East."))

        session.undo()
        XCTAssertEqual(session.world.line(id: line)?.stops, [stations[0], stations[2]])
    }

    /// The stops picked for a new line keep the order they were picked in;
    /// only an existing line's stops are placed (the tutorial's "create a
    /// line" step relies on it).
    func testANewLineKeepsTheOrderItsStopsWerePicked() throws {
        let (session, stations, _) = try makeSession()
        for station in [stations[0], stations[2], stations[1]] {
            session.selectStation(station)
            session.addSelectedStationToLineDraft()
        }
        XCTAssertEqual(session.lineDraft, [stations[0], stations[2], stations[1]])
        session.createLineFromDraft()
        XCTAssertEqual(session.selectedLine?.stops, [stations[0], stations[2], stations[1]])
    }

    func testTheStopsAreReversed() throws {
        let (session, stations, line) = try makeSession(language: .traditionalChinese)
        session.addStationToSelectedLine(stations[1])
        session.reverseSelectedLine()
        XCTAssertEqual(session.world.line(id: line)?.stops, stations.reversed())
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "已反轉 Line 1 的站序：East – Middle – West。"))
        XCTAssertEqual(session.undoCount, 2)

        session.undo()
        XCTAssertEqual(session.world.line(id: line)?.stops, stations)
    }

    func testACopyIsSelectedAndUndoneAsOne() throws {
        let (session, stations, line) = try makeSession()
        session.duplicateSelectedLine()
        let copy = try XCTUnwrap(session.selectedLine)
        XCTAssertNotEqual(copy.id, line)
        XCTAssertEqual(copy.name, "Line 1 - Fork")
        XCTAssertEqual(copy.stops, [stations[0], stations[2]])
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Copied Line 1 as Line 1 - Fork. Assign trains to run it."))

        session.undo()
        XCTAssertNil(session.world.line(id: copy.id))
        XCTAssertNil(session.selectedLineID, "the copy is gone")
        XCTAssertEqual(session.world.lines.map(\.id), [line])
    }

    func testTheCopyIsNamedInTheSessionsLanguage() throws {
        let (session, _, _) = try makeSession(language: .traditionalChinese)
        session.duplicateSelectedLine()
        XCTAssertEqual(session.selectedLine?.name, "Line 1 - 分支")
    }

    func testWithoutASelectedLineNothingChanges() throws {
        let (_, stations, _) = try makeSession()
        let world = try makeWorld()
        let empty = GameSession(world: world)
        empty.addStationToSelectedLine(stations[1])
        empty.reverseSelectedLine()
        empty.duplicateSelectedLine()
        XCTAssertEqual(empty.world, world)
        XCTAssertEqual(empty.undoCount, 0)
        XCTAssertEqual(empty.message?.kind, .failure)
    }
}
