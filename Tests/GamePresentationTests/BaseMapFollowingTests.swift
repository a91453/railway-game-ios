import GameCore
import GamePresentation
import XCTest

/// TestFlight 56.1: after changing from OpenStreetMap to satellite the
/// player's route no longer lay on the map. The base map is asked again
/// when it moves on its own, never for ever, and a zoom it refuses limits
/// the camera (ARCHITECTURE decision 50's later amendment).
final class BaseMapFollowingTests: XCTestCase {
    private typealias Piece = BaseMapFollowing.Piece
    private let target = Piece(x: 1_000, y: 2_000, width: 400, height: 300)

    func testANewPieceIsAskedForAndOneAlreadyShownIsNot() {
        var following = BaseMapFollowing()
        let elsewhere = Piece(x: 0, y: 0, width: 4_000, height: 3_000)
        XCTAssertTrue(following.shouldAsk(for: target, shown: elsewhere))
        following.answered(target)
        XCTAssertFalse(following.shouldAsk(for: target, shown: target), "already shown")
        let nearly = Piece(x: 1_000.2, y: 2_000, width: 400, height: 300)
        XCTAssertFalse(following.shouldAsk(for: target, shown: nearly), "within a thousandth")
    }

    func testABaseMapThatMovesOnItsOwnIsPulledBack() {
        var following = BaseMapFollowing()
        XCTAssertTrue(following.shouldAsk(for: target, shown: Piece(x: 0, y: 0, width: 4_000, height: 3_000)))
        following.answered(target)
        // MapKit moved after loading, or after the satellite style came.
        let drifted = Piece(x: 1_500, y: 2_500, width: 400, height: 300)
        XCTAssertTrue(following.shouldAsk(for: target, shown: drifted))
        following.answered(target)
        XCTAssertNil(following.refusal)
    }

    func testARefusedZoomIsNotAskedForAgainAndIsMeasured() {
        var following = BaseMapFollowing()
        XCTAssertTrue(following.shouldAsk(for: target, shown: Piece(x: 0, y: 0, width: 4_000, height: 3_000)))
        // Its imagery stops short: the same middle, twice as wide.
        let wider = Piece(x: 800, y: 1_850, width: 800, height: 600)
        following.answered(wider)
        XCTAssertEqual(following.refusal ?? 0, 2, accuracy: 1e-9)
        XCTAssertFalse(following.shouldAsk(for: target, shown: wider), "its answer: asking again would loop")
        XCTAssertEqual(following.refusal ?? 0, 2, accuracy: 1e-9)
    }

    func testTheSamePieceIsAskedForAgainOnlyAFewTimes() {
        var following = BaseMapFollowing()
        var asks = 0
        for step in 0..<10 {
            // A base map that goes somewhere else each time.
            let shown = Piece(x: Double(step) * 100, y: 0, width: 400, height: 300)
            if following.shouldAsk(for: target, shown: shown) {
                asks += 1
                following.answered(Piece(x: Double(step) * 100 + 50, y: 0, width: 400, height: 300))
            }
        }
        XCTAssertEqual(asks, 1 + BaseMapFollowing.maximumRetries)
        // A new piece starts again.
        let next = Piece(x: 5_000, y: 5_000, width: 400, height: 300)
        XCTAssertTrue(following.shouldAsk(for: next, shown: target))
    }

    func testAWiderPieceElsewhereIsNoRefusal() {
        var following = BaseMapFollowing()
        XCTAssertTrue(following.shouldAsk(for: target, shown: Piece(x: 0, y: 0, width: 4_000, height: 3_000)))
        following.answered(Piece(x: 0, y: 0, width: 4_000, height: 3_000))
        XCTAssertNil(following.refusal, "not round the same middle: it moved, it did not refuse")
    }

    func testTheCameraIsLimitedAboutTheMiddle() throws {
        let map = try WorldBounds(width: 32_768, height: 24_576)
        let camera = PlanCamera(bounds: map, viewport: ScreenSize(width: 800, height: 400))
            .centered(on: WorldCoordinate(x: 16_000, y: 12_000))
            .zoomed(by: 1_000, around: ScreenPoint(x: 400, y: 200))
        XCTAssertEqual(camera.referenceSize, MapScale.largestSize, accuracy: 1e-9)
        let limited = camera.limited(toReferenceSize: 40)
        XCTAssertEqual(limited.referenceSize, 40, accuracy: 1e-9)
        XCTAssertEqual(limited.worldPosition(at: ScreenPoint(x: 400, y: 200)).x, 16_000, accuracy: 1e-6)
        XCTAssertEqual(limited.worldPosition(at: ScreenPoint(x: 400, y: 200)).y, 12_000, accuracy: 1e-6)
        XCTAssertEqual(camera.limited(toReferenceSize: nil), camera)
        XCTAssertEqual(camera.limited(toReferenceSize: 100), camera, "no closer than it is")
        XCTAssertEqual(limited.limited(toReferenceSize: 40), limited)
    }
}
