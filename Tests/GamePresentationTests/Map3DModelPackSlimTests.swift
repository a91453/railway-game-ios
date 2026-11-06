@testable import GamePresentation
import XCTest

/// Decision 608: the app puts the model pack's vertices on the GPU and
/// keeps the pack without them (``Map3DModelPack/withoutVertices()``). What
/// it keeps is what the renderer, the train layout, the lamps and the
/// destination signs read: every model's name, vertex count and bounds,
/// in the same order, and the pack's lamps, signs and locked sets.
final class Map3DModelPackSlimTests: XCTestCase {
    func testTheSlimPackKeepsEveryModelsCountAndBounds() {
        for (label, full) in [("standard", Map3DModelPack.standard), ("studies", Map3DModelPack.studies)] {
            let slim = full.withoutVertices()
            XCTAssertEqual(slim.models.count, full.models.count, label)
            for (kept, model) in zip(slim.models, full.models) {
                XCTAssertEqual(kept.name, model.name, label)
                XCTAssertTrue(kept.vertices.isEmpty, "\(label) \(model.name)")
                XCTAssertEqual(kept.vertexCount, model.vertices.count, "\(label) \(model.name)")
                XCTAssertEqual(model.vertexCount, model.vertices.count, "\(label) \(model.name)")
                XCTAssertEqual(kept.triangleCount, model.vertices.count / 3, "\(label) \(model.name)")
                XCTAssertEqual(kept.minimum, model.minimum, "\(label) \(model.name)")
                XCTAssertEqual(kept.maximum, model.maximum, "\(label) \(model.name)")
                XCTAssertEqual(kept.length, model.length, "\(label) \(model.name)")
            }
        }
    }

    func testTheSlimPackKeepsTheLampsSignsAndLocks() {
        var full = Map3DModelPack.standard
        full.locked = ["set-test"]
        let slim = full.withoutVertices()
        XCTAssertEqual(slim.locked, full.locked)
        XCTAssertEqual(slim.headSigns, full.headSigns)
        XCTAssertEqual(Set(slim.lights.keys), Set(full.lights.keys))
        XCTAssertFalse(full.lights.isEmpty)
        for (model, car) in full.lights {
            let kept = slim.lights[model]
            XCTAssertEqual(kept?.windows, car.windows)
            for front in [true, false] {
                XCTAssertEqual(kept?.lamps(atFront: front).head.map(\.x), car.lamps(atFront: front).head.map(\.x))
                XCTAssertEqual(kept?.lamps(atFront: front).tail.map(\.z), car.lamps(atFront: front).tail.map(\.z))
            }
        }
    }

    /// What the renderer looks up by name and lays out by length answers
    /// the same without the vertices.
    func testLookupsAndLayoutsAnswerAsBefore() {
        let full = Map3DModelPack.standard
        let slim = full.withoutVertices()
        for model in full.models.prefix(200) {
            XCTAssertEqual(slim.index(of: model.name), full.index(of: model.name))
        }
        let codes = Array(Map3DModelPack.styleByType.keys) + Map3DTrainSet.all.map(\.key)
        XCTAssertFalse(codes.isEmpty)
        for code in codes {
            XCTAssertEqual(slim.models(forType: code)?.head, full.models(forType: code)?.head, code)
            XCTAssertEqual(slim.models(forType: code)?.middle, full.models(forType: code)?.middle, code)
            XCTAssertEqual(slim.layout(forType: code, count: 6), full.layout(forType: code, count: 6), code)
        }
        XCTAssertEqual(Map3DProp.modelsLeftOut(.saving, in: slim), Map3DProp.modelsLeftOut(.saving, in: full))
    }
}
