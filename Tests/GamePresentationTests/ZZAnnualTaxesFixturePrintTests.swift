import Foundation
@testable import GameCore
import XCTest

/// TEMPORARY (decision 734): the session that wrote the v99 save had no
/// Swift, so CI prints it here to copy into SaveFixtures; removed in the
/// commit that adds the file. Builds the same world as
/// `AnnualTaxesTests.closedFirstYear()`.
final class ZZAnnualTaxesFixturePrintTests: XCTestCase {
    func testPrintTheVersion99Save() throws {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        world.setEconomyMode(.management)
        world.setAnnualTaxes(true)
        try world.advance(ticks: 359 * 1_440 + 1)
        let fares = Money(90_000_000)
        world.write(LedgerEntry(
            kind: .hourlyNet, time: world.clock.now, amount: fares,
            breakdown: [
                LedgerLine(item: .fareRevenue, amount: fares), LedgerLine(item: .operatingCost, amount: .zero),
                LedgerLine(item: .maintenanceCost, amount: .zero),
            ],
            crowding: CrowdingMetrics(crowdedStations: 0, fullTrains: 0, maxWaiting: 0, maxLoad: 0)
        ), day: world.dayIndex(of: world.clock.now))
        try world.advance(ticks: 1_440)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let text = String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self)
        print("V99-FIXTURE-BEGIN")
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            print("V99|" + line)
        }
        print("V99-FIXTURE-END")
        XCTFail("print only: the v99 save is not committed yet")
    }
}
