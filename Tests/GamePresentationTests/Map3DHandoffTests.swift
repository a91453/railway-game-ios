import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 269: the 2D map hands over to the 3D map as a
/// pinch comes close, at the same middle and scale, and gets it back;
/// decision 313: only as the fingers lift, past the 2D map's closest zoom.
final class Map3DHandoffTests: XCTestCase {
    func testTheScaleGoesBothWays() {
        for size in [4.0, 26.8, 64] {
            let distance = Map3DHandoff.distance(referenceSize: size, viewportHeight: 844)
            XCTAssertEqual(Map3DHandoff.referenceSize(distance: distance, viewportHeight: 844), size, accuracy: size * 1e-5)
        }
        // Twice as close on the 2D map, half the distance.
        XCTAssertEqual(Map3DHandoff.distance(referenceSize: 32, viewportHeight: 844),
                       Map3DHandoff.distance(referenceSize: 16, viewportHeight: 844) / 2, accuracy: 0.01)
        // 16 m shown 844 points tall... as many metres as points / size × 16.
        let distance = Map3DHandoff.distance(referenceSize: 16, viewportHeight: 844)
        XCTAssertEqual(2 * distance * tanf(Map3DCamera.fieldOfView / 2), 844, accuracy: 0.1)
    }

    /// Decision 313: only a pinch let go past the 2D map's closest zoom
    /// opens the 3D map; reaching the end, or coming back out before the
    /// fingers lift, stays 2D.
    func testOnlyAReleasePastTheClosestZoomOpens() {
        let closest = MapScale.largestSize
        XCTAssertTrue(Map3DHandoff.opensOnRelease(referenceSize: closest, asked: closest * 1.3))
        XCTAssertTrue(Map3DHandoff.opensOnRelease(referenceSize: closest, asked: closest * 4))
        XCTAssertFalse(Map3DHandoff.opensOnRelease(referenceSize: closest, asked: closest), "just reached the end")
        XCTAssertFalse(Map3DHandoff.opensOnRelease(referenceSize: closest, asked: closest * 1.29))
        // Asked far past it, but let go farther out (the pinch came back).
        XCTAssertFalse(Map3DHandoff.opensOnRelease(referenceSize: 40, asked: closest * 2))
        // The old line (decision 269, about 27 points on a phone) no longer opens.
        XCTAssertFalse(Map3DHandoff.opensOnRelease(referenceSize: 27, asked: 27))
        XCTAssertTrue(Map3DHandoff.hands(building: false, tutorialRuns: false))
        XCTAssertFalse(Map3DHandoff.hands(building: true, tutorialRuns: false))
        XCTAssertFalse(Map3DHandoff.hands(building: false, tutorialRuns: true))
        XCTAssertFalse(Map3DHandoff.hands(building: false, tutorialRuns: false, pinchOpens: false), "the setting off")
    }

