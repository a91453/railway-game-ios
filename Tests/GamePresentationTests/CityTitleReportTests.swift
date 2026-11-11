import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The titles the app's maps get (decision 683): Taiwan's places as a new
/// real-world game reads their land in, the blank map's towns, and the
/// whole of Taiwan, so the steps and the usual shares are set from what
/// the maps hold, not guessed.
final class CityTitleReportTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func grid<T>(_ name: String, _ make: (Data) throws -> T) throws -> T {
        try make(Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/\(name)")))
    }

    private static func title(of id: String, population: PopulationGrid, places: PlaceGrid) throws -> CityTitle {
        let place = try XCTUnwrap(RealWorldPlace.all.first { $0.id == id }, id)
        let frame = RealWorldFrame(anchor: place.anchor, bounds: GameWorld.newGameBounds)
        let cells = try XCTUnwrap(LandImport.cells(population: population, places: places, frame: frame, bounds: GameWorld.newGameBounds), id)
        return try XCTUnwrap(CityTitle(cells: cells), id)
    }

    /// The places people know: Taipei is no small town, Nangan no city.
    func testTaiwansPlacesReadAsPeopleKnowThem() throws {
        let population = try Self.grid("taiwan_population.json", PopulationGrid.init(data:))
        let places = try Self.grid("taiwan_places.json", PlaceGrid.init(data:))
        let expected: [(String, CityTitle.Rank, CityTitle.Kind)] = [
            ("tra-taipei", .metropolis, .commercial),
            ("tra-taichung", .largeCity, .commercial),
            ("tra-kaohsiung", .largeCity, .residential),
            ("tra-tainan", .city, .commercial),
            ("tra-hualien", .smallCity, .business),
            ("tra-taitung", .smallCity, .business),
        ]
        for (id, rank, kind) in expected {
            let title = try Self.title(of: id, population: population, places: places)
            XCTAssertEqual(title.rank, rank, id)
            XCTAssertEqual(title.kind, kind, id)
        }
    }

    /// Prints every place's title as Markdown; asserts only that the usual
    /// shares are the whole of Taiwan's. Runs on request:
    ///
    ///     CITY_TITLE_REPORT=1 swift test --skip-build --filter CityTitleReportTests
    func testReport() throws {
        guard ProcessInfo.processInfo.environment["CITY_TITLE_REPORT"] != nil else {
            throw XCTSkip("set CITY_TITLE_REPORT=1 to print the titles of the app's maps")
        }
        let population = try Self.grid("taiwan_population.json", PopulationGrid.init(data:))
        let places = try Self.grid("taiwan_places.json", PlaceGrid.init(data:))
        var lines = [
            "| Map | Residents | Jobs per 1,000 residents | Shops | Offices | Industry | Civic | Tourism | Farming | Title |",
            "| --- | --: | --: | --: | --: | --: | --: | --: | --: | --- |",
        ]
        func shares(_ cells: [LandCell]) -> (residents: Int64, total: Int64, permille: [Int64]) {
            var residents: Int64 = 0
            var jobs: [CityTitle.Kind: Int64] = [:]
            for cell in cells {
                residents += cell.residents
                jobs[CityTitle.Kind.sector(of: cell.use), default: 0] += cell.jobs
            }
            let total = jobs.values.reduce(0, +)
            return (residents, total, CityTitle.Kind.sectors.map { total > 0 ? (jobs[$0] ?? 0) * 1_000 / total : 0 })
        }
        func row(_ name: String, _ cells: [LandCell]) {
            let (residents, total, permille) = shares(cells)
            let title = CityTitle(cells: cells)
            let headline = title.map { "\($0.headline(in: .traditionalChinese)) (\($0.headline(in: .english)))" } ?? "—"
            let perThousand = residents > 0 ? "\(total * 1_000 / residents)" : "—"
            let parts = permille.map { "\($0 / 10).\($0 % 10)%" }.joined(separator: " | ")
            lines.append("| \(name) | \(residents.groupedText) | \(perThousand) | \(parts) | \(headline) |")
        }
        for place in RealWorldPlace.all where place.country == "TW" {
            let frame = RealWorldFrame(anchor: place.anchor, bounds: GameWorld.newGameBounds)
            guard let cells = LandImport.cells(population: population, places: places, frame: frame, bounds: GameWorld.newGameBounds) else { continue }
            row(place.name(in: .traditionalChinese), cells)
        }
        for seed: UInt32 in [1, 2, 3, 7] {
            row("Blank map, seed \(seed)", GameWorld.newGame(eventSeed: seed).land.cells)
        }
        let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
        let taiwan = try XCTUnwrap(LandImport.cells(population: population, places: places, frame: frame, bounds: WholeTaiwan.bounds))
        row("The whole of Taiwan, all read in", taiwan)
        print(lines.joined(separator: "\n"))
        XCTAssertEqual(shares(taiwan).permille, CityTitle.Kind.sectors.map { CityTitle.Kind.usualShare[$0] ?? 0 })
    }
}
