@testable import GamePresentation
import XCTest

/// K1-1: what the game's model pack holds, pinned. The app builds
/// ``Map3DModelPack/standard`` (with the bus and trucks from their files)
/// before the first 3D scene and keeps it twice, in memory and on the GPU
/// (40 bytes a vertex each). A pull request that adds models to it updates
/// these numbers and says in its description by how much they grew; a
/// static study the game does not draw goes in ``Map3DModelPack/studies``.
final class Map3DModelPackSizeTests: XCTestCase {
    func testTheStandardPacksSizeIsPinned() {
        let pack = Map3DModelPack.standard
        let vertices = pack.models.reduce(0) { $0 + $1.vertices.count }
        // K1-1 (2026-10-28): 618 models and 4,200,744 vertices before the
        // 89 studies (1,073,040 vertices) moved out. Decision 458 added the
        // six scenery stand-ins (954 vertices; the app swaps in their
        // files' 2,760). Decision 461 added the C371, C381 and 610 sets,
        // near and far (48 models, 203,424 vertices). Decision 466 added
        // the Sanying set, near and far (8 models, 42,024 vertices).
        // Decision 467 added the post boxes' and stop pole's stand-ins (498
        // vertices; the app swaps in their files' 6,072). Decision 483
        // added the Kaohsiung and Taichung Green sets, near and far (20
        // models, 107,856 vertices), and made the Ming-Ri #1480's E200
        // and Chu-Kuang coaches (37,716 more vertices than its E500 and
        // generic coaches).
        XCTAssertEqual(pack.models.count, 613)
        XCTAssertEqual(vertices, 3_520_176)
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
