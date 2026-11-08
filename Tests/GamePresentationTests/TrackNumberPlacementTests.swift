@testable import GamePresentation
import XCTest

/// Decision 631: the tracks' numbers keep off the switches, the names and
/// each other.
final class TrackNumberPlacementTests: XCTestCase {
    private typealias P = TrackNumberPlacement
    private let view = P.Box(minX: 0, minY: 0, maxX: 400, maxY: 400)

    private func point(_ x: Double, _ y: Double) -> ScreenPoint { ScreenPoint(x: x, y: y) }

    func testANumberStandsAtTheMiddleWhereNothingIsInTheWay() {
        let candidate = P.Candidate(id: 1, positions: [point(100, 100), point(150, 100)], width: 30, height: 14)
        let placed = P.place([candidate], obstacles: [], view: view, limit: 10)
        XCTAssertEqual(placed.map(\.center), [point(100, 100)])
        XCTAssertEqual(placed.first?.scale, 1)
    }

    func testANumberMovesAlongItsTrackOffASwitch() {
        let candidate = P.Candidate(id: 1, positions: [point(100, 100), point(150, 100)], width: 30, height: 14)
        let junction = P.switchBox(at: point(100, 100), radius: 10)
        let placed = P.place([candidate], obstacles: [junction], view: view, limit: 10)
        XCTAssertEqual(placed.map(\.center), [point(150, 100)])
        XCTAssertEqual(placed.first?.scale, 1)
    }

    func testANumberShrinksWhereOnlyASmallerPlateFits() {
        // One place; a name 40 wide and 20 tall leaves a gap only a
        // smaller plate fits (full: 34 + 4 = 38 wide).
        let candidate = P.Candidate(id: 1, positions: [point(100, 100)], width: 34, height: 14)
        let near = P.Box(minX: 70, minY: 80, maxX: 85, maxY: 120)
        let far = P.Box(minX: 119, minY: 80, maxX: 140, maxY: 120)
        let placed = P.place([candidate], obstacles: [near, far], view: view, limit: 10)
        XCTAssertEqual(placed.count, 1)
        XCTAssertLessThan(placed[0].scale, 1)
        XCTAssertFalse(placed[0].box.intersects(near))
        XCTAssertFalse(placed[0].box.intersects(far))
    }

    func testANumberIsLeftOutWhereNothingFits() {
        let candidate = P.Candidate(id: 1, positions: [point(100, 100), point(160, 100)], width: 30, height: 14)
        let walls = [P.Box(minX: 60, minY: 60, maxX: 200, maxY: 140)]
        XCTAssertTrue(P.place([candidate], obstacles: walls, view: view, limit: 10).isEmpty)
    }

    func testNumbersKeepOffEachOtherAndTheEarlierOneWins() {
        let a = P.Candidate(id: 1, positions: [point(100, 100)], width: 30, height: 14)
        let b = P.Candidate(id: 2, positions: [point(110, 100), point(200, 100)], width: 30, height: 14)
        let placed = P.place([a, b], obstacles: [], view: view, limit: 10)
        XCTAssertEqual(placed.map(\.id), [1, 2])
        XCTAssertEqual(placed[1].center, point(200, 100))
        XCTAssertFalse(placed[0].box.intersects(placed[1].box))
    }

    func testNumbersAlreadyDrawnAreKeptClearOfAndThePreviewKeepsItsPlace() {
        let taken = [P.Box(center: point(100, 100), width: 40, height: 20)]
        let candidate = P.Candidate(id: 1, positions: [point(100, 100)], width: 30, height: 14)
        XCTAssertTrue(P.place([candidate], obstacles: [], taken: taken, view: view, limit: 10).isEmpty)
    }

    func testTheLimitAndTheViewHold() {
        let inView = P.Candidate(id: 1, positions: [point(100, 100)], width: 30, height: 14)
        let outside = P.Candidate(id: 2, positions: [point(900, 900)], width: 30, height: 14)
        let more = P.Candidate(id: 3, positions: [point(300, 300)], width: 30, height: 14)
        XCTAssertEqual(P.place([outside, inView, more], obstacles: [], view: view, limit: 1).map(\.id), [1])
        XCTAssertEqual(P.place([inView, more], obstacles: [], view: view, limit: 10).map(\.id), [1, 3])
    }

    func testPositionsRunFromTheMiddleOutAndBesideTheTrack() {
        let track = [point(0, 0), point(100, 0)]
        let positions = P.positions(along: track, beside: 9)
        XCTAssertEqual(positions.count, P.fractions.count)
        XCTAssertEqual(positions[0].x, 50, accuracy: 1e-9)
        // To the left of a track pointing right on a screen whose y grows
        // down is up.
        XCTAssertEqual(positions[0].y, -9, accuracy: 1e-9)
        XCTAssertEqual(positions[1].x, 35, accuracy: 1e-9)
        XCTAssertTrue(P.positions(along: [point(5, 5)], beside: 9).isEmpty)
    }

    func testANameBoxHangsBelowItsStation() {
        let box = P.nameBox(station: point(100, 100), nameTop: 12, nameWidth: 60, height: 30)
        XCTAssertEqual(box, P.Box(minX: 70, minY: 112, maxX: 130, maxY: 142))
    }
}
