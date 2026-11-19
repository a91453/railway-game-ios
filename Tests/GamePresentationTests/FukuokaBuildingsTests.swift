import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// FUKUOKA-GROUND (decision 854, later): Fukuoka's buildings
/// (`MapPacks/fukuoka/buildings.pmtiles`), by Rovaniemi's rule (decision
/// 799, `tools/overseas-map/overseas_buildings.py`): OpenStreetMap's
/// outlines and uses, its storeys or height where tagged (nine in ten of
/// Fukuoka's), a guess from the tagged ones elsewhere.
final class FukuokaBuildingsTests: XCTestCase {
    static func tiles() throws -> FootprintTiles {
        let file = try XCTUnwrap(XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka)).buildingsFile, "the pack's buildings")
        return try FootprintTiles(data: Data(contentsOf: HongKongBuildingsTests.taiwan, options: .alwaysMapped),
                                  cities: [Data(contentsOf: file, options: .alwaysMapped)])
    }

    /// The buildings with their middles within `reach` metres of a place
    /// on Fukuoka's map.
    static func buildings(latitude: Double, longitude: Double, reach: Double) throws -> [Map3DFootprints.Building] {
        let world = GameWorld.newOverseasGame(try FukuokaRailwaysTests.ground())
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let place = frame.worldPosition(latitude: latitude, longitude: longitude)
        let region = WorldRegion(minX: place.x - reach * metre, minY: place.y - reach * metre, maxX: place.x + reach * metre, maxY: place.y + reach * metre)
        return Map3DFootprints(tiles: try tiles(), frame: frame, region: region).buildings.filter { building in
            guard let ring = building.rings.first, !ring.isEmpty else { return false }
            let x = ring.reduce(0) { $0 + $1.x } / Double(ring.count), y = ring.reduce(0) { $0 + $1.y } / Double(ring.count)
            return abs(x - place.x) <= reach * metre && abs(y - place.y) <= reach * metre
        }
    }

    /// Tenjin is a city of tall buildings, many with their
    /// storeys from the map; the houses of Nishijin are low.
    func testTheCentreIsTallAndTheSuburbsLow() throws {
        let tenjin = try Self.buildings(latitude: 33.5913, longitude: 130.3990, reach: 400)
        XCTAssertGreaterThan(tenjin.count, 300)
        XCTAssertGreaterThan(tenjin.filter { $0.drawnStoreys >= 8 }.count, 50)
        XCTAssertGreaterThan(tenjin.filter { $0.storeysFrom == .tags }.count, 50)
        let nishijin = try Self.buildings(latitude: 33.5780, longitude: 130.3530, reach: 300)
        XCTAssertGreaterThan(nishijin.count, 200)
        let storeys = nishijin.map(\.drawnStoreys).sorted()
        XCTAssertLessThanOrEqual(storeys[storeys.count / 2], 3, "half of \(storeys.count)")
    }

    /// The pack lists the file and where it comes from.
    func testThePackListsItsBuildings() throws {
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: pack.file("pack", "json")) as? [String: Any])
        let files = try XCTUnwrap(manifest["files"] as? [String: Any])
        XCTAssertNotNil(files["buildings.pmtiles"])
        for language in DisplayLanguage.allCases {
            let section = try XCTUnwrap(DataSourceCredits.sections(in: language, overseas: [.fukuoka]).first { $0.id == "fukuokaRailways" })
            XCTAssertTrue(section.credits.contains { $0.id == "fukuokaBuildings" })
        }
    }
}
