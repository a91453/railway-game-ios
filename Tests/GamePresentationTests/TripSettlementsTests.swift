import GameCore
@testable import GamePresentation
import XCTest

/// Today's trips settled for the operations overview (decision 224, 1C),
/// from the trip log (decision 223, point 5).
final class TripSettlementsTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private static let track = TestLine(tiles: 7)

    /// The line A–B with one train, managed with line accounts; the people
    /// of A go to B.
    private func build(accounts: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        try Self.track.build(in: &world)
        _ = try Self.track.buildStation(named: "A", beside: 1, at: 1, in: &world)
        _ = try Self.track.buildStation(named: "B", beside: 3, at: 1, in: &world)
        let line = try world.createLine(named: "First", stops: [a, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "One").id
        try world.placeTrain(train, at: Self.track.at(1, facingEast: true))
        try world.setTrainMovementRate(train, to: 1024)
        try world.assignTrain(train, to: line)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 1_500))
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: 1_500))
        world.setEconomyMode(.management)
        world.setLineAccounts(accounts)
        world.setSpeed(.normal)
        return world
    }

    func testTodaysFinishedTripsAreCountedAndTheLatestListed() throws {
        var world = try build()
        try world.advance(ticks: 1_440 + 300)
        let settled = TripSettlements(world: world, limit: 3)
        let today = world.clock.now.seconds / GameTime.secondsPerDay * GameTime.secondsPerDay
        let finished = world.tripLog.filter { ($0.arrival?.seconds ?? -1) >= today && !$0.isInterrupted && !$0.isDeadhead }
        XCTAssertGreaterThan(finished.count, 3)
        XCTAssertEqual(settled.completed, finished.count)
        XCTAssertEqual(settled.onTime, finished.filter { $0.isLate == false }.count)
        XCTAssertEqual(settled.fares, finished.reduce(.zero) { $0 + $1.fare })
        XCTAssertGreaterThan(settled.fares, .zero)
        XCTAssertEqual(settled.onTimePercent, settled.onTime * 100 / settled.completed)
        XCTAssertEqual(settled.entries.count, 3)
        XCTAssertEqual(settled.entries.map(\.arrival), settled.entries.map(\.arrival).sorted(by: >), "the latest first")
        XCTAssertEqual(settled.entries.first?.arrival, finished.compactMap { $0.arrival?.seconds }.max())
        let entry = try XCTUnwrap(settled.entries.first)
        XCTAssertEqual(entry.trainName, "One")
        XCTAssertEqual(entry.routeText, "A → A")
        XCTAssertEqual(entry.lineCode, LineBadge.codes(for: world.lines)[try XCTUnwrap(entry.line)])
        XCTAssertEqual(entry.fareText, "+" + TrainRoster.shortMoney(entry.fare))
        XCTAssertNil(entry.lateText(in: .english))
        XCTAssertEqual(entry.stampText(in: .traditionalChinese), "準")
    }

    func testWithoutTheLogThereIsNothingToSettle() throws {
        var world = try build(accounts: false)
        try world.advance(ticks: 300)
        let settled = TripSettlements(world: world)
        XCTAssertEqual(settled.completed, 0)
        XCTAssertNil(settled.onTimePercent)
        XCTAssertEqual(settled.entries, [])
        XCTAssertEqual(settled.fares, .zero)
    }

    func testALateEntrySaysHowLate() {
        let late = TripSettlements.Entry(train: TrainID(rawValue: 1), trainName: "1207", line: nil, lineCode: nil, from: "新竹", to: "基隆",
                                         arrival: 36_720, fare: Money(220_000), lateMinutes: 9)
        XCTAssertTrue(late.isLate)
        XCTAssertEqual(late.lateText(in: .traditionalChinese), "+9 分")
        XCTAssertEqual(late.lateText(in: .english), "+9 min")
        XCTAssertEqual(late.stampText(in: .traditionalChinese), "誤")
        XCTAssertEqual(late.fareText, "+$2.2k")
    }
}
