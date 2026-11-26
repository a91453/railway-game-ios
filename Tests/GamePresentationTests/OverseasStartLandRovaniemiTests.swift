import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 992, Rovaniemi's part (``OverseasStartLandTests`` has the
/// rules every map shares): the map stays whole and counted.
/// SPLIT-HOTSPOTS-2: a map of its own file.
@MainActor
final class OverseasStartLandRovaniemiTests: XCTestCase {
    static let ground: OverseasGround = {
        do {
            return try OverseasGround(city: .rovaniemi, pack: XCTUnwrap(HongKongRailwaysTests.pack(.rovaniemi)))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    /// Rovaniemi has no tiles to start with: it stays whole.
    func testRovaniemiHasNoStartTiles() {
        XCTAssertEqual(Self.ground.startTiles, [])
        XCTAssertFalse(OverseasMap.rovaniemi.buysLand)
        XCTAssertNil(OverseasMap.rovaniemi.wholeMapSummary(in: .english))
    }

    func testRovaniemiIsWholeAndCountedEitherWay() {
        let ground = Self.ground
        for wholeMap in [false, true] {
            let world = GameWorld.newOverseasGame(ground, wholeMap: wholeMap, eventSeed: 3)
            XCTAssertEqual(world, GameWorld.newOverseasGame(ground, eventSeed: 3))
            XCTAssertNil(world.mapExpansion)
            XCTAssertFalse(world.wholeMapOpen)
        }
    }
}
