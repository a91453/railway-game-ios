@testable import GamePresentation
import XCTest

/// Decision 820: the catalog a scene places its models from, made from the
/// recipes alone, names every model of ``Map3DModelPack/standard`` in its
/// place with its bounds, to the bit, so a scene built from it is the
/// scene built from the pack.
final class Map3DModelCatalogTests: XCTestCase {
    private func bits(_ point: Map3DPoint) -> [UInt32] {
        [point.x.bitPattern, point.y.bitPattern, point.z.bitPattern]
    }

    func testTheRecipesCatalogIsThePacks() {
        let pack = Map3DModelPack.standard.models
        let catalog = Map3DModelCatalog(models: Map3DModelPack.recipesWithWindows(styles: Map3DTrainStyle.all))
        XCTAssertEqual(catalog.names, pack.map(\.name))
        XCTAssertEqual(catalog.minimum.map(bits), pack.map(\.minimum).map(bits))
        XCTAssertEqual(catalog.maximum.map(bits), pack.map(\.maximum).map(bits))
        for name in Set(catalog.names) {
            XCTAssertEqual(catalog.index(of: name), Map3DModelPack.standard.index(of: name), name)
        }
    }

    func testTheSharedCatalogIsThePacks() {
        let catalog = Map3DModelCatalog.standard, pack = Map3DModelPack.standard.models
        XCTAssertEqual(catalog.names, pack.map(\.name))
        XCTAssertEqual(catalog.minimum.map(bits), pack.map(\.minimum).map(bits))
        XCTAssertEqual(catalog.maximum.map(bits), pack.map(\.maximum).map(bits))
    }

    func testAPlacedModelsBoxIsThePacks() {
        let transform: [Float] = [0.8, 0.6, 0, 0, -0.6, 0.8, 0, 0, 0, 0, 1.2, 0, 120.5, -33.25, 4, 1]
        for model in [0, 7, Map3DModelPack.standard.models.count - 1, Map3DModelPack.standard.models.count] {
            let placed = Map3DInstance(model: model, transform: transform, stripe: (0, 0, 0))
            let fromPack = placed.bounds(in: Map3DModelPack.standard), fromCatalog = placed.bounds(from: Map3DModelCatalog.standard)
            XCTAssertEqual(fromPack.map { bits($0.min) + bits($0.max) }, fromCatalog.map { bits($0.min) + bits($0.max) })
        }
    }
}
