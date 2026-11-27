import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// STATION-ALIGN-APPLY (decision 1022, the station rules of 2026-11-27,
/// part (c) 4): where a station's real model stands (an exterior study,
/// decisions 625, 626, 665, 929), the base map's own building of it
/// (Overture's or the official footprints', `taiwan_buildings.pmtiles`)
/// is not drawn as well. Found by where it lies, under the study's
/// OpenStreetMap outlines (``Map3DScene/Builder/addStationExteriors(_:frame:)``'s
/// cells), never by a building's id, so a new month's Overture file
/// (decision 1026) is cleared the same way.
@MainActor
final class Map3DStationExteriorFootprintsTests: XCTestCase {
    static let tiles = Result {
        try FootprintTiles(data: Data(contentsOf: Map3DFrameCostReportTests.baseMap.appendingPathComponent("taiwan_buildings.pmtiles"),
                                      options: .alwaysMapped))
    }

    /// Whether the footprint `ring` (in the scene) and the outline overlap:
    /// a corner of either inside the other, or their middles.
    static func overlaps(_ ring: [Map3DPoint], _ outline: [Map3DPoint]) -> Bool {
        let middle = ring.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * (1 / Float(ring.count))
        return (ring + [middle]).contains { Map3DStationExterior.distance(from: $0, to: outline) == 0 }
            || outline.contains { Map3DStationExterior.distance(from: $0, to: ring) == 0 }
    }

    func testNoBaseMapBuildingUnderAStationsRealModel() throws {
        let tiles = try Self.tiles.get()
        let m = Double(WorldCoordinate.unitsPerMetre)
        var found: [Map3DExteriorStudy: Int] = [:]
        for study in Map3DExteriorStudy.allCases {
            let origin = study.origin
            let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: origin.latitude, longitudeDegrees: origin.longitude))
            let world = GameWorld.newGame(anchor: anchor)
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            let middle = frame.worldPosition(latitude: origin.latitude, longitude: origin.longitude)
            let region = WorldRegion(minX: middle.x - 400 * m, minY: middle.y - 400 * m, maxX: middle.x + 400 * m, maxY: middle.y + 400 * m)
            var builder = Map3DScene.Builder(originX: middle.x.rounded(), originY: middle.y.rounded(), region: region, world: world)
            let cells = builder.addStationExteriors(world.railwaySnapshot(), frame: frame)[study] ?? []
            let placed = try XCTUnwrap(builder.state.exteriors.stationExteriors.first { $0.station == study }, "\(study) stands")
            let under = Map3DFootprints(tiles: tiles, frame: frame, region: region).buildings.filter { building in
                guard let ring = building.rings.first, ring.count >= 3 else { return false }
                let scene = ring.map { builder.point(x: $0.x, y: $0.y, height: 0) }
                return placed.outlines.contains { Self.overlaps(scene, $0) }
            }
            found[study] = under.count
            builder.target = .near
            let standing = builder.addFootprints(Map3DFootprints(buildings: under), clearOf: cells, takenBy: [])
            XCTAssertTrue(standing.isEmpty, "\(study): \(under.count) base-map buildings under it, drawn in \(standing.count) cells")
        }
        print("STATION_FOOTPRINTS under each study: \(found.map { "\($0.key)=\($0.value)" }.sorted())")
        // Tainan's study stands on the 1936 station, which the base map
        // has too (before, on the bus station west of it).
        XCTAssertGreaterThan(found[.batch2(.tainan)] ?? 0, 0)
    }
}
