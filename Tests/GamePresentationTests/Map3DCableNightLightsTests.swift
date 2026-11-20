@testable import GamePresentation
import XCTest

/// Decision 896: every cable car's cabins and halls are lit after dark,
/// as the trains' windows are: a cabin's glass lit from within, near
/// cabins with their seats and a lamp lit too, a hall's glass band lit.
/// The checks read the drawn pack by name, so a cabin or hall added later
/// is held to them as well.
final class Map3DCableNightLightsTests: XCTestCase {
    private static let litGlass: Set<Float> = [Map3DVertex.trainGlassLit, Map3DVertex.transparentGlassLit]
    private static let darkGlass: Set<Float> = [Map3DVertex.trainGlass, Map3DVertex.transparentGlass]

    /// The models as made (their colours unshaded), every one the pack draws.
    private func drawn(_ prefix: String) -> [Map3DModelPack.Model] {
        let made = Map3DCableCar.drawn.filter { $0.name.hasPrefix(prefix) }
        let packed = Map3DModelPack.standard.models.filter { $0.name.hasPrefix(prefix) }
        XCTAssertEqual(made.map(\.name), packed.map(\.name))
        return made
    }

    /// The pack's shading and glass marking keep what is lit lit.
    func testThePackKeepsTheLights() throws {
        let pack = Map3DModelPack.standard
        for model in Map3DCableCar.drawn where model.name.hasPrefix("cablecar-cabin-") || model.name.hasPrefix("cablecar-station-") {
            let packed = try XCTUnwrap(pack.index(of: model.name).map { pack.models[$0] }, model.name)
            XCTAssertEqual(packed.vertices.filter(\.glows).count, model.vertices.filter(\.glows).count, model.name)
        }
    }

    func testEveryCabinsGlassIsLitAfterDark() {
        let cabins = drawn("cablecar-cabin-")
        // Maokong's two, Sun Moon Lake's four and Ngong Ping's two, near and far.
        XCTAssertEqual(cabins.count, 16)
        for cabin in cabins {
            let lit = cabin.vertices.filter { Self.litGlass.contains($0.layer) }.count
            let dark = cabin.vertices.filter { Self.darkGlass.contains($0.layer) }.count
            XCTAssertGreaterThan(lit, 0, "\(cabin.name): no window lit at night")
            XCTAssertEqual(dark, 0, "\(cabin.name): a pane left dark at night")
        }
    }

    func testEveryNearCabinHasItsInsideLit() {
        for cabin in drawn("cablecar-cabin-") where !cabin.name.hasSuffix("-far") {
            // Lit, and not glass: its seats and ceiling lamp.
            let inside = cabin.vertices.filter { $0.glows && !Self.litGlass.contains($0.layer) }
            XCTAssertGreaterThanOrEqual(inside.count / 3, 12, "\(cabin.name): its seats and lamp unlit")
            XCTAssertTrue(inside.contains { $0.color == Map3DPalette.tunnelLamp }, "\(cabin.name): no lamp")
            // Inside the body: under its roof, over its floor.
            for v in inside {
                XCTAssertLessThan(v.z, -1.2, cabin.name)
                XCTAssertGreaterThan(v.z, CableParts.cabinFloor - 0.05, cabin.name)
            }
        }
    }

    func testEveryHallsGlassBandIsLitAfterDark() {
        let halls = drawn("cablecar-station-")
        XCTAssertEqual(halls.count, 6)
        for hall in halls {
            // The glass in any of its faces' shades (``Map3DTrainMaterial``'s rule).
            let lit = hall.vertices.filter { $0.glows && Map3DTrainMaterial.isGlassColour($0.color) }.count / 3
            let dark = hall.vertices.filter { !$0.glows && Map3DTrainMaterial.isGlassColour($0.color) }.count / 3
            XCTAssertGreaterThanOrEqual(lit, 16, "\(hall.name): its glass band dark at night")
            XCTAssertEqual(dark, 0, hall.name)
        }
    }

    func testTheNgongPingCabinsAreTheStudios() throws {
        for kind in Map3DNgongPingCabin.Kind.allCases {
            for far in [false, true] {
                let cabin = try XCTUnwrap(Map3DNgongPingCabin.model(kind, far: far))
                // On the rope at the origin, the floor where the other cabins' is.
                XCTAssertEqual(cabin.maximum.z, 0.14, accuracy: 0.03, cabin.name)
                XCTAssertEqual(cabin.minimum.z, -4.58, accuracy: 0.03, cabin.name)
                let floor = cabin.vertices.filter { abs($0.z - CableParts.cabinFloor) < 0.002 && $0.nz > 0.9 }
                XCTAssertFalse(floor.isEmpty, cabin.name)
                XCTAssertEqual(cabin.maximum.x, -cabin.minimum.x, accuracy: 0.01, cabin.name)
                // Every colour is one of its palette's; the gold slats the standard cabin's only.
                XCTAssertTrue(cabin.vertices.allSatisfy { Map3DNgongPingCabin.meshPalette.contains($0.color) }, cabin.name)
                XCTAssertEqual(cabin.vertices.contains { $0.color == Map3DPalette.slatGold }, kind == .standard, cabin.name)
            }
            let near = try XCTUnwrap(Map3DNgongPingCabin.model(kind)), far = try XCTUnwrap(Map3DNgongPingCabin.model(kind, far: true))
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(kind): the far one under half")
        }
        XCTAssertEqual(Map3DNgongPingCabin.kind(0), CablewayCabins.isCrystal(0) ? .crystal : .standard)
        XCTAssertEqual(Map3DPalette.slatGold, Map3DColor.rgb(0xA8904A))
    }
}
