@testable import GamePresentation
import XCTest

/// K1-1: what the game's model pack holds, pinned. The app builds
/// ``Map3DModelPack/standard`` (with the bus and trucks from their files)
/// before the first 3D scene and keeps it twice, in memory and on the GPU
/// (40 bytes a vertex each). A pull request that adds models to it adds
/// their lines to the lock files and says in its description by how much
/// the pack grew; a
/// static study the game does not draw goes in ``Map3DModelPack/studies``.
final class Map3DModelPackSizeTests: XCTestCase {
    func testTheStandardPacksSizeIsPinned() throws {
        // Decision 782: the registered trains (``Map3DTrainRegistry``) left
        // out; each one's models and triangles are pinned in its own lock
        // file, and its pull request says how much it adds.
        let models = Map3DModelPack.standard.models.filter { Map3DTrainRegistry.registration(ofModel: $0.name) == nil }
        let vertices = models.reduce(0) { $0 + $1.vertices.count }
        // MODEL-PACK-PINS-SPLIT (2026-11-25): the count and the vertices
        // are no longer one number every pull request rewrote (and so
        // conflicted on; the growth from decision 458 to 956 is in git's
        // history of this file). They are the sum of the lock files' lines:
        // one a model in `pack.lock.txt`, its triangles in
        // `hashes.lock.json`; a pull request that adds a model adds its
        // lines there and says in its description how much it grew.
        let names = try Map3DModelPackLockTests.lockedPackLines().map { String($0.prefix { $0 != " " }) }
        let triangles = try XCTUnwrap(Map3DModelPackLockTests.lockFile(Map3DModelPackLockTests.toolDirectory
            .appendingPathComponent("hashes.lock.json"))["models"] as? [String: [String: Any]])
        let locked = try names.reduce(0) { sum, name in
            try sum + 3 * XCTUnwrap(triangles[name]?["triangles"] as? Int, "\(name): not in hashes.lock.json")
        }
        print("model pack: \(models.count) models, \(vertices) vertices, \(vertices * MemoryLayout<Map3DVertex>.stride) bytes a copy")
        XCTAssertEqual(models.count, names.count)
        XCTAssertEqual(vertices, locked)
        XCTAssertEqual(MemoryLayout<Map3DVertex>.stride, 40)
    }

    /// No model is in both packs, and the studies hold no running car (no
    /// lamps or window models of their own, ``Map3DTrainLights``).
    func testTheStudiesAreApartFromTheGamesPack() {
        let standard = Set(Map3DModelPack.standard.models.map(\.name))
        let studies = Map3DModelPack.studies
        XCTAssertFalse(studies.models.isEmpty)
        XCTAssertTrue(studies.models.allSatisfy { !standard.contains($0.name) })
        XCTAssertTrue(studies.lights.isEmpty)
        XCTAssertFalse(studies.models.contains { Map3DTrainLights.isRunning($0.name) })
    }
}
