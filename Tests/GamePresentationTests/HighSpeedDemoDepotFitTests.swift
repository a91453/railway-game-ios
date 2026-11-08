@testable import GamePresentation
import XCTest

/// Decision 661 (review L13-10): a timetable whose night sets the depots
/// cannot hold, or a depot that keeps a line the spec does not have, makes
/// the high-speed demo's layout throw rather than stop the app; and a
/// depot names the lines it keeps, so the kinds' order does not move them.
final class HighSpeedDemoDepotFitTests: XCTestCase {
    /// Every depot one siding: the north end's sets at night fit nowhere.
    func testDepotsTooSmallForTheNightSetsThrow() throws {
        var spec = HighSpeedDemo.spec
        spec.depots = spec.depots.map { var depot = $0; depot.sidings = 1; return depot }
        XCTAssertThrowsError(try HighSpeedDemo.Layout(railways: HighSpeedDemoTests.railways(), spec: spec)) { error in
            XCTAssertEqual(error as? HighSpeedDemo.Failure, .depotsDoNotFit)
        }
    }

    /// A depot keeping a line no kind of the spec is.
    func testADepotKeepingAnUnknownLineThrows() throws {
        var spec = HighSpeedDemo.spec
        spec.depots[0].lines = ["THSR Seven Stops"]
        XCTAssertThrowsError(try HighSpeedDemo.Layout(railways: HighSpeedDemoTests.railways(), spec: spec)) { error in
            XCTAssertEqual(error as? HighSpeedDemo.Failure, .depotsDoNotFit)
        }
    }

    /// The lines a depot keeps follow the kinds' names wherever they stand.
    func testADepotsLinesFollowTheKindsNamesNotTheirOrder() {
        let kinds = HighSpeedDemo.spec.kinds
        let nangang = HighSpeedDemo.realDepots[0], liujia = HighSpeedDemo.realDepots[1]
        XCTAssertEqual(nangang.lineIndices(in: kinds), [0, 1])
        XCTAssertEqual(liujia.lineIndices(in: kinds), [2])
        let reversed = Array(kinds.reversed())
        XCTAssertEqual(nangang.lineIndices(in: reversed), [2, 1])
        XCTAssertEqual(liujia.lineIndices(in: reversed), [0])
        XCTAssertNil(HighSpeedDemo.realDepots[2].lineIndices(in: kinds), "Wuri keeps every line's sets")
    }
}
