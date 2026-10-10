import Foundation
import GameCore
import GamePresentation
import XCTest

/// City building P0-B (ARCHITECTURE decision 98): the building tool's
/// zoning mode zones the cell tapped or the rectangle dragged, as one edit
/// Undo takes back, and the zoning layer draws the zones.
@MainActor
final class ZoningSessionTests: XCTestCase {
    /// A world 32 × 24 cells of 64 m.
    private func session(_ language: DisplayLanguage = .english) throws -> GameSession {
        GameSession(world: try makeWorld(width: 131_072, height: 98_304), language: language)
    }

    func testATapZonesOneCellAndADragARectangle() throws {
        let session = try session()
        session.selectTool(.building)
        session.buildingMode = .zone
        XCTAssertEqual(session.zoningZone, .residential, "homes to begin with")
        XCTAssertEqual(session.zonedCellsText, "0 cells zoned")

        // (5,000, 9,000) lies in row 2, column 1.
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 9_000), reach: 0))
        XCTAssertEqual(session.world.zones.zone(row: 2, column: 1), .residential)
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Zoned 1 cell: Homes."))

        // While the finger is down the map shows the rectangle and nothing
        // is zoned; from row 2, column 1 to row 4, column 3.
        session.zoningZone = .commercial
        session.dragZone(from: PlanPoint(x: 5_000, y: 9_000), to: PlanPoint(x: 13_000, y: 17_000))
        XCTAssertEqual(session.zoneDrag, CellRectangle(rows: 2...4, columns: 1...3))
        XCTAssertEqual(session.buildingOverlay?.zoneDrag, PlanRect(minX: 4_096, minY: 8_192, maxX: 16_384, maxY: 20_480))
        XCTAssertEqual(session.buildingOverlay?.zoneDragColor, CityMap.zoneColor(.commercial))
        XCTAssertEqual(session.world.zones.cells.count, 1)

        XCTAssertTrue(session.endZoneDrag(from: PlanPoint(x: 5_000, y: 9_000), to: PlanPoint(x: 13_000, y: 17_000)))
        XCTAssertNil(session.zoneDrag)
        XCTAssertEqual(session.world.zones.cells.count, 9)
        XCTAssertEqual(session.world.zones.zone(row: 2, column: 1), .commercial)
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Zoned 9 cells: Shops."))
        XCTAssertEqual(session.zonedCellsText, "9 cells zoned")

        // One drag is one edit.
        session.undo()
        XCTAssertEqual(session.world.zones.cells, [ZonedCell(row: 2, column: 1, zone: .residential)])

        // Clearing.
        session.zoningZone = nil
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 9_000), reach: 0))
        XCTAssertTrue(session.world.zones.isEmpty)
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Cleared the zone of 1 cell."))
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 9_000), reach: 0))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "No cell changed."))
    }

    func testADragIsClampedToTheWorldAndToTheLargestSide() throws {
        let session = try session()
        // Past the world's north-west corner and its south-east one.
        XCTAssertEqual(
            session.zoneRectangle(from: PlanPoint(x: -500, y: -500), to: PlanPoint(x: 999_999, y: 999_999)),
            CellRectangle(rows: 0...23, columns: 0...31)
        )
        let large = GameSession(world: try makeWorld(width: 1_048_576, height: 1_048_576), language: .english)
        // 256 cells a side: 128 at most, counted from where the drag began.
        XCTAssertEqual(
            large.zoneRectangle(from: PlanPoint(x: 1_000_000, y: 10), to: PlanPoint(x: 10, y: 10)),
            CellRectangle(rows: 0...0, columns: 117...244)
        )
        large.selectTool(.building)
        large.buildingMode = .zone
        XCTAssertTrue(large.endZoneDrag(from: PlanPoint(x: 1_000_000, y: 10), to: PlanPoint(x: 10, y: 10)))
        XCTAssertEqual(large.world.zones.cells.count, 128)
    }

    func testChangingModeOrToolDropsTheDrag() throws {
        let session = try session()
        session.selectTool(.building)
        session.buildingMode = .zone
        session.dragZone(from: PlanPoint(x: 0, y: 0), to: PlanPoint(x: 9_000, y: 0))
        XCTAssertNotNil(session.zoneDrag)
        session.buildingMode = .build
        XCTAssertNil(session.zoneDrag)
        XCTAssertNil(session.buildingOverlay?.zoneDrag)
        session.buildingMode = .zone
        session.dragZone(from: PlanPoint(x: 0, y: 0), to: PlanPoint(x: 9_000, y: 0))
        session.selectTool(.select)
        XCTAssertNil(session.zoneDrag)
        session.cancelZoneDrag()
        XCTAssertTrue(session.world.zones.isEmpty)
    }

    func testTheZoningToolReadsInChinese() throws {
        let session = try session(.traditionalChinese)
        session.selectTool(.building)
        session.buildingMode = .zone
        XCTAssertEqual(
            Zone.allCases.map { $0.title(in: .traditionalChinese) },
            ["住宅區", "商業區", "辦公區", "工業區", "公共設施", "觀光休閒", "不開發", "保留地"]
        )
        session.zoningZone = .noDevelopment
        XCTAssertTrue(session.endZoneDrag(from: PlanPoint(x: 0, y: 0), to: PlanPoint(x: 9_000, y: 0)))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "劃設不開發 3 格。"))
        XCTAssertEqual(session.zonedCellsText, "已劃分區 3 格")
        XCTAssertEqual(session.zoningHelpText, "城市不在這裡蓋新建物，已有的建物不再成長或升級。")
        XCTAssertEqual(PopTravelMode.zoning.title(in: .traditionalChinese), "土地分區")
        XCTAssertTrue(PopTravelMode.zoning.isCityLayer)
        XCTAssertEqual(GameError.invalidZoneArea.playerMessage(in: .traditionalChinese), "分區要在地圖內，一次最多 128 × 128 格。")
    }

    func testTheZoningLayerDrawsEachZoneInItsColour() throws {
        var world = try makeWorld(width: 131_072, height: 98_304)
        try world.setZone(.office, rows: 0...0, columns: 0...2)
        try world.setZone(.reserved, rows: 1...1, columns: 0...0)
        let map = CityMap(world: world)
        let everywhere = WorldRegion(minX: 0, minY: 0, maxX: 131_072, maxY: 98_304)
        let tiles = map.tiles(for: .zoning, in: everywhere)
        XCTAssertEqual(tiles.count, 4)
        XCTAssertEqual(tiles.map(\.color), [CityMap.zoneColor(.office), CityMap.zoneColor(.office), CityMap.zoneColor(.office), CityMap.zoneColor(.reserved)])
        // A block of 4 × 4 cells takes the zone most of its cells have.
        let blocks = map.tiles(for: .zoning, in: everywhere, blockSize: 4)
        XCTAssertEqual(blocks.map(\.color), [CityMap.zoneColor(.office)])
        // Zones are not drawn by the other city layers.
        XCTAssertTrue(map.tiles(for: .landUse, in: everywhere).isEmpty)
        // The tooltip names the zone.
        let info = try XCTUnwrap(world.cityCellInfo(atX: 100, y: 100))
        XCTAssertEqual(info.zone, .office)
        XCTAssertTrue(info.lines(in: .english).contains("Zoned: Offices"))
    }

    /// Decision 139: the zoning tool shows the city's demand, and says the
    /// valves hold homes, shops and work back; without them it shows
    /// neither.
    func testTheZoningToolShowsTheCitysDemand() throws {
        let land = [
            LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 0),
            LandCell(row: 5, column: 6, use: .commercial, residents: 0, jobs: 400),
            LandCell(row: 5, column: 7, use: .office, residents: 0, jobs: 600),
        ]
        var world = try makeWorld(width: 131_072, height: 98_304)
        try world.setLand(land)
        let off = GameSession(world: world, language: .english)
        off.selectTool(.building)
        off.buildingMode = .zone
        XCTAssertNil(off.cityDemandText)
        XCTAssertFalse(off.zoningHelpText.contains("wants"))

        // The mix kept: 500 shop jobs and 500 in work for each thousand
        // residents. Now 400 and 600: shops 10 × 100 / 500 = +200%, past
        // full; work −10 × 100 / 600 = −166.7%, past full the other way;
        // jobs a resident the same, so homes 0.
        world.setCityDemand(true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(world), as: UTF8.self)
            .replacingOccurrences(of: #""baseline":{"shopJobs":400000,"workJobs":600000}"#, with: #""baseline":{"shopJobs":500000,"workJobs":500000}"#)
        XCTAssertTrue(json.contains(#""shopJobs":500000"#), "the mix kept is replaced")
        let steered = try JSONDecoder().decode(GameWorld.self, from: Data(json.utf8))
        for (language, text, help) in [
            (DisplayLanguage.english, "City demand: homes 0% · shops +100% · work −100%", " They are built only while the city wants that use."),
            (.traditionalChinese, "城市需求：住宅 0% · 商業 +100% · 辦公與工業 −100%", "只有城市需要這種用途（需求不是負的）時才會蓋。"),
        ] {
            let session = GameSession(world: steered, language: language)
            session.selectTool(.building)
            session.buildingMode = .zone
            XCTAssertEqual(session.cityDemandText, text)
            XCTAssertTrue(session.zoningHelpText.hasSuffix(help), session.zoningHelpText)
            session.zoningZone = .civic
            XCTAssertFalse(session.zoningHelpText.hasSuffix(help), "schools are not held back")
        }
    }
}
