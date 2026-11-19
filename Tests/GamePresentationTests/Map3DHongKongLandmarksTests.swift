import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 791: Hong Kong's landmark towers, the local studio's models of
/// the Lands Department's surveyed shapes, on Hong Kong's 3D map.
final class Map3DHongKongLandmarksTests: XCTestCase {
    /// Each surveyed model's size (metres east, north, up), from
    /// `base/landmarks.json` in the studio's brief.
    private static let surveyed: [Map3DHongKongLandmark: (x: Float, y: Float, z: Float)] = [
        .internationalCommerceCentre: (90.4, 89.2, 463.2),
        .twoIFC: (68.8, 78.8, 414.2),
        .centralPlaza: (78.6, 82.9, 374.5),
        .bankOfChinaTower: (68.5, 68.5, 365.8),
        .cheungKongCenter: (66.5, 66.2, 284.9),
        .hsbcMainBuilding: (80.3, 72.8, 185.1),
        .theCenter: (59.1, 59.2, 346.7),
        .tsimShaTsuiClockTower: (11.6, 11.6, 49.2),
        .culturalCentre: (144.3, 123.5, 56.3),
        .conventionCentre: (201.3, 349.0, 67.9),
        // FUKUOKA-LANDMARKS: the earlier version's model, its mast to the
        // real 234 m, turned as OpenStreetMap's outline.
        .fukuokaTower: (19.8, 21.4, 234.0),
    ]

    /// Every model decodes, near and far, as tall and wide as the surveyed
    /// building (half a metre either way), standing on its foot; the far
    /// model has at most half the near one's triangles and no colour it
    /// lacks; each stays within one model's budget.
    func testTheModels() {
        XCTAssertEqual(Set(Self.surveyed.keys), Set(Map3DHongKongLandmark.allCases))
        for landmark in Map3DHongKongLandmark.allCases {
            let near = landmark.model(full: true), far = landmark.model(full: false)
            let size = Self.surveyed[landmark]!
            for model in [near, far] {
                XCTAssertFalse(model.vertices.isEmpty, "\(landmark)")
                let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
                XCTAssertEqual(xs.max()! - xs.min()!, size.x, accuracy: 0.5, "\(landmark) east")
                XCTAssertEqual(ys.max()! - ys.min()!, size.y, accuracy: 0.5, "\(landmark) north")
                XCTAssertEqual(zs.max()!, size.z, accuracy: 0.5, "\(landmark) height")
                XCTAssertEqual(zs.min()!, 0, accuracy: 0.01, "\(landmark) foot")
                XCTAssertEqual(abs(xs.max()! + xs.min()!) / 2, 0, accuracy: 0.5, "\(landmark) centred east")
                XCTAssertEqual(abs(ys.max()! + ys.min()!) / 2, 0, accuracy: 0.5, "\(landmark) centred north")
            }
            XCTAssertLessThanOrEqual(near.indices.count / 3, 15_000, "\(landmark)")
            XCTAssertLessThanOrEqual(far.indices.count * 2, near.indices.count + 3, "\(landmark) far")
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), "\(landmark) far colours")
            XCTAssertTrue(Set(near.vertices.map(\.color)).isSubset(of: Set(Map3DHongKongLandmark.materialColours)), "\(landmark) colours")
        }
        let total = Map3DHongKongLandmark.allCases.reduce(0) { $0 + $1.model(full: true).indices.count / 3 }
        XCTAssertLessThanOrEqual(total, 60_000)
    }

    /// The encoding is read whole or not at all.
    func testABrokenMeshIsRefused() throws {
        let text = try XCTUnwrap(Map3DHongKongLandmark.encodedMeshes["two-ifc"])
        let bytes = try Array(XCTUnwrap(Data(base64Encoded: text)))
        XCTAssertNotNil(Map3DHongKongLandmark.decoded(bytes, full: true))
        XCTAssertNil(Map3DHongKongLandmark.decoded(Array(bytes.dropLast()), full: true))
        XCTAssertNil(Map3DHongKongLandmark.decoded(bytes + [0], full: true))
    }

    /// On Hong Kong's map the landmarks within the scene stand where they
    /// are, near and far; a footprint at a landmark's middle is not drawn
    /// again, one a street away is; a track over one keeps it off the map,
    /// a tunnel does not.
    func testOnHongKongsMap() throws {
        let world = GameWorld.newOverseasGame(try HongKongBaseMapTests.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let ifc = Map3DHongKongLandmark.twoIFC
        let place = frame.worldPosition(latitude: ifc.latitude, longitude: ifc.longitude)
        let metre = Double(WorldCoordinate.unitsPerMetre), reach = 1_500 * metre
        let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
        func builder() -> Map3DScene.Builder {
            Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: nil)
        }
        var central = builder()
        let built = central.addHongKongLandmarks(frame: frame)
        XCTAssertTrue(built.isSuperset(of: [.twoIFC, .bankOfChinaTower, .cheungKongCenter, .hsbcMainBuilding, .theCenter, .centralPlaza, .conventionCentre]), "\(built)")
        let triangles = { (meshes: [Map3DScene.ChunkKey: Map3DMesh]) in meshes.values.reduce(0) { $0 + $1.indices.count / 3 } }
        XCTAssertEqual(triangles(central.nearMeshes), built.reduce(0) { $0 + $1.model(full: true).indices.count / 3 })
        XCTAssertEqual(triangles(central.farMeshes), built.reduce(0) { $0 + $1.model(full: false).indices.count / 3 })
        let middle = central.point(x: place.x, y: place.y, height: 0)
        XCTAssertTrue(central.underLandmark(middle))
        XCTAssertFalse(central.underLandmark(middle + Map3DPoint(0, 0, 120)))
        // Its top as high as the surveyed tower's: on its foot 7.3 m up.
        let top = central.nearMeshes.values.flatMap(\.vertices).map(\.y).max() ?? 0
        XCTAssertEqual(top, 414.2 + 7.28, accuracy: 0.5)

        let line = stride(from: Float(-60), through: 60, by: 2).map { middle + Map3DPoint($0, 0, 0) }
        var blocked = builder()
        blocked.trackLines = [(line, .surface)]
        XCTAssertFalse(blocked.addHongKongLandmarks(frame: frame).contains(.twoIFC))
        var tunnel = builder()
        tunnel.trackLines = [(line, .tunnel)]
        XCTAssertTrue(tunnel.addHongKongLandmarks(frame: frame).contains(.twoIFC))
    }

    /// FUKUOKA-LANDMARKS: on Fukuoka's map, Fukuoka Tower stands at
    /// Momochihama, its mast as high as the real one's.
    func testFukuokaTowerOnFukuokasMap() throws {
        let world = GameWorld.newOverseasGame(try FukuokaRailwaysTests.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let tower = Map3DHongKongLandmark.fukuokaTower
        let place = frame.worldPosition(latitude: tower.latitude, longitude: tower.longitude)
        let metre = Double(WorldCoordinate.unitsPerMetre), reach = 800 * metre
        let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
        var builder = Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: nil)
        XCTAssertEqual(builder.addHongKongLandmarks(frame: frame), [.fukuokaTower])
        let top = builder.nearMeshes.values.flatMap(\.vertices).map(\.y).max() ?? 0
        XCTAssertEqual(top, 234, accuracy: 1)
        XCTAssertTrue(builder.underLandmark(builder.point(x: place.x, y: place.y, height: 0)))
    }
}
