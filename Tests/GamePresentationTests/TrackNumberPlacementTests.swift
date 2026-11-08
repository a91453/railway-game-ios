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

    // MARK: - Decision 642: badges, waiting counts and crossings

    func testTwoTracksThatCrossAreFoundAndTracksMeetingAtANodeAreNot() {
        let across = [point(0, 100), point(200, 100)]
        let down = [point(100, 0), point(100, 200)]
        XCTAssertEqual(P.crossings(of: [across, down], in: view), [point(100, 100)])
        // Two tracks that meet end to end at a node, and one that turns
        // there, do not cross.
        let into = [point(0, 50), point(80, 50)]
        let onward = [point(80, 50), point(160, 90)]
        let branch = [point(80, 50), point(160, 10)]
        XCTAssertTrue(P.crossings(of: [into, onward, branch], in: view).isEmpty)
        // Parallel tracks never do; a crossing off the screen is not kept.
        XCTAssertTrue(P.crossings(of: [[point(0, 10), point(200, 10)], [point(0, 20), point(200, 20)]], in: view).isEmpty)
        XCTAssertTrue(P.crossings(of: [[point(500, 0), point(700, 200)], [point(700, 0), point(500, 200)]], in: view).isEmpty)
    }

    func testACrossingOfLongTracksSpanningManyCellsIsFoundOnce() {
        let a = [point(0, 0), point(400, 400)]
        let b = [point(0, 400), point(400, 0)]
        let found = P.crossings(of: [a, b], in: view, cell: 10)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].x, 200, accuracy: 1e-9)
        XCTAssertEqual(found[0].y, 200, accuracy: 1e-9)
    }

    func testAStationsBadgeCoversItsCrowdedRingAndTheWaitingPillSitsAboveIt() {
        let station = point(200, 200)
        let radius = 14.0
        let badge = P.stationBox(at: station, stationRadius: radius)
        let ring = MapProblems.ringRadius(stationRadius: radius) + MapProblems.ringHaloReach
        XCTAssertEqual(badge.minX, station.x - ring, accuracy: 1e-9)
        XCTAssertEqual(badge.maxY, station.y + ring, accuracy: 1e-9)
        let font = MapProblems.countFontSize(.full, stationRadius: radius)
        let pill = P.waitingBox(at: station, stationRadius: radius, fontSize: font)
        // Above the badge, reaching over the ring, centred on the station
        // and wide enough for "1,234" and its glyph.
        XCTAssertLessThan(pill.minY, station.y - MapProblems.ringRadius(stationRadius: radius) - font)
        XCTAssertEqual((pill.minX + pill.maxX) / 2, station.x, accuracy: 1e-9)
        XCTAssertGreaterThan(pill.maxX - pill.minX, 5 * font * 0.6 + font)
    }

    /// The author's screenshot: "#1" on a station's badge and its waiting
    /// count, "#11" against a crossing. Given a station, its pill, a
    /// switch and a crossing, every number placed keeps clear of all of
    /// them (and the crossing by ``TrackNumberPlacement/junctionClearance``).
    func testNumbersKeepClearOfBadgesWaitingCountsSwitchesAndCrossings() {
        let station = point(120, 200)
        let radius = 12.0
        let font = MapProblems.countFontSize(.full, stationRadius: radius)
        let crossing = P.crossings(of: [[point(200, 120), point(320, 280)], [point(200, 280), point(320, 120)]], in: view)
        XCTAssertEqual(crossing.count, 1)
        let obstacles = [
            P.stationBox(at: station, stationRadius: radius),
            P.waitingBox(at: station, stationRadius: radius, fontSize: font),
            P.nameBox(station: station, nameTop: MapProblems.nameTop(stationRadius: radius), nameWidth: 60, height: 30),
            P.switchBox(at: point(60, 80), radius: P.junctionClearance),
        ] + crossing.map { P.switchBox(at: $0, radius: P.junctionClearance) }
        // A track through the station, one along the top past the switch,
        // and the two crossing tracks: each's middle is in the way.
        let tracks = [
            [point(20, 200), point(220, 200)],
            [point(120, 100), point(120, 300)],
            [point(0, 80), point(120, 80)],
            [point(200, 120), point(320, 280)],
            [point(200, 280), point(320, 120)],
        ]
        let candidates = tracks.enumerated().map { index, points in
            P.Candidate(id: index + 1, positions: P.positions(along: points, beside: 0), width: 26, height: 14)
        }
        let placed = P.place(candidates, obstacles: obstacles, view: view, limit: 10)
        XCTAssertFalse(placed.isEmpty)
        for number in placed {
            for obstacle in obstacles {
                XCTAssertFalse(number.box.intersects(obstacle), "#\(number.id) at \(number.center) covers \(obstacle)")
            }
        }
        // None stands at the middle of its track, where the obstacles are.
        for number in placed {
            XCTAssertNotEqual(number.center, candidates[number.id - 1].positions[0])
        }
    }

    func testTheCountsFigureSizeMatchesTheLevel() {
        XCTAssertEqual(MapProblems.countFontSize(.medium, stationRadius: 30), 8)
        XCTAssertEqual(MapProblems.countFontSize(.full, stationRadius: 30), 11)
        XCTAssertEqual(MapProblems.countFontSize(.full, stationRadius: 5), 8)
    }
}
