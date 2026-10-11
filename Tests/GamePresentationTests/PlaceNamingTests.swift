import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 159: a new station on a real-world map is named after the
/// place it is in when no real station is right there.
final class PlaceNamingTests: XCTestCase {
    private static let bundled: PlaceNames? = {
        let url = BundledRealData.directory
            .deletingLastPathComponent()
            .appendingPathComponent("RealWorld/taiwan_place_names.json")
        return (try? Data(contentsOf: url)).flatMap { try? PlaceNames(data: $0) }
    }()

    private func bundled() throws -> PlaceNames {
        try XCTUnwrap(Self.bundled, "The app's place names file reads")
    }

    /// Place names with only `places`: (latitude, longitude, Chinese,
    /// English) each.
    private func placeNames(_ places: [(Double, Double, String, String?)], wards: [(Double, Double, String, String?)] = []) throws -> PlaceNames {
        func rows(_ entries: [(Double, Double, String, String?)]) -> [[Any]] {
            entries.map { [Int(($0.0 * 100_000).rounded()), Int(($0.1 * 100_000).rounded()), $0.2, $0.3 as Any? ?? NSNull()] }
        }
        let file: [String: Any] = ["scale": 100_000, "places": rows(places), "wards": rows(wards), "townships": []]
        return try PlaceNames(data: JSONSerialization.data(withJSONObject: file))
    }

    private let jiufen = RealRailways.Coordinate(latitude: 25.11166, longitude: 121.84507)

    func testTheBundledNamesAreTaiwans() throws {
        let names = try bundled()
        XCTAssertGreaterThan(names.settlements.count, 15_000)
        XCTAssertGreaterThan(names.wards.count, 7_000)
        XCTAssertGreaterThan(names.townships.count, 360)
        // Taipei Main Station is in Zhongzheng District; Jiufen in Ruifang.
        let taipei = RealRailways.Coordinate(latitude: 25.0478, longitude: 121.5170)
        XCTAssertEqual(names.township(containing: taipei), PlaceNames.Name(chinese: "中正", english: "Zhongzheng"))
        XCTAssertEqual(names.township(containing: jiufen)?.chinese, "瑞芳")
        // Off the coast, and in Xiamen (the extract reaches it): none.
        XCTAssertNil(names.township(containing: RealRailways.Coordinate(latitude: 24.0, longitude: 122.5)))
        XCTAssertNil(names.township(containing: RealRailways.Coordinate(latitude: 24.48, longitude: 118.09)))
        XCTAssertEqual(names.nearby(jiufen).first?.name(in: .english), "Jiufen")
    }

    func testAStationAwayFromTheRealOnesIsNamedAfterItsPlace() throws {
        let railways = try BundledRealData.railways()
        let names = try bundled()
        var world = GameWorld.newGame(anchor: RealWorldDemo.anchor)
        let here = try BundledRealData.point(jiufen, in: world)
        XCTAssertNil(railways.nearestStation(to: jiufen, maximumDistanceMetres: GameSession.realStationNamingDistanceMetres))
        func suggestion(_ language: DisplayLanguage) -> String {
            GameSession.suggestedStationName(for: world, at: here, in: language, railways: railways, placeNames: names)
        }
        XCTAssertEqual(suggestion(.traditionalChinese), "九份")
        XCTAssertEqual(suggestion(.english), "Jiufen")
        XCTAssertEqual(
            GameSession.suggestedStationName(for: world, at: here, in: .traditionalChinese, railways: railways),
            "車站 1", "Without the place names, as before"
        )

        // Taken, in either language: the next place round it.
        _ = try world.buildStation(named: "Jiufen", at: here)
        let next = suggestion(.traditionalChinese)
        XCTAssertNotEqual(next, "九份")
        XCTAssertFalse(next.hasPrefix("車站"), next)
        XCTAssertTrue(railways.stations(named: next, near: nil).isEmpty, "\(next) is no real station's name")
    }

