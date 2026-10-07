import Foundation
@testable import GameCore
import XCTest

/// Land (Phase 6a, ARCHITECTURE decision 72): 64 m cells with their use,
/// residents and jobs; the towns a blank map starts with, drawn from a
/// seed; a station's catchment; the save form.
final class LandTests: XCTestCase {
    private func world(bounds: WorldBounds = .maximum) -> GameWorld {
        GameWorld(bounds: bounds, economy: GameEconomy(balance: 100_000_000, costs: testCosts))
    }

    // MARK: - Towns

    /// The towns, worked out again cell by cell rather than town by town:
    /// for each cell of the world, the town whose disc holds it (an
    /// independent reading of ``Land/towns(seed:in:)``'s rule; it also
    /// checks that no cell is in two towns).
    private static func referenceTowns(seed: UInt32, in bounds: WorldBounds) -> [LandCell] {
        func hash(_ key: String) -> UInt32 {
            var value: UInt32 = 2_166_136_261
            for byte in "\(seed)|\(key)".utf8 {
                value = (value ^ UInt32(byte)) &* 16_777_619
            }
            return value
        }
        func roll(_ key: String, _ low: Int64, _ high: Int64) -> Int64 {
            low + Int64(hash(key)) % (high - low + 1)
        }
        func cellOf(_ value: Int64) -> Int64 {
            // Rounded down, also west or north of the world.
            Int64((Double(value) / 4_096).rounded(.down))
        }
        let quarter = roll("town.quarter", 0, 3)
        // (middle row, middle column, radius, peak) of each town.
        var towns: [(row: Int64, column: Int64, radius: Int64, peak: Int64)] = [
            (cellOf(bounds.height / 2), cellOf(bounds.width / 2), 12, 260)
        ]
        let signs: [Int64: (east: Int64, south: Int64)] = [0: (1, -1), 1: (1, 1), 2: (-1, 1), 3: (-1, -1)]
        for number in 1...2 {
            let side = number == 1 ? quarter : (quarter + 2) % 4
            let sign = signs[side]!
            let x = bounds.width / 2 + sign.east * roll("town.\(number).east", 2_000, 5_000) * 64
            let y = bounds.height / 2 + sign.south * roll("town.\(number).south", 2_000, 5_000) * 64
            towns.append((cellOf(y), cellOf(x), roll("town.\(number).radius", 7, 10), roll("town.\(number).peak", 160, 240)))
        }
        var cells: [LandCell] = []
        let rows = (bounds.height + 4_095) / 4_096, columns = (bounds.width + 4_095) / 4_096
        for row in 0..<rows {
            for column in 0..<columns {
                var found: [LandCell] = []
                for (number, town) in towns.enumerated() {
                    let dr = row - town.row, dc = column - town.column
                    let squared = town.radius * town.radius, distance = dr * dr + dc * dc
                    guard distance < squared else { continue }
                    let full = town.peak * ((squared - distance) * 1_000 / squared) / 1_000
                    let isCore = 9 * distance < squared
                    let here = (residents: isCore ? full / 4 : full, jobs: isCore ? 3 * full : 0)
                    guard here.residents + here.jobs > 0 else { continue }
                    let use: LandUse = !isCore ? .residential : roll("town.\(number).cell.\(dr).\(dc)", 0, 1) == 0 ? .office : .commercial
                    found.append(LandCell(row: Int(row), column: Int(column), use: use, residents: here.residents, jobs: here.jobs))
                }
                cells += found
            }
        }
        return cells
    }

    func testTheTownsFollowTheRuleWorkedOutCellByCell() throws {
        let small = try WorldBounds(width: 135_000, height: 70_001)
        // In a world 300 m a side only part of the first town fits, and the
        // outer two lie outside it.
        let tiny = try WorldBounds(width: 19_200, height: 19_200)
        for bounds in [WorldBounds.maximum, small, tiny] {
            for seed: UInt32 in [0, 1, 7, 2_026, .max] {
                let land = Land.towns(seed: seed, in: bounds)
                XCTAssertEqual(land.cells, Self.referenceTowns(seed: seed, in: bounds), "seed \(seed), \(bounds)")
                XCTAssertNil(land.problem(in: bounds), "each cell once, in order and in range")
            }
        }
    }

