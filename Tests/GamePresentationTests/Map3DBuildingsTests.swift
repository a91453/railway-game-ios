import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 235: the city's factories, schools, clinics,
/// temples and malls, and the shapes they are put together from.
final class Map3DBuildingsTests: XCTestCase {
    // MARK: - Shapes

    /// Every face of `mesh` looks away from `inside`.
    private func assertFacesOutward(_ mesh: Map3DMesh, from inside: Map3DPoint, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(mesh.isEmpty, name, file: file, line: line)
        for at in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.vertices[Int(mesh.indices[at])], b = mesh.vertices[Int(mesh.indices[at + 1])], c = mesh.vertices[Int(mesh.indices[at + 2])]
            let middle = (a.position + b.position + c.position) * (1 / 3)
            let normal = Map3DPoint(a.nx, a.ny, a.nz)
            XCTAssertGreaterThan(normal.dot(middle - inside), 0, "\(name): a face looks in", file: file, line: line)
            // The normal is the triangle's own, wound counter-clockwise.
            let wound = (b.position - a.position).cross(c.position - a.position)
            XCTAssertGreaterThan(wound.dot(normal), 0, "\(name): a face wound the wrong way", file: file, line: line)
        }
    }

    func testRoofsAndCylindersFaceOut() {
        for forward in [Map3DPoint(0, 0, -1), Map3DPoint(1, 0, 0)] {
            var gable = Map3DMesh()
            gable.addGableRoof(base: .zero, forward: forward, length: 12, width: 8, rise: 2, color: 1, gable: 2)
            assertFacesOutward(gable, from: Map3DPoint(0, 0.5, 0), "gable")
            XCTAssertEqual(gable.triangleCount, 6)

            var hip = Map3DMesh()
            hip.addHipRoof(base: .zero, forward: forward, length: 12, width: 8, rise: 2, sweep: 0.6, color: 1)
            assertFacesOutward(hip, from: Map3DPoint(0, 0.5, 0), "hip")

            var barrel = Map3DMesh()
            barrel.addBarrelRoof(base: .zero, forward: forward, length: 20, width: 10, rise: 2, color: 1, end: 2)
            assertFacesOutward(barrel, from: Map3DPoint(0, 0.2, 0), "barrel")
        }
        var cylinder = Map3DMesh()
        cylinder.addCylinder(base: .zero, radius: 2, height: 6, sides: 10, top: 1, side: 2)
        assertFacesOutward(cylinder, from: Map3DPoint(0, 3, 0), "cylinder")
        XCTAssertEqual(cylinder.triangleCount, 10 * 2 + 8)
    }

    func testASawtoothRoofsGlazingLooksForward() {
        var mesh = Map3DMesh()
        let grey = Map3DColor.rgb(0x808080)
        mesh.addSawtoothRoof(base: .zero, forward: Map3DPoint(0, 0, -1), length: 21, width: 10, teeth: 3, rise: 2.4, color: grey, glazing: 7)
        let glazing = mesh.vertices.filter { $0.color == 7 }
        XCTAssertEqual(glazing.count, 3 * 4)
        XCTAssertTrue(glazing.allSatisfy { $0.nz < -0.99 }, "north light")
        // The slopes face up and back.
        let slopes = mesh.vertices.filter { $0.color == grey }
        XCTAssertEqual(slopes.count, 3 * 4)
        XCTAssertTrue(slopes.allSatisfy { $0.ny > 0.9 && $0.nz > 0 })
    }

    // MARK: - Buildings

    private func builder() -> Map3DScene.Builder {
        let world = GameWorld.newGame()
        return Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
    }

    private func drawn(_ build: (inout Map3DScene.Builder) -> Void) -> Map3DMesh {
        var builder = builder()
        build(&builder)
        var mesh = Map3DMesh()
        for key in builder.meshes.keys.sorted() { mesh.append(builder.meshes[key] ?? Map3DMesh()) }
        return mesh
    }

    func testEveryKindOfLotStandsWithinItsLotAndItsBudget() {
        // Many lots of each use, a 40 m lot (the city's standard side) and
        // a smaller one: everything stays on the lot, few hundred
        // triangles, and the same lot draws the same building.
        var kinds = Set<UInt32>()
        for side: Float in [40, 24] {
            for column in Int32(0)..<24 {
                let seed = (column, Int32(7))
                for (name, build) in [
                    ("factory", { (b: inout Map3DScene.Builder) in b.addFactory(base: .zero, side: side, seed: seed) }),
                    ("civic", { (b: inout Map3DScene.Builder) in b.addCivic(base: .zero, side: side, density: 2, seed: seed) }),
                    ("leisure", { (b: inout Map3DScene.Builder) in b.addLeisure(base: .zero, side: side, seed: seed) }),
                ] {
                    let mesh = drawn(build)
                    XCTAssertFalse(mesh.isEmpty, name)
                    XCTAssertLessThan(mesh.triangleCount, 700, "\(name) \(side) m, lot \(column)")
                    let reach = side / 2 + 2
                    XCTAssertTrue(mesh.vertices.allSatisfy { abs($0.x) <= reach && abs($0.z) <= reach }, "\(name) \(side) m, lot \(column) spills over")
                    XCTAssertEqual(drawn(build).vertices, mesh.vertices, "\(name) the same every time")
                    kinds.formUnion(mesh.vertices.map(\.color))
                }
            }
        }
        // Factory yards, tanks, temple ridges and school tracks (each
        // drawn in its colour unshaded somewhere) are all among them.
        for color in [Map3DPalette.concrete, Map3DPalette.tankSteel, Map3DPalette.templeRidge, Map3DPalette.track] {
            XCTAssertTrue(kinds.contains(color), String(color, radix: 16))
        }
    }

    /// A clinic's shadow lies under the clinic, its long side along the
    /// building's, and the canopy over its door stands out in front.
    func testAClinicsShadowAndCanopyFollowItsFootprint() throws {
        let world = GameWorld.newGame()
        for facing: Float in [0.3, 0.7] {
            var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
            builder.target = .near
            let lot: Float = 60
            // r(6) < 0.5 faces north (along z), otherwise east (along x).
            builder.addClinic(base: Map3DPoint(100, 0, 100), lot: lot, floors: 4, r: { $0 == 6 ? facing : 0.3 })
            let length = lot * (0.6 + 0.3 * 0.2), width = lot * (0.4 + 0.3 * 0.15)
            let inner = Array(try XCTUnwrap(builder.shadows.values.first).vertices.prefix(4))
            let along = facing < 0.5 ? inner.map(\.z) : inner.map(\.x), across = facing < 0.5 ? inner.map(\.x) : inner.map(\.z)
            XCTAssertEqual(along.max()! - along.min()!, length, accuracy: 0.01, "facing \(facing)")
            XCTAssertEqual(across.max()! - across.min()!, width, accuracy: 0.01, "facing \(facing)")
            // The canopy, 3.2 m up: in front of the face, not inside.
            let canopy = builder.nearMeshes.values.flatMap(\.vertices).filter { $0.y > 3.3 && $0.y < 3.6 && $0.color == Map3DPalette.plant }
            XCTAssertFalse(canopy.isEmpty, "facing \(facing)")
            let out = canopy.map { facing < 0.5 ? 100 - $0.z : $0.x - 100 }
            XCTAssertGreaterThanOrEqual(out.min()!, length / 2 - 0.01, "facing \(facing): the canopy is inside the clinic")
        }
    }

    func testTheTownsHaveFactoriesSchoolsAndRoofRooms() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let scene = Map3DScene(world: world)
        let colors = Set(scene.chunks.flatMap(\.mesh.vertices).map(\.color))
        // Sheet-steel roofs, on factories and on the houses' roof rooms
        // (decision 370: in the model look).
        XCTAssertFalse(colors.isDisjoint(with: Map3DPalette.tinRoofs.flatMap { [$0, Map3DColor.shaded($0, 0.95), Map3DColor.shaded($0, 0.82)] }.map(Map3DLook.colour)))
        XCTAssertEqual(Map3DScene(world: world).chunks.map(\.mesh.vertices), scene.chunks.map(\.mesh.vertices))
    }
}
