import GamePresentation
import XCTest

/// Decision 269, later: the 3D map's compass shows only when the view does
/// not face north, and a tap turns it back the shorter way.
final class Map3DCompassTests: XCTestCase {
    private let degree = Float.pi / 180

    /// A turn from north is between -180° and 180°, whichever way and
    /// however many times the fingers turned the map.
    func testATurnFromNorthIsTheShorterWayRound() {
        let cases: [(heading: Float, turn: Float)] = [
            (0, 0), (30, 30), (-30, -30), (179, 179), (-179, -179),
            (190, -170), (-190, 170), (350, -10), (-350, 10), (720 + 45, 45),
        ]
        for (heading, turn) in cases {
            XCTAssertEqual(Map3DCamera.turnFromNorth(heading * degree), turn * degree, accuracy: 1e-4, "\(heading)°")
        }
        // Facing south either way round is as short.
        XCTAssertEqual(abs(Map3DCamera.turnFromNorth(.pi)), .pi, accuracy: 1e-4)
        XCTAssertEqual(abs(Map3DCamera.turnFromNorth(-.pi)), .pi, accuracy: 1e-4)
    }

    /// The compass shows from 0.05° either way; a whole turn round is north
    /// again, and so is what `turned(by:)` leaves after one.
    func testTheViewFacesNorthWithinTheTolerance() {
        XCTAssertTrue(Map3DCamera(heading: 0).facesNorth)
        XCTAssertTrue(Map3DCamera(heading: 0.04 * degree).facesNorth)
        XCTAssertTrue(Map3DCamera(heading: -0.04 * degree).facesNorth)
        XCTAssertFalse(Map3DCamera(heading: 0.06 * degree).facesNorth)
        XCTAssertFalse(Map3DCamera(heading: -0.06 * degree).facesNorth)
        XCTAssertFalse(Map3DCamera(heading: .pi).facesNorth)
        XCTAssertTrue(Map3DCamera(heading: 2 * .pi).facesNorth)
        XCTAssertTrue(Map3DCamera().turned(by: .pi).turned(by: .pi).facesNorth)
        XCTAssertFalse(Map3DCamera().turned(by: 5 * degree).facesNorth)
    }

    /// Back to north the shorter way: from 300° it turns on through 330°,
    /// not back through 180°; fast at first, gently at the end, and
    /// exactly north at the end, keeping where it looks and how close.
    func testTurningBackGoesTheShorterWayAndEndsExactlyNorth() {
        let camera = Map3DCamera(target: Map3DPoint(40, 0, -25), distance: 180, heading: 300 * degree)
        let start = camera.heading
        let halfway = camera.turnedNorth(from: start, progress: 0.5)
        XCTAssertEqual(halfway.turnFromNorth, -15 * degree, accuracy: 1e-4, "a quarter of the 60° left: decelerating")
        let steps = (0...10).map { camera.turnedNorth(from: start, progress: Float($0) / 10).turnFromNorth }
        XCTAssertEqual(steps.first ?? 0, -60 * degree, accuracy: 1e-4)
        for (a, b) in zip(steps, steps.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b, a, "never turns back the other way")
        }
        let moves = zip(steps, steps.dropFirst()).map { $1 - $0 }
        XCTAssertEqual(moves, moves.sorted(by: >), "each step smaller than the last")
        let end = camera.turnedNorth(from: start, progress: 1)
        XCTAssertEqual(end.heading, 0)
        XCTAssertTrue(end.facesNorth)
        XCTAssertEqual(end.target, camera.target)
        XCTAssertEqual(end.distance, camera.distance)
        XCTAssertEqual(camera.turnedNorth(from: start, progress: 2).heading, 0, "past the end")
        XCTAssertEqual(camera.turnedNorth(from: start, progress: -1).turnFromNorth, -60 * degree, accuracy: 1e-4, "before the start")

        let east = Map3DCamera(heading: 90 * degree)
        XCTAssertEqual(east.turnedNorth(from: east.heading, progress: 0.5).turnFromNorth, 22.5 * degree, accuracy: 1e-4,
                       "from the east it turns back anticlockwise")
    }

    /// Facing north, the view from far away has north up (the compass's
    /// promise): the target's north lies up the screen.
    func testFacingNorthNorthIsUpTheScreen() throws {
        let turned = Map3DCamera(distance: 1_000, heading: 120 * degree)
        let matrix = turned.turnedNorth(from: turned.heading, progress: 1).viewProjection
        let north = try XCTUnwrap(matrix.project(Map3DPoint(0, 0, -100)))
        XCTAssertEqual(north.x, 0, accuracy: 1e-4, "straight up, not to the side")
        XCTAssertGreaterThan(north.y, 0.01, "up")
    }
}
