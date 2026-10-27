import GameCore
import XCTest
@testable import GamePresentation

/// Decision 439: the trains' soft shade, baked into their colour once, when
/// the pack is made.
final class Map3DTrainOcclusionTests: XCTestCase {
    private let pack = Map3DModelPack.standard
    private let recipes = Map3DModelPack.unbaked

    private func brightness(_ colour: UInt32) -> Int {
        Int(colour & 0xFF) + Int((colour >> 8) & 0xFF) + Int((colour >> 16) & 0xFF)
    }

    func testThePackIsTheRecipesWithTheShadeBaked() {
        XCTAssertEqual(pack.models.map(\.name), recipes.models.map(\.name))
        for (shaded, recipe) in zip(pack.models, recipes.models) {
            XCTAssertEqual(shaded.vertices.count, recipe.vertices.count, recipe.name)
            // Decision 450: glass and stainless keep their shade in `u` too.
            XCTAssertEqual(shaded.vertices.map { [$0.x, $0.y, $0.z, $0.nx, $0.ny, $0.nz, $0.isTrainMaterial ? 0 : $0.u, $0.v] },
                           recipe.vertices.map { [$0.x, $0.y, $0.z, $0.nx, $0.ny, $0.nz, $0.u, $0.v] }, recipe.name)
            if Map3DTrainOcclusion.isTrain(recipe.name) {
                XCTAssertEqual(shaded.vertices, Map3DTrainOcclusion.baked(Map3DTrainMaterial.marked(recipe)).vertices, recipe.name)
            } else {
                XCTAssertEqual(shaded.vertices, recipe.vertices, "\(recipe.name): props, people and road vehicles are not shaded")
            }
        }
    }

    func testTheShadeOnlyDarkensAndLeavesLampsAndLineShares() {
        for (shaded, recipe) in zip(pack.models, recipes.models) where Map3DTrainOcclusion.isTrain(recipe.name) {
            for (after, before) in zip(shaded.vertices, recipe.vertices) {
                XCTAssertEqual(after.color >> 24, before.color >> 24, "\(recipe.name): the line colour's share stays")
                if before.glows {
                    XCTAssertEqual(after.color, before.color, "\(recipe.name): a lamp is not darkened")
                } else {
                    XCTAssertLessThanOrEqual(brightness(after.color), brightness(before.color), recipe.name)
                    // At most 42% darker (a channel rounds by one).
                    XCTAssertGreaterThanOrEqual(brightness(after.color) + 3, brightness(before.color) * 58 / 100, recipe.name)
                }
            }
        }
    }

    func testUnderTheCarIsDarkerThanItsSide() throws {
        let index = try XCTUnwrap(pack.index(of: "commuter-car"))
        let shaded = pack.models[index].vertices, recipe = recipes.models[index].vertices
        func darkening(_ keep: (Map3DVertex) -> Bool) -> Double {
            let pairs = zip(shaded, recipe).filter { keep($0.1) && !$0.1.glows && brightness($0.1.color) > 0 }
            XCTAssertFalse(pairs.isEmpty)
            return pairs.map { 1 - Double(brightness($0.0.color)) / Double(brightness($0.1.color)) }.reduce(0, +) / Double(pairs.count)
        }
        let under = darkening { $0.nz < -0.5 }
        let side = darkening { abs($0.ny) > 0.9 && $0.z > 2 }
        XCTAssertGreaterThan(under, 0.1, "the underframe is in shade")
        XCTAssertLessThan(side, 0.05, "the open side is not")
    }

    func testALongFaceIsOneShade() {
        for (shaded, recipe) in zip(pack.models, recipes.models) where Map3DTrainOcclusion.isTrain(recipe.name) {
            for start in stride(from: 0, to: recipe.vertices.count, by: 3) {
                let corners = recipe.vertices[start ..< start + 3]
                guard Set(corners.map(\.color)).count == 1 else { continue }
                let long = zip(corners, corners.dropFirst() + corners.prefix(1)).contains { a, b in
                    let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
                    return (dx * dx + dy * dy + dz * dz).squareRoot() > Map3DTrainOcclusion.longEdge
                }
                if long {
                    XCTAssertEqual(Set(shaded.vertices[start ..< start + 3].map(\.color)).count, 1, recipe.name)
                }
            }
        }
    }

    func testTheBakeIsTheSameEveryTimeAndInAnyOrder() throws {
        let names = ["commuter-car", "commuter-cab", "express-car"]
        let models = try names.map { recipes.models[try XCTUnwrap(recipes.index(of: $0))] }
        let together = Map3DTrainOcclusion.baked(models + models.reversed())
        XCTAssertEqual(together.map(\.vertices), (models + models.reversed()).map { Map3DTrainOcclusion.baked($0).vertices })
    }
}