    /// Decision 313: handed over at the 2D map's closest zoom, the 3D map
    /// starts straight down there, whatever the view's height, and leans
    /// as it comes closer, all the way before the closest distance.
    func testTheHandedOverMapStartsFlatAndLeansCloser() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let scene = Map3DScene(world: world)
        let plan = Map3DHandoff.Plan(x: Double(towns[0].x), y: Double(towns[0].y), referenceSize: MapScale.largestSize)
        for (width, height) in [(Float(390), Float(844)), (844, 390), (1_024, 1_366)] {
            let camera = Map3DHandoff.camera(from: plan, in: scene, viewport: (width, height))
            XCTAssertLessThan(camera.distance, Map3DCamera.flatFrom)
            XCTAssertEqual(camera.tilt, 0, accuracy: 1e-5, "straight down as it opens")
            let closer = camera.zoomed(by: 1.3)
            XCTAssertGreaterThan(closer.tilt, 0, "leans as it comes closer")
            XCTAssertEqual(closer.tiltsFrom, camera.tiltsFrom)
            XCTAssertEqual(Map3DCamera.tilt(atDistance: Map3DCamera.mostTiltedDistance(flatFrom: camera.tiltsFrom), from: camera.tiltsFrom), Map3DCamera.mostTilt)
            XCTAssertGreaterThan(Map3DCamera.mostTiltedDistance(flatFrom: camera.tiltsFrom), Map3DCamera.nearest - 0.01)
            XCTAssertLessThan(Map3DCamera.mostTiltedDistance(flatFrom: camera.tiltsFrom), camera.distance * 0.5)
        }
        // A camera the 3D button opens keeps the usual curve.
        XCTAssertEqual(Map3DCamera().tiltsFrom, Map3DCamera.flatFrom)
        XCTAssertEqual(Map3DCamera.mostTiltedDistance(flatFrom: Map3DCamera.flatFrom), Map3DCamera.tiltedFrom)
    }

    func testTheMiddleAndScaleComeBackWhereTheyWent() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let scene = Map3DScene(world: world)
        let x = Double(towns[0].x), y = Double(towns[0].y)
        let size = MapScale.largestSize
        let camera = Map3DHandoff.camera(from: Map3DHandoff.Plan(x: x, y: y, referenceSize: size), in: scene, viewport: (390, 844))
        XCTAssertEqual(scene.worldPosition(of: camera.target).x, x, accuracy: 64)
        let back = Map3DHandoff.plan(from: camera, in: scene)
        XCTAssertEqual(back.x, x, accuracy: 64)
        XCTAssertEqual(back.y, y, accuracy: 64)
        XCTAssertEqual(back.referenceSize, size, accuracy: size * 1e-4)
    }

    /// Decision 269, later fix (71.1, the owner: "3D 一放大就跳回 2D"): a
    /// 3D map the button opened, kilometres out, never hands back. Decision
    /// 313: one a pinch handed over hands back only as a pinch out is let
    /// go half again as far out as it opened.
    func testOnlyAPinchOutLetGoFarEnoughHandsBack() {
        // The button's 3D map, opened kilometres out: no pinch hands back.
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: nil, from: 9_000, to: 7_000))
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: nil, from: 9_000, to: 11_000))
        // Handed over at 280 m: closer never; out past 420 m, yes.
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: 280, from: 280, to: 200))
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: 280, from: 200, to: 400))
        XCTAssertTrue(Map3DHandoff.handsBack(handedOverAt: 280, from: 200, to: 430))
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: 280, from: 900, to: 600), "coming closer")
    }

    /// Decision 269, later (#785's review): the 3D scene builds ahead only
    /// near where the 3D map opens; decision 313: near the 2D map's closest.
    func testTheSceneBuildsAheadOnlyNearTheClosestZoom() {
        let closest = MapScale.largestSize
        XCTAssertFalse(Map3DHandoff.buildsAhead(referenceSize: 27), "decision 269's line")
        XCTAssertFalse(Map3DHandoff.buildsAhead(referenceSize: closest * 0.74))
        XCTAssertTrue(Map3DHandoff.buildsAhead(referenceSize: closest * 0.75))
        XCTAssertTrue(Map3DHandoff.buildsAhead(referenceSize: closest), "resting at the end")
        XCTAssertGreaterThan(Map3DHandoff.buildsAfterResting, 0)
    }

    /// The same on a real-world map's scene: handed over from its 2D map's
    /// zoom, the camera opens inside the line and a pinch closer keeps it.
    func testOnARealMapAPinchCloserStaysInThreeD() {
        let world = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 24.8016, longitudeDegrees: 120.9716)!)
        let scene = Map3DScene(world: world)
        for (width, height) in [(Float(390), Float(844)), (844, 390)] {
            let size = MapScale.largestSize
            let middle = scene.worldPosition(of: .zero)
            let camera = Map3DHandoff.camera(from: Map3DHandoff.Plan(x: middle.x, y: middle.y, referenceSize: size), in: scene, viewport: (width, height))
            XCTAssertLessThanOrEqual(camera.distance, Map3DCamera.flatFrom)
            let closer = camera.zoomed(by: 1.5)
            XCTAssertLessThan(closer.distance, camera.distance)
            XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: camera.distance, from: camera.distance, to: closer.distance))
            XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: camera.distance, from: camera.distance, to: camera.zoomed(by: 0.8).distance),
                           "a little farther stays 3D")
            let farther = camera.zoomed(by: 0.3)
            XCTAssertTrue(Map3DHandoff.handsBack(handedOverAt: camera.distance, from: camera.distance, to: farther.distance))
        }
    }
}
