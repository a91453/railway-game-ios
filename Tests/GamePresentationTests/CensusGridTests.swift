import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 1000 (JAPAN-CENSUS-GRID): a map pack's population grid with the
/// jobs of its cells, from a census of workplaces, gives a real-world map
/// its jobs, and places counted on another grid are not read by row and
/// column.
final class CensusGridTests: XCTestCase {
    /// 7.5″ cells from 33.6° N, 130.4° E: the form of Japan's census grid.
    private static let corner = #""north":33.6,"west":130.4,"cellDegrees":0.0020833333333333333"#

    private static func grid(_ jobs: String?) throws -> PopulationGrid {
        let people = #""runs":[{"r":3,"c":4,"p":[0]},{"r":4,"c":4,"p":[120,300]}]"#
        let file = "{\(corner),\(people)\(jobs.map { ",\"jobs\":\($0)" } ?? "")}"
        return try PopulationGrid(data: Data(file.utf8))
    }

    private static let jobs = #"{"office":[{"r":4,"c":4,"p":[600]}],"shop":[{"r":3,"c":4,"p":[50]}],"civic":[],"leisure":[]}"#

    /// A 2 km world round the middle of the cell (4, 4).
    private static func world() throws -> (RealWorldFrame, WorldBounds) {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 33.6 - 4.5 / 480, longitudeDegrees: 130.4 + 4.5 / 480))
        let bounds = try WorldBounds(width: 131_072, height: 131_072)
        return (RealWorldFrame(anchor: anchor, bounds: bounds), bounds)
    }

    func testAGridReadsItsJobsByKind() throws {
        let grid = try Self.grid(Self.jobs)
        XCTAssertTrue(grid.hasJobs)
        XCTAssertEqual(grid.total, 420)
        XCTAssertEqual(grid.totalJobs, 650)
        XCTAssertFalse(try Self.grid(nil).hasJobs)
        XCTAssertEqual(try Self.grid(nil).totalJobs, 0)
        XCTAssertThrowsError(try Self.grid(#"{"factory":[]}"#), "a kind of job it does not know")
        XCTAssertThrowsError(try Self.grid(#"{"office":[{"r":0,"c":0,"p":[-1]}]}"#), "a negative count")
    }

    func testTheJobsBecomeTheLandsJobsAndItsUse() throws {
        let (frame, bounds) = try Self.world()
        let cells = try XCTUnwrap(LandImport.cells(population: Self.grid(Self.jobs), frame: frame, bounds: bounds))
        XCTAssertEqual(cells.reduce(0) { $0 + $1.residents }, 420, "everyone inside is kept")
        XCTAssertEqual(cells.reduce(0) { $0 + $1.jobs }, 650)
        let uses = Dictionary(grouping: cells, by: \.use).mapValues { cells in cells.reduce(0) { $0 + $1.residents + $1.jobs } }
        // The cell of 120 people and 600 office jobs is offices; the one of
        // 300 people homes; the one of 50 shop jobs and no one shops.
        XCTAssertEqual(uses[.office], 720)
        XCTAssertEqual(uses[.residential], 300)
        XCTAssertEqual(uses[.commercial], 50)
        // Without its jobs it is all homes.
        let homes = try XCTUnwrap(LandImport.cells(population: Self.grid(nil), frame: frame, bounds: bounds))
        XCTAssertTrue(homes.allSatisfy { $0.use == .residential && $0.jobs == 0 })
        XCTAssertEqual(homes.reduce(0) { $0 + $1.residents }, 420)
    }

    /// Places counted on a grid of another corner (Taiwan's, on a map
    /// abroad) give no jobs; on the people's own grid they do, as before.
    func testPlacesCountOnlyOnThePeoplesOwnGrid() throws {
        let (frame, bounds) = try Self.world()
        func places(_ corner: String) throws -> PlaceGrid {
            let layers = #""layers":{"shops":[{"r":4,"c":4,"p":[2]}],"offices":[{"r":4,"c":4,"p":[1]}],"schools":[],"attractions":[]}"#
            return try PlaceGrid(data: Data("{\(corner),\(layers)}".utf8))
        }
        let taiwan = try places(#""north":26.391666897100002,"west":116.70833214650004,"cellDegrees":0.0083333333"#)
        let abroad = try XCTUnwrap(LandImport.cells(population: Self.grid(nil), places: taiwan, frame: frame, bounds: bounds))
        XCTAssertEqual(abroad.reduce(0) { $0 + $1.jobs }, 0)
        let own = try XCTUnwrap(LandImport.cells(population: Self.grid(nil), places: places(Self.corner), frame: frame, bounds: bounds))
        XCTAssertEqual(own.reduce(0) { $0 + $1.jobs }, 2 * LandImport.jobsPerPlace[.shops]! + LandImport.jobsPerPlace[.offices]!)
        // A grid with its own jobs reads them, not the places.
        let both = try XCTUnwrap(LandImport.cells(population: Self.grid(Self.jobs), places: places(Self.corner), frame: frame, bounds: bounds))
        XCTAssertEqual(both.reduce(0) { $0 + $1.jobs }, 650)
    }
}
