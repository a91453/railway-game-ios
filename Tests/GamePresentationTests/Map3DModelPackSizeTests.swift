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
        // 46,416 vertices more, 1.9 MB a copy). Decision 531 added the
        // Alishan train's DL-38 and coaches, near and far (10 models with
        // the coaches' windows' models, 62,580 vertices more, 2.5 MB a
        // copy, drawn from photographs of the real cars).
        // R100 native heads and new cab window light: +25,356 vertices.
        // Decision 541: the Blue Train's two R100s and #1671's four coach
        // roles, near and far, in place of the R135 set (14 models more with
        // the windows' models, 295,182 vertices more, 11.8 MB a copy).
        // Decision 539: the freight train's container wagons, near and
        // far, behind the R200 Chu-Kuang's own R200 model (8 models, no
        // window models, 53,184 vertices more, 2.1 MB a copy).
        // Decision 554: the Hai-Feng and Shan-Lan as #1539's converted
        // EMU500 units, near and far (32 models with the windows' models,
        // 197,880 vertices more, 7.9 MB a copy).
        // Decision 558: the Wenhu line's VAL256 and 370 as #1742's A and
        // B units, near and far (32 models with the windows' models,
        // 441,888 vertices more, 17.7 MB a copy); the old generic car
        // stays, drawn only before them. Decision 560: the EMU700 as
        // #1730's units, near and far, after them (32 models more with the
        // windows' models, 312,264 vertices more, 12.5 MB a copy).
        // Decision 561: the Taoyuan Airport MRT's 1000 and 2000 as #1700's
        // units, near and far, after them (35 models more with the
        // windows' models, 487,980 vertices more, 19.5 MB a copy).
        // Decision 575 續 (CABLEMAP): the cable car's cabins, tower and
        // halls, near and far, and a rope's metre, last (13 models, 53,148
        // vertices more, 2.1 MB a copy). Decision 585 PR-3 (FERRY3): the
        // two ferries and the pier, near and far, after them (6 models,
        // 43,464 vertices more, 1.7 MB a copy). Decision 615: the Sun Moon
        // Lake cabins, near and far, in the cable car's (8 models, 101,424
        // vertices more, 4.1 MB a copy). Decision 699: the four aircraft,
        // near and far, and the four airfield vehicles, after the ferries
        // (12 models, 54,240 vertices more, 2.2 MB a copy). Decision 708:
        // the coaches' seven liveries, near and far, and the coach stop,
        // near and far, after the aircraft (16 models, 97,050 vertices
        // more, 3.9 MB a copy). Decision 732: Hong Kong's four signals,
        // after the coaches (4 models, 960 vertices more, 38 KB a copy).
        // Decision 738: Hong Kong's double-decker, minibus and taxi
        // stand-ins, after its signals (3 models, 1,200 vertices more).
        XCTAssertEqual(pack.models.count, 889)
        XCTAssertEqual(vertices, 6_585_732)
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
