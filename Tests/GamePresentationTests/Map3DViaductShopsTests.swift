import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1035: the shops under the player's viaducts by an elevated
/// station: as many spans as its commerce, beyond its platforms' ends
/// within 300 m, one span left empty after every three, none where a road
/// passes under, none under a real line's scenery.
final class Map3DViaductShopsTests: XCTestCase {
    private let station = StationID(rawValue: 7)

    /// A Taiwan Railway pair 12 m up from 200 m west to 200 m east of
    /// Taipei Main Station, laid (``Map3DViaducts``) but not drawn, and an
    /// elevated platform of ``station`` from 200 m to 130 m west.
    private func viaduct(owned: Bool = true) throws -> Map3DScene.Builder {
        let latitude = 25.0478, longitude = 121.5170
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let origin = frame.worldPosition(latitude: latitude, longitude: longitude)
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y,
                                         region: WorldRegion(minX: origin.x - 2_000 * metre, minY: origin.y - 2_000 * metre,
                                                             maxX: origin.x + 2_000 * metre, maxY: origin.y + 2_000 * metre),
                                         world: world)
        let lon = Int(longitude * 1e6) - 2_000, lat = Int(latitude * 1e6)
        let json = #"{"systems":["tra_sched"],"ways":[{"system":0,"kind":"b","points":[\#(lon),\#(lat),120,4000,0,0]},"#
            + #"{"system":0,"kind":"b","points":[\#(lon),\#(lat - 36),120,4000,0,0]}]}"#
        builder.state.elevated.viaducts.owned = owned
        _ = builder.realTracks(try RealRailTracks(data: Data(json.utf8)), systems: ["tra_sched"], frame: frame,
                               clearOf: Map3DRealTrains.PlayerTrack([]))
        let start = builder.point(x: origin.x, y: origin.y, height: 0)
        let rail = builder.drawnGround(x: start.x, z: start.z) + 12
        builder.state.platforms.laidPlatforms = [
            Map3DScene.Builder.LaidPlatform(station: station, line: stride(from: Float(-200), through: -130, by: 10).map { Map3DPoint($0, rail, start.z) },
                                            offset: 4, width: 4, structure: .elevated),
        ]
        return builder
    }

    /// `builder`'s viaducts drawn, and the middles along the line (x) of
    /// the bays of shops it then draws near for `level`.
    private func bays(_ builder: Map3DScene.Builder, _ level: StationCommerceLevel?) throws -> [Float] {
        var builder = builder
        builder.addViaducts()
        let before = builder.nearMeshes.mapValues { $0.indices.count }
        builder.addViaductShops { _ in level }
        let each = try XCTUnwrap(Map3DViaductShops.bay.model).triangleCount + XCTUnwrap(Map3DViaductShops.infill.model).triangleCount
        var middles: [Float] = []
        for (key, mesh) in builder.nearMeshes {
            let first = before[key] ?? 0
            XCTAssertEqual((mesh.indices.count - first) / 3 % each, 0)
            for start in stride(from: first, to: mesh.indices.count, by: each * 3) {
                let xs = (start..<start + each * 3).map { mesh.vertices[Int(mesh.indices[$0])].position.x }
                middles.append((xs.min()! + xs.max()!) / 2)
            }
        }
        return middles.sorted()
    }

    func testTheModels() throws {
        let bay = try XCTUnwrap(Map3DViaductShops.bay.model), far = try XCTUnwrap(Map3DViaductShops.bayFar.model)
        let infill = try XCTUnwrap(Map3DViaductShops.infill.model)
        XCTAssertEqual(bay.triangleCount, 1_052)
        XCTAssertEqual(far.triangleCount, 196)
        XCTAssertEqual(infill.triangleCount, 12)
        for model in [bay, far] {
            XCTAssertEqual(model.maximum.x - model.minimum.x, Map3DViaductShops.length, accuracy: 0.3)
            XCTAssertEqual(model.maximum.y - model.minimum.y, Map3DViaductShops.width, accuracy: 0.3)
            XCTAssertEqual(model.maximum.z, Map3DViaductShops.height, accuracy: 0.05)
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.05)
        }
        XCTAssertEqual(infill.minimum.z, 5, accuracy: 0.05)
        XCTAssertEqual(infill.maximum.z, 6, accuracy: 0.05)
    }

    /// The spans of the pair's viaduct are kept once it is drawn, one
    /// under the pair, not one under each track.
    func testTheSpans() throws {
        var builder = try viaduct()
        builder.addViaducts()
        let spans = builder.state.elevated.shopSpans
        XCTAssertGreaterThan(spans.count, 8)
        for span in spans {
            XCTAssertEqual(span.clear, 32 - 1.6 - 0.3, accuracy: 0.5)
            XCTAssertGreaterThan(span.wide, 7.5)
            XCTAssertEqual(abs(span.forward.x), 1, accuracy: 0.01)
        }
        XCTAssertEqual(Set(spans.map { Int($0.middle.x.rounded()) }).count, spans.count, "one span under the pair")
        // A real line's scenery keeps none.
        var scenery = try viaduct(owned: false)
        scenery.addViaducts()
        XCTAssertTrue(scenery.state.elevated.shopSpans.isEmpty)
    }

    /// As many bays as the station's commerce, nearest the station first,
    /// beyond its platforms, three in a row then one span empty.
    func testAsManyAsTheCommerce() throws {
        for (level, count) in [(StationCommerceLevel?.none, 0), (.convenienceStore, 1), (.arcade, 3), (.mall, 6)] {
            let middles = try bays(try viaduct(), level)
            XCTAssertEqual(middles.count, count, "\(String(describing: level))")
            // Beyond the platforms' east end (−130 m), within 300 m.
            for x in middles {
                XCTAssertGreaterThan(x, -130 + 15)
                XCTAssertLessThan(x, -130 + 300)
            }
            guard count == 6 else { continue }
            let gaps = zip(middles, middles.dropFirst()).map { ($1 - $0 + 1) / 32 }.map { Int($0.rounded(.down)) }
            XCTAssertEqual(gaps, [1, 1, 2, 1, 1], "three, one empty, three")
        }
    }

    /// A road under a span: none there, and the row begins again after it.
    func testNotWhereARoadPassesUnder() throws {
        let first = try XCTUnwrap(try bays(try viaduct(), .mall).first)
        var road = try viaduct()
        road.state.baseMap.roadLines = [([Map3DPoint(first, 0, -60), Map3DPoint(first, 0, 60)], 4)]
        let middles = try bays(road, .mall)
        XCTAssertEqual(middles.count, 6)
        XCTAssertFalse(middles.contains { abs($0 - first) < 20 })
    }
}
