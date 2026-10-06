import Foundation
import GameCore
import GamePresentation
import XCTest

/// Stage E2 (ARCHITECTURE decision 50): a real-world game's map lies over
/// the Earth with its middle at the world's anchor; the places a game can
/// start at are the references' own.
final class RealWorldMapTests: XCTestCase {
    private let taipei = RealWorldPlace.standard.anchor

    // MARK: - Degrees

    func testDegreesRoundToTenMillionths() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.047_930_84, longitudeDegrees: 121.517_004_56))
        XCTAssertEqual(anchor, GeoAnchor(latitude: 250_479_308, longitude: 1_215_170_046))
        XCTAssertEqual(anchor.latitudeDegrees, 25.047_930_8, accuracy: 1e-12)
        XCTAssertEqual(anchor.longitudeDegrees, 121.517_004_6, accuracy: 1e-12)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: anchor.latitudeDegrees, longitudeDegrees: anchor.longitudeDegrees), anchor)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: -33.7, longitudeDegrees: -58.381_6), GeoAnchor(latitude: -337_000_000, longitude: -583_816_000))
    }

    /// A map panned round the Earth reports longitudes past ±180°.
    func testLongitudesComeBackRoundTheEarth() {
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: 190)?.longitude, -1_700_000_000)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: -190)?.longitude, 1_700_000_000)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: 180)?.longitude, -1_800_000_000, "180° east is 180° west")
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: -180)?.longitude, -1_800_000_000)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: 179.999_999_99)?.longitude, -1_800_000_000, "rounds to 180°")
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: 540)?.longitude, -1_800_000_000)
        XCTAssertEqual(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: 721.5)?.longitude, 15_000_000)
    }

    func testOnlyTheEarthsLatitudes() {
        XCTAssertNotNil(GeoAnchor(latitudeDegrees: 90, longitudeDegrees: 0))
        XCTAssertNotNil(GeoAnchor(latitudeDegrees: -90, longitudeDegrees: 0))
        XCTAssertNil(GeoAnchor(latitudeDegrees: 90.000_001, longitudeDegrees: 0))
        XCTAssertNil(GeoAnchor(latitudeDegrees: -91, longitudeDegrees: 0))
        XCTAssertNil(GeoAnchor(latitudeDegrees: .nan, longitudeDegrees: 0))
        XCTAssertNil(GeoAnchor(latitudeDegrees: 0, longitudeDegrees: .infinity))
    }

    // MARK: - The frame

    /// The middle of a new game's 16 km map is at the anchor; its edges are
    /// 8,192 m away, and a world metre is 64 units.
    func testTheMapsMiddleIsAtTheAnchor() throws {
        let world = GameWorld.newGame(anchor: taipei)
        XCTAssertEqual(world.bounds, .maximum, "16,384 m a side, as the map of 1024 tiles was (Stage F3d)")
        XCTAssertEqual(GameWorld.newGame().bounds, .maximum)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        XCTAssertEqual(frame.anchor, taipei)
        XCTAssertEqual(frame.middleX, 524_288)
        XCTAssertEqual(frame.middleY, 524_288)
        XCTAssertEqual(RealWorldFrame.halfExtent(of: world.bounds).east, 8_192)
        XCTAssertEqual(RealWorldFrame.halfExtent(of: world.bounds).south, 8_192)

        let middle = frame.metresFromAnchor(worldX: 524_288, worldY: 524_288)
        XCTAssertEqual(middle.east, 0)
        XCTAssertEqual(middle.south, 0)
        let corner = frame.metresFromAnchor(worldX: 0, worldY: 0)
        XCTAssertEqual(corner.east, -8_192)
        XCTAssertEqual(corner.south, -8_192)
        let point = frame.metresFromAnchor(worldX: 524_288 + 640, worldY: 524_288 - 32)
        XCTAssertEqual(point.east, 10)
        XCTAssertEqual(point.south, -0.5)
        let back = frame.worldPosition(east: 10, south: -0.5)
        XCTAssertEqual(back.x, 524_928)
        XCTAssertEqual(back.y, 524_256)
    }

    /// An old save's 32 × 24 map has its middle at the anchor too.
    func testAnySizeOfMapHasItsMiddleThere() throws {
        let frame = RealWorldFrame(anchor: taipei, bounds: try WorldBounds(width: 32_768, height: 24_576))
        XCTAssertEqual(frame.middleX, 16_384)
        XCTAssertEqual(frame.middleY, 12_288)
        XCTAssertEqual(RealWorldFrame.halfExtent(of: try WorldBounds(width: 32_768, height: 24_576)).east, 256)
        // Bounds need not be whole tiles (Stage F3d).
        let odd = RealWorldFrame(anchor: taipei, bounds: try WorldBounds(width: 1_000, height: 333))
        XCTAssertEqual(odd.middleX, 500)
        XCTAssertEqual(odd.middleY, 166.5)
        XCTAssertEqual(RealWorldFrame.halfExtent(of: try WorldBounds(width: 1_000, height: 333)).south, 2.6015625)
    }

    func testABlankMapHasNoFrame() {
        XCTAssertNil(RealWorldFrame(world: .newGame()))
        XCTAssertNil(RealWorldFrame(world: DemoWorld.make(in: .english)))
    }

    // MARK: - New games

    /// A real-world new game is a new game on a map laid over the Earth:
    /// the same money, prices, city and empty map.
    func testARealWorldNewGameIsANewGameOverTheEarth() {
        let real = GameWorld.newGame(anchor: taipei)
        XCTAssertEqual(real.geoAnchor, taipei)
        var blank = real
        blank.setGeoAnchor(nil)
        XCTAssertEqual(blank, .newGame())
        XCTAssertNil(GameWorld.newGame().geoAnchor)
    }

    func testTheLauncherStartsARealWorldGameAndKeepsItsAnchor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RealWorldMapTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        let paris = try XCTUnwrap(RealWorldPlace.all.first { $0.id == "paris" }).anchor
        try await MainActor.run {
            let launcher = GameLauncher(library: library, language: .english)
            launcher.startNewGame(at: paris)
            let seed = try XCTUnwrap(launcher.session?.world.demandEvents?.seed)
            XCTAssertEqual(launcher.session?.world, .newGame(anchor: paris, eventSeed: seed))
            launcher.returnToStart()
            let autosave = try XCTUnwrap(launcher.autosave)
            XCTAssertEqual(autosave.summary?.realWorld, true)
            XCTAssertEqual(autosave.summary?.text(in: .english), "Real-world map · Day 1 · 00:00 · $ 3,000,000 · 0 stations · 0 lines · 0 trains")
            XCTAssertEqual(autosave.summary?.text(in: .traditionalChinese), "實景地圖 · 第 1 日 · 00:00 · $ 3,000,000 · 0 座車站 · 0 條路線 · 0 列列車")
            launcher.continueGame()
            XCTAssertEqual(launcher.session?.world.geoAnchor, paris)

            launcher.startNewGame()
            XCTAssertNil(launcher.session?.world.geoAnchor, "a blank map")
            launcher.returnToStart()
            XCTAssertNil(launcher.autosave?.summary?.realWorld)
        }
    }

    /// A save list written before E2 has no `"realWorld"`, and reads as a
    /// blank map's.
    func testSummariesFromBeforeE2ReadAsBlankMaps() throws {
        let json = #"{"seconds": 60, "balance": 100, "stations": 1, "lines": 0, "trains": 0}"#
        let summary = try JSONDecoder().decode(SaveSummary.self, from: Data(json.utf8))
        XCTAssertNil(summary.realWorld)
        XCTAssertFalse(summary.text(in: .english).contains("Real-world"))
        let blank = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SaveSummary(world: .newGame()))) as? [String: Any])
        XCTAssertNil(blank["realWorld"], "written only on a real-world map")
    }

    // MARK: - Places

    /// The references' places: the eleven Taiwan Railway stations of
    /// `Railway/` and the 53 cities of `Ci/`, grouped by region.
    func testThePlacesAreTheReferences() {
        let places = RealWorldPlace.all
        XCTAssertEqual(places.count, 64)
        XCTAssertEqual(Set(places.map(\.id)).count, 64)
        XCTAssertEqual(Set(places.map(\.anchor)).count, 64)
        XCTAssertEqual(places.filter { $0.id.hasPrefix("tra-") }.count, 11)
        XCTAssertEqual(places.map(\.region), places.map(\.region).sorted { a, b in
            RealWorldPlace.Region.allCases.firstIndex(of: a)! < RealWorldPlace.Region.allCases.firstIndex(of: b)!
        }, "grouped in the regions' order")
        XCTAssertEqual(places.first?.region, .taiwan)
        XCTAssertEqual(RealWorldPlace.standard.id, "tra-taipei")
        XCTAssertEqual(RealWorldPlace.standard.name(in: .english), "Taipei")
        XCTAssertEqual(RealWorldPlace.standard.name(in: .traditionalChinese), "臺北")
        // `Ci/`'s Shanghai: center [31.2304, 121.4737].
        XCTAssertEqual(places.first { $0.id == "shanghai" }?.anchor, GeoAnchor(latitude: 312_304_000, longitude: 1_214_737_000))
        XCTAssertEqual(places.first { $0.id == "london" }?.anchor, GeoAnchor(latitude: 515_074_000, longitude: -1_278_000))
        for place in places {
            XCTAssertNotEqual(place.name(in: .english), place.name(in: .traditionalChinese), place.id)
            // Apple's maps (Web Mercator) show up to about 85°.
            XCTAssertLessThan(abs(place.anchor.latitudeDegrees), 85, place.id)
        }
        for region in RealWorldPlace.Region.allCases {
            XCTAssertTrue(places.contains { $0.region == region }, "\(region)")
            XCTAssertNotEqual(region.name(in: .english), region.name(in: .traditionalChinese))
        }
    }
}
