import GameCore
import GamePresentation
import XCTest

/// Decision 332: what the station and line cards say of the riders who
/// take a scooter or a car instead, and what brings most of them back.
final class ModeShiftTextTests: XCTestCase {
    private static let track = TestLine(tiles: 140)
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let near = StationID(rawValue: 3)

    private func loss(switched: Int64 = 0, tooExpensive: Int64 = 0, waitsLongest: Bool = false, byCar: Bool = false,
                      isNear: Bool = false) -> ModeShiftLoss {
        ModeShiftLoss(destination: b, switched: switched, tooExpensive: tooExpensive, waitsLongest: waitsLongest,
                      byCar: byCar, isNear: isNear, lines: [])
    }

    func testTheReasonIsWhatLostMost() throws {
        let waiting = try XCTUnwrap(ModeShiftSummary([loss(switched: 300, waitsLongest: true), loss(switched: 200)]))
        XCTAssertEqual(waiting.reason, .fewTrains)
        XCTAssertEqual(waiting.riders, 500)
        let riding = try XCTUnwrap(ModeShiftSummary([loss(switched: 100, waitsLongest: true), loss(switched: 200)]))
        XCTAssertEqual(riding.reason, .slowTrains)
        let fares = try XCTUnwrap(ModeShiftSummary([loss(switched: 100), loss(tooExpensive: 150)]))
        XCTAssertEqual(fares.reason, .fares)
        XCTAssertEqual(fares.riders, 250)
        // A tie goes to more trains, then to faster ones.
        XCTAssertEqual(ModeShiftSummary([loss(switched: 100, waitsLongest: true), loss(switched: 100)])?.reason, .fewTrains)
        XCTAssertEqual(ModeShiftSummary([loss(switched: 100), loss(tooExpensive: 100)])?.reason, .slowTrains)
    }

    func testRidersAreRoundedToTensAndCarsShowWhenMoreDrive() throws {
        XCTAssertEqual(ModeShiftSummary([loss(switched: 14)])?.riders, 10)
        XCTAssertEqual(ModeShiftSummary([loss(switched: 15)])?.riders, 20)
        XCTAssertNil(ModeShiftSummary([loss(switched: 4)]))
        XCTAssertNil(ModeShiftSummary([]))
        XCTAssertEqual(ModeShiftSummary([loss(switched: 30, byCar: true), loss(switched: 20)])?.symbol, "car.fill")
        XCTAssertEqual(ModeShiftSummary([loss(switched: 20, byCar: true), loss(switched: 20)])?.symbol, "scooter")
    }

    func testNearbyStationsSayPeopleWalk() throws {
        let nearby = try XCTUnwrap(ModeShiftSummary([loss(isNear: true)]))
        XCTAssertEqual(nearby.reason, .nearby)
        XCTAssertEqual(nearby.stationText(in: .english), "Most people this close walk or ride")
        XCTAssertNil(ModeShiftSummary([loss(isNear: true), loss()]))
    }

    func testTheTextsSayHowManyAndWhatBringsThemBack() {
        let summary = ModeShiftSummary(riders: 1_250, reason: .fewTrains, byCar: false)
        XCTAssertEqual(summary.stationText(in: .english), "About 1,250 a day ride or drive instead")
        XCTAssertEqual(summary.stationText(in: .traditionalChinese), "每天約 1,250 人改騎機車或開車")
        XCTAssertEqual(summary.reasonText(in: .english), "Trains are too few; more trains bring them back")
        XCTAssertEqual(ModeShiftSummary(riders: 10, reason: .fares, byCar: true).reasonText(in: .traditionalChinese),
                       "票價太貴，降一點可以拉回來")
    }

    /// A–Near–B, as in ModeShiftTests: a train every 10 minutes, the
    /// simple rule; A's riders to B wait longer than they ride.
    private func corridor() throws -> GameWorld {
        var world = try makeWorld(width: 143 * TestLine.tile, height: 4 * TestLine.tile, balance: 100_000_000)
        try Self.track.build(in: &world)
        _ = try Self.track.buildStation(named: "A", beside: 1, at: 2, in: &world)
        _ = try Self.track.buildStation(named: "B", beside: 135, at: 2, in: &world)
        _ = try Self.track.buildStation(named: "Near", beside: 10, at: 2, in: &world)
        let line = try world.createLine(named: "Main", stops: [a, near, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTargetHeadways(line, to: TargetHeadways(peak: 10, offPeak: 10, low: 10))
        let train = try world.purchaseTrain(named: "T").id
        try world.assignTrain(train, to: line)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 10_000))
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: 10_000))
        try world.setStationDemand(near, to: StationDemand(kind: .office, dailyTrips: 10_000))
        world.setPassengerRoutingMode(.network)
        return world
    }

    func testTheCardsReadTheWorld() throws {
        var world = try corridor()
        let line = try XCTUnwrap(world.lines.first).id
        XCTAssertNil(world.stationModeShift(of: a))
        XCTAssertNil(world.lineModeShift(line))
        try world.setModeShift(.simple)

        let station = try XCTUnwrap(world.stationModeShift(of: a))
        XCTAssertEqual(station, ModeShiftSummary(riders: 1_000, reason: .fewTrains, byCar: false))

        let onLine = try XCTUnwrap(world.lineModeShift(line))
        let lost = [a, b, near].flatMap { world.modeShiftLosses(from: $0) }.reduce(0) { $0 + $1.switched + $1.tooExpensive }
        XCTAssertEqual(onLine.riders, (lost + 5) / 10 * 10)
        XCTAssertEqual(onLine.riders, 4_000)
        XCTAssertEqual(onLine.top?.from, a)
        XCTAssertEqual(onLine.top?.to, b)
        XCTAssertEqual(onLine.lineText(in: world, language: .english),
                       "About 4,000 a day on this line ride or drive instead; most from A to B")
        XCTAssertEqual(onLine.lineText(in: world, language: .traditionalChinese), "這條線每天約 4,000 人改騎車；最多的是A到B")
    }
}
