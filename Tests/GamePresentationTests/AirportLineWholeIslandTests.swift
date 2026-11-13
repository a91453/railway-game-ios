import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The Taoyuan Airport MRT is on sale wherever the world was picked
/// (COACH-HEALTH, 2026-11-12: in a world picked at 25.02, 121.30 it was
/// refused as too steep). The ground under the last metres of its way was
/// not read there, and counted as sea level under a station 133 m up.
@MainActor
final class AirportLineWholeIslandTests: XCTestCase {
    func testItIsOnSaleInAWorldPickedBesideIt() throws {
        let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.02, longitudeDegrees: 121.30))
        // The player's world, its tiles bought, and the demo's.
        for demo in [false, true] {
            let world = GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
                population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights,
                placeNames: data.placeNames
            ), demo: demo)
            let session = GameSession(world: world, language: .english)
            session.population = data.population
            session.places = data.places
            session.water = data.water
            session.heights = data.heights
            session.coverage = data.coverage
            session.railways = data.railways
            session.news.isDemo = demo
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "tymc:A" }, "demo \(demo)")
            let offer = session.realLineOffer(for: line)
            XCTAssertNil(offer.problem, "demo \(demo)")
            XCTAssertNotNil(offer.acquisition, "demo \(demo)")
        }
    }
}
