import Foundation
import GameCore
import XCTest

/// Stage E2 (ARCHITECTURE decision 50): a real-world game's map is laid over
/// the Earth by the anchor of its middle. GameCore only keeps and saves it;
/// no rule reads it.
final class GeoAnchorTests: XCTestCase {
    private func makeWorld() throws -> GameWorld {
        var world = try GameWorld(bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 3_072))
        try world.buildTrackEdge(from: a, to: b)
        return world
    }

    /// Taipei Main Station, as `Railway/`'s TRA stations place it.
    private let taipei = GeoAnchor(latitude: 250_479_308, longitude: 1_215_170_046)

    func testTheRangeIsTheEarths() {
        XCTAssertNotNil(taipei)
        XCTAssertNotNil(GeoAnchor(latitude: 900_000_000, longitude: 0), "a pole")
        XCTAssertNotNil(GeoAnchor(latitude: -900_000_000, longitude: 0))
        XCTAssertNotNil(GeoAnchor(latitude: 0, longitude: -1_800_000_000), "180° west")
        XCTAssertNotNil(GeoAnchor(latitude: 0, longitude: 1_799_999_999))
        XCTAssertNil(GeoAnchor(latitude: 900_000_001, longitude: 0))
        XCTAssertNil(GeoAnchor(latitude: -900_000_001, longitude: 0))
        XCTAssertNil(GeoAnchor(latitude: 0, longitude: 1_800_000_000), "180° east is 180° west")
        XCTAssertNil(GeoAnchor(latitude: 0, longitude: -1_800_000_001))
        XCTAssertNil(GeoAnchor(latitude: .min, longitude: .max))
    }

    func testANewWorldIsABlankMap() throws {
        XCTAssertNil(try makeWorld().geoAnchor)
    }

    /// Setting the anchor changes nothing but the anchor: not the track,
    /// the money or the clock; and the simulation runs the same with it.
    func testTheAnchorChangesNothingElse() throws {
        let blank = try makeWorld()
        var real = blank
        real.setGeoAnchor(taipei)
        XCTAssertEqual(real.geoAnchor, taipei)
        XCTAssertNotEqual(real, blank)
        XCTAssertEqual(real.network, blank.network)
        XCTAssertEqual(real.economy, blank.economy)
        XCTAssertEqual(real.clock, blank.clock)

        var blankRun = blank, realRun = real
        try blankRun.advance(ticks: 30)
        try realRun.advance(ticks: 30)
        realRun.setGeoAnchor(nil)
        XCTAssertEqual(realRun, blankRun)
    }

    /// The world saves its anchor as `"geoAnchor": {"latitude", "longitude"}`
    /// and a blank map without the key, as every save before E2.
    func testTheAnchorIsSavedOnlyOnARealWorldMap() throws {
        let blank = try makeWorld()
        let blankObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(blank)) as? [String: Any])
        XCTAssertNil(blankObject["geoAnchor"])

        var real = blank
        real.setGeoAnchor(taipei)
        let data = try JSONEncoder().encode(real)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["geoAnchor"] as? [String: Int64], ["latitude": 250_479_308, "longitude": 1_215_170_046])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), real)
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: real))).world, real)
    }

    func testBadAnchorsAreRefused() throws {
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(try makeWorld())) as? [String: Any])
        func load(_ anchor: String) -> GameWorld? {
            object["geoAnchor"] = try? JSONSerialization.jsonObject(with: Data(anchor.utf8), options: .fragmentsAllowed)
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return try? JSONDecoder().decode(GameWorld.self, from: data)
        }
        XCTAssertEqual(load(#"{"latitude": -337_000_000, "longitude": 1_512_000_000}"#.replacingOccurrences(of: "_", with: ""))?.geoAnchor,
                       GeoAnchor(latitude: -337_000_000, longitude: 1_512_000_000))
        XCTAssertNil(load(#"{"latitude": 900000001, "longitude": 0}"#), "beyond a pole")
        XCTAssertNil(load(#"{"latitude": 0, "longitude": 1800000000}"#), "180° east is written as 180° west")
        XCTAssertNil(load(#"{"latitude": 0}"#), "no longitude")
        XCTAssertNil(load(#"{"latitude": 25.04, "longitude": 121.51}"#), "degrees, not ten-millionths")
        XCTAssertNil(load("null"), "an explicit null")
    }
}
