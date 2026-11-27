import Foundation
@testable import GameCore
import XCTest
@testable import GamePresentation

/// Decision 1033: every other station's building materials yard is a
/// cement silo yard, and a train loaded mostly there runs cement wagons.
final class Map3DCementFreightTests: XCTestCase {
    func testCementIsTheMaterialsOfTheSiloYards() {
        let train = TrainID(rawValue: 1), stone = StationID(rawValue: 1), silo = StationID(rawValue: 2)
        XCTAssertFalse(Map3DFreightYard.isCement(stone))
        XCTAssertTrue(Map3DFreightYard.isCement(silo))
        func load(_ groups: [CargoGroup]) -> Map3DFreightLoad { Map3DFreightLoad.of(TrainCargo(train: train, groups: groups)) }
        XCTAssertEqual(load([CargoGroup(origin: silo, kind: .materials, tons: 40)]), .cement)
        XCTAssertEqual(load([CargoGroup(origin: stone, kind: .materials, tons: 40)]), .materials)
        XCTAssertEqual(load([CargoGroup(origin: stone, kind: .materials, tons: 30), CargoGroup(origin: silo, kind: .materials, tons: 31)]), .cement)
        XCTAssertEqual(load([CargoGroup(origin: stone, kind: .materials, tons: 31), CargoGroup(origin: silo, kind: .materials, tons: 31)]), .materials,
                       "stone on a tie")
        // Goods against all the materials, stone and cement together.
        XCTAssertEqual(load([CargoGroup(origin: stone, kind: .goods, tons: 50), CargoGroup(origin: stone, kind: .materials, tons: 26),
                             CargoGroup(origin: silo, kind: .materials, tons: 25)]), .materials)
        XCTAssertEqual(load([CargoGroup(origin: stone, kind: .goods, tons: 60), CargoGroup(origin: silo, kind: .materials, tons: 59)]), .goods)
        XCTAssertEqual(Map3DFreightLoad.cement.setKey, Map3DFreightWagons.cementKey)
    }

    /// The studio's wagon: 11.6 m over its couplers, 2.86 m wide, 3.7 m
    /// over the rail, the far one under half its triangles, no glass, only
    /// the last one's tail lamp lit, at its back end.
    func testTheWagons() {
        for tail in [false, true] {
            let near = Map3DCementWagon.model(tail: tail, far: false), far = Map3DCementWagon.model(tail: tail, far: true)
            for model in [near, far] {
                XCTAssertEqual(model.length, 11.6, accuracy: 0.02, "\(model.name)")
                XCTAssertEqual(model.maximum.y - model.minimum.y, 2.86, accuracy: 0.02, "\(model.name)")
                XCTAssertEqual(model.maximum.z, 3.7, accuracy: 0.02, "\(model.name)")
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.001, "\(model.name)")
                XCTAssertTrue(model.name.hasPrefix("freight-cement-car"), "\(model.name): the studio's, not the hopper in its place")
                XCTAssertEqual(Set(model.vertices.map(\.color).filter(Map3DTrainLights.isGlass)), [], "\(model.name): no window")
                XCTAssertFalse(Map3DTrainMaterial.marksOwnGlass(model), "\(model.name)")
                XCTAssertNil(Map3DTrainLights.windowModel(of: model), "\(model.name)")
            }
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount)
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))))
            let lit = near.vertices.filter(\.glows)
            XCTAssertEqual(lit.isEmpty, !tail, "only the last wagon's tail lamp")
            XCTAssertTrue(lit.allSatisfy { $0.x < near.minimum.x + 0.5 && $0.color == Map3DPalette.lantern })
        }
        // The silver body, not the hopper's black.
        XCTAssertTrue(Map3DCementWagon.model(tail: false, far: false).vertices.contains { $0.color == Map3DPalette.tankSteel })
    }

    /// The silo yard: within the stone yard's 40 × 18 m, its foot where
    /// the stone yard's paving is, the far one a few hundred triangles,
    /// the silos 20.5 m tall.
    func testTheSiloYard() throws {
        let silo = StationID(rawValue: 2), stone = StationID(rawValue: 1)
        let near = Map3DFreightYard.mesh(.materials, at: silo), far = Map3DFreightYard.farMesh(.materials, at: silo)
        XCTAssertEqual(near.triangleCount, 1_588)
        XCTAssertEqual(far.triangleCount, 856)
        for mesh in [near, far] {
            let bounds = try XCTUnwrap(mesh.bounds)
            XCTAssertEqual(bounds.max.x - bounds.min.x, Map3DFreightYard.depth, accuracy: 0.02)
            XCTAssertEqual(bounds.max.z - bounds.min.z, Map3DFreightYard.length, accuracy: 0.02)
            XCTAssertEqual(bounds.min.y, -0.15, accuracy: 0.01)
            XCTAssertEqual(bounds.max.y, 20.5, accuracy: 0.02)
            XCTAssertTrue(Set(mesh.vertices.map(\.color)).isSubset(of: Set(Map3DCementSilo.palette)))
        }
        // The blue loading canopy by the track, at its back (−x).
        let canopy = near.vertices.filter { $0.color == Map3DPalette.canopy }
        XCTAssertFalse(canopy.isEmpty)
        XCTAssertLessThan(canopy.map(\.position.x).min()!, -5)
        // Every other station's yard stays the stone yard, and goods' the container yard.
        XCTAssertTrue(Map3DFreightYard.mesh(.materials, at: stone).vertices.contains { $0.color == Map3DFreightWagons.stone })
        XCTAssertEqual(Map3DFreightYard.mesh(.goods, at: silo).triangleCount, Map3DFreightYard.mesh(.goods).triangleCount)
    }
}
