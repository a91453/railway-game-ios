import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 581, later: the locomotives parked in the Changhua Roundhouse
/// stand on their stalls' tracks, through the doorway, clear of the walls,
/// the piers and the turntable's pit; the roundhouse, the turntable and
/// every other landmark are as they were on main.
final class Map3DRoundhouseStockTests: XCTestCase {
    /// Every vertex field and index, FNV-1a.
    private func hash(_ vertices: [Map3DVertex], _ indices: [UInt32]) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        func eat(_ word: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) { h = (h ^ UInt64((word >> UInt32(shift)) & 0xFF)) &* 0x100000001b3 }
        }
        for v in vertices {
            for word in [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern, v.nx.bitPattern, v.ny.bitPattern, v.nz.bitPattern,
                         v.color, v.u.bitPattern, v.v.bitPattern, v.layer.bitPattern] { eat(word) }
        }
        indices.forEach(eat)
        return String(h, radix: 16)
    }

    /// Main's landmarks before this change: triangles and hash, close by
    /// and far off.
    private static let landmarks: [Map3DTaipeiLandmark: ((Int, String), (Int, String))] = [
        .taipei101: ((5804, "d39feb200da3d6a"), (2580, "e33f55ca7a11483b")),
        .taipeiMainStation: ((4194, "c996605fad46a8c4"), (902, "556ec393e3e36776")),
        .kaohsiungMainStation: ((5883, "b836f2a68da26235"), (2065, "86b76b7d4699aa7b")),
        .kaohsiung85SkyTower: ((2310, "ee4d44cd820089ff"), (1078, "ebfea4bf09eb8a98")),
        .shinKongLifeTower: ((2413, "1ef60c5af94aa660"), (1217, "8a127e71d49e2b93")),
        .changhuaRoundhouse: ((5702, "40208a78c3f9d6ac"), (2002, "3e1c6486c60de5ec")),
        .greatHarborBridge: ((1190, "24d63acf20f009b9"), (466, "953685369d06f14f")),
        .kaohsiungMusicCenter: ((5584, "3161343a74054c98"), (1784, "d2a0e0f7cd4c47ac")),
        .gushanFerryTerminal: ((774, "b5cc6f28be300997"), (268, "a81434fe3c8223b5")),
        .cijinFerryTerminal: ((1121, "2afe5b61589b3071"), (415, "f040db6e78aee5e6")),
        .chiangKaiShekMemorialHall: ((590, "e8821300844e35d4"), (222, "c5fffde0b91f2475")),
        .libertySquareGate: ((2392, "f6182ae366b1d6fe"), (1152, "37c9d1b9f27c3890")),
        .nationalTheater: ((2080, "338f211c66388c19"), (468, "67dc20236a53999b")),
        .nationalConcertHall: ((2010, "b55d73922db6229"), (470, "f96458e1aae66993")),
        .presidentialOffice: ((720, "e3a258a2893a4853"), (344, "7146dabc1947295d")),
        .ximenRedHouse: ((1984, "b9d744d65970dd07"), (760, "a9efb58917194011")),
        .sunYatSenMemorialHall: ((1616, "7b535578f6b8e7a5"), (352, "5a4f4365710b95a0")),
        .grandHotel: ((2394, "314cc07e6c55e951"), (794, "cdba46882d9da1c2")),
        .northGate: ((550, "45c021b0f214875"), (254, "b19de8210b88fc3e")),
        .eastGate: ((770, "d0ac19154df5c17f"), (370, "e66997502e61b288")),
        .southGate: ((914, "81227e1961eac32b"), (370, "9a0dc8b1e0f6b454")),
        .smallSouthGate: ((582, "381dd7e14f101bd"), (262, "aa78cdf67928014e")),
    ]

    /// The roundhouse (decision 581) and its turntable (decision 441) are
    /// main's, and so is every other landmark, close by and far off.
    func testTheLandmarksAndTheTurntableAreAsTheyWere() {
        XCTAssertEqual(Set(Self.landmarks.keys), Set(Map3DTaipeiLandmark.allCases))
        for landmark in Map3DTaipeiLandmark.allCases {
            guard let pinned = Self.landmarks[landmark] else { continue }
            for (full, expected) in [(true, pinned.0), (false, pinned.1)] {
                let model = landmark.model(full: full)
                XCTAssertEqual(model.indices.count / 3, expected.0, "\(landmark) \(full)")
                XCTAssertEqual(hash(model.vertices, model.indices), expected.1, "\(landmark) \(full)")
            }
        }
        XCTAssertEqual(hash(Map3DDepotFacilities.turntable.vertices, Map3DDepotFacilities.turntable.indices), "2b84de18cfdb7a61")
        XCTAssertEqual(hash(Map3DDepotFacilities.turntableFar.vertices, Map3DDepotFacilities.turntableFar.indices), "a8c505f8448f48fe")
    }

    /// The stalls and their locomotives: fixed, none side by side, none in
    /// the narrow middle stalls (5–9, whose doorways are narrower than a
    /// locomotive), at least one of each kind.
    func testWhichStallsHoldWhich() {
        let stalls = Map3DRoundhouseStock.parked.map(\.stall)
        XCTAssertEqual(stalls, [1, 4, 10, 12])
        XCTAssertEqual(Set(Map3DRoundhouseStock.parked.map(\.kind)), Set(Map3DRoundhouseStock.Kind.allCases))
        for (a, b) in zip(stalls, stalls.dropFirst()) { XCTAssertGreaterThan(b - a, 1) }
        XCTAssertTrue(stalls.allSatisfy { !(5 ... 9).contains($0) })
    }

    /// Each locomotive, close by and far off, in the roundhouse's own
    /// space: its wheels on the rails, centred on its stall's track, its
    /// front towards the turntable; within its stall's side walls and in
    /// front of the rear wall; through the doorway under the lintel, clear
    /// of the piers and the corner haunches; outside the turntable's pit.
    func testParkedOnTheStallTracksClearOfTheWalls() {
        let focus = LandmarkMesh.roundhouseFocus
        let bounds = LandmarkMesh.roundhouseStallBounds
        let inner = LandmarkMesh.roundhouseStallRIn, outer = LandmarkMesh.roundhouseStallROut
        for full in [true, false] {
            let mesh = Map3DRoundhouseStock.model(full: full)
            XCTAssertFalse(mesh.vertices.contains { $0.layer == Map3DVertex.glowing }, "parked, its lamps are off")
            var start = 0
            for spot in Map3DRoundhouseStock.parked {
                let count = spot.kind.model(far: !full).vertices.count
                let vertices = mesh.vertices[start ..< start + count]
                start += count
                let i = spot.stall - 1, a0 = bounds[i], a1 = bounds[i + 1], span = a1 - a0
                let axis = Map3DRoundhouseStock.axis(ofStall: spot.stall) * .pi / 180
                let along = (x: cos(axis), y: sin(axis)), across = (x: -sin(axis), y: cos(axis))
                var radii: [Float] = [], sides: [Float] = []
                for v in vertices {
                    let dx = v.x - focus.x, dy = v.y - focus.y
                    let r = (dx * dx + dy * dy).squareRoot()
                    let angle = atan2(dy, dx) * 180 / .pi
                    radii.append(dx * along.x + dy * along.y)
                    sides.append(dx * across.x + dy * across.y)
                    let label = "stall \(spot.stall) \(full) at r \(r), angle \(angle), z \(v.z)"
                    XCTAssertGreaterThanOrEqual(v.z, Map3DRoundhouseStock.railTop - 0.001, label)
                    XCTAssertLessThan(r, outer[i] - 0.25, "rear wall: " + label)
                    if r > inner[i] + 0.45 {
                        XCTAssertTrue(angle > a0 && angle < a1, "side walls: " + label)
                    } else if r > inner[i] - 0.34 {
                        XCTAssertTrue(angle > a0 + 0.52 && angle < a1 - 0.52, "piers: " + label)
                        XCTAssertLessThan(v.z, 4.50, "lintel: " + label)
                        if v.z > 3.80 {
                            XCTAssertTrue(angle > a0 + 0.20 * span && angle < a1 - 0.20 * span, "haunches: " + label)
                        }
                    }
                    let tx = v.x - 3.47, ty = v.y + 19.53
                    XCTAssertGreaterThan((tx * tx + ty * ty).squareRoot(), Map3DDepotFacilities.pitRadius + 0.3, "pit: " + label)
                }
                XCTAssertEqual(vertices.map(\.z).min() ?? 0, Map3DRoundhouseStock.railTop, accuracy: 0.001)
                XCTAssertEqual(((sides.min() ?? 0) + (sides.max() ?? 0)) / 2, 0, accuracy: 0.05, "on the track's centre")
                // The front, the model's +x, out of the doorway towards the turntable.
                XCTAssertEqual(radii.min() ?? 0, inner[i] - spot.out, accuracy: 0.05)
                XCTAssertLessThan(radii.max() ?? 0, outer[i] - 0.25)
            }
            XCTAssertEqual(start, mesh.vertices.count)
        }
    }

    /// The front is the locomotive's front: the R200's radiator and fan
    /// end (+x, decision 529's lamps lit there in a train) is the end
    /// nearest the turntable.
    func testTheFrontFacesTheTurntable() throws {
        let spot = try XCTUnwrap(Map3DRoundhouseStock.parked.first { $0.kind == .r200 })
        let axis = Map3DRoundhouseStock.axis(ofStall: spot.stall) * .pi / 180
        let focus = LandmarkMesh.roundhouseFocus
        let mesh = Map3DRoundhouseStock.model(full: true)
        let offset = Map3DRoundhouseStock.parked.prefix { $0.stall != spot.stall }.reduce(0) { $0 + $1.kind.model(far: false).vertices.count }
        let model = Map3DR200.model()
        let placed = mesh.vertices[offset ..< offset + model.vertices.count]
        let r0 = Map3DRoundhouseStock.originRadius(stall: spot.stall, front: model.maximum.x, out: spot.out)
        for (v, original) in zip(placed, model.vertices) {
            let radius = (v.x - focus.x) * cos(axis) + (v.y - focus.y) * sin(axis)
            XCTAssertEqual(radius, r0 - original.x, accuracy: 0.01)
        }
    }

    /// Triangles (decision 368): the four close by and far off.
    func testTheTriangles() {
        XCTAssertEqual(Map3DRoundhouseStock.model(full: true).indices.count / 3, 2 * 7_318 + 2 * 12_702)
        XCTAssertEqual(Map3DRoundhouseStock.model(full: false).indices.count / 3, 2 * 3_466 + 2 * 5_098)
    }

    /// A new game at the roundhouse builds it with its locomotives, close
    /// by and far off, their colours kept; Taipei's scene has none.
    func testTheSceneHasThem() throws {
        let roundhouse = Map3DTaipeiLandmark.changhuaRoundhouse
        let world = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: roundhouse.latitude, longitudeDegrees: roundhouse.longitude)!)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
        XCTAssertEqual(Set(builder.addTaipeiLandmarks(frame: frame).keys), [roundhouse])
        func triangles(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Int { meshes.values.reduce(0) { $0 + $1.indices.count / 3 } }
        XCTAssertEqual(triangles(builder.nearMeshes),
                       (roundhouse.model(full: true).indices.count + Map3DRoundhouseStock.model(full: true).indices.count) / 3)
        XCTAssertEqual(triangles(builder.farMeshes),
                       (roundhouse.model(full: false).indices.count + Map3DRoundhouseStock.model(full: false).indices.count) / 3)
        XCTAssertTrue(builder.keptColours.contains(Map3DR200.navy))
        XCTAssertTrue(builder.keptColours.contains(Map3DR200.white))
    }
}
