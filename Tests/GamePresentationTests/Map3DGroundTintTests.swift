@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 720: the ground under the city's lots in their colours, plain
/// where the player's track runs, and the city's roofs a step deeper.
final class Map3DGroundTintTests: XCTestCase {
    private func lightness(_ color: UInt32) -> Double {
        func linear(_ c: UInt32) -> Double {
            let v = Double(c & 0xFF) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let y = 0.2126 * linear(color) + 0.7152 * linear(color >> 8) + 0.0722 * linear(color >> 16)
        return y > 0.008856 ? 116 * cbrt(y) - 16 : 903.3 * y
    }

    func testALotsGroundIsItsUsesAndDensitys() {
        typealias Kind = Map3DPalette.GroundKind
        XCTAssertEqual(Kind(CitySkyline.Lot(row: 0, column: 0, use: .residential, density: 1)), .yard)
        XCTAssertEqual(Kind(CitySkyline.Lot(row: 0, column: 0, use: .residential, density: 2)), .yard)
        XCTAssertEqual(Kind(CitySkyline.Lot(row: 0, column: 0, use: .residential, density: 3)), .paved)
        XCTAssertEqual(Kind(CitySkyline.Lot(row: 0, column: 0, use: .commercial, density: 1)), .paved)
        XCTAssertEqual(Kind(CitySkyline.Lot(row: 0, column: 0, use: .office, density: 4)), .paved)
        // Open ground draws its own park or field.
        XCTAssertNil(Kind(CitySkyline.Lot(row: 0, column: 0, use: .park, density: 0)))
    }

    func testFourSquaresOfOneKindMeetInItsColour() {
        XCTAssertEqual(Map3DPalette.ground(mixing: [.plain, .plain, .plain, .plain]), Map3DPalette.ground)
        XCTAssertEqual(Map3DPalette.ground(mixing: [.yard, .yard, .yard, .yard]), Map3DPalette.yard)
        XCTAssertEqual(Map3DPalette.ground(mixing: [.paved, .paved, .paved, .paved]), Map3DPalette.paved)
        XCTAssertEqual(Map3DPalette.ground(mixing: [.yard, .plain, .paved, .plain]), Map3DPalette.ground(mixing: [.plain, .paved, .plain, .yard]))
    }

    /// The look leaves every colour the ground can take as it is: a paler
    /// one would differ from the square beside it.
    func testTheLookKeepsTheGroundsColours() {
        XCTAssertEqual(Map3DPalette.groundMixes.count, 15)
        for colour in Map3DPalette.groundMixes { XCTAssertEqual(Map3DLook.colour(colour), colour) }
    }

    /// The track and the trains must stand off the tinted ground as they
    /// do off the plain: every colour within 5 L* of it, and lighter than
    /// the roofs.
    func testTheTintedGroundStaysPale() {
        let plain = lightness(Map3DPalette.ground)
        for colour in Map3DPalette.groundMixes {
            XCTAssertLessThan(plain - lightness(colour), 5)
            XCTAssertGreaterThan(lightness(colour), lightness(Map3DPalette.cityRoof) + 10)
        }
    }

    /// The city's roofs a step deeper than the ground, not the pale
    /// version that ran into it.
    func testTheCitysRoofsStandOffTheGround() {
        XCTAssertEqual(Map3DLook.colour(Map3DPalette.roof), Map3DPalette.cityRoof)
        XCTAssertEqual(Map3DLook.colour(Map3DPalette.cityRoof), Map3DPalette.cityRoof)
        XCTAssertGreaterThan(lightness(Map3DPalette.ground) - lightness(Map3DPalette.cityRoof), 12)
    }

    /// A town with a line through it: its houses' ground in the yards'
    /// colour, and none of it under the track.
    func testATownsGroundTakesItsLotsColoursClearOfTheTrack() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let scene = Map3DScene(world: world)
        let flat = scene.chunks.flatMap { $0.mesh.vertices }.filter { $0.ny > 0.99 }
        XCTAssertTrue(flat.contains { $0.color == Map3DPalette.yard }, "no ground in the yards' colour")
        // The square the track stands in is plain, so each of its corners
        // mixes at least one plain square: never a whole yard or paving.
        let whole: Set<UInt32> = [Map3DPalette.yard, Map3DPalette.paved]
        let cell = Double(Land.cellLength)
        var corners = 0
        for alignment in world.railwaySnapshot().edges {
            for coordinate in alignment.geometry.points {
                let column = (Double(coordinate.x) / cell).rounded(.down), row = (Double(coordinate.y) / cell).rounded(.down)
                for (dx, dy) in [(0.0, 0.0), (1, 0), (0, 1), (1, 1)] {
                    let at = scene.point(worldX: (column + dx) * cell, worldY: (row + dy) * cell, height: 0)
                    let here = flat.filter { abs($0.x - at.x) < 0.5 && abs($0.z - at.z) < 0.5 }
                    corners += here.count
                    XCTAssertFalse(here.contains { whole.contains($0.color) }, "whole tint at a corner of the track's square \(at)")
                }
            }
        }
        XCTAssertGreaterThan(corners, 0, "found none of the ground's corners")
    }
}
