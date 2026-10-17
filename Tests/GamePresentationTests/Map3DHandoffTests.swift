import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 269: the 2D map hands over to the 3D map as a
/// pinch comes close, at the same middle and scale, and gets it back.
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

    func testItOpensAmongTheTwoDMapsCloserZoomsLookingStraightDown() {
        for height in [667.0, 844, 1_024] {
            let opens = Map3DHandoff.opensAt(viewportHeight: height)
            XCTAssertLessThan(opens, MapScale.largestSize, "the 2D map can reach it")
            XCTAssertGreaterThan(opens, MapScale.compactSize / 2)
            XCTAssertEqual(Map3DCamera.tilt(atDistance: Map3DHandoff.distance(referenceSize: opens, viewportHeight: height)), 0, accuracy: 1e-5)
        }
        // Handed back a fifth farther out than it opened.
        XCTAssertGreaterThan(Map3DHandoff.closesAt, Map3DCamera.flatFrom)
        XCTAssertTrue(Map3DHandoff.hands(building: false, tutorialRuns: false))
        XCTAssertFalse(Map3DHandoff.hands(building: true, tutorialRuns: false))
        XCTAssertFalse(Map3DHandoff.hands(building: false, tutorialRuns: true))
    }

    func testTheMiddleAndScaleComeBackWhereTheyWent() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let scene = Map3DScene(world: world)
        let x = Double(towns[0].x), y = Double(towns[0].y)
        let size = Map3DHandoff.opensAt(viewportHeight: 844) * 1.1
        let camera = Map3DHandoff.camera(from: Map3DHandoff.Plan(x: x, y: y, referenceSize: size), in: scene, viewport: (390, 844))
        XCTAssertEqual(scene.worldPosition(of: camera.target).x, x, accuracy: 64)
        let back = Map3DHandoff.plan(from: camera, in: scene)
        XCTAssertEqual(back.x, x, accuracy: 64)
        XCTAssertEqual(back.y, y, accuracy: 64)
        XCTAssertEqual(back.referenceSize, size, accuracy: size * 1e-4)
    }

    /// Decision 269, later fix (71.1, the owner: "3D 一放大就跳回 2D"): a
    /// 3D map the button opened, kilometres out, never hands back; one a
    /// pinch handed over hands back only as it is pinched out past the line.
    func testOnlyAPinchOutPastTheLineHandsBack() {
        // The button's 3D map, opened kilometres out: no pinch hands back.
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: nil, from: 9_000, to: 7_000))
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: nil, from: 9_000, to: 11_000))
        // Handed over at 400 m: closer never; out past 960 m, yes.
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: 400, from: 400, to: 300))
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: 400, from: 800, to: 900))
        XCTAssertTrue(Map3DHandoff.handsBack(handedOverAt: 400, from: 900, to: 1_000))
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: 400, from: 1_100, to: 1_000), "coming closer")
        // A 3D view taller than the 2D map's opens farther out at the same
        // scale: a fifth past that, not at once.
        XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: 1_040, from: 1_040, to: 1_100))
        XCTAssertTrue(Map3DHandoff.handsBack(handedOverAt: 1_040, from: 1_200, to: 1_300))
    }

    /// The same on a real-world map's scene: handed over from its 2D map's
    /// zoom, the camera opens inside the line and a pinch closer keeps it.
    func testOnARealMapAPinchCloserStaysInThreeD() {
        let world = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 24.8016, longitudeDegrees: 120.9716)!)
        let scene = Map3DScene(world: world)
        for (width, height) in [(Float(390), Float(844)), (844, 390)] {
            let size = Map3DHandoff.opensAt(viewportHeight: Double(height))
            let middle = scene.worldPosition(of: .zero)
            let camera = Map3DHandoff.camera(from: Map3DHandoff.Plan(x: middle.x, y: middle.y, referenceSize: size), in: scene, viewport: (width, height))
            XCTAssertLessThanOrEqual(camera.distance, Map3DCamera.flatFrom + 1)
            let closer = camera.zoomed(by: 1.5)
            XCTAssertLessThan(closer.distance, camera.distance)
            XCTAssertFalse(Map3DHandoff.handsBack(handedOverAt: camera.distance, from: camera.distance, to: closer.distance))
            let farther = camera.zoomed(by: 0.3)
            XCTAssertTrue(Map3DHandoff.handsBack(handedOverAt: camera.distance, from: camera.distance, to: farther.distance))
        }
    }
}
