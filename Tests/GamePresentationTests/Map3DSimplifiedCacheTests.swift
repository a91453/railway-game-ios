import Foundation
import XCTest
@testable import GamePresentation

/// Decision 467: the lighter versions made off the main thread and kept in
/// the device's caches.
final class Map3DSimplifiedCacheTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lod-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var model: Map3DModelPack.Model {
        let pack = Map3DModelPack.unbaked
        return pack.models[pack.index(of: "commuter-cab")!]
    }

    func testAVersionIsMadeOnceAndKept() async throws {
        let cache = Map3DSimplifiedCache(folder: folder)
        let made = await cache.versions(of: model, shares: [0.5, 0.25], maxError: 0.01)
        let expected = model.simplified(to: [0.5, 0.25], maxError: 0.01)
        XCTAssertEqual(made.map(\.vertices), expected.map(\.vertices))
        XCTAssertEqual(made.map(\.name), [model.name, model.name])
        XCTAssertEqual(made[0].minimum, model.minimum)
        XCTAssertEqual(made[0].maximum, model.maximum)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(files.count, 2)
        // Read back as it was written.
        let again = await cache.versions(of: model, shares: [0.5, 0.25], maxError: 0.01)
        XCTAssertEqual(again.map(\.vertices), expected.map(\.vertices))
    }

    func testAKeptVersionIsReadNotMade() async {
        // What the folder holds under the key is what comes back.
        let cache = Map3DSimplifiedCache(folder: folder)
        let kept = Array(model.vertices.prefix(6))
        cache.write(kept, key: Map3DSimplifiedCache.key(of: model, share: 0.5, maxError: Map3DMeshSimplifier.recommendedMaxError))
        let read = await cache.versions(of: model, shares: [0.5])
        XCTAssertEqual(read[0].vertices, kept)
    }

    func testAFileThatCannotBeReadIsMadeAgain() async throws {
        let cache = Map3DSimplifiedCache(folder: folder)
        let key = Map3DSimplifiedCache.key(of: model, share: 0.5, maxError: nil)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Cut short.
        try Data("M3DL\u{1}\0\0\0\u{9}\0\0\0abc".utf8).write(to: cache.url(of: key))
        XCTAssertNil(cache.read(key: key))
        let made = await cache.versions(of: model, shares: [0.5], maxError: nil)
        XCTAssertEqual(made[0].vertices, model.simplified(to: 0.5).vertices)
        XCTAssertEqual(cache.read(key: key), made[0].vertices)
    }

    func testTheKeyFollowsTheModelShareAndLimit() {
        let key = Map3DSimplifiedCache.key(of: model, share: 0.5, maxError: nil)
        XCTAssertEqual(key, Map3DSimplifiedCache.key(of: model, share: 0.5, maxError: nil))
        XCTAssertNotEqual(key, Map3DSimplifiedCache.key(of: model, share: 0.25, maxError: nil))
        XCTAssertNotEqual(key, Map3DSimplifiedCache.key(of: model, share: 0.5, maxError: 0.01))
        var moved = model.vertices
        moved[0].x += 0.001
        let other = Map3DModelPack.Model(name: model.name, vertices: moved, minimum: model.minimum, maximum: model.maximum)
        XCTAssertNotEqual(key, Map3DSimplifiedCache.key(of: other, share: 0.5, maxError: nil))
    }
}
