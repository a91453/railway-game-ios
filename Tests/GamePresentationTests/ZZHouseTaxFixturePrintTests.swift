import Foundation
@testable import GameCore
import XCTest

/// TEMPORARY (decision 736): the session that wrote the v100 save had no
/// Swift, so CI prints it here to copy into SaveFixtures; removed in the
/// commit that adds the file. Builds the same world as
/// `AnnualPropertyTaxesTests.closedFirstYear()`.
final class ZZHouseTaxFixturePrintTests: XCTestCase {
    func testPrintTheVersion100Save() throws {
        var world = try GameWorld(
            bounds: WorldBounds(width: 32_768, height: 4_096),
            economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 100, station: 72_000_000, train: 5_000)),
            clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        world.setAnnualTaxes(true)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 1_024))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 17_408, y: 1_024))
        try world.buildTrackEdge(from: a, to: b)
        let station = try world.buildStation(named: "A", at: PlanPoint(x: 5_120, y: 2_048)).id
        try world.addTrackPlatform(station, on: .edge(1), from: 1_024, to: 1_024 + 100 * WorldCoordinate.unitsPerMetre)
        try world.advance(ticks: 360 * 1_440 + 1)
        // Compact, in pieces of 1,000 characters, so the whole save fits in
        // the last lines of the job's log.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = Array(String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self))
        print("V100-FIXTURE-BEGIN \(text.count)")
        var start = 0
        while start < text.count {
            let end = min(start + 1_000, text.count)
            print("V100|" + String(text[start..<end]) + "|")
            start = end
        }
        print("V100-FIXTURE-END")
        XCTFail("print only: the v100 save is not committed yet")
    }
}
