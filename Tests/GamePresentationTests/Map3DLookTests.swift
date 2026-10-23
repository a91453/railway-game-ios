import GameCore
@testable import GamePresentation
import XCTest

/// Decision 370: the 3D map's model look ((e)): the palette's colours and
/// what the player built kept, the rest of the city pale, the roads lit
/// after dark.
final class Map3DLookTests: XCTestCase {
    func testTheCityIsPaleItsHueKept() {
        // The preview's `pale()` (Python's colorsys), byte for byte.
        let expected: [UInt32: UInt32] = [
            0xFFFFFF: 0xF7F7F7, 0xAEBFCC: 0xEAECEE, 0xC8433F: 0xEADCDB, 0x000000: 0xCCCCCC, 0x4E9E3E: 0xDAE5D8,
        ]
        for (from, to) in expected {
            XCTAssertEqual(Map3DLook.colour(Map3DColor.rgb(from)), Map3DColor.rgb(to), String(from, radix: 16))
        }
        // A model's line share (its alpha) is kept.
        XCTAssertEqual(Map3DLook.colour(Map3DColor.rgb(0xFFFFFF) & 0x00FF_FFFF), Map3DColor.rgb(0xF7F7F7) & 0x00FF_FFFF)
    }

    func testThePaletteAndWhatThePlayerBuiltKeepTheirColours() {
        for kept in [Map3DPalette.ground, Map3DPalette.road(.motorway), Map3DPalette.road(.minor), Map3DPalette.sidewalk,
                     Map3DPalette.centreLine, Map3DPalette.platformEdge, Map3DPalette.ballast, Map3DPalette.rail,
                     Map3DPalette.player, Map3DPalette.playerRoof, Map3DPalette.playerRim, Map3DPalette.canopy] {
            XCTAssertEqual(Map3DLook.colour(kept), kept, String(kept, radix: 16))
        }
        // The owner's pick: the centre line the icon's yellow, the platform
        // edge the safety yellow.
        XCTAssertEqual(Map3DPalette.centreLine, Map3DColor.rgb(0xFFC86B))
        XCTAssertEqual(Map3DPalette.platformEdge, Map3DColor.rgb(0xF2C94C))
        // A street light's head the icon's yellow; its pool stays warm white.
        XCTAssertEqual(Map3DLook.colour(Map3DProp.lampLight), Map3DColor.rgb(0xFFC86B))
        XCTAssertEqual(Map3DProp.lampLight, Map3DColor.rgb(0xFFE3B0))
    }

    func testOnlyAPlainRoadIsLitAfterDark() {
        var mesh = Map3DMesh()
        let road = Map3DPalette.road(.primary)
        mesh.appendTriangle([Map3DVertex(.zero, normal: .up, color: road), Map3DVertex(.zero, normal: .up, color: road),
                             Map3DVertex(.zero, normal: .up, color: road, layer: Float(Map3DSurface.crosswalk.rawValue))])
        mesh.appendTriangle([Map3DVertex(.zero, normal: .up, color: Map3DPalette.water, layer: Map3DVertex.water),
                             Map3DVertex(.zero, normal: .up, color: Map3DPalette.ground),
                             Map3DVertex(.zero, normal: .up, color: Map3DColor.rgb(0x123456))])
        Map3DLook.restyle(&mesh, keeping: [Map3DColor.rgb(0x123456)])
        XCTAssertEqual(mesh.vertices.map(\.layer), [Map3DVertex.road, Map3DVertex.road, Float(Map3DSurface.crosswalk.rawValue),
                                                     Map3DVertex.water, Map3DVertex.plain, Map3DVertex.plain])
        XCTAssertEqual(mesh.vertices.map(\.color), [road, road, road, Map3DPalette.water, Map3DPalette.ground, Map3DColor.rgb(0x123456)])
        // A lit road is neither water nor a glowing lamp.
        XCTAssertFalse(mesh.vertices[0].isWater)
        XCTAssertFalse(mesh.vertices[0].glows)
        XCTAssertTrue(mesh.vertices[3].isWater)
    }

    func testTheStreetFurnitureIsInTheLook() throws {
        let pack = Map3DModelPack.standard
        let lamp = try XCTUnwrap(pack.index(of: Map3DProp.lamp.modelName))
        let colours = Set(pack.models[lamp].vertices.map(\.color))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0xFFC86B)))
        XCTAssertFalse(colours.contains(Map3DProp.lampLight))
    }
}
