@testable import GameCore
import XCTest

/// Decision 890 (FUKUOKA-LATE): the home signal (decision 849) is also
/// for a line whose runs not running its whole length only take a train
/// out of a station between its ends before the day's first whole run
/// the same way calls there, or into one after the last (the positioning
/// runs of a line with no depot), never for one with short runs turning
/// back between its ends in the day.
final class ShortRunsAtDayEdgesTests: XCTestCase {
    /// Four stops, 0 to 3, two minutes apart; whole runs each way at
    /// 06:00 and 06:30 (up) and 06:10 and 06:40 (down).
    private func line(adding extra: [LineRun]) -> ServiceLine {
        var line = ServiceLine(id: LineID(rawValue: 1), name: "L", stops: (1...4).map { StationID(rawValue: $0) })
        line.runs = [run(0, 3, at: 360), run(0, 3, at: 390), run(3, 0, at: 370), run(3, 0, at: 400)] + extra
        return line
    }

    /// A run from stop `from` to stop `to` leaving at minute `minute`,
    /// two minutes a leg.
    private func run(_ from: Int, _ to: Int, at minute: Int64) -> LineRun {
        let legs = Int64(abs(to - from))
        return LineRun(from: from, to: to, times: (0...legs).map {
            LineRunTime(arrival: (minute + 2 * $0) * 60, departure: (minute + 2 * $0) * 60)
        })
    }

    func testWholeRunsOnlyNeedNothingMore() {
        XCTAssertTrue(line(adding: []).shortRunsOnlyAtDayEdges)
    }

    func testAMorningRunOutOfAStationBetween() {
        // Out of stop 2 toward 3 at 05:50, before 06:00's up run calls there
        // (06:04); and out of stop 1 toward 0 at 05:55, before 06:10's down
        // run calls there (06:14).
        XCTAssertTrue(line(adding: [run(2, 3, at: 350), run(1, 0, at: 355)]).shortRunsOnlyAtDayEdges)
    }

    func testANightRunIntoAStationBetween() {
        // Into stop 1 at 06:42, after 06:30's up run called there (06:32).
        XCTAssertTrue(line(adding: [run(0, 1, at: 400)]).shortRunsOnlyAtDayEdges)
    }

    func testAShortRunInTheDayIsNot() {
        // Out of stop 2 at 06:10, after 06:00's up run called there: a
        // short run turning back there in the day.
        XCTAssertFalse(line(adding: [run(2, 3, at: 370)]).shortRunsOnlyAtDayEdges)
        // Into stop 1 at 06:12, before 06:30's up run calls there.
        XCTAssertFalse(line(adding: [run(0, 1, at: 370)]).shortRunsOnlyAtDayEdges)
    }

    func testAShortRunWithNoWholeRunItsWayIsNot() {
        var line = ServiceLine(id: LineID(rawValue: 1), name: "L", stops: (1...4).map { StationID(rawValue: $0) })
        line.runs = [run(0, 3, at: 360), run(2, 0, at: 350)]
        XCTAssertFalse(line.shortRunsOnlyAtDayEdges)
    }
}
