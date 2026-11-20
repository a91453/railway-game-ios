import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 817: the towers' windows in several kinds, each tower's bays
/// and floors its own, and near, their balconies, fins and bay windows.
final class Map3DFacadeVarietyTests: XCTestCase {
    /// Seeded numbers as a building's are: the same salt, the same number.
    private func seeded(_ seed: UInt64) -> (Int32) -> Float {
        { salt in
            var value = seed &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: Int64(salt)) &* 0xBF58_476D_1CE4_E5B9
            value ^= value >> 31
            value = value &* 0x94D0_49BB_1331_11EB
            value ^= value >> 29
            return Float(value % 10_000) / 10_000
        }
    }

    private func looks(_ kind: Map3DScene.Builder.RealKind, storeys: Int, hongKong: Bool = false, solid: Bool = false) -> [Map3DFacadeLook?] {
        (0..<400).map { Map3DFacadeVariety.look(kind, storeys: storeys, hongKong: hongKong, nordic: false, solid: solid, r: seeded($0)) }
    }

    /// Taiwan's towers of flats: balconies or the grid; Hong Kong's mostly
    /// its dense windows; offices of stone ribbons or fins, of glass a
    /// curtain wall, glass alone or fins. Low buildings and a northern
    /// map's keep what they had.
    func testWhichTowersTakeWhichWindows() {
        func styles(_ looks: [Map3DFacadeLook?]) -> Set<Map3DFacadeStyle> { Set(looks.compactMap { $0?.style }) }
        XCTAssertEqual(styles(looks(.flats, storeys: 14)), [.balconies, .grid])
        XCTAssertEqual(styles(looks(.flats, storeys: 30, hongKong: true)), [.hongKong, .balconies, .grid])
        let hongKong = looks(.flats, storeys: 30, hongKong: true).compactMap { $0 }
        XCTAssertGreaterThan(hongKong.filter { $0.style == .hongKong }.count, hongKong.count / 2)
        XCTAssertEqual(styles(looks(.office, storeys: 12, solid: true)), [.ribbon, .fins])
        XCTAssertEqual(styles(looks(.office, storeys: 12)), [.curtain, .glass, .fins])
        XCTAssertTrue(looks(.flats, storeys: 5).allSatisfy { $0 == nil }, "a walk-up keeps decision 610's front")
        XCTAssertTrue(looks(.temple, storeys: 20).allSatisfy { $0 == nil })
        XCTAssertNil(Map3DFacadeVariety.look(.flats, storeys: 30, hongKong: false, nordic: true, solid: false, r: seeded(1)))
    }

    /// Each tower its own bay, floor and narrow-side bay, within its kind's
    /// ranges; the same tower the same every time; the walls painted whole
    /// bays across and floors up on the kind's layer.
    func testEachTowerHasItsOwnBaysAndFloors() throws {
        let all = looks(.flats, storeys: 20) + looks(.office, storeys: 20) + looks(.office, storeys: 20, solid: true)
            + looks(.flats, storeys: 30, hongKong: true)
        for look in all.compactMap({ $0 }) {
            XCTAssertTrue(look.style.bays.contains(look.bay), "\(look)")
            XCTAssertTrue(look.style.storeys.contains(look.storey), "\(look)")
            XCTAssertTrue(Map3DFacadeVariety.sideBays.contains { abs(look.sideBay - look.bay * $0) < 0.001 }, "\(look)")
            if look.style == .hongKong { XCTAssertEqual(look.sideBay, look.bay, "windows round every side") }
            XCTAssertEqual(look.surface == .flatWindows || look.surface == .flatBlinds, look.style == .grid, "\(look)")
        }
        XCTAssertGreaterThan(Set(all.compactMap { $0?.bay }).count, 300, "bays differ tower to tower")
        XCTAssertGreaterThan(Set(all.compactMap { $0?.storey }).count, 300, "and floors")
        XCTAssertEqual(looks(.flats, storeys: 20), looks(.flats, storeys: 20))
        let look = Map3DFacadeVariety.look(.ribbon, r: seeded(7))
        var mesh = Map3DMesh()
        mesh.addBox(base: .zero, length: 30, width: 20, height: 60, top: 1, side: 2, frontPaint: look.paint(high: 60, detail: nil),
                    flankPaint: look.paint(high: 60, detail: nil, side: true))
        let front = mesh.vertices.filter { $0.surface == .officeRibbon }
        XCTAssertFalse(front.isEmpty)
        XCTAssertEqual(try XCTUnwrap(front.map(\.v).max()), Float(look.floors(60)), accuracy: 1e-4)
        XCTAssertEqual(Float(look.floors(60)), (60 / look.storey).rounded())
    }

    /// The five layers light at night as homes and offices do and mirror
    /// as their glass does; the spandrels' curtain wall is all glass.
    func testTheNewWindowsLightAndMirror() {
        for surface in [Map3DSurface.flatBalconies, .hkWindows] {
            XCTAssertEqual(Map3DNightWindows.rule(surface).share, Map3DNightWindows.rule(.flatWindows).share, "\(surface)")
        }
        for surface in [Map3DSurface.officeRibbon, .curtainSpandrel, .officeFins] {
            XCTAssertEqual(Map3DNightWindows.rule(surface).share, Map3DNightWindows.rule(.officeGlass).share, "\(surface)")
            XCTAssertGreaterThan(Map3DReflection.glass(surface).share, 0)
        }
        XCTAssertEqual(Map3DReflection.glass(.curtainSpandrel).share, 1)
    }

    /// A tower of flats `storeys` high, 24 by 16 m, its reliefs near (in
    /// a chunk built in full, with the street fronts built) or none.
    private func tower(at x: Float = 0, storeys: Int = 20, kind: Map3DScene.Builder.RealKind = .flats, world: GameWorld = .newGame(),
                       facades: Bool = true, target: Map3DScene.Builder.Target = .near) -> Map3DMesh {
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        builder.target = target
        builder.buildsFacades = facades
        builder.facadeStreets = target == .far ? nil : []
        let ring = [Map3DPoint(x, 0, 0), Map3DPoint(x + 24, 0, 0), Map3DPoint(x + 24, 0, 16), Map3DPoint(x, 0, 16)]
        builder.addRealBuilding([[ring]], ground: 0, height: Float(storeys) * 3.2, storeys: storeys, kind: kind)
        var facade = Map3DMesh()
        for chunk in builder.chunks() { facade.append(chunk.facade) }
        return facade
    }

    /// Near, some towers' walls have something standing out of them, all
    /// of it against the walls and below the roof; far, or where the
    /// street fronts are never drawn, nothing.
    func testReliefsStandAgainstTheWallsOnlyNear() {
        var built = 0
        for x in stride(from: Float(0), to: 1_600, by: 40) {
            let relief = tower(at: x)
            guard !relief.isEmpty else { continue }
            built += 1
            XCTAssertTrue(relief.vertices.allSatisfy { $0.x >= x - 1.3 && $0.x <= x + 25.3 && $0.z >= -1.3 && $0.z <= 17.3 }, "at \(x)")
            XCTAssertTrue(relief.vertices.allSatisfy { $0.y >= 0 && $0.y <= 64.001 }, "at \(x)")
            XCTAssertTrue(relief.vertices.contains { $0.x < x - 0.1 || $0.x > x + 24.1 || $0.z < -0.1 || $0.z > 16.1 }, "out of a wall at \(x)")
        }
        XCTAssertGreaterThan(built, 4)
        XCTAssertLessThan(built, 40, "not every tower")
        for x in stride(from: Float(0), to: 400, by: 40) {
            XCTAssertTrue(tower(at: x, facades: false).isEmpty)
            XCTAssertTrue(tower(at: x, target: .far).isEmpty)
            XCTAssertTrue(tower(at: x, storeys: 4).isEmpty, "a walk-up keeps decision 610's front alone")
        }
    }

    /// A chunk of 300 towers keeps their reliefs to its own budget, the
    /// same ones whatever order they were built in.
    func testABusyChunkKeepsItsReliefsToItsBudget() {
        let world = GameWorld.newGame()
        func built(_ order: [Int]) -> Map3DMesh {
            var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
            builder.target = .near
            builder.facadeStreets = []
            for index in order {
                let x = Float(index % 20) * 26, z = Float(index / 20) * 20
                let ring = [Map3DPoint(x, 0, z), Map3DPoint(x + 24, 0, z), Map3DPoint(x + 24, 0, z + 16), Map3DPoint(x, 0, z + 16)]
                builder.addRealBuilding([[ring]], ground: 0, height: 64, storeys: 20, kind: .flats)
            }
            var facade = Map3DMesh()
            for chunk in builder.chunks() {
                XCTAssertLessThanOrEqual(chunk.facade.triangleCount, Map3DFacadeVariety.chunkBudget + Map3DRealFacade.chunkBudget)
                facade.append(chunk.facade)
            }
            return facade
        }
        let forward = built(Array(0..<300))
        XCTAssertFalse(forward.isEmpty)
        let backward = built(Array((0..<300).reversed()))
        XCTAssertEqual(backward.triangleCount, forward.triangleCount)
        XCTAssertEqual(Set(backward.vertices.map { [$0.x, $0.y, $0.z] }), Set(forward.vertices.map { [$0.x, $0.y, $0.z] }))
    }

    /// Decision 791 續: a Hong Kong landmark's glass walls are lit by the
    /// bay at night, as a station's curtain wall is (decision 625).
    func testALandmarksGlassWallsLightByTheBay() throws {
        let glass = Set(Map3DHongKongLandmark.glassMaterials.map { Map3DHongKongLandmark.materialColours[$0] })
        var lit = 0
        for landmark in Map3DHongKongLandmark.allCases {
            let curtain = landmark.model(full: true).vertices.filter { $0.layer == Map3DVertex.curtainGlass }
            XCTAssertTrue(curtain.allSatisfy { glass.contains($0.color) }, "\(landmark): only glass")
            XCTAssertTrue(curtain.allSatisfy { abs($0.nz) < 0.7 }, "\(landmark): only walls (z up in the model)")
            lit += curtain.count
        }
        XCTAssertGreaterThan(lit, 0)
    }

    /// FUKUOKA-TOWER-GLASS: Fukuoka Tower's mirror glass is banded by
    /// its floors, not by mullions: its walls are floor-lined glass (lit
    /// at night as curtain glass is), and none of it curtain glass.
    func testFukuokaTowersGlassIsBandedByItsFloors() throws {
        for full in [true, false] {
            let vertices = Map3DHongKongLandmark.fukuokaTower.model(full: full).vertices
            let banded = vertices.filter { $0.layer == Map3DVertex.floorLines }
            XCTAssertGreaterThan(banded.count, 0)
            XCTAssertTrue(banded.allSatisfy { abs($0.nz) < 0.7 }, "only walls")
            XCTAssertEqual(Set(banded.map(\.color)), [Map3DHongKongLandmark.materialColours[18]])
            XCTAssertTrue(banded.contains { $0.v > 100 }, "v is the height in metres")
            XCTAssertFalse(vertices.contains { $0.layer == Map3DVertex.curtainGlass })
        }
        // The other landmarks keep their curtain glass.
        XCTAssertFalse(Map3DHongKongLandmark.fukuokaDome.model(full: true).vertices.contains { $0.layer == Map3DVertex.floorLines && $0.color == Map3DHongKongLandmark.materialColours[18] })
    }
}
