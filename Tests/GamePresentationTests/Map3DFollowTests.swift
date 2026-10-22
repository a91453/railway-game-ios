import GameCore
@testable import GamePresentation
import XCTest

/// Decision 333: the 3D camera following a train from behind (Mini Tokyo
/// 3D's `back` and `topback`), and the flight there (the reference's
/// `cameraMotion`).
final class Map3DFollowTests: XCTestCase {
    private let train = TrainID(rawValue: 7)

    /// A train's front at (x, z), running toward `heading` (radians
    /// clockwise from north, as the camera counts it).
    private func head(x: Float, z: Float, heading: Float) -> Map3DTrains.Head {
        let rail = Map3DPoint(x, 2, z)
        return Map3DTrains.Head(train: train, point: rail + Map3DPoint(0, Map3DTrains.carHeight + Map3DTrains.headClearance, 0),
                                forward: Map3DPoint(sinf(heading), 0, -cosf(heading)))
    }

    /// Mini Tokyo 3D's tilts, 85° behind and 60° above behind.
    func testTheViewsTiltAsMiniTokyo3D() {
        XCTAssertEqual(Map3DFollow.View.back.tilt * 180 / .pi, 85, accuracy: 0.001)
        XCTAssertEqual(Map3DFollow.View.aboveBack.tilt * 180 / .pi, 60, accuracy: 0.001)
    }

    /// Zoom 18.5 at Tokyo is about 0.171 m a pixel; a phone held upright
    /// (844 points tall) stands about 230 m from the train.
    func testTheDistanceKeepsMiniTokyo3DsScale() {
        XCTAssertEqual(Map3DFollow.metresPerPoint, 0.1715, accuracy: 0.0005)
        let distance = Map3DFollow.distance(viewportHeight: 844)
        XCTAssertEqual(distance, 229.5, accuracy: 1)
        let camera = Map3DCamera(distance: distance, viewport: (390, 844))
        XCTAssertEqual(camera.metresPerPoint, Map3DFollow.metresPerPoint, accuracy: 0.0001, "the ground at the train is the same scale")
    }

    /// The camera looks at the rail under the front, from behind it: the
    /// eye is on the far side of the way the train runs, low behind and
    /// higher above behind.
    func testTheCameraStandsBehindTheTrain() {
        let front = head(x: 100, z: -50, heading: .pi / 2)  // running east
        let start = Map3DCamera(target: .zero, distance: 1_000, heading: .pi / 2, viewport: (390, 844))
        for view in [Map3DFollow.View.back, .aboveBack] {
            let camera = Map3DFollow(train: train, view: view).camera(following: front, from: start, elapsed: 1 / 60)
            XCTAssertEqual(camera.target, front.rail)
            XCTAssertEqual(camera.tilt, view.tilt)
            XCTAssertLessThan(camera.eye.x, front.rail.x - 10, "\(view): west of a train running east")
            XCTAssertEqual(camera.eye.z, front.rail.z, accuracy: 0.01)
            XCTAssertEqual((camera.eye - camera.target).length, camera.distance, accuracy: 0.01)
        }
        let back = Map3DFollow(train: train, view: .back).camera(following: front, from: start, elapsed: 1 / 60)
        let above = Map3DFollow(train: train, view: .aboveBack).camera(following: front, from: start, elapsed: 1 / 60)
        XCTAssertLessThan(back.eye.y, above.eye.y)
        XCTAssertEqual(back.eye.y - front.rail.y, back.distance * cosf(85 * .pi / 180), accuracy: 0.01)
    }

    /// The camera turns after the train 2 % of the way a 60th of a second,
    /// the shorter way round; twice as far on a 30-frame screen, no more
    /// for a longer pause; at once when asked.
    func testTheCameraTurnsAfterTheTrainSlowly() {
        let front = head(x: 0, z: 0, heading: 0.5)
        let start = Map3DCamera(heading: 0, viewport: (390, 844))
        let follow = Map3DFollow(train: train)
        XCTAssertEqual(follow.camera(following: front, from: start, elapsed: 1 / 60).heading, 0.01, accuracy: 0.0001)
        XCTAssertEqual(Map3DFollow.headingShare(elapsed: 1 / 30), 1 - 0.98 * 0.98, accuracy: 0.0001)
        XCTAssertEqual(Map3DFollow.headingShare(elapsed: 5), Map3DFollow.headingShare(elapsed: 1 / 30), "at most two frames")
        XCTAssertEqual(follow.camera(following: front, from: start, elapsed: 1 / 60, turnsAtOnce: true).heading, 0.5, accuracy: 0.0001)
        // Across south: from just west of it to just east, through it.
        let south = head(x: 0, z: 0, heading: -3.1)
        let turned = follow.camera(following: south, from: Map3DCamera(heading: 3.1, viewport: (390, 844)), elapsed: 1 / 60)
        XCTAssertGreaterThan(abs(turned.heading), 3.1, "the shorter way, through south")
    }

