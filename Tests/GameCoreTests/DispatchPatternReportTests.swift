import Foundation
@testable import GameCore
import XCTest

/// The numbers of decision 309 (economy-balance skill): a line of two
/// trains run a day under each dispatch pattern. Asserts nothing; runs only
/// with `DISPATCH_PATTERN_REPORT=1`:
///
///     DISPATCH_PATTERN_REPORT=1 swift test --skip-build --filter DispatchPatternReportTests
///
/// `DispatchPatternTests`' straight track, Alpha, Beta and Gamma two links
/// apart, the line Main Alpha–Beta–Gamma all day at a crawl with two
/// trains (Gamma's placed there for both ends), managed, network routing,
/// line accounts and realistic operation (punctuality) on, Alpha
/// residential and Gamma office with 3,000 trips a day each, Beta shopping
/// with 1,000.
final class DispatchPatternReportTests: XCTestCase {
    private let line = TestLine(tiles: 7)
    private let main = LineID(rawValue: 1)
    private let crawl = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1)

    private func makeWorld(_ pattern: DispatchPattern) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 0), speed: .normal)
        )
        world.setFlexDispatch(true)
        try line.build(in: &world)
        let alpha = try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let beta = try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        let gamma = try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.setLinePerformance(main, to: crawl)
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        for index in 1...2 {
            let train = try world.purchaseTrain(named: "T\(index)")
            let atGamma = pattern == .fromBothEnds && index == 2
            try world.placeTrain(train.id, at: atGamma ? line.at(5, facingEast: false) : line.at(1, facingEast: true))
            try world.setTrainMovementRate(train.id, to: 1024)
            try world.assignTrain(train.id, to: main)
        }
        try world.setLineDispatchPattern(main, to: pattern)
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 3_000))
        try world.setStationDemand(beta, to: StationDemand(kind: .shopping, dailyTrips: 1_000))
        try world.setStationDemand(gamma, to: StationDemand(kind: .office, dailyTrips: 3_000))
        world.setPassengerRoutingMode(.network)
        world.setEconomyMode(.management)
        world.setLineAccounts(true)
        world.setRealisticOperation(true)
        return world
    }

    func testTwoTrainsADayUnderEachPattern() throws {
        guard ProcessInfo.processInfo.environment["DISPATCH_PATTERN_REPORT"] != nil else {
            throw XCTSkip("Set DISPATCH_PATTERN_REPORT=1 to print the report.")
        }
        var rows = ["| Pattern | Boardings | Mean wait (min) | On time | Trips |", "| --- | ---: | ---: | ---: | ---: |"]
        for pattern in [DispatchPattern.even, .fromBothEnds, .staggered(minutes: 2), .staggered(minutes: 10)] {
            var world = try makeWorld(pattern)
            var waitingMinutes: Int64 = 0
            for _ in 0..<(24 * 60) {
                try world.advance(ticks: 1)
                waitingMinutes += world.stations.reduce(0) { sum, station in
                    sum + world.waitingPassengers(at: station.id).reduce(0) { $0 + $1.count }
                }
            }
            try world.advance(ticks: 1)
            let day = try XCTUnwrap(world.lineYesterday(main))
            let wait = day.boardings > 0 ? Double(waitingMinutes) / Double(day.boardings) : 0
            let onTime = day.punctualityPermille.map { String(format: "%.1f %%", Double($0) / 10) } ?? "—"
            rows.append("| \(pattern) | \(day.boardings) | \(String(format: "%.1f", wait)) | \(onTime) | \(day.trips) |")
        }
        print(rows.joined(separator: "\n"))
    }
}
