import GameCore
import GamePresentation
import XCTest

/// Decision 568: while a new line is picked on the map, the screen puts away
/// what is not about it, says the draft once (in the map's pill) and keeps
/// the pill off the cards and buttons over the map. The owner's report: a
/// phone held sideways, five stations picked, the draft's line in the pill
/// and again in the lines panel, the pill over the layer's legend, and the
/// layer strip, the next step, the map's expansion and Undo all still out.
@MainActor
final class LineDrawingChromeTests: XCTestCase {
    private let track = TestLine(tiles: 7, row: 1)

    private func makeSession() throws -> (session: GameSession, stations: [StationID]) {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        try track.build(in: &world)
        let alpha = try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let gamma = try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        return (GameSession(world: world, language: .english), [alpha, gamma])
    }

    func testNothingIsPutAwayUntilAStationIsPicked() throws {
        let (session, _) = try makeSession()
        XCTAssertEqual(session.lineDrawingChrome(linesPanelOpen: false), LineDrawingChrome(isDrawing: false))
        session.startPickingLineStops(announces: false)
        // No station yet: the pill is not out, and the panel says what to
        // tap, so it is said once.
        let chrome = session.lineDrawingChrome(linesPanelOpen: true)
        XCTAssertFalse(chrome.isDrawing)
        XCTAssertTrue(chrome.panelShowsSummary)
        XCTAssertTrue(chrome.showsLayers)
        XCTAssertTrue(chrome.showsWorldEdits)
    }

    func testPickingALinePutsTheRestAwayAndSaysTheDraftOnce() throws {
        let (session, stations) = try makeSession()
        session.selectStation(stations[0])
        session.startLineFromSelectedStation()
        session.selectStation(stations[1])
        session.addSelectedStationToLineDraft()
        XCTAssertNotNil(session.mapLineDraft, "the pill shows the draft")

        for panel in [true, false] {
            let chrome = session.lineDrawingChrome(linesPanelOpen: panel)
            XCTAssertTrue(chrome.isDrawing, "lines panel open: \(panel)")
            XCTAssertFalse(chrome.panelShowsSummary, "the pill says it; the panel does not again")
            XCTAssertFalse(chrome.showsLayers)
            XCTAssertFalse(chrome.showsMapExpansion)
            XCTAssertFalse(chrome.showsWorldEdits, "the pill's ↶ is the one taking back")
            XCTAssertTrue(chrome.foldsLegend)
        }

        // ✓ (or ✕): all back as it was.
        session.createLineFromDraft()
        XCTAssertEqual(session.lineDrawingChrome(linesPanelOpen: true), LineDrawingChrome(isDrawing: false))
    }

    func testClearingTheDraftPutsEverythingBack() throws {
        let (session, stations) = try makeSession()
        session.selectStation(stations[0])
        session.startLineFromSelectedStation()
        XCTAssertTrue(session.lineDrawingChrome(linesPanelOpen: false).isDrawing)
        session.clearLineDraft()
        let chrome = session.lineDrawingChrome(linesPanelOpen: false)
        XCTAssertFalse(chrome.isDrawing)
        XCTAssertTrue(chrome.showsLayers)
        XCTAssertTrue(chrome.showsMapExpansion)
        XCTAssertTrue(chrome.showsWorldEdits)
        XCTAssertFalse(chrome.foldsLegend)
    }

    func testABuildingToolKeepsItsOwnPillAndTheScreen() throws {
        let (session, stations) = try makeSession()
        session.selectStation(stations[0])
        session.startLineFromSelectedStation()
        session.selectTool(.network)
        // Off the lines panel a tap on the map lays track, not stations:
        // the pill is the tool's, and the panel keeps the draft's line.
        XCTAssertFalse(session.drawsLineOnMap(linesPanelOpen: false))
        XCTAssertFalse(session.lineDrawingChrome(linesPanelOpen: false).isDrawing)
        XCTAssertTrue(session.drawsLineOnMap(linesPanelOpen: true))
    }

    func testTheTutorialKeepsItsControlsWhereItsStepsPoint() throws {
        let (session, stations) = try makeSession()
        session.startTutorial()
        session.selectStation(stations[0])
        session.startLineFromSelectedStation()
        if session.mapLineDraft != nil {
            XCTAssertTrue(session.drawsLineOnMap(linesPanelOpen: true))
        }
        XCTAssertFalse(session.lineDrawingChrome(linesPanelOpen: true).isDrawing)
    }
}

/// Decision 568: the pill keeps off every card and button over the map, not
/// only the first it was moved off.
final class BuildConfirmKeepingOffTests: XCTestCase {
    private static let pill = (width: 300.0, height: 70.0)

    private func place(_ obstacles: [ScreenFrame], x: Double, y: Double, lowest: Double = 330) -> (x: Double, y: Double) {
        BuildConfirmLayout.keepingOff(
            obstacles, x: x, y: y, width: Self.pill.width, height: Self.pill.height,
            minX: 90, maxX: 480, highest: 60, lowest: lowest
        )
    }

    private func clear(_ place: (x: Double, y: Double), of obstacles: [ScreenFrame], file: StaticString = #filePath, line: UInt = #line) {
        for frame in obstacles {
            XCTAssertFalse(
                BuildConfirmLayout.overlaps(x: place.x, y: place.y, width: Self.pill.width, height: Self.pill.height, frame),
                "the pill at \(place) covers \(frame)", file: file, line: line
            )
        }
    }

    func testAPillClearOfEverythingStaysPut() {
        let legend = ScreenFrame(x: 420, y: 300, width: 160, height: 80)
        let placed = place([legend], x: 100, y: 100)
        XCTAssertEqual(placed.x, 100)
        XCTAssertEqual(placed.y, 100)
    }

    func testThePillGoesAboveTheLegend() {
        // A phone on its side, the lines panel at the trailing side: the
        // layer's legend at the bottom beside it, the last station picked
        // just above.
        let legend = ScreenFrame(x: 400, y: 260, width: 180, height: 90)
        let placed = place([legend], x: 250, y: 230)
        clear(placed, of: [legend])
        XCTAssertEqual(placed.y, 260 - BuildConfirmLayout.margin - Self.pill.height)
    }

    func testMovedOffTheLegendItDoesNotLandOnTheButtonsAbove() {
        // The owner's report: above the legend stood the corner's buttons;
        // moved up off the one, the pill went over the other.
        let legend = ScreenFrame(x: 400, y: 240, width: 180, height: 110)
        let buttons = ScreenFrame(x: 380, y: 120, width: 200, height: 50)
        let placed = place([legend, buttons], x: 250, y: 220)
        clear(placed, of: [legend, buttons])
        XCTAssertGreaterThanOrEqual(placed.x, 90)
        XCTAssertLessThanOrEqual(placed.x, 480)
        XCTAssertGreaterThanOrEqual(placed.y, 60)
        XCTAssertLessThanOrEqual(placed.y, 330)
    }

    func testWithNoRoomAnywhereItCoversTheLeast() {
        // A band with no clear place: what it covers is the least it can.
        let wall = ScreenFrame(x: 0, y: 0, width: 1_000, height: 1_000)
        let placed = place([wall], x: 200, y: 200)
        XCTAssertEqual(placed.x, 200)
        XCTAssertEqual(placed.y, 200)
    }
}
