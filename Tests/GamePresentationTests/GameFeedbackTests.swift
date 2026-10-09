import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 117: a pulse and a sound for something put up,
/// and for money that came in. Read from the world after the fact; never
/// changes it.
@MainActor
final class GameFeedbackTests: XCTestCase {
    private func row(_ minute: Int64, _ lines: [(LedgerItem, Int64)]) -> LedgerEntry {
        let breakdown = lines.map { LedgerLine(item: $0.0, amount: Money($0.1)) }
        return LedgerEntry(kind: .hourlyNet, time: GameTime(minutes: minute), amount: breakdown.reduce(.zero) { $0 + $1.amount }, breakdown: breakdown)
    }

    func testIncomeIsTheFaresAndRentOfTheRowsWrittenAfterTheLast() {
        let first = row(60, [(.fareRevenue, 500), (.operatingCost, -200)])
        let second = row(120, [(.fareRevenue, 700), (.maintenanceCost, -50)])
        let third = row(1_440, [(.propertyRent, 300), (.propertyUpkeep, -100)])
        XCTAssertEqual(CompanyAccounts.income(writtenAfter: nil, in: []), .zero)
        XCTAssertEqual(CompanyAccounts.income(writtenAfter: nil, in: [first]), Money(500), "the first row ever")
        XCTAssertEqual(CompanyAccounts.income(writtenAfter: first, in: [first]), .zero, "nothing new")
        XCTAssertEqual(CompanyAccounts.income(writtenAfter: first, in: [first, second, third]), Money(1_000))
        XCTAssertEqual(CompanyAccounts.income(writtenAfter: first, in: [second, third]), Money(1_000), "the last is no longer kept")
        XCTAssertEqual(CompanyAccounts.income(writtenAfter: second, in: [first, second, row(180, [(.operatingCost, -200)])]), .zero, "costs only")
    }

    func testPuttingUpABuildingPulsesWhereItStands() throws {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480), language: .english)
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        session.selectTool(.building)
        heard.removeAll()
        XCTAssertNil(session.buildPulse)

        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000)))
        XCTAssertEqual(session.buildPulse, BuildPulse(location: PlanPoint(x: 5_000, y: 5_000), serial: 1))
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 10_000, y: 10_000)))
        XCTAssertEqual(session.buildPulse?.serial, 2)
        XCTAssertEqual(heard, [.built, .built])

        // Refused: no pulse, no sound.
        XCTAssertFalse(session.placeBuilding(at: PlanPoint(x: 10_500, y: 10_000)))
        XCTAssertEqual(session.buildPulse?.serial, 2)
        XCTAssertEqual(heard, [.built, .built])
    }

    func testAnHourOfFaresPulsesTheCash() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        let line = TestLine(tiles: 7, row: 1)
        try line.build(in: &world)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try line.buildStation(named: name, beside: x, at: 0, in: &world)
        }
        let main = LineID(rawValue: 1)
        try world.createLine(named: "Main", stops: [StationID(rawValue: 1), StationID(rawValue: 2), StationID(rawValue: 3)])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.assignTrain(train.id, to: main)
        world.setEconomyMode(.management)
        try world.setStationDemand(StationID(rawValue: 1), to: StationDemand(kind: .residential, dailyTrips: 200_000))
        try world.setStationDemand(StationID(rawValue: 3), to: StationDemand(kind: .office, dailyTrips: 200_000))

        let session = GameSession(world: world)
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        // A tick is a minute at 600×; the hour ending at 60 is settled as
        // the step from 60 starts.
        for _ in 0..<61 {
            session.advance(realElapsed: GameSession.tickInterval)
        }
        let entry = try XCTUnwrap(session.world.accounts.entries.last)
        let fares = entry.breakdown.filter { $0.item == .fareRevenue }.reduce(Money.zero) { $0 + $1.amount }
        XCTAssertGreaterThan(fares, .zero, "the test needs fares")
        XCTAssertEqual(session.incomePulse, IncomePulse(amount: fares, serial: 1))
        XCTAssertEqual(heard.filter { $0 == .income }.count, 1)

        // The next minutes settle nothing: no new pulse.
        session.advance(realElapsed: GameSession.tickInterval)
        XCTAssertEqual(session.incomePulse?.serial, 1)
    }
}