    /// A seed always makes the same towns, and the numbers a new game's
    /// map gets from seed 1 are pinned.
    func testASeedMakesTheSameTownsAndOtherSeedsMoveThem() throws {
        let one = Land.towns(seed: 1, in: .maximum)
        XCTAssertEqual(one, Land.towns(seed: 1, in: .maximum))
        XCTAssertNotEqual(one, Land.towns(seed: 2, in: .maximum))
        XCTAssertEqual(one.cells.count, 887)
        XCTAssertEqual(one.totals, LandTotals(residents: 90_900, jobs: 67_413))
        XCTAssertEqual(Set(one.cells.map(\.use)), Set(LandUse.allCases))
        // The first town stands in the middle whatever the seed: its middle
        // cell is shops or offices with 65 residents (260 / 4) and 780 jobs.
        for seed: UInt32 in [1, 2, 99] {
            let middle = Land.towns(seed: seed, in: .maximum).cell(at: PlanPoint(x: 524_288, y: 524_288))
            XCTAssertEqual(middle?.residents, 65)
            XCTAssertEqual(middle?.jobs, 780)
            XCTAssertNotEqual(middle?.use, .residential)
        }
        // A home 11 cells east of the middle: 260 × (144 − 121) / 144.
        let home = one.cell(row: 128, column: 139)
        XCTAssertEqual(home, LandCell(row: 128, column: 139, use: .residential, residents: 41, jobs: 0))
        XCTAssertNil(one.cell(row: 128, column: 140), "12 cells is the radius, outside")
    }

    func testFoundingTownsReplacesTheLand() throws {
        var world = world()
        try world.setLand([LandCell(row: 0, column: 0, use: .residential, residents: 5, jobs: 0)])
        world.foundTowns(seed: 1)
        XCTAssertEqual(world.land, Land.towns(seed: 1, in: .maximum))
        XCTAssertNil(world.land.cell(row: 0, column: 0))
    }

    // MARK: - Setting land

    func testSetLandSortsTheCellsAndAnEmptyListClearsIt() throws {
        var world = world(bounds: try WorldBounds(width: 10_000, height: 10_000))
        let a = LandCell(row: 1, column: 0, use: .office, residents: 0, jobs: 40)
        let b = LandCell(row: 0, column: 2, use: .residential, residents: 12, jobs: 0)
        let c = LandCell(row: 0, column: 1, use: .commercial, residents: 3, jobs: 9)
        try world.setLand([a, b, c])
        XCTAssertEqual(world.land.cells, [c, b, a])
        XCTAssertEqual(world.land.totals, LandTotals(residents: 15, jobs: 49))
        XCTAssertEqual(world.land.cell(at: PlanPoint(x: 4_096, y: 4_095)), c)
        XCTAssertEqual(world.land.cell(at: PlanPoint(x: 100, y: 4_096)), a)
        XCTAssertNil(world.land.cell(at: PlanPoint(x: 0, y: 0)))
        XCTAssertNil(world.land.cell(at: PlanPoint(x: -1, y: 4_096)))
        try world.setLand([])
        XCTAssertTrue(world.land.isEmpty)
    }

    func testBadLandIsRejectedAndChangesNothing() throws {
        // 10,000 units: three cells a side, the last only partly in the world.
        var world = world(bounds: try WorldBounds(width: 10_000, height: 10_000))
        let good = LandCell(row: 2, column: 2, use: .residential, residents: 1, jobs: 0)
        try world.setLand([good])
        let before = world
        let bad: [[LandCell]] = [
            [LandCell(row: 3, column: 0, use: .residential, residents: 1, jobs: 0)],
            [LandCell(row: 0, column: 3, use: .residential, residents: 1, jobs: 0)],
            [LandCell(row: -1, column: 0, use: .residential, residents: 1, jobs: 0)],
            [LandCell(row: 0, column: -1, use: .residential, residents: 1, jobs: 0)],
            [LandCell(row: 0, column: 0, use: .residential, residents: 0, jobs: 0)],
            [LandCell(row: 0, column: 0, use: .residential, residents: -1, jobs: 5)],
            [LandCell(row: 0, column: 0, use: .office, residents: 0, jobs: Land.maximumPerCell + 1)],
            [good, LandCell(row: 2, column: 2, use: .office, residents: 0, jobs: 1)],
        ]
        for cells in bad {
            XCTAssertThrowsError(try world.setLand(cells)) { XCTAssertEqual($0 as? GameError, .invalidLand) }
            XCTAssertEqual(world, before)
        }
        XCTAssertNoThrow(try world.setLand([LandCell(row: 0, column: 0, use: .office, residents: Land.maximumPerCell, jobs: Land.maximumPerCell)]))
    }

    // MARK: - Catchment

    func testTotalsWithinARadiusMatchEveryCellCounted() throws {
        let land = Land.towns(seed: 7, in: .maximum)
        let points = [
            PlanPoint(x: 524_288, y: 524_288), PlanPoint(x: 520_000, y: 530_123), PlanPoint(x: 0, y: 0),
            PlanPoint(x: -60_000, y: 524_288), PlanPoint(x: 1_048_575, y: 1_048_575),
        ] + land.cells.prefix(40).map(\.middle) + land.cells.suffix(40).map(\.middle)
        for point in points {
            for radius: Int64 in [1, 2_048, 2_049, 30_000, Land.catchmentRadius, 400_000] {
                var expected = LandTotals()
                for cell in land.cells {
                    let dx = cell.middle.x - point.x, dy = cell.middle.y - point.y
                    if dx * dx + dy * dy < radius * radius {
                        expected.residents += cell.residents
                        expected.jobs += cell.jobs
                    }
                }
                XCTAssertEqual(land.totals(within: radius, of: point), expected, "\(point), \(radius)")
            }
        }
        XCTAssertEqual(land.totals(within: 0, of: points[0]), LandTotals())
        XCTAssertEqual(Land().totals(within: 51_200, of: points[0]), LandTotals())
    }

