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
        // vertices; the app swaps in their files' 6,072). Decision 484 put
        // #1456's revision-2 units in the Puyuma set, near and far (the
        // same models; 45,612 vertices more, 1.8 MB a copy). Decision 483
        // added the Kaohsiung and Taichung Green sets, near and far (20
        // models, 107,856 vertices), and made the Ming-Ri #1480's E200
        // and Chu-Kuang coaches (37,716 more vertices than its E500 and
        // generic coaches). Decision 496 added the Danhai, Ankeng and
        // Kaohsiung CAF and Citadis light rail sets, near and far (32
        // models with their windows' models, 679,008 vertices, 27.2 MB a copy).
        // #1530 made the DR1000 railcar the 45DR1000, near and far (8
        // models with the far cars' windows' models, 32,592 vertices
        // more, 1.3 MB a copy). Decision 511 drew the DR3100 on the
        // 45DR1000's shape in its own paint, near and far, instead of the
        // scene kit's three cars (10 models more, 34,128 vertices more,
        // 1.4 MB a copy). Decision 529 put #1589's R200 in the R200CK
        // sets, near and far, in place of the scene kit's (the same models,
        // 46,416 vertices more, 1.9 MB a copy).
        XCTAssertEqual(pack.models.count, 664)
        // R100 native near/far heads and actual cab-window light payload: +25,356 vertices.
        XCTAssertEqual(vertices, 4_383_288)
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