    func testARealStationRightThereStillNamesIt() throws {
        let railways = try BundledRealData.railways()
        let tra = try BundledRealData.station("猴硐", in: "tra_sched")
        let world = GameWorld.newGame(anchor: RealWorldDemo.anchor)
        let houtong = try BundledRealData.point(tra.coordinate, in: world)
        XCTAssertEqual(
            GameSession.suggestedStationName(for: world, at: houtong, in: .traditionalChinese, railways: railways, placeNames: try bundled()),
            "猴硐"
        )
    }

    func testAPlaceNamedLikeARealStationElsewhereIsNotOffered() throws {
        let railways = try BundledRealData.railways()
        let world = GameWorld.newGame(anchor: RealWorldDemo.anchor)
        let names = try placeNames([(jiufen.latitude, jiufen.longitude, "臺北", "Taipei")])
        let here = try BundledRealData.point(jiufen, in: world)
        XCTAssertEqual(GameSession.suggestedStationName(for: world, at: here, in: .traditionalChinese, railways: railways, placeNames: names), "車站 1")
    }

    func testASecondStationOfAPlaceIsNamedForItsSide() throws {
        let names = try placeNames([(jiufen.latitude, jiufen.longitude, "甲村", "Jiacun")])
        var world = GameWorld.newGame(anchor: RealWorldDemo.anchor)
        let first = try BundledRealData.point(jiufen, in: world)
        _ = try world.buildStation(named: "甲村", at: first)
        // The world's y runs south.
        let sides: [(PlanPoint, String, String)] = [
            (PlanPoint(x: first.x, y: first.y - 500), "北甲村", "North Jiacun"),
            (PlanPoint(x: first.x, y: first.y + 500), "南甲村", "South Jiacun"),
            (PlanPoint(x: first.x + 500, y: first.y + 100), "東甲村", "East Jiacun"),
            (PlanPoint(x: first.x - 500, y: first.y), "西甲村", "West Jiacun"),
        ]
        for (point, chinese, english) in sides {
            XCTAssertEqual(GameSession.suggestedStationName(for: world, at: point, in: .traditionalChinese, placeNames: names), chinese)
            XCTAssertEqual(GameSession.suggestedStationName(for: world, at: point, in: .english, placeNames: names), english)
        }
        let north = sides[0].0
        _ = try world.buildStation(named: "北甲村", at: north)
        XCTAssertEqual(
            GameSession.suggestedStationName(for: world, at: PlanPoint(x: north.x, y: north.y - 10), in: .traditionalChinese, placeNames: names),
            "車站 3", "Every name of it taken"
        )
    }

    func testAWardCountsAsTwiceAsFar() throws {
        let metre = 1 / 111_195.0
        let names = try placeNames(
            [(jiufen.latitude + 700 * metre, jiufen.longitude, "聚落", nil)],
            wards: [(jiufen.latitude + 300 * metre, jiufen.longitude, "近里", nil), (jiufen.latitude + 400 * metre, jiufen.longitude, "遠里", nil)]
        )
        XCTAssertEqual(names.nearby(jiufen).map(\.chinese), ["近里", "聚落", "遠里"])
        XCTAssertEqual(names.nearby(jiufen).first?.name(in: .english), "近里", "No English name: the Chinese one")
    }

    func testAMapWithoutRealGroundHasNumberedStations() throws {
        let world = GameWorld.newGame()
        XCTAssertEqual(
            GameSession.suggestedStationName(for: world, at: PlanPoint(x: 1_000, y: 1_000), in: .traditionalChinese, placeNames: try bundled()),
            "車站 1"
        )
    }

    @MainActor
    func testThePlaceNamesArrivingNameTheMiddleOfTheMap() throws {
        let world = GameWorld.newGame(anchor: RealWorldDemo.anchor)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        session.placeNames = try bundled()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let middle = PlanPoint(x: Int64(frame.middleX), y: Int64(frame.middleY))
        XCTAssertEqual(
            session.stationName,
            GameSession.suggestedStationName(for: world, at: middle, in: .traditionalChinese, railways: session.railways, placeNames: session.placeNames)
        )
        XCTAssertNotEqual(session.stationName, "車站 1")
    }
}
