import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Real land prices (decision 1025): the app's land price file, in the
/// heights file's form under `TWLP`, says how dear each place's land is
/// against the country, and a Taiwan map's land takes it as it is read.
@MainActor
final class LandPriceGridTests: XCTestCase {
    private static let grid: LandPriceGrid = {
        do {
            return try LandPriceGrid(data: RealWorldDataLoadTests.file("taiwan_land_price", "dat"))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    /// 32 × 24 cells: 8 × 6 squares.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)

    /// The mean factor of a small world's squares with its middle at
    /// `latitude`, `longitude`.
    private func factor(_ latitude: Double, _ longitude: Double) throws -> Int64 {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
        let found = Self.grid.locations(frame: RealWorldFrame(anchor: anchor, bounds: Self.small), bounds: Self.small)
        XCTAssertEqual(found.count, 48, "every square of land has one")
        XCTAssertTrue(found.allSatisfy { (LandLocations.lowest...LandLocations.highest).contains($0.factor) })
        return found.map(\.factor).reduce(0, +) / Int64(found.count)
    }

    /// Taipei's middle is dearer than Taichung's, which is dearer than a
    /// mountain village; each square of land is known.
    func testTaipeiIsDearerThanTaichungAndTheHills() throws {
        let taipei = try factor(25.0478, 121.5172)
        let taichung = try factor(24.1372, 120.6869)
        let alishan = try factor(23.5100, 120.8055)
        XCTAssertGreaterThan(taipei, 1_500, "Taipei Main Station")
        XCTAssertGreaterThan(taipei, taichung)
        XCTAssertGreaterThan(taichung, alishan)
        XCTAssertLessThan(alishan, 500, "Alishan")
    }

    /// The open sea has no factor.
    func testTheSeaHasNone() throws {
        let strait = try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.0, longitudeDegrees: 119.9))
        XCTAssertTrue(Self.grid.locations(frame: RealWorldFrame(anchor: strait, bounds: Self.small), bounds: Self.small).isEmpty)
    }

    /// A block's squares are its 16 cells' four a side, by row and then
    /// column, as the whole world's are.
    func testABlocksSquaresAreThoseOfTheWholeWorld() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5172))
        let frame = RealWorldFrame(anchor: anchor, bounds: Self.small)
        let whole = Self.grid.locations(frame: frame, bounds: Self.small)
        let block = Self.grid.locations(in: [LandBlock(row: 0, column: 1)], frame: frame, bounds: Self.small)
        XCTAssertEqual(block, whole.filter { (0..<4).contains($0.row) && (4..<8).contains($0.column) })
        XCTAssertEqual(block.count, 16)
    }

    func testAHeightsFileIsNotALandPriceFile() throws {
        XCTAssertThrowsError(try LandPriceGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat")))
    }

    /// A Taiwan map bought tile by tile gives the land it reads its
    /// places' factors; without the file, none.
    func testTheLandAMapReadsKnowsWhereItLies() throws {
        let session = try ThsrSaleTests.game(at: 25.0478, 121.5172)
        XCTAssertNotNil(session.coverage?.landPrice)
        var world = session.world
        GameSession.readLand(roundStationsOf: &world, population: session.population, places: session.places, water: session.water, coverage: session.coverage)
        XCTAssertFalse(world.land.cells.isEmpty)
        XCTAssertFalse(world.landLocations.isEmpty)
        let cell = try XCTUnwrap(world.land.cells.first { world.landLocations.factor(row: $0.row, column: $0.column) != nil })
        let factor = try XCTUnwrap(world.landLocations.factor(row: cell.row, column: cell.column))
        XCTAssertGreaterThan(factor, 1_000, "Taipei is dearer than the country")
        var bare = session.world
        var plain = session.coverage
        plain?.landPrice = nil
        GameSession.readLand(roundStationsOf: &bare, population: session.population, places: session.places, water: session.water, coverage: plain)
        XCTAssertFalse(bare.land.cells.isEmpty)
        XCTAssertTrue(bare.landLocations.isEmpty)
    }
}
