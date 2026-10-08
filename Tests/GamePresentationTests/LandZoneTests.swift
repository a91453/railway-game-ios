import Foundation
import GameCore
import GamePresentation
import XCTest

/// OpenStreetMap's industrial land, parks and farmland on real-world maps
/// (ARCHITECTURE decision 93): the places file's zones and the land they
/// make.
final class LandZoneTests: XCTestCase {
    /// A places file of 0.01° cells north and east of the equator's and
    /// prime meridian's crossing, without places, with `zones` (runs per
    /// kind) on zone cells of half a cell (cuts 2) of 4 points each.
    private func places(_ zones: [PlaceGrid.Zone: String]) throws -> PlaceGrid {
        let layers = PlaceGrid.Zone.allCases.map { "\"\($0.rawValue)\":[\(zones[$0] ?? "")]" }.joined(separator: ",")
        return try PlaceGrid(data: Data("""
        {"north":0.02,"west":0,"cellDegrees":0.01,"layers":{"shops":[],"offices":[],"schools":[],"attractions":[]},
         "zones":{"cuts":2,"samples":4,"layers":{\(layers)}}}
        """.utf8))
    }

    /// WorldPop's people on the same grid: `runs`.
    private func population(_ runs: String) throws -> PopulationGrid {
        try PopulationGrid(data: Data(#"{"north":0.02,"west":0,"cellDegrees":0.01,"runs":[\#(runs)]}"#.utf8))
    }

    /// A world 4,096 m a side round the crossing of the grid's four middle
    /// cells (rows 0 and 1, columns 0 and 1, some 1.1 km a side), all four
    /// wholly inside.
    private let bounds = try! WorldBounds(width: 262_144, height: 262_144)
    private var frame: RealWorldFrame {
        RealWorldFrame(anchor: GeoAnchor(latitudeDegrees: 0.01, longitudeDegrees: 0.01)!, bounds: bounds)
    }

    /// The zone of a 64 m cell, from where its middle lies: the zone grid
    /// cell (row, column) it is in.
    private func zoneCell(of cell: LandCell) -> (row: Int, column: Int) {
        let place = frame.coordinate(worldX: Double(cell.middle.x), worldY: Double(cell.middle.y))
        return (Int(((0.02 - place.latitude) / 0.005).rounded(.down)), Int((place.longitude / 0.005).rounded(.down)))
    }

    func testAPlacesFileWithZonesOutOfShapeIsRefused() {
        let base = #""north":0.02,"west":0,"cellDegrees":0.01,"layers":{"shops":[],"offices":[],"schools":[],"attractions":[]}"#
        XCTAssertNoThrow(try PlaceGrid(data: Data("{\(base)}".utf8)), "no zones at all")
        XCTAssertThrowsError(try PlaceGrid(data: Data(#"{\#(base),"zones":{"cuts":2,"samples":4,"layers":{"industrial":[],"park":[]}}}"#.utf8)), "no farmland")
        XCTAssertThrowsError(try PlaceGrid(data: Data(#"{\#(base),"zones":{"cuts":0,"samples":4,"layers":{"industrial":[],"park":[],"farmland":[]}}}"#.utf8)))
        XCTAssertThrowsError(
            try PlaceGrid(data: Data(#"{\#(base),"zones":{"cuts":2,"samples":4,"layers":{"industrial":[{"r":0,"c":0,"p":[5]}],"park":[],"farmland":[]}}}"#.utf8)),
            "more points than a zone cell has"
        )
    }

    /// A zone cell is the kind of land at least half of it is, the most of
    /// it first, ties to industrial land, then parks, then farmland.
    func testAZoneCellIsTheLandAtLeastHalfOfItIs() throws {
        let places = try places([
            .industrial: #"{"r":0,"c":0,"p":[2,1,0,2]}"#,
            .park: #"{"r":0,"c":1,"p":[3]},{"r":0,"c":3,"p":[2]}"#,
            .farmland: #"{"r":0,"c":0,"p":[2,0,1]}"#,
        ])
        func zone(_ column: Int) -> PlaceGrid.Zone? {
            places.zone(atLatitude: 0.0175, longitude: 0.0025 + 0.005 * Double(column))
        }
        XCTAssertEqual(zone(0), .industrial, "a tie with farmland")
        XCTAssertEqual(zone(1), .park, "3 of 4")
        XCTAssertNil(zone(2), "a quarter is not enough")
        XCTAssertEqual(zone(3), .industrial, "a tie with a park")
        XCTAssertNil(zone(4))
        // Two points of industrial land a quarter of 0.005° square each.
        let pointArea = 0.005 * 110_574.0 * 0.005 * 111_320.0 * cos(0.0175 * .pi / 180) / 4 / 1_000_000
        XCTAssertEqual(places.area(of: .industrial), 5 * pointArea, accuracy: 1e-9)
        XCTAssertEqual(places.area(of: .park), 5 * pointArea, accuracy: 1e-9)
        XCTAssertEqual(try PlaceGrid(data: Data(#"{"north":0,"west":0,"cellDegrees":1,"layers":{"shops":[],"offices":[],"schools":[],"attractions":[]}}"#.utf8)).area(of: .park), 0)
    }

    /// The four middle WorldPop cells, each cut into four zone cells:
    ///
    /// - row 0, column 0: 1,000 people; its north-west zone cell a park,
    ///   its north-east one industrial land, the rest no zone;
    /// - row 0, column 1: 500 people, all farmland;
    /// - row 1, column 0: no one, all industrial land;
    /// - row 1, column 1: 300 people, all park.
    private func fourCells() throws -> (PopulationGrid, PlaceGrid) {
        let population = try population(#"{"r":0,"c":0,"p":[1000,500]},{"r":1,"c":0,"p":[0,300]}"#)
        let places = try places([
            .industrial: #"{"r":0,"c":1,"p":[4]},{"r":2,"c":0,"p":[4,4]},{"r":3,"c":0,"p":[4,4]}"#,
            .park: #"{"r":0,"c":0,"p":[4]},{"r":2,"c":2,"p":[4,4]},{"r":3,"c":2,"p":[4,4]}"#,
            .farmland: #"{"r":0,"c":2,"p":[4,4]},{"r":1,"c":2,"p":[4,4]}"#,
        ])
        return (population, places)
    }

    func testZonesMakeParksFactoriesAndFarms() throws {
        let (population, places) = try fourCells()
        let cells = try XCTUnwrap(LandImport.cells(population: population, places: places, frame: frame, bounds: bounds))
        XCTAssertEqual(GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 0.01, longitudeDegrees: 0.01)!, land: cells).land.cells, cells, "valid land")
        var byZoneCell: [String: [LandCell]] = [:]
        for cell in cells {
            let zone = zoneCell(of: cell)
            byZoneCell["\(zone.row),\(zone.column)", default: []].append(cell)
        }
        func residents(_ keys: [String]) -> Int64 {
            keys.flatMap { byZoneCell[$0] ?? [] }.reduce(0) { $0 + $1.residents }
        }

        // Row 0, column 0: the park has no one; the factories have jobs
        // and no one living there; the 1,000 people live in the rest.
        let park = try XCTUnwrap(byZoneCell["0,0"])
        XCTAssertTrue(park.allSatisfy { $0.use == .park && $0.residents == 0 && $0.jobs == 0 })
        let factories = try XCTUnwrap(byZoneCell["0,1"])
        XCTAssertTrue(factories.allSatisfy { $0.use == .industrial && $0.residents == 0 && $0.jobs == LandImport.industrialJobsPerCell })
        XCTAssertTrue(["1,0", "1,1"].flatMap { byZoneCell[$0] ?? [] }.allSatisfy { $0.use == .residential && $0.jobs == 0 })
        XCTAssertEqual(residents(["0,0", "0,1", "1,0", "1,1"]), 1_000, "everyone is kept")

        // Row 0, column 1: every cell a farm, the 500 people in the farms.
        let farms = ["0,2", "0,3", "1,2", "1,3"].flatMap { byZoneCell[$0] ?? [] }
        XCTAssertFalse(farms.isEmpty)
        XCTAssertTrue(farms.allSatisfy { $0.use == .agricultural && $0.jobs == LandImport.farmJobsPerCell })
        XCTAssertEqual(residents(["0,2", "0,3", "1,2", "1,3"]), 500)

        // Row 1, column 0: factories where no one lives.
        let empty = ["2,0", "2,1", "3,0", "3,1"].flatMap { byZoneCell[$0] ?? [] }
        XCTAssertFalse(empty.isEmpty)
        XCTAssertTrue(empty.allSatisfy { $0.use == .industrial && $0.residents == 0 && $0.jobs == LandImport.industrialJobsPerCell })

        // Row 1, column 1: all park, so its 300 people keep their homes
        // rather than be lost.
        let parkland = ["2,2", "2,3", "3,2", "3,3"].flatMap { byZoneCell[$0] ?? [] }
        XCTAssertTrue(parkland.allSatisfy { $0.use == .residential })
        XCTAssertEqual(residents(["2,2", "2,3", "3,2", "3,3"]), 300)

        // Without zones the same people live there, all in homes.
        let without = try XCTUnwrap(LandImport.cells(population: population, frame: frame, bounds: bounds))
        XCTAssertEqual(without.reduce(0) { $0 + $1.residents }, cells.reduce(0) { $0 + $1.residents })
        XCTAssertEqual(Set(without.map(\.use)), [.residential])
    }

    /// A world read in by blocks (decision 88) gets the very cells of
    /// those blocks the whole world would.
    func testBlocksGetTheWholeWorldsZones() throws {
        let (population, places) = try fourCells()
        let whole = try XCTUnwrap(LandImport.cells(population: population, places: places, frame: frame, bounds: bounds))
        let blocks: Set<LandBlock> = [LandBlock(row: 0, column: 0), LandBlock(row: 1, column: 1), LandBlock(row: 0, column: 1)]
        let some = LandImport.cells(in: blocks, population: population, places: places, frame: frame, bounds: bounds)
        XCTAssertFalse(some.isEmpty)
        XCTAssertEqual(some, whole.filter { blocks.contains(LandBlock(cellRow: $0.row, column: $0.column)) })
    }

    /// Factories or farms with no one are land of their own; parks alone
    /// are not, and a new game there founds towns as on a map with no one.
    func testFactoriesWithoutPeopleAreStillLand() throws {
        let nobody = try population("")
        let factories = try places([.industrial: #"{"r":2,"c":0,"p":[4]}"#])
        let cells = try XCTUnwrap(LandImport.cells(population: nobody, places: factories, frame: frame, bounds: bounds))
        XCTAssertFalse(cells.isEmpty)
        XCTAssertTrue(cells.allSatisfy { $0.use == .industrial })
        XCTAssertNil(LandImport.cells(population: nobody, places: try places([.park: #"{"r":2,"c":0,"p":[4]}"#]), frame: frame, bounds: bounds))
    }

    // MARK: - The bundled zones

    /// The app's zones: OpenStreetMap's industrial land, parks and farmland
    /// of Taiwan (an osmtoday.com extract of 2026-10-06), as
    /// `build_zone_grid.py` measured them with decision 96's tags (429.0,
    /// 134.7 and 2,244.7 with decision 93's three).
    func testTaiwansZones() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let places = try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json")))
        // Square kilometres: every point of every zone cell, before the
        // half-a-cell rule picks a cell's one zone.
        XCTAssertEqual(places.area(of: .industrial), 454.0, accuracy: 0.5)
        XCTAssertEqual(places.area(of: .park), 181.7, accuracy: 0.5)
        XCTAssertEqual(places.area(of: .farmland), 2_681.6, accuracy: 0.5)
        XCTAssertEqual(places.zone(atLatitude: 25.0300, longitude: 121.5357), .park, "Daan Forest Park")
        XCTAssertEqual(places.zone(atLatitude: 24.7800, longitude: 121.0050), .industrial, "Hsinchu Science Park")
        XCTAssertEqual(places.zone(atLatitude: 23.1050, longitude: 120.2750), .industrial, "Southern Taiwan Science Park")
        XCTAssertEqual(places.zone(atLatitude: 23.7000, longitude: 120.3500), .farmland, "Yunlin's fields")
        XCTAssertNil(places.zone(atLatitude: 25.0478, longitude: 121.5172), "Taipei Main Station")
    }
}
