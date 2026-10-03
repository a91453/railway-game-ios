import GameCore
import GamePresentation
import XCTest

/// Ring lines in the line panel (decision 49): the switch, what the panel
/// says about a ring's service, its lap and its coverage, and counts in
/// pairs; on the demo map's Ring Line and on its other lines.
final class RingLineSessionTests: XCTestCase {
    /// The demo's ring: West, North, East and South, once round, with a
    /// two-car train each way. Its lap is four legs of 49 s and a minute at
    /// each stop, 436 s, planned as 8 minutes; one train each way is a
    /// train every 8 minutes each way.
    func testTheDemoRingReadsAsARing() throws {
        let world = DemoWorld.make(in: .english)
        let ring = world.lines[2].id
        let summaries = world.lineServiceSummaries(ring, in: .english)
        XCTAssertEqual(summaries.count, 1, "a ring has no patterns")
        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summary.title, "Ring")
        XCTAssertEqual(summary.callsText, "West · North · East · South · West, and half the trains the other way round")
        XCTAssertEqual(summary.levels[0].text(in: .english), "2 trains (1 each way) · Every 8 min each way")
        XCTAssertEqual(summary.assigned, 2)
        XCTAssertEqual(world.lineJourneyText(ring, in: .english), "Lap 7 min 16 s · legs 49 s, 49 s, 49 s, 49 s")
        XCTAssertNil(world.lineCoverageText(ring, at: .peak, in: .english))

        let chinese = DemoWorld.make(in: .traditionalChinese)
        let zh = try XCTUnwrap(chinese.lineServiceSummaries(ring, in: .traditionalChinese).first)
        XCTAssertEqual(zh.title, "環線")
        XCTAssertEqual(zh.callsText, "西站 · 北站 · 東站 · 南站 · 西站，一半列車反方向")
        XCTAssertEqual(zh.levels[0].text(in: .traditionalChinese), "2 列（每個方向 1 列）· 每個方向每 8 分鐘一班")
        XCTAssertEqual(chinese.lineJourneyText(ring, in: .traditionalChinese), "一圈 7 分 16 秒 · 各段 49 秒、49 秒、49 秒、49 秒")
    }

    /// The switch makes the selected line a ring, its count of one made
    /// even, none; counts then go in pairs, and with none the whole ring is
    /// uncovered. Line 1 runs on straight track, so as a ring it has no way
    /// back from East to West. Turning the switch off makes it a line
    /// again; a line of two stops cannot be a ring.
    @MainActor
    func testTheSwitchMakesALineARingAndBack() throws {
        let session = GameSession(world: DemoWorld.make(in: .english))
        let line = session.world.lines[0].id
        session.selectLine(line)
        session.setSelectedLineRing(true)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.message?.text, "Line 1 is a ring: its trains go on from the last stop to the first, half of them each way round.")
        XCTAssertEqual(session.selectedLine?.isRing, true)
        XCTAssertEqual(session.selectedLine?.trainsInService, TrainsInService(peak: 0, offPeak: 0, low: 0))
        XCTAssertEqual(session.world.lineCoverageText(line, at: .peak, in: .english), "Not covered: the whole ring")
        XCTAssertEqual(session.world.lineServiceSummaries(line, in: .english).first?.levels[0].text(in: .english), "No route")

        session.setSelectedLineTrains(3, at: .peak)
        XCTAssertEqual(session.selectedLine?.trainsInService.peak, 2, "in pairs")

        session.setSelectedLineRing(false)
        XCTAssertEqual(session.message?.text, "Line 1 turns round at its ends again.")
        XCTAssertEqual(session.selectedLine?.isRing, false)
        XCTAssertEqual(session.selectedLine?.trainsInService.peak, 2)

        // Two stops: refused, with the ring's rule.
        session.selectStation(session.world.stations[0].id)
        session.addSelectedStationToLineDraft()
        session.selectStation(session.world.stations[1].id)
        session.addSelectedStationToLineDraft()
        session.createLineFromDraft()
        let before = session.world
        session.setSelectedLineRing(true)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(
            session.message?.text,
            "A line calls at two stations or more, and not at the same station twice in a row. A ring calls at three or more, and not at the same station first and last."
        )
        XCTAssertEqual(session.world, before)
    }
}
