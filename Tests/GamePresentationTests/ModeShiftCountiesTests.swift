import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 332: a real-world map's realistic rule stops at the share of
/// trips by scooter and car of the county or city it starts in (MOTC 2024
/// travel survey, table 4).
final class ModeShiftCountiesTests: XCTestCase {
    private static let bundled: PlaceNames? = {
        let url = BundledRealData.directory
            .deletingLastPathComponent()
            .appendingPathComponent("RealWorld/taiwan_place_names.json")
        return (try? Data(contentsOf: url)).flatMap { try? PlaceNames(data: $0) }
    }()

    private func names() throws -> PlaceNames {
        try XCTUnwrap(Self.bundled, "The app's place names file reads")
    }

    private func anchor(_ latitude: Double, _ longitude: Double) throws -> GeoAnchor {
        try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
    }

    func testTheTableHasEveryCountyOfTaiwan() {
        XCTAssertEqual(ModeShiftCounties.shares.count, 22)
        XCTAssertTrue(ModeShiftCounties.shares.values.allSatisfy { (0...1_000).contains($0) })
        XCTAssertEqual(ModeShiftCounties.shares["臺北市"], 370)
        XCTAssertEqual(ModeShiftCounties.shares["彰化縣"], 891)
    }

    /// Every township in the bundled file names one of the table's
    /// counties, and the main stations stand in theirs.
    func testTheTownshipsKnowTheirCounties() throws {
        let names = try names()
        for (latitude, longitude, county) in [
            (25.04780, 121.51700, "臺北市"), // Taipei
            (25.01390, 121.46410, "新北市"), // Banqiao
            (24.08160, 120.53850, "彰化縣"), // Changhua
            (22.63940, 120.30250, "高雄市"), // Kaohsiung
            (24.43740, 118.31930, "金門縣"), // Kinmen
        ] {
            XCTAssertEqual(names.county(containing: RealRailways.Coordinate(latitude: latitude, longitude: longitude)), county)
        }
        XCTAssertNil(names.county(containing: RealRailways.Coordinate(latitude: 24.0, longitude: 119.9)), "the strait")
    }

    func testANewGameTakesItsCountysShare() throws {
        let names = try names()
        XCTAssertEqual(ModeShiftCounties.cap(at: try anchor(25.04780, 121.51700), in: names), 370)
        XCTAssertEqual(ModeShiftCounties.cap(at: try anchor(24.08160, 120.53850), in: names), 891)
        // A blank map, abroad, or without the names: the national share.
        XCTAssertEqual(ModeShiftCounties.cap(at: nil, in: names), ModeShift.nationalShare)
        XCTAssertEqual(ModeShiftCounties.cap(at: try anchor(35.68120, 139.76710), in: names), ModeShift.nationalShare)
        XCTAssertEqual(ModeShiftCounties.cap(at: try anchor(25.04780, 121.51700), in: nil), ModeShift.nationalShare)

        var world = GameWorld.newGame()
        var options = NewGameOptions()
        options.rules = .realistic
        options.apply(to: &world, modeShiftCap: 370)
        XCTAssertEqual(world.modeShift, ModeShift(rule: .realistic, cap: 370))
        options.rules = .simple
        options.apply(to: &world, modeShiftCap: 370)
        XCTAssertEqual(world.modeShift, .simple)
    }
}
