import Foundation
@testable import GameCore
import XCTest

/// Decision 488: ``GameWorld/buildingPlacement(_:at:look:)`` answers what
/// ``GameWorld/placeBuilding(_:at:look:)`` would do, the building it puts
/// up or what it throws, without changing the world, so the building
/// tool's preview can ask at every step of a drag.
final class BuildingPlacementTrialTests: XCTestCase {
    /// 32 × 24 cells of homes and offices round cells (5…8, 5…8), a track
    /// across them, a building of the company's, and the city's buildings
    /// and footprints on; buying out by area as `area`, with `balance`.
    private func world(area: Bool, balance: Money) throws -> GameWorld {
        var world = GameWorld(
            bounds: try WorldBounds(width: 131_072, height: 98_304),
            economy: GameEconomy(balance: balance, costs: testCosts), clock: GameClock(speed: .paused)
        )
        var cells: [LandCell] = []
        for row in 5...8 {
            for column in 5...8 {
                let office = (row + column) % 3 == 0
                cells.append(LandCell(row: row, column: column, use: office ? .commercial : .residential,
                                      residents: office ? 0 : Int64(40 + 7 * column), jobs: office ? Int64(120 + 9 * row) : 8))
            }
        }
        try world.setLand(cells)
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setCityFootprints(true)
        world.setAreaBuyOut(area)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 20_480, y: 30_000))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 40_960, y: 30_000))
        try world.buildTrackEdge(from: west, to: east)
        try world.placeBuilding(.house, at: PlanPoint(x: 34_000, y: 24_000))
        return world
    }

    func testItAnswersWhatPlacingWouldDoAndChangesNothing() throws {
        var answers = 0, refusals = Set<String>()
        for area in [false, true] {
            for balance: Money in [1_000_000_000, 500_000] {
                let world = try world(area: area, balance: balance)
                for kind: PlacedBuildingKind in [.house, .shop, .office, .wharf] {
                    for y in stride(from: Int64(18_000), through: 38_000, by: 1_250) {
                        for x in stride(from: Int64(18_000), through: 38_000, by: 1_250) {
                            let site = PlanPoint(x: x, y: y)
                            let trial = Result { () throws(GameError) in try world.buildingPlacement(kind, at: site) }
                            var placed = world
                            let real = Result { () throws(GameError) in try placed.placeBuilding(kind, at: site) }
                            XCTAssertEqual(trial, real, "\(kind) at \(site), area \(area), balance \(balance)")
                            if case .failure(let error) = real { refusals.insert("\(error)".prefix(while: { $0 != "(" }).description) }
                            answers += 1
                        }
                    }
                }
            }
        }
        // The sweep met the refusals it is about, and buildings that stand.
        XCTAssertTrue(["buildingOnTrack", "buildingOverlaps", "insufficientFunds"].allSatisfy(refusals.contains), "\(refusals)")
        XCTAssertGreaterThan(answers, 1_000)
    }

    func testALookItDoesNotHaveIsRefusedFirst() throws {
        let world = try world(area: false, balance: 1_000_000_000)
        XCTAssertThrowsGameError(try world.buildingPlacement(.shop, at: PlanPoint(x: 1, y: 1), look: 9), .invalidBuildingLook)
    }
}
