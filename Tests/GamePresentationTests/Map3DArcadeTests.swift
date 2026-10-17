import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 267: a row house's street life: the arcade's
/// pillars, a shop's counter, crates and awning, the tin awnings over the
/// windows, the washing and the round water tanks; near only.
final class Map3DArcadeTests: XCTestCase {
    private func builder(_ target: Map3DScene.Builder.Target) -> Map3DScene.Builder {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                                         world: GameWorld.newGame())
        builder.target = target
        return builder
    }

    private func colours(_ builder: Map3DScene.Builder) -> Set<UInt32> {
        Set((builder.nearMeshes.values.flatMap(\.vertices) + builder.farMeshes.values.flatMap(\.vertices)
            + builder.closeMeshes.values.flatMap(\.vertices)).map(\.color))
    }

    func testAShoppingStreetHasItsLifeNearAndOnlyItsTanksAfar() {
        var near = builder(.near)
        var far = builder(.far)
        // A row of low shops on many lots, so each detail turns up.
        for lot in 0..<12 {
            let base = Map3DPoint(Float(lot) * 64, 0, 0)
            near.addRowHouses(base: base, side: 40, density: 1, shops: true, seed: (Int32(lot), 7))
            far.addRowHouses(base: base, side: 40, density: 1, shops: true, seed: (Int32(lot), 7))
        }
        let nearColours = colours(near), farColours = colours(far)
        for (name, palette) in [("counters", Map3DPalette.counters), ("crates", Map3DPalette.crates), ("shop awnings", Map3DPalette.shopAwnings),
                                ("tin awnings", Map3DPalette.tinAwnings), ("washing", Map3DPalette.washing)] {
            XCTAssertFalse(nearColours.isDisjoint(with: palette), "\(name) near")
        }
        // They are the closest detail, apart from the full mesh.
        XCTAssertTrue(Set(near.nearMeshes.values.flatMap(\.vertices).map(\.color)).isDisjoint(with: Map3DPalette.crates))
        XCTAssertFalse(near.closeMeshes.isEmpty)
        // Afar, none of the street's small things; the roofs' tanks stay,
        for palette in [Map3DPalette.crates, Map3DPalette.shopAwnings] {
            XCTAssertTrue(farColours.isDisjoint(with: palette), "nothing small afar")
        }
        // as one box in the tank's colour, with no stand.
        XCTAssertTrue(farColours.contains(Map3DPalette.tankBlue) || farColours.contains(Map3DPalette.tankSteel))
        XCTAssertFalse(farColours.contains(Map3DPalette.tankStand))
        XCTAssertTrue(nearColours.contains(Map3DPalette.tankStand))
        // The same every time.
        var again = builder(.near)
        for lot in 0..<12 { again.addRowHouses(base: Map3DPoint(Float(lot) * 64, 0, 0), side: 40, density: 1, shops: true, seed: (Int32(lot), 7)) }
        XCTAssertEqual(again.nearMeshes.values.map(\.vertices.count).sorted(), near.nearMeshes.values.map(\.vertices.count).sorted())
    }

    func testAnAwningSlopesOutAndDownWithItsFaceUp() {
        var mesh = Map3DMesh()
        Map3DScene.Builder.addSlope(&mesh, from: Map3DPoint(0, 3, 0), facing: Map3DPoint(0, 0, 1), width: 4, depth: 1.1, drop: 0.28, color: 1)
        XCTAssertEqual(mesh.triangleCount, 2)
        XCTAssertTrue(mesh.vertices.allSatisfy { $0.ny > 0.9 }, "face up")
        XCTAssertEqual(mesh.vertices.map(\.z).max() ?? 0, 1.1, accuracy: 1e-4)
        XCTAssertEqual(mesh.vertices.map(\.y).min() ?? 0, 3 - 0.28, accuracy: 1e-4)
        // Washing hangs upright, facing out.
        var panel = Map3DMesh()
        Map3DScene.Builder.addPanel(&panel, at: Map3DPoint(0, 2, 1), facing: Map3DPoint(0, 0, 1), width: 0.45, height: 0.6, color: 1)
        XCTAssertTrue(panel.vertices.allSatisfy { $0.nz > 0.9 })
        XCTAssertEqual(panel.vertices.map(\.y).min() ?? 0, 1.4, accuracy: 1e-4)
    }
}
