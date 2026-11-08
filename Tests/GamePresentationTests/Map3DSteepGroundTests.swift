@testable import GamePresentation
import XCTest

/// Decision 645 (D8): `map3dShade` in Map3DShaders.metal gives a steep face
/// a wall's bay lines, stronger detail and darker foot only when its
/// surface is not layer 0, the ground's grass. A steep grass slope (the
/// real ground's cover, fields, parks, banks) took them all, and showed
/// dark hatched squares on the mountains. These pin what the shader takes
/// for granted: the ground's paints are the grass layer, layer 0.
final class Map3DSteepGroundTests: XCTestCase {
    func testTheGroundsPaintsAreTheLayerTheShaderLeavesWithoutWalls() {
        XCTAssertEqual(Map3DSurface.grass.rawValue, 0)
        for paint in [Map3DScene.Builder.grass, Map3DScene.Builder.bank] {
            XCTAssertEqual(paint.surface, .grass)
            XCTAssertEqual(Int(paint.layer) % Map3DPaint.detailStep, 0, "the shader reads the surface as layer % 64")
        }
    }

    func testAWallsSurfaceIsNeverTheGroundsLayer() {
        // The surfaces walls are painted with keep their bay lines and foot.
        for wall in [Map3DSurface.plaster, .homeWindows, .shopfront, .flatWindows, .officeGlass, .concrete, .brickTile] {
            XCTAssertNotEqual(wall.rawValue, 0, "\(wall)")
        }
    }
}
