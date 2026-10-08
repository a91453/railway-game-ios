import Foundation
import GameCore
import GamePresentation
import XCTest

/// What there is around a place on a real-world map (OpenStreetMap's
/// shops, offices, schools and sights on WorldPop's grid), and the kind of
/// place a new station there serves.
final class PlaceGridTests: XCTestCase {
    /// A grid of one 0.1° cell at the equator with `counts` places of each
    /// kind.
    private func grid(_ counts: [PlaceGrid.Kind: Int]) throws -> PlaceGrid {
        let layers = PlaceGrid.Kind.allCases.map { kind in
            let count = counts[kind] ?? 0
            return "\"\(kind.rawValue)\":" + (count > 0 ? "[{\"r\":0,\"c\":0,\"p\":[\(count)]}]" : "[]")
        }
        return try PlaceGrid(data: Data("{\"north\":0.1,\"west\":0,\"cellDegrees\":0.1,\"layers\":{\(layers.joined(separator: ","))}}".utf8))
    }

    func testAPlacesFileOutOfShapeIsRefused() {
        XCTAssertThrowsError(try PlaceGrid(data: Data("{}".utf8)))
        XCTAssertThrowsError(
            try PlaceGrid(data: Data(#"{"north":0.1,"west":0,"cellDegrees":0.1,"layers":{"shops":[],"offices":[],"schools":[]}}"#.utf8)),
            "no attractions"
        )
        XCTAssertThrowsError(
            try PlaceGrid(data: Data(#"{"north":0.1,"west":0,"cellDegrees":0.1,"layers":{"shops":[{"r":0,"c":0,"p":[-1]}],"offices":[],"schools":[],"attractions":[]}}"#.utf8))
        )
    }

    /// A cell's places count by the share of the circle in it.
    func testPlacesCountByTheCircleInTheirCell() throws {
        let places = try grid([.shops: 1_000_000, .attractions: 10])
        XCTAssertEqual(places.total(of: .shops), 1_000_000)
        XCTAssertEqual(places.total(of: .offices), 0)
        let nearby = places.places(within: 800, ofLatitude: 0.05, longitude: 0.05)
        // The circle is π·800² m² of the cell's 0.1°·0.1° (about 123 km²).
        let share = Double.pi * 800 * 800 / (0.1 * 110_574.0 * 0.1 * 111_320.0 * cos(0.05 * .pi / 180))
        XCTAssertEqual(try XCTUnwrap(nearby[.shops]), 1_000_000 * share, accuracy: 1)
        XCTAssertEqual(nearby[.offices], 0)
    }

    // MARK: - The kind of place

    /// The country of these tests: 1,000,000 people with 10,000 shops,
    /// 1,000 offices, 1,000 schools and 500 sights, so 10,000 residents
    /// "should" have 100 shops, 10 offices, 10 schools and 5 sights.
    private let totals: [PlaceGrid.Kind: Int] = [.shops: 10_000, .offices: 1_000, .schools: 1_000, .attractions: 500]

    private func kind(residents: Int, _ places: [PlaceGrid.Kind: Double]) -> StationDemandKind {
        .realWorld(residents: residents, places: places, totals: totals, population: 1_000_000)
    }

    func testAStationServesHomesUnlessOneKindStandsOut() {
        XCTAssertEqual(kind(residents: 10_000, [.shops: 100, .offices: 10, .schools: 10, .attractions: 5]), .residential, "the country's mix")
        XCTAssertEqual(kind(residents: 10_000, [.shops: 149]), .residential, "just under one and a half times the shops")
        XCTAssertEqual(kind(residents: 10_000, [.shops: 150]), .shopping, "one and a half times the shops")
        XCTAssertEqual(kind(residents: 10_000, [.offices: 30, .schools: 10]), .office)
        // Decision 91: schools are a kind of their own, no longer counted
        // with offices.
        XCTAssertEqual(kind(residents: 10_000, [.offices: 10, .schools: 20]), .civic)
        XCTAssertEqual(kind(residents: 10_000, [.attractions: 10]), .scenic)
        XCTAssertEqual(kind(residents: 0, [:]), .residential, "nothing there")
    }

    /// Few residents are measured against a minimum, so a village's
    /// handful of shops is not a shopping district, but its sights make
    /// it a scenic one.
    func testAVillageIsMeasuredAgainstMinimums() {
        XCTAssertEqual(kind(residents: 300, [.shops: 20]), .residential, "20 shops against at least 30")
        XCTAssertEqual(kind(residents: 300, [.shops: 60]), .shopping)
        XCTAssertEqual(kind(residents: 300, [.attractions: 1]), .residential, "1 sight against at least 1")
        XCTAssertEqual(kind(residents: 300, [.attractions: 2]), .scenic, "2 sights against at least 1")
        XCTAssertEqual(kind(residents: 300, [.offices: 7]), .residential, "7 offices against at least 5")
        XCTAssertEqual(kind(residents: 300, [.offices: 8]), .office, "8 against at least 5")
        XCTAssertEqual(kind(residents: 300, [.offices: 7, .schools: 4]), .residential, "4 schools against at least 3")
        XCTAssertEqual(kind(residents: 300, [.offices: 7, .schools: 5]), .civic, "5 against at least 3")
    }

    /// The kind most above its expectation wins; ties go to offices, then
    /// shops, then sights, then schools.
    func testTheKindMostAboveItsShareWins() {
        XCTAssertEqual(kind(residents: 10_000, [.shops: 300, .attractions: 20]), .scenic, "4 times the sights beats 3 times the shops")
        XCTAssertEqual(kind(residents: 10_000, [.shops: 300, .offices: 25]), .shopping, "3 times the shops beats 2.5 times the offices")
        XCTAssertEqual(kind(residents: 10_000, [.shops: 300, .schools: 30]), .shopping, "a tie of 3 goes to shops before schools")
        XCTAssertEqual(kind(residents: 10_000, [.attractions: 15, .schools: 30]), .scenic, "and to sights before schools")
        XCTAssertEqual(kind(residents: 10_000, [.shops: 300, .offices: 60]), .office, "a tie of 3 goes to offices")
    }

    // MARK: - Taiwan

    /// The bundled grids decide real stations as they are: Taipei Main
    /// and Taipei City Hall among offices (Taipei Main was shops while
    /// schools were counted with offices, before decision 91), Yong'an Market among
    /// homes, Houtong (the cat village) among sights.
    func testTaiwansStationsServeWhatIsAroundThem() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RailwayGameApp/Resources/RealWorld")
        let population = try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("taiwan_population.json")))
        let places = try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("taiwan_places.json")))
        // OpenStreetMap's places of Taiwan's 2026-10-06 extract, counted
        // once each (decision 93; 102,090, 8,614, 4,588 and 6,511 from
        // Overpass on 2026-10-05, Xiamen's by Kinmen with them).
        XCTAssertEqual(PlaceGrid.Kind.allCases.map { places.total(of: $0) }, [101_189, 8_485, 4_393, 6_300])
        let totals = Dictionary(uniqueKeysWithValues: PlaceGrid.Kind.allCases.map { ($0, places.total(of: $0)) })
        let stations: [(String, Double, Double, StationDemandKind)] = [
            ("Taipei Main", 25.047_931, 121.517_005, .office),
            ("Taipei City Hall", 25.041_135, 121.565_685, .office),
            ("Yong'an Market", 25.002_895, 121.511_225, .residential),
            ("Houtong", 25.087_019, 121.827_214, .scenic),
        ]
        for (name, latitude, longitude, expected) in stations {
            let residents = try XCTUnwrap(population.people(within: 800, ofLatitude: latitude, longitude: longitude))
            let kind = StationDemandKind.realWorld(
                residents: residents,
                places: places.places(within: 800, ofLatitude: latitude, longitude: longitude),
                totals: totals,
                population: population.total
            )
            XCTAssertEqual(kind, expected, name)
        }
    }

    func testTheKindComesWithTheResidentsRidership() {
        XCTAssertEqual(StationDemand.realWorld(residents: 44_604, kind: .office), StationDemand(kind: .office, dailyTrips: 17_800))
        XCTAssertEqual(StationDemand.realWorld(residents: 44_604), StationDemand(kind: .residential, dailyTrips: 17_800))
    }
}
