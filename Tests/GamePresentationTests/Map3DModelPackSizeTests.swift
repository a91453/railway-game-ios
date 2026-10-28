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
        // 89 studies (1,073,040 vertices) moved out.
        XCTAssertEqual(pack.models.count, 529)
        XCTAssertEqual(vertices, 3_127_704)
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
