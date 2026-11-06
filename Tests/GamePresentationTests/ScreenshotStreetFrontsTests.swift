import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 610 續 (FACADE-B): the street-fronts screenshots
/// (``ScreenshotScene/streetFronts``, `WebsiteScreenshotTests`'
/// `testRealStreetFronts` and `testRealStreetFrontsAbove`) look at the real
/// buildings' street fronts. Their first camera, over Fuzhong, had 52 of
/// the fronts' vertices within 80 m and stood against a 48 m tower, so the
/// screenshots before and after were the same.
final class ScreenshotStreetFrontsTests: XCTestCase {
    private static let baseMap = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Resources/BaseMap")
    /// The screenshots' cameras (`-screenshot-3d-view`), as the UI tests ask.
    static let views = ["70,240,55", "140,60,35"]
    /// An iPhone Pro held sideways, in points.
    static let viewport: (width: Float, height: Float) = (874, 402)

    /// The scene as the app builds it, round the scene's place, with the
    /// app's base map and footprints.
    func testTheCamerasSeeStreetFrontsOverTheRoofs() throws {
        let screenshot = ScreenshotScene.streetFronts
        let world = screenshot.make(in: .english)
        let place = try XCTUnwrap(screenshot.place)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
        let tiles = try BaseMapTiles(data: Data(contentsOf: Self.baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let footprints = try FootprintTiles(data: Data(contentsOf: Self.baseMap.appendingPathComponent("taiwan_buildings.pmtiles"),
                                                       options: .alwaysMapped))
        let scene = Map3DScene(world: world, snapshot: world.railwaySnapshot(), focus: (x: at.x, y: at.y), baseMap: tiles,
                               cityTiles: CityTileArea.areas(in: Self.baseMap.appendingPathComponent("city")), footprints: footprints,
                               heights: HighSpeedDemoTests.heights)
        for text in Self.views {
            let view = try XCTUnwrap(Map3DScreenshotView(text))
            let camera = try XCTUnwrap(view.camera(at: place, in: scene, of: world, viewport: Self.viewport))
            let seen = Self.seen(scene, camera)
            print("\(text): \(seen.fronts) street-front vertices in view, tallest \(seen.tallest) m, eye \(camera.eye.y - camera.target.y) m")
            // Thousands of the fronts' vertices in view (the first camera's
            // place had 52 within 80 m).
            XCTAssertGreaterThan(seen.fronts, 2_000, text)
            // The eye over the roofs round what it looks at, not against a
            // tower's wall.
            XCTAssertLessThan(seen.tallest, camera.eye.y - camera.target.y - 10, text)
            // And those chunks draw their close detail from there.
            XCTAssertTrue(scene.chunks.contains {
                !$0.facade.isEmpty && camera.drawsClose(minimum: $0.minimum, maximum: $0.maximum, detailed: true, coarse: $0.coarse)
            }, text)
        }
    }

    /// What the screenshots ask of the app (`-map3D.quality high`,
    /// `-screenshot-device-tier 1`) draws the fronts: the load governor's
    /// first rung is the higher tier's.
    func testTheScreenshotsSettingsDrawTheFronts() {
        let device = Map3DDeviceTier(rawValue: 1)
        let tier = Map3DQuality.high.tier(device: device)
        XCTAssertNotNil(tier)
        let load = Map3DLoadGovernor(top: tier.map(Map3DLoadLevel.top(of:)) ?? 0, start: Map3DLoadGovernor.start(for: .high, device: device))
        XCTAssertTrue(Map3DRealFacade.draws(quality: .high, lowPower: false, heat: .nominal, tier: load.level.tier))
        // The Simulator's own GPU has no tier: without the argument, none.
        XCTAssertFalse(Map3DRealFacade.draws(quality: .high, lowPower: false, heat: .nominal, tier: nil))
    }

    /// The street fronts' vertices `camera` has in view within 150 m of
    /// its eye, and the tallest of the scene within 80 m of its target
    /// (metres above it).
    static func seen(_ scene: Map3DScene, _ camera: Map3DCamera) -> (fronts: Int, tallest: Float) {
        let m = camera.viewProjection.columns, eye = camera.eye, target = camera.target
        var fronts = 0
        for v in scene.chunks.flatMap(\.facade.vertices) {
            let dx = v.x - eye.x, dy = v.y - eye.y, dz = v.z - eye.z
            guard dx * dx + dy * dy + dz * dz < 150 * 150 else { continue }
            let x = m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12], y = m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13]
            let w = m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15]
            if w > 0, abs(x) < w, abs(y) < w { fronts += 1 }
        }
        let tallest = scene.chunks.flatMap(\.mesh.vertices).filter {
            let dx = $0.x - target.x, dz = $0.z - target.z
            return dx * dx + dz * dz < 80 * 80
        }.map { $0.y - target.y }.max() ?? 0
        return (fronts, tallest)
    }
}
