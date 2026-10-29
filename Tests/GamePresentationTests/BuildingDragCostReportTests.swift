import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// What dragging a building over the flat map costs the main actor (95.1:
/// a shop dragged over the real map, the game paused, dropped to 11–50 fps
/// with stalls of up to 1.4 s). Each step of the finger moves the
/// ``GameSession/buildingSite``, and the map, the build card and the
/// confirm button each read the preview again. On the real map round
/// Miaoli with `BUILDING_DRAG_REPORT` lines of eleven stations. Run on
/// request, in release:
///
///     BUILDING_DRAG_REPORT=4 swift test -c release -Xswiftc -enable-testing \
///       --filter BuildingDragCostReportTests
@MainActor
final class BuildingDragCostReportTests: XCTestCase {
    func testWhatAStepOfTheDragCosts() throws {
        guard let value = ProcessInfo.processInfo.environment["BUILDING_DRAG_REPORT"] else {
            throw XCTSkip("set BUILDING_DRAG_REPORT=<lines> to time a building dragged over a map of that many 11-station lines")
        }
        let lines = try XCTUnwrap(Int(value).flatMap { (1...16).contains($0) ? $0 : nil }, "BUILDING_DRAG_REPORT is 1 to 16 lines")
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        var world = try MapFrameCostReportTests.miaoli(lines: lines, data: data)
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
        let now = session.world
        // Before decision 488, each read placed it on a copy of the world;
        // over sites round each station, the longest and the mean.
        var before: [Double] = [], after: [Double] = [], clears = 0
        func ms(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        }
        for station in stride(from: 0, to: now.stations.count, by: max(1, now.stations.count / 11)).map({ now.stations[$0] }) {
            for dy in stride(from: Int64(-6_000), through: 6_000, by: 2_000) where dy != 0 {
                let site = PlanPoint(x: station.point.x + 1_000, y: station.point.y + dy)
                before.append(ms(clock.measure {
                    var draft = now.pricingCopy()
                    if let placed = try? draft.placeBuilding(.shop, at: site), placed.residents + placed.jobs > 0 { clears += 1 }
                }))
                after.append(ms(clock.measure { _ = try? now.pricingCopy().buildingPlacement(.shop, at: site) }))
            }
        }
        func row(_ label: String, _ values: [Double]) -> String {
            String(format: "| %@ | %.3f | %.3f |", label, values.reduce(0, +) / Double(values.count), values.max() ?? 0)
        }
        print("stations \(now.stations.count), edges \(now.network.edges.count), land cells \(now.land.cells.count); \(before.count) sites, \(clears) buying out")
        print("| a step of the drag (\(reads) reads, now) | \(LongGameCostReportTests.ms(spent, per: steps)) ms |")
        print("| | mean ms | longest ms |")
        print(row("placeBuilding on a copy (each read before)", before))
        print(row("buildingPlacement (once a step now)", after))
    }
}