    /// A pinch moves the follow camera in or out, within its limits.
    func testAPinchMovesTheCameraInAndOut() {
        let follow = Map3DFollow(train: train)
        XCTAssertEqual(follow.zoomed(by: 2).scale, 0.5)
        XCTAssertEqual(follow.zoomed(by: 100).scale, Map3DFollow.scales.lowerBound)
        XCTAssertEqual(follow.zoomed(by: 0.01).scale, Map3DFollow.scales.upperBound)
        XCTAssertEqual(follow.zoomed(by: 0).scale, 1)
        let front = head(x: 0, z: 0, heading: 0)
        let camera = Map3DCamera(viewport: (390, 844))
        XCTAssertEqual(follow.zoomed(by: 2).camera(following: front, from: camera, elapsed: 0).distance,
                       Map3DFollow.distance(viewportHeight: 844) / 2, accuracy: 0.01)
    }

    /// The flight runs 1.2 s smooth at both ends from the start to the
    /// goal, the shorter way round, and is the goal once over; with Reduce
    /// Motion it is the goal at once.
    func testTheFlightBlendsSmoothlyToTheGoal() {
        let start = Map3DCamera(target: .zero, distance: 400, heading: 3, viewport: (390, 844))
        var goal = Map3DCamera(target: Map3DPoint(50, 0, 0), distance: 230, heading: -3, viewport: (390, 844))
        goal.pitch = Map3DFollow.View.back.tilt
        let flight = Map3DFlight(from: start, began: 10, rule: MotionRule.cameraFlight.running(reduceMotion: false))
        XCTAssertEqual(flight.seconds, 1.2)
        XCTAssertEqual(flight.camera(toward: goal, at: 10).target, start.target)
        XCTAssertEqual(flight.camera(toward: goal, at: 10).distance, 400, accuracy: 0.01)
        let middle = flight.camera(toward: goal, at: 10.6)
        XCTAssertEqual(middle.target.x, 25, accuracy: 0.01, "smoothstep is half way at half time")
        XCTAssertGreaterThan(abs(middle.heading), 3, "through south, not round by north")
        XCTAssertEqual(middle.tilt, (start.tilt + goal.tilt) / 2, accuracy: 0.001)
        XCTAssertEqual(flight.camera(toward: goal, at: 11.2), goal)
        XCTAssertTrue(flight.isOver(at: 11.2))
        let early = flight.camera(toward: goal, at: 10.1).target.x
        let late = flight.camera(toward: goal, at: 11.1).target.x
        XCTAssertLessThan(early, 1.5, "it starts gently")
        XCTAssertGreaterThan(late, 48.5, "and lands gently")
        let reduced = Map3DFlight(from: start, began: 10, rule: MotionRule.cameraFlight.running(reduceMotion: true))
        XCTAssertEqual(reduced.camera(toward: goal, at: 10), goal)
    }

    /// A short way does not rise; a long one rises over the middle, as the
    /// reference's `dip`, and lands where it was going.
    func testALongFlightRisesOverTheMiddle() {
        // 140 m (1.4 times at least 100 m) fit across a phone held upright
        // from about 480 m out.
        let wide = Map3DCamera(target: .zero, distance: 600, viewport: (390, 844))
        let near = Map3DCamera(target: Map3DPoint(30, 0, 0), distance: 600, viewport: (390, 844))
        XCTAssertEqual(Map3DFlight.dip(from: wide, to: near), 0)
        let start = Map3DCamera(target: .zero, distance: 230, viewport: (390, 844))
        let far = Map3DCamera(target: Map3DPoint(5_000, 0, 0), distance: 230, viewport: (390, 844))
        let dip = Map3DFlight.dip(from: start, to: far)
        XCTAssertGreaterThan(dip, 3, "doublings of the distance")
        let flight = Map3DFlight(from: start, began: 0, rule: .cameraFlight)
        let middle = flight.camera(toward: far, at: 0.6)
        XCTAssertGreaterThan(middle.distance, 230 * 8)
        XCTAssertLessThanOrEqual(middle.distance, Map3DCamera.farthest)
        XCTAssertEqual(flight.camera(toward: far, at: 1.2).distance, 230)
    }

