import GamePresentation
import XCTest

final class ScrollEdgeFadeTests: XCTestCase {
    func testARowThatFitsHasNoFade() {
        XCTAssertEqual(ScrollEdgeFade(offset: 0, contentWidth: 300, viewportWidth: 320), .none)
        XCTAssertEqual(ScrollEdgeFade(offset: 0, contentWidth: 320, viewportWidth: 320), .none)
    }

    func testAtTheStartOnlyTheFarEndFades() {
        XCTAssertEqual(ScrollEdgeFade(offset: 0, contentWidth: 500, viewportWidth: 320), ScrollEdgeFade(leading: 0, trailing: 1))
    }

    func testScrolledToTheEndOnlyTheStartFades() {
        XCTAssertEqual(ScrollEdgeFade(offset: 180, contentWidth: 500, viewportWidth: 320), ScrollEdgeFade(leading: 1, trailing: 0))
    }

    func testInTheMiddleBothEndsFade() {
        XCTAssertEqual(ScrollEdgeFade(offset: 90, contentWidth: 500, viewportWidth: 320), ScrollEdgeFade(leading: 1, trailing: 1))
    }

    func testTheFadeGrowsOverItsWidthNearAnEnd() {
        let half = ScrollEdgeFade.width / 2
        XCTAssertEqual(ScrollEdgeFade(offset: half, contentWidth: 500, viewportWidth: 320).leading, 0.5)
        XCTAssertEqual(ScrollEdgeFade(offset: 180 - half, contentWidth: 500, viewportWidth: 320).trailing, 0.5)
    }

    func testRoundingAndBouncePastAnEndShowNoFade() {
        XCTAssertEqual(ScrollEdgeFade(offset: 0.3, contentWidth: 500, viewportWidth: 320).leading, 0)
        XCTAssertEqual(ScrollEdgeFade(offset: -20, contentWidth: 500, viewportWidth: 320).leading, 0)
        XCTAssertEqual(ScrollEdgeFade(offset: 200, contentWidth: 500, viewportWidth: 320).trailing, 0)
        XCTAssertEqual(ScrollEdgeFade(offset: .nan, contentWidth: 500, viewportWidth: 320), .none)
    }
}
