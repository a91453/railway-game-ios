import GamePresentation
import XCTest

/// The map's ✕ and ✓ pill on the screen of TestFlight 67.1's report: an
/// iPhone 17 held on its side (874 points across), the tools down the
/// leading edge and the track card over the trailing third, and a refusal
/// of some 640 points on one line. The pill stood from the tools to under
/// the card, its words cut off at the card's edge.
final class BuildConfirmLayoutTests: XCTestCase {
    private static let viewport = 874.0
    /// The tools column, past the camera housing.
    private static let leading = 130.0
    /// The track card and its gap.
    private static let trailing = 300.0
    /// The refusal on one line, at the caption's size.
    private static let refusalWidth = 640.0

    func testALongRefusalStaysBetweenTheToolsAndTheCard() {
        let widest = BuildConfirmLayout.maximumWidth(viewportWidth: Self.viewport, leading: Self.leading, trailing: Self.trailing)
        XCTAssertEqual(widest, 874 - 130 - 300 - 16)
        XCTAssertLessThan(widest, Self.refusalWidth, "The refusal wraps")
        let width = min(Self.refusalWidth, widest)
        for anchor in [0.0, 300, 437, 700, 874] {
            let x = BuildConfirmLayout.originX(
                anchorX: anchor, width: width, viewportWidth: Self.viewport, leading: Self.leading, trailing: Self.trailing
            )
            XCTAssertGreaterThanOrEqual(x, Self.leading, "Under the tools, anchored at \(anchor)")
            XCTAssertLessThanOrEqual(x + width, Self.viewport - Self.trailing, "Under the card, anchored at \(anchor)")
        }
    }

    func testAShortPillStaysCentredOnItsAnchor() {
        let x = BuildConfirmLayout.originX(
            anchorX: 300, width: 120, viewportWidth: Self.viewport, leading: Self.leading, trailing: Self.trailing
        )
        XCTAssertEqual(x, 240)
    }

    func testASqueezedMapKeepsTheWordsReadable() {
        let widest = BuildConfirmLayout.maximumWidth(viewportWidth: 400, leading: 130, trailing: 300)
        XCTAssertEqual(widest, BuildConfirmLayout.minimumWidth)
        // Wider than the band: at its leading side, not under the tools.
        XCTAssertEqual(BuildConfirmLayout.originX(anchorX: 200, width: widest, viewportWidth: 400, leading: 130, trailing: 300), 138)
    }
}
