import GameCore
@testable import GamePresentation
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

    /// The tutorial's and lesson 2's "Tap Station… to see who rides": the
    /// panel opens at the riders, where trips by the hour and who is
    /// waiting are, not at the operations above them.
    func testTheRidershipStepOpensTheRidersGroup() throws {
        let step = try XCTUnwrap(Tutorial.standardSteps.first { $0.id == "station.ridership" })
        XCTAssertEqual(StationPanelGroup.opening(for: step), .riders)
        XCTAssertTrue(StationPanelGroup.riders.parts.contains(.tripsByHour))
        XCTAssertTrue(StationPanelGroup.riders.parts.contains(.passengers), "Who is waiting is in the riders group too")
        let lessonTwo = try XCTUnwrap(Lesson.all.first { $0.number == 2 })
        XCTAssertTrue(lessonTwo.guide.contains { $0.id == "station.ridership" }, "Lesson 2 ends on the same step")
    }

    func testOtherStepsOpenThePanelAtItsTop() throws {
        XCTAssertNil(StationPanelGroup.opening(for: nil))
        let freight = try XCTUnwrap(Lesson.all.first { $0.number == 8 }?.guide.first { $0.id == "lesson.8.panel" })
        XCTAssertNil(StationPanelGroup.opening(for: freight), "Lesson 8 scrolls to its freight yard itself")
    }
}
