import Foundation
import GameCore
@testable import GamePresentation
import XCTest

final class NearestStationNamingTests: XCTestCase {
    private static func bundledFile(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
    }

    private static func makeRailways() throws -> RealRailways {
        try RealRailways(
            lines: bundledFile("track_lines.geojson"),
            stations: bundledFile("track_stations.geojson"),
            names: bundledFile("station_names.json")
        )
    }

    func testNearestStationCoordinateLookup() throws {
        let railways = try Self.makeRailways()

        // Point near Taipei Main Station (25.0478, 121.5170)
        let tpeCoord = RealRailways.Coordinate(latitude: 25.0478, longitude: 121.5170)
        let nearestTpe = try XCTUnwrap(railways.nearestStation(to: tpeCoord))
        let tpeName = nearestTpe.station.name(in: .traditionalChinese)
        XCTAssertTrue(tpeName.contains("台北") || tpeName.contains("臺北"))
        XCTAssertLessThan(nearestTpe.distanceMetres, 1_000)

        // Point near Houtong (25.087, 121.828)
        let houtongCoord = RealRailways.Coordinate(latitude: 25.087, longitude: 121.828)
        let nearestHoutong = try XCTUnwrap(railways.nearestStation(to: houtongCoord))
        XCTAssertEqual(nearestHoutong.station.name(in: .traditionalChinese), "猴硐")
        XCTAssertLessThan(nearestHoutong.distanceMetres, 500)

        // Point far out in the Pacific Ocean (30.0, 130.0) with a 5 km limit returns nil
        let oceanCoord = RealRailways.Coordinate(latitude: 30.0, longitude: 130.0)
        XCTAssertNil(railways.nearestStation(to: oceanCoord, maximumDistanceMetres: 5_000))
    }

    func testSuggestedStationNameOnRealWorldMap() throws {
        let railways = try Self.makeRailways()

        // Real-world map centered at Houtong / RealWorldDemo anchor
        let anchor = RealWorldDemo.anchor
        var world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))

        // Position corresponding to Houtong station coordinates
        let houtongCoord = RealRailways.Coordinate(latitude: 25.0872, longitude: 121.8282)
        let houtongPos = frame.worldPosition(latitude: houtongCoord.latitude, longitude: houtongCoord.longitude)
        let houtongPlan = PlanPoint(x: Int64(houtongPos.x), y: Int64(houtongPos.y))

        // Proposes "猴硐" in Chinese
        let nameZH = GameSession.suggestedStationName(for: world, at: houtongPlan, in: .traditionalChinese, railways: railways)
        XCTAssertEqual(nameZH, "猴硐")

        // Proposes "Houtong" in English
        let nameEN = GameSession.suggestedStationName(for: world, at: houtongPlan, in: .english, railways: railways)
        XCTAssertEqual(nameEN, "Houtong")

        // Once "猴硐" is built, a new station at the same location suggests the next nearest or falls back
        _ = try world.buildStation(named: "猴硐", at: houtongPlan)
        let nextNameZH = GameSession.suggestedStationName(for: world, at: houtongPlan, in: .traditionalChinese, railways: railways)
        XCTAssertNotEqual(nextNameZH, "猴硐", "Does not duplicate existing station name")
    }

    func testSuggestedStationNameOnBlankMapFallsBackToNumberedStation() throws {
        let railways = try Self.makeRailways()

        // Blank map (no anchor)
        let world = GameWorld.newGame()
        let plan = PlanPoint(x: 1000, y: 1000)

        let nameZH = GameSession.suggestedStationName(for: world, at: plan, in: .traditionalChinese, railways: railways)
        XCTAssertEqual(nameZH, "車站 1")

        let nameEN = GameSession.suggestedStationName(for: world, at: plan, in: .english, railways: railways)
        XCTAssertEqual(nameEN, "Station 1")
    }
}