    /// A camera with a tilt set keeps it at any distance; without, it tilts
    /// by the distance as before.
    func testASetTiltHoldsAtAnyDistance() {
        var camera = Map3DCamera(distance: 2_000)
        XCTAssertEqual(camera.tilt, 0)
        camera.pitch = 1
        XCTAssertEqual(camera.tilt, 1)
        XCTAssertNotEqual(camera, Map3DCamera(distance: 2_000))
    }

    /// Decision 337: the cab view stands just ahead of the nose at the
    /// driver's eye, looks down the line 1.15° under level through a 68°
    /// lens, and turns with the train at once; a pinch does not move it.
    func testTheCabViewLooksAheadFromTheNose() {
        let nose = Map3DPoint(100, 2, -50)
        let forward = Map3DPoint(1, 0, 0)  // running east
        let front = Map3DTrains.Head(train: train, point: nose + Map3DPoint(-4, Map3DTrains.carHeight + Map3DTrains.headClearance, 0),
                                     forward: forward, nose: nose)
        let start = Map3DCamera(target: .zero, distance: 1_000, heading: 0, viewport: (390, 844))
        let follow = Map3DFollow(train: train, view: .cab)
        let camera = follow.camera(following: front, from: start, elapsed: 1 / 60)
        let eye = camera.eye
        XCTAssertEqual(eye.x, nose.x + Map3DFollow.cabLead, accuracy: 0.01)
        XCTAssertEqual(eye.y, nose.y + Map3DFollow.cabEyeHeight, accuracy: 0.01)
        XCTAssertEqual(eye.z, nose.z, accuracy: 0.01)
        XCTAssertEqual(Map3DFollow.cabEyeHeight, 1.935, accuracy: 0.001)
        XCTAssertEqual(camera.heading, .pi / 2, accuracy: 0.0001, "facing the way it runs at once")
        let look = (camera.target - eye).normalized ?? .zero
        XCTAssertEqual(asinf(-look.y) * 180 / .pi, 1.146, accuracy: 0.01, "the reference's driverLook")
        XCTAssertGreaterThan(look.x, 0.99)
        XCTAssertEqual(camera.lens ?? 0, 68 * .pi / 180, accuracy: 0.0001)
        XCTAssertEqual(camera.fieldOfViewTall, Map3DFollow.cabLens)
        XCTAssertEqual(follow.zoomed(by: 2).camera(following: front, from: start, elapsed: 1 / 60), camera, "a pinch does not move it")
        // Leaving the cab for behind puts the map's own lens back.
        let behind = Map3DFollow(train: train, view: .back).camera(following: front, from: camera, elapsed: 1 / 60)
        XCTAssertNil(behind.lens)
        XCTAssertEqual(Map3DFollow.View.cab.text(in: .traditionalChinese), "駕駛室")
    }

    /// Decision 337: a wider lens draws the same distance smaller, and the
    /// flight into the cab opens the lens on the way.
    func testTheLensWidensTheViewAndFlies() {
        var camera = Map3DCamera(distance: 600, viewport: (390, 844))
        let narrow = camera.metresPerPoint
        camera.lens = Map3DFollow.cabLens
        XCTAssertGreaterThan(camera.metresPerPoint, narrow * 2)
        XCTAssertLessThan(camera.projection.columns[5], Map3DCamera(distance: 600).projection.columns[5])
        let start = Map3DCamera(distance: 230, viewport: (390, 844))
        let flight = Map3DFlight(from: start, began: 0, rule: .cameraFlight)
        let middle = flight.camera(toward: camera, at: 0.6)
        XCTAssertEqual(middle.fieldOfViewTall, (Map3DCamera.fieldOfView + Map3DFollow.cabLens) / 2, accuracy: 0.0001)
        XCTAssertNil(flight.camera(toward: start, at: 0.6).lens, "no lens either end, none on the way")
    }

    /// The trains' fronts say the way their front car faces.
    func testAHeadSaysTheWayItsTrainFaces() {
        let head = Map3DTrains.Head(train: train, point: Map3DPoint(0, 10, 0))
        XCTAssertEqual(head.forward, Map3DPoint(0, 0, -1))
        XCTAssertEqual(head.rail.y, 10 - Map3DTrains.carHeight - Map3DTrains.headClearance, accuracy: 0.001)
        XCTAssertEqual(head.nose, head.rail, "without a nose given, the rail under the label")
        XCTAssertEqual(Map3DFollow.heading(of: Map3DPoint(1, 0, 0)), .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(Map3DFollow.heading(of: Map3DPoint(0, 0, -1)), 0, accuracy: 0.0001)
    }
}
