import GameCore
import GamePresentation
import XCTest

/// Decision 477: a bubble about a town short of materials opens its
/// station's panel at the freight group, where the materials row is.
final class StationPanelFocusTests: XCTestCase {
    func testAShortOfMaterialsBubbleOpensTheFreightGroup() {
        XCTAssertEqual(StationPanelGroup.answering(.materialsShort), .freight)
        XCTAssertTrue(StationPanelGroup.freight.parts.contains(.freight), "The materials row is in the freight section")
    }

    func testOtherBubblesOpenThePanelAtItsTop() {
        XCTAssertNil(StationPanelGroup.answering(.crowded(waiting: 120)))
        XCTAssertNil(StationPanelGroup.answering(.full(waiting: 300)))
    }
}
