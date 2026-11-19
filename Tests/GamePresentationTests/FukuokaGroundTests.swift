import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// FUKUOKA-GROUND (decision 854, later): Fukuoka's map pack has its own
/// ground, the Geospatial Information Authority of Japan's bare-earth
/// heights, OpenStreetMap's sea, rivers and ponds, and WorldPop's people
/// (`tools/fukuoka-map/build_fukuoka_ground.py`).
@MainActor
final class FukuokaGroundTests: XCTestCase {
    private func ground() throws -> (heights: HeightGrid, water: WaterGrid) {
        let ground = try FukuokaRailwaysTests.ground()
        return (try XCTUnwrap(ground.heights), try XCTUnwrap(ground.water))
    }

    /// The highest of the ground within some 160 m of a place, every 27 m.
    private func top(_ heights: HeightGrid, _ latitude: Double, _ longitude: Double) -> Double {
        var best = -Double.infinity
        for row in -6...6 {
            for column in -6...6 {
                best = max(best, heights.height(latitude: latitude + Double(row) * 0.00025, longitude: longitude + Double(column) * 0.00025))
            }
        }
        return best
    }

    /// Atagoyama stands where it is (68 m; each cell is the mean of its
    /// 50 m, so its sharp top is lower), and the city's centre is low,
    /// bare ground, not the tops of its buildings.
    func testTheGroundIsTheBareEarth() throws {
        let (heights, water) = try ground()
        XCTAssertEqual(top(heights, 33.5856, 130.3347), 68, accuracy: 25, "Atagoyama")
        for (name, latitude, longitude) in [
            ("Hakata Station", 33.5897, 130.4207), ("Tenjin", 33.5913, 130.3990), ("Nakasu-Kawabata", 33.5944, 130.4065),
            ("Fukuoka Airport", 33.5859, 130.4500),
        ] {
            XCTAssertFalse(water.isWater(latitude: latitude, longitude: longitude), name)
            XCTAssertTrue((0...20).contains(heights.height(latitude: latitude, longitude: longitude)), name)
        }
    }

    /// Hakata Bay is sea at 0 m: the coast the extract cuts open is closed
    /// along its edge, the land on the right side of it.
    func testHakataBayIsSea() throws {
        let (heights, water) = try ground()
        XCTAssertTrue(water.isWater(latitude: 33.6400, longitude: 130.3600), "Hakata Bay")
        XCTAssertEqual(heights.height(latitude: 33.6400, longitude: 130.3600), 0, "the middle of Hakata Bay")
        XCTAssertTrue(water.hasLand(nearLatitude: 33.6400, longitude: 130.3600, within: 4_000), "the bay's shores")
        XCTAssertFalse(water.isWater(latitude: 33.5300, longitude: 130.4700), "the south-east corner, inland")
    }

    /// The people: some 1.7 million on the map, WorldPop's.
    func testThePeople() throws {
        let population = try XCTUnwrap(try FukuokaRailwaysTests.ground().population)
        XCTAssertTrue((1_400_000...2_000_000).contains(population.total), "\(population.total)")
    }

    /// The pack lists its ground and credits where it comes from.
    func testThePackListsItsGround() throws {
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka))
        let manifest = try JSONSerialization.jsonObject(with: pack.file("pack", "json")) as? [String: Any]
        let files = try XCTUnwrap(manifest?["files"] as? [String: Any])
        for name in ["population.json", "basemap.pmtiles", "heights.dat", "water.json", "terrain.pmtiles", "airfields.json", "no_build.json"] {
            XCTAssertNotNil(files[name], name)
        }
        let licences = try XCTUnwrap(manifest?["licences"] as? [String: String])
        XCTAssertTrue(licences.values.contains { $0.contains("国土地理院の標高タイルを加工して作成") })
        XCTAssertTrue(licences.values.contains { $0.contains("WorldPop") })
        for language in DisplayLanguage.allCases {
            let section = try XCTUnwrap(DataSourceCredits.sections(in: language, overseas: [.fukuoka]).first { $0.id == "fukuokaRailways" })
            XCTAssertEqual(section.credits.map(\.id), ["fukuokaSubway", "fukuokaMap", "fukuokaBuildings", "fukuokaTerrain", "fukuokaPopulation"])
        }
    }
}
