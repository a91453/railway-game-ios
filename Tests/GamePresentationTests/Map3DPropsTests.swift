import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 244: street trees, lights and utility poles along a
/// real-world map's roads, drawn as instances near the camera.
final class Map3DPropsTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }
    private let pack = Map3DModelPack.standard

    func testTheModelsAreTheirRealSizes() throws {
        for (prop, height, triangles) in [(Map3DProp.tree, Float(4.4 + 2.3 * 0.95), 60...90), (.lamp, 8.62, 30...60), (.pole, 10.2, 60...120)] {
            let model = pack.models[try XCTUnwrap(pack.index(of: prop.modelName))]
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.01, "\(prop) stands on the ground")
            XCTAssertEqual(model.maximum.z, height, accuracy: 0.1, "\(prop)")
            XCTAssertTrue(triangles.contains(model.triangleCount), "\(prop): \(model.triangleCount) triangles")
        }
        // A light's arm and head reach out over the road (+y), 2.25 m.
        let lamp = pack.models[try XCTUnwrap(pack.index(of: "prop-lamp"))]
        XCTAssertEqual(lamp.maximum.y, 2.25 + 0.375, accuracy: 0.05)
        // A tree's crown takes the instance's green (alpha 0), its trunk not.
        let tree = pack.models[try XCTUnwrap(pack.index(of: "prop-tree"))]
        XCTAssertTrue(tree.vertices.contains { $0.color >> 24 == 0 && $0.z > 2 })
        XCTAssertTrue(tree.vertices.filter { $0.z < 2 }.allSatisfy { $0.color >> 24 == 0xFF })
    }

    func testAPropStandsOnItsFootAndLooksTowardTheRoad() {
        // Along the street to the east; the road to its north (−z).
        let instance = Map3DInstance.prop(3, at: Map3DPoint(10, 1, 20), forward: Map3DPoint(1, 0, 0), scale: 2, tint: Map3DColor.rgb(0x336699))
        let t = instance.transform
        func apply(_ p: Map3DPoint) -> Map3DPoint {
            Map3DPoint(t[0] * p.x + t[4] * p.y + t[8] * p.z + t[12], t[1] * p.x + t[5] * p.y + t[9] * p.z + t[13], t[2] * p.x + t[6] * p.y + t[10] * p.z + t[14])
        }
        XCTAssertEqual(apply(.zero), Map3DPoint(10, 1, 20))
        XCTAssertEqual(apply(Map3DPoint(0, 0, 1)), Map3DPoint(10, 3, 20), "up, twice the size")
        XCTAssertEqual(apply(Map3DPoint(0, 1, 0)), Map3DPoint(10, 1, 18), "its left to the north")
        XCTAssertEqual(instance.stripe.0, 0x33 / 255, accuracy: 1e-6)
    }

    func testATaipeiStreetHasTreesLightsAndPoles() throws {
        let tiles = try Self.tiles.get()
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        let scene = Map3DScene(world: world, baseMap: tiles)
        let props = scene.chunks.flatMap(\.props)
        let counts = Dictionary(grouping: props, by: \.model).mapValues(\.count)
        // Decision 391: none on the elevated roads round the station, so
        // fewer bus stops (75, 102 with the roads on the ground).
        // Decision 429: the amber signal is only drawn, as the clock shows.
        XCTAssertNil(counts[try XCTUnwrap(pack.index(of: Map3DProp.signalAmber.modelName))])
        for prop in Map3DProp.allCases where prop != .signalAmber {
            XCTAssertGreaterThan(counts[try XCTUnwrap(pack.index(of: prop.modelName))] ?? 0, prop == .busStop ? 60 : 100, "\(prop)")
        }
        // Every one stands in the chunk it is drawn with, the same every time.
        for chunk in scene.chunks {
            for prop in chunk.props {
                XCTAssertEqual(Int((prop.transform[12] / Map3DScene.chunkSize).rounded(.down)), chunk.column)
                XCTAssertEqual(Int((prop.transform[14] / Map3DScene.chunkSize).rounded(.down)), chunk.row)
            }
        }
        XCTAssertEqual(Map3DScene(world: world, baseMap: tiles).chunks.flatMap(\.props).map(\.floats), props.map(\.floats))
        // Decision 263: a blank map's are along its seeded streets.
        XCTAssertFalse(Map3DScene(world: GameWorld.newGame()).chunks.allSatisfy(\.props.isEmpty))
    }

    func testNoPropStandsWhereTheTrackRuns() throws {
        let tiles = try Self.tiles.get()
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)))
        guard let frame = RealWorldFrame(world: world) else { return XCTFail("a real-world map") }
        let region = WorldRegion(minX: frame.middleX - 64_000, minY: frame.middleY - 64_000, maxX: frame.middleX + 64_000, maxY: frame.middleY + 64_000)
        var builder = Map3DScene.Builder(originX: frame.middleX, originY: frame.middleY, region: region, world: world)
        let map = Map3DBaseMap(tiles: tiles, frame: frame, region: region, originX: frame.middleX, originY: frame.middleY)
        _ = builder.addBaseMap(map)
        let all = builder.props.values.flatMap { $0 }
        XCTAssertFalse(all.isEmpty)
        let cells = Set(all.map { instance in
            Map3DScene.ChunkKey(column: builder.gridCell(Double(instance.transform[12]), origin: builder.originX),
                                row: builder.gridCell(Double(instance.transform[14]), origin: builder.originY))
        })
        builder.removeProps(on: cells)
        XCTAssertTrue(builder.props.values.allSatisfy(\.isEmpty))
    }
}

extension Map3DPropsTests {
    func testATreesCrownFacesOut() throws {
        // Every face of a lump looks away from its middle, so the sun lights
        // the top of the crown.
        var mesh = Map3DMesh()
        Map3DProp.addLump(&mesh, centre: Map3DPoint(0, 4, 0), radius: 2)
        XCTAssertEqual(mesh.triangleCount, 20)
        for at in stride(from: 0, to: mesh.indices.count, by: 3) {
            let corners = (0..<3).map { mesh.vertices[Int(mesh.indices[at + $0])] }
            let middle = corners.reduce(Map3DPoint.zero) { $0 + $1.position } * (1 / 3)
            XCTAssertGreaterThan(Map3DPoint(corners[0].nx, corners[0].ny, corners[0].nz).dot(middle - Map3DPoint(0, 4, 0)), 0)
        }
    }
}
