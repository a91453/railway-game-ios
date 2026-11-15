@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 764: the city's own buildings in more colours, each picked by
/// where the building stands, and every roof still a step deeper than the
/// ground (decision 720).
final class Map3DCityPaletteTests: XCTestCase {
    private func lightness(_ color: UInt32) -> Double {
        func linear(_ c: UInt32) -> Double {
            let v = Double(c & 0xFF) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let y = 0.2126 * linear(color) + 0.7152 * linear(color >> 8) + 0.0722 * linear(color >> 16)
        return y > 0.008856 ? 116 * cbrt(y) - 16 : 903.3 * y
    }

    /// Every roof, as the look draws it, stands off the ground as the
    /// concrete one does (decision 720: more than 12 L*).
    func testEveryRoofStandsOffTheGround() {
        let roofs = Map3DPalette.cityRoofs.map(\.color) + Map3DPalette.hallRoofs
        XCTAssertEqual(Set(Map3DPalette.cityRoofs.map(\.color)).count, 6)
        for roof in roofs {
            XCTAssertGreaterThan(lightness(Map3DPalette.ground) - lightness(Map3DLook.colour(roof)), 12, String(roof, radix: 16))
        }
    }

    /// Each roof comes up, by its weight; red tiles only on a low house.
    func testRoofsArePickedByWeightAndRedTilesOnlyLow() {
        var low = Set<UInt32>(), high = Set<UInt32>()
        for step in 0..<200 {
            let share = Float(step) / 200
            low.insert(Map3DScene.Builder.pickRoof(share, low: true))
            high.insert(Map3DScene.Builder.pickRoof(share, low: false))
        }
        XCTAssertEqual(low, Set(Map3DPalette.cityRoofs.map(\.color)))
        let red = Map3DPalette.cityRoofs.filter(\.low).map(\.color)
        XCTAssertEqual(high, Set(Map3DPalette.cityRoofs.map(\.color)).subtracting(red))
        // The grey concrete still the most.
        XCTAssertEqual(Map3DScene.Builder.pickRoof(0, low: true), Map3DPalette.roof)
        XCTAssertEqual(Map3DScene.Builder.pickRoof(1, low: true), Map3DPalette.cityRoofs.last?.color)
    }

    /// The kits keep their colours: the city's lists only add to theirs.
    func testTheCitysWallsAddToTheKits() {
        XCTAssertEqual(Array(Map3DPalette.cityOfficeWalls.prefix(3)), Map3DPalette.officeWalls)
        XCTAssertEqual(Array(Map3DPalette.cityConcreteWalls.prefix(3)), Map3DPalette.concreteWalls)
        XCTAssertEqual(Map3DPalette.officeWalls.count, 3)
        XCTAssertEqual(Map3DPalette.concreteWalls.count, 3)
        XCTAssertEqual(Set(Map3DPalette.cityOfficeWalls).count, 6)
        XCTAssertEqual(Set(Map3DPalette.cityConcreteWalls).count, 6)
    }

    /// A wall at most 8 % darker, never lighter, and the same each time.
    func testAWallVariesALittle() {
        let wall = Map3DPalette.houseWalls[1].color
        XCTAssertEqual(Map3DScene.Builder.varied(wall, 0), wall)
        let darkest = Map3DScene.Builder.varied(wall, 1)
        XCTAssertEqual(darkest, Map3DColor.shaded(wall, 0.92))
        XCTAssertEqual(Map3DScene.Builder.varied(wall, 0.5), Map3DScene.Builder.varied(wall, 0.5))
    }

    /// A town's roofs in several colours, and the same ones each time the
    /// scene is built (a save opens to the same city).
    func testATownsRoofsDifferAndStayTheSame() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let looks = Set((Map3DPalette.cityRoofs.map(\.color) + Map3DPalette.hallRoofs).map { Map3DLook.colour($0) })
        func roofs(_ scene: Map3DScene) -> [UInt32] {
            scene.chunks.flatMap { $0.mesh.vertices }.filter { $0.ny > 0.99 && $0.y > 3 && looks.contains($0.color) }.map(\.color)
        }
        let first = roofs(Map3DScene(world: world))
        XCTAssertGreaterThanOrEqual(Set(first).count, 4, "too few roof colours: \(Set(first).map { String($0, radix: 16) })")
        XCTAssertEqual(first, roofs(Map3DScene(world: world)))
    }
}
