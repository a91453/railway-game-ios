import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// What dragging a building over the flat map costs the main actor (95.1:
/// a shop dragged over the real map, the game paused, dropped to 11–50 fps
/// with stalls of up to 1.4 s). Each step of the finger moves the
/// ``GameSession/buildingSite``, and the map, the build card and the
/// confirm button each read the preview again. On the real map round
/// Miaoli with four lines of eleven stations. Run on request, in release:
///
///     BUILDING_DRAG_REPORT=1 swift test -c release -Xswiftc -enable-testing \
///       --filter BuildingDragCostReportTests
@MainActor
final class BuildingDragCostReportTests: XCTestCase {
    func testWhatAStepOfTheDragCosts() throws {
        guard ProcessInfo.processInfo.environment["BUILDING_DRAG_REPORT"] != nil else {
            throw XCTSkip("set BUILDING_DRAG_REPORT=1 to time a building dragged over a 44-station map")
        }
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        var world = try MapFrameCostReportTests.miaoli(lines: 4, data: data)
        world.setEconomyMode(.management)
        let session = GameSession(world: world)
        session.selectTool(.building)
        session.buildingKind = .shop
        let station = try XCTUnwrap(session.world.stations.first).point
        let start = PlanPoint(x: station.x, y: station.y + 3_000)
        session.tapBuildingTool(at: start, reach: 0)
        let clock = ContinuousClock()
        let steps = 20
        let reads = 5
        let spent = clock.measure {
            for step in 1...steps {
                session.dragBuildingSite(from: start, to: PlanPoint(x: start.x + Int64(step) * 64, y: start.y))
                // What the views read at each step (the map's overlay, the
                // card, its text, the confirm button and its price).
                _ = session.buildingOverlay
                _ = session.buildingPreview
                _ = session.buildingPreviewText
                _ = session.buildingPreview?.problem
                _ = session.buildingPreview?.cost
            }
        }
        let site = try XCTUnwrap(session.buildingSite)
        let world = session.world
        // Before decision 488, each read placed it on a copy of the world.
        let placed = clock.measure {
            for _ in 0..<steps {
                var draft = world.pricingCopy()
                _ = try? draft.placeBuilding(.shop, at: site)
            }
        }
        let tried = clock.measure { for _ in 0..<steps { _ = try? world.pricingCopy().buildingPlacement(.shop, at: site) } }
        print("stations \(world.stations.count), edges \(world.network.edges.count), land cells \(world.land.cells.count)")
        print("| a step of the drag (\(reads) reads) | \(LongGameCostReportTests.ms(spent, per: steps)) ms |")
        print("| placeBuilding on a copy (each read before) | \(LongGameCostReportTests.ms(placed, per: steps)) ms |")
        print("| buildingPlacement (once a step now) | \(LongGameCostReportTests.ms(tried, per: steps)) ms |")
    }
}
