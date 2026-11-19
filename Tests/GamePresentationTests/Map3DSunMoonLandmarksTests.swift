import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 879: the owner's earlier Sun Moon Lake models (the Shuishe
/// pier, three boats, the Wenwu temple, a lakeside pavilion) where the
/// real ones stand on Taiwan's 3D map.
final class Map3DSunMoonLandmarksTests: XCTestCase {
    private typealias Landmark = Map3DSunMoonLandmark

    private static let tiles = Result {
        try BaseMapTiles(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"),
                                    options: .alwaysMapped))
    }

    /// Each model's size as the earlier scene stood it (metres right,
    /// back, and its top): the pier 0.67 × 1 × 2.5 of its 11.8 m by
    /// 12.1 m, the temple 2.1 × 1.3 × 2 of its 17.8 m by 13.3 m by 11.2 m.
    private static let sizes: [Landmark.Model: (x: Float, y: Float, top: Float)] = [
        .pier: (7.88, 30.3, 1.16), .temple: (37.38, 26.51, 14.51), .boat: (2.91, 6.96, 2.53), .pavilion: (5, 5.03, 4.9),
    ]

    /// Every model decodes as large as the earlier scene's, in the
    /// palette's colours only; the far models are a quarter of the near
    /// ones or less, and the pavilion has none.
    func testTheModels() {
        XCTAssertEqual(Set(Self.sizes.keys), Set(Landmark.Model.allCases))
        for model in Landmark.Model.allCases {
            let near = model.mesh(full: true), far = model.mesh(full: false), size = Self.sizes[model]!
            XCTAssertEqual(far.vertices.isEmpty, !model.hasFar, "\(model)")
            for mesh in [near, far] where !mesh.vertices.isEmpty {
                let xs = mesh.vertices.map(\.x), ys = mesh.vertices.map(\.y), zs = mesh.vertices.map(\.z)
                XCTAssertEqual(xs.max()! - xs.min()!, size.x, accuracy: 0.1, "\(model) across")
                XCTAssertEqual(ys.max()! - ys.min()!, size.y, accuracy: 0.1, "\(model) along")
                XCTAssertEqual(zs.max()!, size.top, accuracy: 0.02, "\(model) top")
                XCTAssertTrue(Set(mesh.vertices.map(\.color)).isSubset(of: Set(Landmark.materialColours)), "\(model) colours")
            }
            XCTAssertLessThanOrEqual(near.indices.count / 3, 15_000, "\(model)")
            XCTAssertLessThanOrEqual(far.indices.count * 4, near.indices.count * 5 / 4, "\(model) far")
        }
        // The temple and the pavilion stand on the ground; the pier's
        // piles and the boat's hull reach under the water.
        XCTAssertEqual(Landmark.Model.temple.mesh(full: true).vertices.map(\.z).min()!, 0, accuracy: 0.01)
        XCTAssertEqual(Landmark.Model.pavilion.mesh(full: true).vertices.map(\.z).min()!, 0, accuracy: 0.01)
        XCTAssertEqual(Landmark.Model.pier.mesh(full: true).vertices.map(\.z).min()!, -1.8, accuracy: 0.01)
        XCTAssertEqual(Landmark.Model.boat.mesh(full: true).vertices.map(\.z).min()!, -0.55, accuracy: 0.01)
        XCTAssertEqual(Landmark.all.map(\.model), [.pier, .boat, .boat, .boat, .temple, .pavilion])
    }

    /// The encoding is read whole or not at all.
    func testABrokenMeshIsRefused() throws {
        let text = try XCTUnwrap(Landmark.encodedMeshes["boat-lod1"])
        let bytes = try Array(XCTUnwrap(Data(base64Encoded: text)))
        XCTAssertNotNil(Landmark.decoded(bytes, full: true))
        XCTAssertNil(Landmark.decoded(Array(bytes.dropLast()), full: true))
        XCTAssertNil(Landmark.decoded(bytes + [0], full: true))
    }

    /// A game at the lake, a scene `reach` metres round the point `east`
    /// metres east of the pier, with
    /// the app's base map (its water) when `water`.
    private func scene(reach: Double = 2_500, water: Bool = false, east: Double = 0) throws -> (builder: Map3DScene.Builder, frame: RealWorldFrame) {
        let pier = Landmark.all[0]
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: pier.latitude, longitudeDegrees: pier.longitude)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let origin = frame.worldPosition(latitude: pier.latitude, longitude: pier.longitude)
        let region = WorldRegion(minX: origin.x + (east - reach) * metre, minY: origin.y - reach * metre,
                                 maxX: origin.x + (east + reach) * metre, maxY: origin.y + reach * metre)
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y, region: region, world: world, heights: nil)
        if water {
            _ = builder.addBaseMap(Map3DBaseMap(tiles: try Self.tiles.get(), frame: frame, region: region, originX: origin.x, originY: origin.y))
        }
        return (builder, frame)
    }

    /// Where each model's origin stands in `builder`'s scene.
    private func origin(_ landmark: Landmark, _ builder: Map3DScene.Builder, _ frame: RealWorldFrame) -> Map3DPoint {
        let place = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
        return landmark.origin(anchor: builder.point(x: place.x, y: place.y, height: 0))
    }

    /// All six stand in a scene that holds the lake's north shore, near
    /// and far; the temple and the pavilion on their stone bases, in the
    /// place of the real building under them alone.
    func testOnTheLake() throws {
        var (builder, frame) = try scene()
        let built = builder.addSunMoonLandmarks(frame: frame)
        let triangles = { (meshes: [Map3DScene.ChunkKey: Map3DMesh]) in meshes.values.reduce(0) { $0 + $1.indices.count / 3 } }
        let models = Landmark.all.map(\.model)
        // Each box is 10 triangles (none underneath): the temple's and
        // the pavilion's bases and the ramp's ten steps at every
        // distance, the ramp's 14 posts close by. In full only in the
        // closest detail; the far models stand in from farther (the
        // pavilion, which has none, in full) and from afar.
        let full = models.reduce(0) { $0 + $1.mesh(full: true).indices.count / 3 }
        let far = models.reduce(0) { $0 + $1.mesh(full: false).indices.count / 3 }
        XCTAssertEqual(triangles(builder.closeMeshes), full + 120 + 140)
        XCTAssertEqual(triangles(builder.standInMeshes), far + Landmark.Model.pavilion.mesh(full: true).indices.count / 3 + 120)
        XCTAssertEqual(triangles(builder.farMeshes), far + 120)
        XCTAssertTrue(builder.nearMeshes.isEmpty)
        XCTAssertLessThanOrEqual(triangles(builder.standInMeshes), 9_000)
        // The temple's roof over flat ground: 14.5 m.
        let top = builder.closeMeshes.values.flatMap(\.vertices).map(\.y).max() ?? 0
        XCTAssertEqual(top, 14.51, accuracy: 0.02)
        // The real building at the temple's middle (its middle hall) is
        // not drawn again; the front and rear halls, 27 m and 29 m down
        // and up the hill, and the pier's shore are.
        XCTAssertEqual(built, Landmark.all.map(\.name))
        let temple = origin(Landmark.all[4], builder, frame), front = Landmark.all[4].front
        func replaced(_ p: Map3DPoint) -> Bool {
            builder.replacedPlots.contains { $0.minX <= p.x && p.x <= $0.maxX && $0.minZ <= p.z && p.z <= $0.maxZ }
        }
        XCTAssertTrue(replaced(temple))
        XCTAssertFalse(replaced(temple + front * 27))
        XCTAssertFalse(replaced(temple - front * 29))
        XCTAssertTrue(replaced(origin(Landmark.all[5], builder, frame)))
        XCTAssertFalse(replaced(origin(Landmark.all[0], builder, frame)))
        // No cell is kept clear of the houses along the roads.
        XCTAssertTrue(builder.landmarkPlots.isEmpty)

        // A scene away from the lake has none.
        var (away, awayFrame) = try scene(reach: 300, east: 5_000)
        XCTAssertTrue(away.addSunMoonLandmarks(frame: awayFrame).isEmpty)
        XCTAssertTrue(away.closeMeshes.isEmpty)
    }

    /// The boats lie in a row off the pier's head, on the lake side, 14 m
    /// apart and clear of the pier; the pavilion is west of the pier, the
    /// temple north-east of it and facing back down to the lake.
    func testWhereTheyStand() throws {
        let (builder, frame) = try scene()
        let all = Landmark.all
        let pier = origin(all[0], builder, frame), boats = all[1...3].map { origin($0, builder, frame) }
        let r = all[0].rotation * .pi / 180
        // The pier's head points where its front does not: (−sin r, cos r) east and north.
        let head = Map3DPoint(-sin(r), 0, -cos(r))
        XCTAssertGreaterThan(head.x, 0.6)
        XCTAssertGreaterThan(head.z, 0.6, "south-east")
        for boat in boats {
            let along = (boat - pier).dot(head)
            XCTAssertEqual(along, 20, accuracy: 0.01)
            // The pier's head is 15.3 m out and the boat 3.5 m long each way.
            XCTAssertGreaterThan(along - 3.5, 15.3)
        }
        XCTAssertEqual((boats[1] - boats[0]).length, 14, accuracy: 0.01)
        XCTAssertEqual((boats[2] - boats[1]).length, 14, accuracy: 0.01)
        let pavilion = origin(all[5], builder, frame), temple = origin(all[4], builder, frame)
        XCTAssertEqual((pavilion - pier).length, 92, accuracy: 10)
        XCTAssertLessThan(pavilion.x, pier.x)
        XCTAssertGreaterThan(temple.x, pier.x + 1_000)
        XCTAssertLessThan(temple.z, pier.z - 400, "north")
        // The temple's front (sin r, −cos r east and north) faces south-west.
        let t = all[4].rotation * .pi / 180
        XCTAssertLessThan(sin(t), -0.5)
        XCTAssertGreaterThan(cos(t), 0.3)
    }

    /// On the app's base map the pier's head and the boats are over the
    /// lake, and the temple and the pavilion on land.
    func testThePierIsOnTheWater() throws {
        let (builder, frame) = try scene(reach: 2_000, water: true)
        let all = Landmark.all
        let pier = origin(all[0], builder, frame), r = all[0].rotation * .pi / 180
        XCTAssertTrue(builder.isOverWater(pier + Map3DPoint(-sin(r), 0, -cos(r)) * 12), "the pier's head")
        for boat in all[1...3] { XCTAssertTrue(builder.isOverWater(origin(boat, builder, frame)), boat.name) }
        XCTAssertFalse(builder.isOverWater(origin(all[4], builder, frame)), "the temple")
        XCTAssertFalse(builder.isOverWater(origin(all[5], builder, frame)), "the pavilion")

        // The base map's shore is not where OpenStreetMap's is: the
        // pier is moved until its ramp's end is at the shore as drawn,
        // its head still over the lake.
        let front = all[0].front, slide = builder.shoreSlide(anchor: pier, front: front, end: Landmark.rampEnd)
        XCTAssertNotEqual(slide, 0)
        XCTAssertLessThan(abs(slide), Landmark.shoreReach)
        XCTAssertFalse(builder.isOverWater(pier + front * (Landmark.rampEnd + slide)))
        XCTAssertTrue(builder.isOverWater(pier + front * (Landmark.rampEnd + slide - Landmark.shoreStep)))
        XCTAssertTrue(builder.isOverWater(pier + front * (slide - 15)), "the pier's head")
        for boat in all[1...3] { XCTAssertTrue(builder.isOverWater(origin(boat, builder, frame) + front * slide), boat.name) }
        // With no base map read, it stays where OpenStreetMap has it.
        let (plain, _) = try scene()
        XCTAssertEqual(plain.shoreSlide(anchor: pier, front: front, end: Landmark.rampEnd), 0)
    }

    /// A track across the temple keeps it off the map; a tunnel under it
    /// does not.
    func testClearOfTrack() throws {
        let (plain, frame) = try scene()
        let temple = origin(Landmark.all[4], plain, frame)
        let line = stride(from: Float(-60), through: 60, by: 2).map { temple + Map3DPoint($0, 0, 0) }
        var blocked = plain
        blocked.trackLines = [(line, .surface)]
        blocked.addSunMoonLandmarks(frame: frame)
        var tunnel = plain
        tunnel.trackLines = [(line, .tunnel)]
        tunnel.addSunMoonLandmarks(frame: frame)
        let triangles = { (builder: Map3DScene.Builder) in builder.closeMeshes.values.reduce(0) { $0 + $1.indices.count / 3 } }
        XCTAssertEqual(triangles(tunnel) - triangles(blocked), Landmark.Model.temple.mesh(full: true).indices.count / 3 + 10)
    }
}
