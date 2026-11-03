import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 555: the screenshot scenes round Taipei Main Station and
/// Taipei 101 open by day, a line laid by each, and
/// `-screenshot-3d-view` sets the 3D camera over the place, leaned as asked.
final class Map3DScreenshotViewTests: XCTestCase {
    func testTheTaipeiScenesAreSetRoundTheirPlaces() throws {
        for scene in [ScreenshotScene.taipeiMain, .taipei101] {
            let world = scene.make(in: .english)
            XCTAssertNotNil(world.geoAnchor, "\(scene): a real-world map")
            XCTAssertEqual(world.lines.count, 1, "\(scene): a line by the place")
            let hour = Double(world.clock.now.seconds % GameTime.secondsPerDay) / 3_600
            XCTAssertGreaterThan(Map3DSunShadow.strength(Map3DLighting(at: world.clock.now)), 0.9, "\(scene): by day, the sun's shadows drawn (\(hour) h)")
            XCTAssertNotNil(scene.place)
        }
        XCTAssertNil(ScreenshotScene.freight.place)
    }

    func testTheAskedCamera() throws {
        XCTAssertNil(Map3DScreenshotView("200,30"))
        XCTAssertNil(Map3DScreenshotView("0,30,60"))
        let asked = try XCTUnwrap(Map3DScreenshotView("200, 225, 60"))
        XCTAssertEqual(asked.distance, 200)
        XCTAssertEqual(asked.heading, 225 * .pi / 180, accuracy: 1e-5)
        let world = ScreenshotScene.taipeiMain.make(in: .english)
        let scene = Map3DScene(world: world)
        let place = try XCTUnwrap(ScreenshotScene.taipeiMain.place)
        let camera = try XCTUnwrap(asked.camera(at: place, in: scene, of: world, viewport: (874, 402)))
        XCTAssertEqual(camera.tilt * 180 / .pi, 60, accuracy: 0.01)
        XCTAssertEqual(camera.distance, 200)
        let own = try XCTUnwrap(Map3DScreenshotView("200,225,0")?.camera(at: place, in: scene, of: world, viewport: (874, 402)))
        XCTAssertEqual(own.tilt, Map3DCamera.tilt(atDistance: 200))
        XCTAssertEqual(own.target, camera.target)
        // The place is 300 m south of the line, which the scene is set
        // round (decision 555 續: the line runs clear of the landmark).
        XCTAssertEqual(own.target.x, 0, accuracy: 50)
        XCTAssertEqual(Map3DPoint(own.target.x, 0, own.target.z).length, 300, accuracy: 50)
    }
}
