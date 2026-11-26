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

    /// The people, WorldPop's: some 9.1 million on the map of Fukuoka,
    /// Saga and Kumamoto Prefectures and the corners of their neighbours
    /// (decision 991), some 1.7 million of them on the map as it was
    /// first, Fukuoka's 17.6 by 22.2 km.
    func testThePeople() throws {
        let population = try XCTUnwrap(try FukuokaRailwaysTests.ground().population)
        XCTAssertTrue((8_500_000...9_800_000).contains(population.total), "\(population.total)")
        let fukuoka = population.cells(north: 33.72, south: 33.52, west: 130.29, east: 130.48)
            .filter { (33.52...33.72).contains($0.centerLatitude) && (130.29...130.48).contains($0.centerLongitude) }
            .reduce(0) { $0 + $1.count }
        XCTAssertTrue((1_400_000...2_000_000).contains(fukuoka), "\(fukuoka)")
    }

    /// KUMAMOTO-GROUND: the ground reaches Kumamoto. Kinpozan (665 m)
    /// stands west of the city, the city's centre and the Chikugo plain
    /// are low and dry, the Ariake Sea is sea, and Aso Kumamoto Airport
    /// is on its plateau (some 190 m).
    func testTheGroundReachesKumamoto() throws {
        let (heights, water) = try ground()
        XCTAssertEqual(top(heights, 32.8140, 130.6388), 665, accuracy: 25, "Kinpozan")
        for (name, latitude, longitude, range) in [
            ("Kumamoto Station", 32.7900, 130.6890, 0.0...30.0), ("Kumamoto Castle's town", 32.8030, 130.7080, 0...40),
            ("Kurume Station", 33.3203, 130.5014, 0...30), ("Shin-Tosu Station", 33.3706, 130.4905, 0...40),
            ("Aso Kumamoto Airport", 32.8373, 130.8551, 150...230),
        ] {
            XCTAssertFalse(water.isWater(latitude: latitude, longitude: longitude), name)
            XCTAssertTrue(range.contains(heights.height(latitude: latitude, longitude: longitude)), "\(name): \(heights.height(latitude: latitude, longitude: longitude))")
        }
        XCTAssertTrue(water.isWater(latitude: 32.9000, longitude: 130.3500), "the Ariake Sea")
        XCTAssertEqual(heights.height(latitude: 32.9000, longitude: 130.3500), 0, "the Ariake Sea")
    }

    /// The ground across the edges the map had (33.52°N and 130.48°E) has
    /// no step: the heights either side of each, 60 m apart, differ by
    /// what a slope does, nowhere by a wall.
    func testTheOldEdgesHaveNoStep() throws {
        let (heights, water) = try ground()
        var worst = 0.0
        for index in 0..<400 {
            let longitude = 130.29 + (130.48 - 130.29) * (Double(index) + 0.5) / 400
            let latitude = 33.52 + (33.72 - 33.52) * (Double(index) + 0.5) / 400
            for (a, b) in [((33.5203, longitude), (33.5197, longitude)), ((latitude, 130.4797), (latitude, 130.4803))] {
                guard !water.isWater(latitude: a.0, longitude: a.1), !water.isWater(latitude: b.0, longitude: b.1) else { continue }
                worst = max(worst, abs(heights.height(latitude: a.0, longitude: a.1) - heights.height(latitude: b.0, longitude: b.1)))
            }
        }
        // 60 m apart on Aburayama's and Sangun's slopes: at most 1 in 1.
        XCTAssertLessThan(worst, 60, "the steepest 60 m across an old edge")
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
            XCTAssertEqual(section.credits.map(\.id), ["fukuokaSubway", "kyushuShinkansen", "fukuokaMap", "fukuokaBuildings", "fukuokaTerrain", "fukuokaPopulation", "fukuokaAirport", "kyushuAirports"])
        }
    }
}
