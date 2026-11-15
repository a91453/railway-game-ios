import GameCore
@testable import GamePresentation
import XCTest

/// Decision 776: the pages of a line's own page, what each holds and when
/// a page stands in two columns.
final class LineDetailLayoutTests: XCTestCase {
    private func facts(
        isFreight: Bool = false, hasReport: Bool = true, showsTrains: Bool = true, showsDepots: Bool = true,
        rebuildsAsReal: Bool = false, hasServices: Bool = true
    ) -> LineDetailLayout.Facts {
        LineDetailLayout.Facts(
            isFreight: isFreight, hasReport: hasReport, showsTrains: showsTrains, showsDepots: showsDepots,
            rebuildsAsReal: rebuildsAsReal, hasServices: hasServices
        )
    }

    private func everyFacts() -> [LineDetailLayout.Facts] {
        (0..<64).map { bits in
            facts(
                isFreight: bits & 1 != 0, hasReport: bits & 2 != 0, showsTrains: bits & 4 != 0, showsDepots: bits & 8 != 0,
                rebuildsAsReal: bits & 16 != 0, hasServices: bits & 32 != 0
            )
        }
    }

    func testAPassengerLineHasFourPagesInOrder() {
        let layout = LineDetailLayout(facts())
        XCTAssertEqual(layout.pages, [.overview, .trains, .stops, .settings])
        XCTAssertEqual(layout.columns(of: .overview).leading, [.summary, .feedback])
        XCTAssertEqual(layout.columns(of: .overview).trailing, [.operations, .load])
        XCTAssertEqual(layout.columns(of: .trains).all, [.trains, .depots])
        XCTAssertEqual(layout.columns(of: .stops).all, [.stops, .services])
        XCTAssertEqual(layout.columns(of: .settings).all, [.settings])
    }

    func testEverySectionTheLongFormHadIsOnOnePageAtMost() {
        for facts in everyFacts() {
            let layout = LineDetailLayout(facts)
            let shown = layout.pages.flatMap { layout.columns(of: $0).all }
            XCTAssertEqual(shown.count, Set(shown).count, "\(facts)")
            XCTAssertEqual(layout.pages.first, .overview, "\(facts)")
            XCTAssertEqual(layout.columns(of: .overview).leading.first, .summary)
            XCTAssertTrue(shown.contains(.stops) && shown.contains(.settings))
            XCTAssertEqual(shown.contains(.depots), facts.showsDepots, "\(facts)")
            XCTAssertEqual(shown.contains(.realRebuild), facts.rebuildsAsReal, "\(facts)")
            XCTAssertEqual(shown.contains(.trains), facts.showsTrains, "\(facts)")
        }
    }

    func testAFreightLineHasNoRidersChartsAndOneColumnOverview() {
        let layout = LineDetailLayout(facts(isFreight: true))
        XCTAssertEqual(layout.columns(of: .overview).all, [.summary, .feedback])
        XCTAssertFalse(layout.isSplit(.overview, width: 1_000, accessibilitySize: false))
    }

    func testARingHasNoTrainsPageAndKeepsItsDepotsInSettings() {
        let layout = LineDetailLayout(facts(showsTrains: false, rebuildsAsReal: true))
        XCTAssertEqual(layout.pages, [.overview, .stops, .settings])
        XCTAssertEqual(layout.columns(of: .settings).trailing, [.depots, .realRebuild])
        XCTAssertEqual(layout.page(of: .depots), .settings)
        XCTAssertEqual(layout.showing(.trains), .overview)
        XCTAssertEqual(layout.showing(.stops), .stops)
    }

    func testTwoColumnsOnlyWhenWideWithBothColumnsAndNormalText() {
        let layout = LineDetailLayout(facts())
        XCTAssertTrue(layout.isSplit(.overview, width: 700, accessibilitySize: false))
        XCTAssertFalse(layout.isSplit(.overview, width: 600, accessibilitySize: false))
        XCTAssertFalse(layout.isSplit(.overview, width: 1_000, accessibilitySize: true))
        XCTAssertFalse(layout.isSplit(.settings, width: 1_000, accessibilitySize: false))
        XCTAssertFalse(LineDetailLayout(facts(hasServices: false)).isSplit(.stops, width: 1_000, accessibilitySize: false))
    }

    func testThePagesHaveNamesInBothLanguages() {
        XCTAssertEqual(LineDetailPage.allCases.map { $0.title(in: .traditionalChinese) }, ["總覽", "列車", "停靠站", "設定"])
        XCTAssertEqual(LineDetailPage.allCases.map { $0.title(in: .english) }, ["Overview", "Trains", "Stops", "Settings"])
    }
}
