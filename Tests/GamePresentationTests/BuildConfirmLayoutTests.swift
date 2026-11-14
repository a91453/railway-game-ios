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

    /// Decision 744, a player's report (2026-11-14): choosing where a
    /// station goes, the pill stood over the line the station goes on. A
    /// line rising across the map, the place picked at its middle: the
    /// pill, which first stood under the place, is moved where it covers
    /// neither the place nor the track near it.
    func testThePillKeepsOffTheSiteAndItsTrack() {
        let line = [ScreenPoint(x: 100, y: 100), ScreenPoint(x: 800, y: 300)]
        let anchor = ScreenPoint(x: 450, y: 200)
        let width = 300.0, height = 120.0
        let obstacles = BuildConfirmLayout.siteObstacles([line], around: anchor, reach: width + 16)
        XCTAssertEqual(obstacles.first, ScreenFrame(x: 438, y: 188, width: 24, height: 24), "the place itself first")
        XCTAssertGreaterThan(obstacles.count, 1)
        XCTAssertLessThanOrEqual(obstacles.count, 17)
        let x = anchor.x - width / 2, y = anchor.y + 18
        XCTAssertTrue(
            obstacles.contains { BuildConfirmLayout.overlaps(x: x, y: y, width: width, height: height, $0) },
            "under the place, the pill covers the line"
        )
        let placed = BuildConfirmLayout.keepingOff(
            obstacles, x: x, y: y, width: width, height: height, minX: 8, maxX: 874 - 8 - width, highest: 8, lowest: 402 - 8 - height
        )
        for frame in obstacles {
            XCTAssertFalse(
                BuildConfirmLayout.overlaps(x: placed.x, y: placed.y, width: width, height: height, frame),
                "clear of \(frame)"
            )
        }
    }

    /// Only the pieces near the place count, nearest first, at most the
    /// limit.
    func testOnlyTheNearestPiecesOfTrackCount() {
        let long = [ScreenPoint(x: -5_000, y: 50), ScreenPoint(x: 5_000, y: 50)]
        let obstacles = BuildConfirmLayout.siteObstacles([long], around: ScreenPoint(x: 0, y: 50), reach: 200, limit: 4)
        XCTAssertEqual(obstacles.count, 5)
        for frame in obstacles.dropFirst() {
            XCTAssertLessThanOrEqual(abs(frame.x + frame.width / 2), 200)
        }
        XCTAssertEqual(BuildConfirmLayout.siteObstacles([long], around: ScreenPoint(x: 0, y: 900), reach: 200).count, 1)
    }
}