    func testAStationsCatchmentIsItsLandWithin800Metres() throws {
        var world = world()
        world.foundTowns(seed: 1)
        let middle = try world.buildStation(named: "Middle", at: PlanPoint(x: 524_288, y: 524_288)).id
        let far = try world.buildStation(named: "Far", at: PlanPoint(x: 10_000, y: 10_000)).id
        XCTAssertEqual(world.landCatchment(of: middle), world.land.totals(within: 51_200, of: PlanPoint(x: 524_288, y: 524_288)))
        // The whole first town, 437 cells: 768 m reaches no farther than
        // the 800 m.
        XCTAssertEqual(world.landCatchment(of: middle), LandTotals(residents: 50_189, jobs: 33_276))
        XCTAssertEqual(world.landCatchment(of: far), LandTotals())
        XCTAssertNil(world.landCatchment(of: StationID(rawValue: 99)))
    }

    // MARK: - Saving

    func testLandSavesAsRunsAndReadsBackTheSame() throws {
        var world = world(bounds: try WorldBounds(width: 40_000, height: 40_000))
        try world.setLand([
            LandCell(row: 0, column: 1, use: .residential, residents: 4, jobs: 0),
            LandCell(row: 0, column: 2, use: .residential, residents: 5, jobs: 0),
            LandCell(row: 0, column: 3, use: .office, residents: 1, jobs: 30),
            LandCell(row: 0, column: 4, use: .office, residents: 0, jobs: 31),
            LandCell(row: 0, column: 5, use: .office, residents: 2, jobs: 0),
            LandCell(row: 0, column: 7, use: .office, residents: 2, jobs: 0),
            LandCell(row: 1, column: 0, use: .commercial, residents: 0, jobs: 6),
        ])
        let data = try JSONEncoder().encode(world.land)
        let runs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(runs.count, 4)
        XCTAssertEqual(runs[0]["residents"] as? [Int], [4, 5])
        XCTAssertNil(runs[0]["jobs"], "jobs left out when all are 0")
        XCTAssertEqual(runs[1]["column"] as? Int, 3)
        XCTAssertEqual(runs[1]["residents"] as? [Int], [1, 0, 2])
        XCTAssertEqual(runs[1]["jobs"] as? [Int], [30, 31, 0])
        XCTAssertEqual(runs[2]["column"] as? Int, 7, "a gap starts a new run")
        XCTAssertEqual(runs[3]["row"] as? Int, 1)
        XCTAssertEqual(try JSONDecoder().decode(Land.self, from: data), world.land)
        let saved = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: saved), world)

        // A world without land writes no "land".
        try world.setLand([])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertNil(object["land"])
    }

    func testBadSavedLandIsRefused() throws {
        func decodeLand(_ json: String) throws -> Land {
            try JSONDecoder().decode(Land.self, from: Data(json.utf8))
        }
        XCTAssertNoThrow(try decodeLand(#"[{"row":0,"column":0,"use":"office","residents":[1],"jobs":[2]}]"#))
        let bad = [
            #"[{"row":0,"column":0,"use":"office","residents":[]}]"#,
            #"[{"row":0,"column":0,"use":"office","residents":[1],"jobs":[1,2]}]"#,
            #"[{"row":0,"column":0,"use":"farm","residents":[1]}]"#,
            #"[{"row":0,"column":0,"use":"office","residents":[0]}]"#,
            #"[{"row":0,"column":-1,"use":"office","residents":[1]}]"#,
            #"[{"row":-1,"column":0,"use":"office","residents":[1]}]"#,
            #"[{"row":0,"column":0,"use":"office","residents":[100001]}]"#,
            #"[{"row":0,"column":1,"use":"office","residents":[1]},{"row":0,"column":0,"use":"office","residents":[1]}]"#,
            #"[{"row":0,"column":0,"use":"office","residents":[1,1]},{"row":0,"column":1,"use":"office","residents":[1]}]"#,
            #"null"#,
        ]
        for json in bad {
            XCTAssertThrowsError(try decodeLand(json), json)
        }
        // The world refuses land outside its bounds.
        var world = world(bounds: try WorldBounds(width: 4_096, height: 4_096))
        try world.setLand([LandCell(row: 0, column: 0, use: .residential, residents: 1, jobs: 0)])
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        let outside = text.replacingOccurrences(of: #""column":0"#, with: #""column":1"#)
        XCTAssertNotEqual(outside, text)
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(outside.utf8)))
    }
}
