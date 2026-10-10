import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Real coverage (ARCHITECTURE decision 147): the app's coverage file, in
/// the heights file's form under `TWCV`, gives each cell of land read from
/// the real-world grids how much of it real buildings cover.
@MainActor
final class CoverageGridTests: XCTestCase {
    private static let grid: CoverageGrid = {
        do {
            return try CoverageGrid(data: RealWorldDataLoadTests.file("taiwan_coverage", "dat"))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    /// The cells of a new game's map round `anchor` within `cells` of its
    /// middle, all homes.
    private func cells(round anchor: GeoAnchor, within cells: Int) -> (frame: RealWorldFrame, cells: [LandCell]) {
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        let middle = Land.rows(in: GameWorld.newGameBounds) / 2
        let land = (middle - cells..<middle + cells).flatMap { row in
            (middle - cells..<middle + cells).map { LandCell(row: row, column: $0, use: .residential, residents: 1, jobs: 0) }
        }
        return (frame, land)
    }

    /// Round Taipei Main Station about a third of the ground is built
    /// (the survey's 36 %); every cell's coverage is known.
    func testTaipeisCellsAreAboutAThirdBuilt() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5172))
        let (frame, land) = cells(round: anchor, within: 8)
        let covered = Self.grid.covering(land, frame: frame)
        XCTAssertEqual(covered.map(\.position), land.map(\.position), "in their order")
        let values = covered.compactMap(\.coverage)
        XCTAssertEqual(values.count, land.count)
        XCTAssertTrue(values.allSatisfy { (0...100).contains($0) })
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        XCTAssertEqual(mean, 35, accuracy: 15)
        XCTAssertEqual(covered.map(\.residents), land.map(\.residents))
    }

    /// Kinmen's coverage is not known: Overture misses most of its towns.
    /// The open sea is none.
    func testKinmenIsUnknownAndTheSeaIsEmpty() throws {
        let kinmen = try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.4335, longitudeDegrees: 118.3171))
        let (frame, land) = cells(round: kinmen, within: 2)
        XCTAssertTrue(Self.grid.covering(land, frame: frame).allSatisfy { $0.coverage == nil })
        let strait = try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.0, longitudeDegrees: 119.9))
        let (seaFrame, sea) = cells(round: strait, within: 2)
        XCTAssertTrue(Self.grid.covering(sea, frame: seaFrame).allSatisfy { $0.coverage == 0 })
    }

    func testAHeightsFileIsNotACoverageFile() throws {
        XCTAssertThrowsError(try CoverageGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat")))
    }

    /// A real-world new game's land has the coverage; a launcher without
    /// the file reads none.
    func testANewGamesLandHasItsCoverage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoverageGridTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        await launcher.loadRealWorldData { RealWorldData.load(file: RealWorldDataLoadTests.file) }.value
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5172))
        let land = try XCTUnwrap(launcher.land(at: anchor))
        XCTAssertTrue(land.allSatisfy { $0.coverage != nil })
        launcher.coverage = nil
        XCTAssertTrue(try XCTUnwrap(launcher.land(at: anchor)).allSatisfy { $0.coverage == nil })
    }
}
