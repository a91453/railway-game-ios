import GameCore
@testable import GamePresentation
import XCTest

/// Decision 911: the station panel's pages over the whole screen, what
/// each holds and when a page stands in two columns.
final class StationPageLayoutTests: XCTestCase {
    private let layouts = [true, false].map { StationPageLayout(StationPageLayout.Facts(showsFreight: $0)) }

    func testThePagesAreTheGroupsInOrder() {
        for layout in layouts {
            XCTAssertEqual(layout.pages, [.operations, .riders, .area, .freight])
        }
    }

    func testEachPageHoldsItsGroupInTheOneListsOrder() {
        let layout = StationPageLayout(StationPageLayout.Facts(showsFreight: true))
        for page in layout.pages {
            XCTAssertEqual(layout.columns(of: page).all, page.parts, "\(page)")
        }
    }

    func testEverySectionIsOnExactlyOnePage() {
        let layout = StationPageLayout(StationPageLayout.Facts(showsFreight: true))
        let shown = layout.pages.flatMap { layout.columns(of: $0).all }
        XCTAssertEqual(shown.count, Set(shown).count, "A section on two pages")
        XCTAssertEqual(Set(shown), Set(StationPanelPart.allCases))
        for part in StationPanelPart.allCases {
            XCTAssertTrue(layout.columns(of: layout.page(of: part)).all.contains(part), "\(part)")
        }
    }

    func testWithoutFreightTheLastPageIsTheRemovalAlone() {
        let layout = StationPageLayout(StationPageLayout.Facts(showsFreight: false))
        XCTAssertEqual(layout.columns(of: .freight).all, [.removal])
        XCTAssertFalse(layout.isSplit(.freight, width: 1200, accessibilitySize: false))
        XCTAssertTrue(StationPageLayout(StationPageLayout.Facts(showsFreight: true)).isSplit(.freight, width: 1200, accessibilitySize: false))
    }

    func testTheEverydayRowsLeadTheFirstPage() {
        let leading = layouts[0].columns(of: .operations).leading
        XCTAssertEqual(Array(leading.prefix(4)), [.buyLine, .operations, .departureBoard, .journey])
    }

    func testTwoColumnsOnlyWhenWideAndTheTextIsNotLarge() {
        let layout = layouts[0]
        for page in layout.pages {
            XCTAssertFalse(layout.isSplit(page, width: 639, accessibilitySize: false), "\(page)")
            XCTAssertTrue(layout.isSplit(page, width: 640, accessibilitySize: false), "\(page)")
            XCTAssertFalse(layout.isSplit(page, width: 1366, accessibilitySize: true), "\(page)")
        }
        XCTAssertEqual(StationPageLayout.twoColumnWidth, EconomyLayout.twoColumnWidth)
    }

    func testOneColumnStandsAtAReadableWidth() {
        XCTAssertEqual(StationPageLayout.oneColumnWidth(in: 390), 390)
        XCTAssertEqual(StationPageLayout.oneColumnWidth(in: 1366), StationPageLayout.oneColumnMaxWidth)
    }

    func testABubbleOpensAtItsPageAndTheTutorialsButtonsAreFound() {
        let layout = layouts[0]
        XCTAssertEqual(layout.opening(at: nil), .operations)
        XCTAssertEqual(layout.opening(at: StationPanelGroup.answering(.materialsShort)), .freight)
        XCTAssertEqual(layout.page(holding: .freightYard), .freight)
    }

    func testThePagesNamesAreShortEnoughForAPhoneHeldUpright() {
        for language in DisplayLanguage.allCases {
            let total = StationPanelGroup.allCases.map { $0.pageTitle(in: language).count }.reduce(0, +)
            XCTAssertLessThanOrEqual(total, 30, "\(language)")
        }
    }
}
