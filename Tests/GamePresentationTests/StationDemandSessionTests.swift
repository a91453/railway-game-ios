import GameCore
import GamePresentation
import XCTest

/// Stage C2: the station demand screen (G1a's `setStationDemand`, after the
/// `Ci/` reference's custom ridership panel): presets, daily trips, copy,
/// paste and apply to the lines, the hourly entries and exits, the pairs and
/// the ledger. Hourly values are worked out by hand from the reference's
/// curves (largest remainder of `PEAK_FACTOR` × the curves).
final class StationDemandSessionTests: XCTestCase {
    func testAPresetGivesTheDefaultTripsAndKeepsTheStationsOwnAfterwards() async throws {
        try await MainActor.run {
            let session = GameSession(world: try makeStations())
            session.selectedStationDemandKind(.residential, at: GridPosition(x: 1, y: 0))
            XCTAssertEqual(session.world.stationDemand(of: alpha), StationDemand(kind: .residential, dailyTrips: 10_000))
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Alpha: Residential · 10,000 trips a day."))

            session.setSelectedStationDailyTrips(20_000)
            session.setSelectedStationDemandKind(.office)
            XCTAssertEqual(session.world.stationDemand(of: alpha), StationDemand(kind: .office, dailyTrips: 20_000), "the preset keeps the total")

            session.setSelectedStationDailyTrips(StationDemand.maximumDailyTrips + 1)
            XCTAssertEqual(session.message?.kind, .failure)
            XCTAssertEqual(session.world.stationDemand(of: alpha)?.dailyTrips, 20_000, "GameCore refused it")

            session.removeSelectedStationDemand()
            XCTAssertNil(session.world.stationDemand(of: alpha))
            XCTAssertEqual(session.message?.text, "Alpha has no ridership now. Passengers already waiting stay.")
            session.setSelectedStationDailyTrips(5_000)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Choose what kind of place Alpha serves first."))
            XCTAssertNil(session.world.stationDemand(of: alpha))

            session.select(GridPosition(x: 0, y: 3))
            session.setSelectedStationDemandKind(.scenic)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Select a station on the map first."))
        }
    }

    /// Decision 46: a managed company's city sets each station's ridership,
    /// as the reference lets only free play change it
    /// (`stationFlowCustomEditingAllowed`); the city gives a station
    /// without ridership its own when the game opens.
    func testAManagedCompanysCitySetsTheRidership() async throws {
        try await MainActor.run {
            var world = try makeStations()
            try world.setStationDemand(beta, to: StationDemand(kind: .office, dailyTrips: 2_000))
            world.setEconomyMode(.management)
            let session = GameSession(world: world)
            XCTAssertEqual(session.world.stationDemand(of: alpha), StationDemand(kind: .residential, dailyTrips: 10_000))
            XCTAssertEqual(session.world.stationDemand(of: beta), StationDemand(kind: .office, dailyTrips: 2_000), "its own kept")
            XCTAssertFalse(session.canEditStationDemand)

            let opened = session.world
            session.selectStation(alpha)
            let refused = StatusMessage(kind: .failure, text: "A managed company's city sets each station's ridership. Only free play can change it.")
            session.setSelectedStationDemandKind(.office)
            XCTAssertEqual(session.message, refused)
            session.setSelectedStationDailyTrips(1_000_000)
            XCTAssertEqual(session.message, refused)
            session.removeSelectedStationDemand()
            session.copySelectedStationDemand()
            XCTAssertEqual(session.message?.kind, .success, "copying changes nothing")
            session.pasteDemandToSelectedStation()
            XCTAssertEqual(session.message, refused)
            session.applySelectedStationDemandToItsLines()
            XCTAssertEqual(session.message, refused)
            XCTAssertEqual(session.world, opened)

            session.setEconomyMode(.free)
            XCTAssertTrue(session.canEditStationDemand)
            session.setSelectedStationDailyTrips(20_000)
            XCTAssertEqual(session.world.stationDemand(of: alpha), StationDemand(kind: .residential, dailyTrips: 20_000))
        }
    }

    func testTheDailyTripsStepThroughOneTwoAndFive() {
        XCTAssertEqual(StationDemand.dailyTrips(above: 10_000), 20_000)
        XCTAssertEqual(StationDemand.dailyTrips(above: 12_345), 20_000)
        XCTAssertEqual(StationDemand.dailyTrips(above: 0), 100)
        XCTAssertNil(StationDemand.dailyTrips(above: StationDemand.maximumDailyTrips))
        XCTAssertEqual(StationDemand.dailyTrips(below: 10_000), 5_000)
        XCTAssertEqual(StationDemand.dailyTrips(below: 12_345), 10_000)
        XCTAssertNil(StationDemand.dailyTrips(below: 100))
        XCTAssertEqual(StationDemand.dailyTripSteps.last, StationDemand.maximumDailyTrips)
        XCTAssertEqual(StationDemand.tripsText(1, in: .english), "1 trip a day")
        XCTAssertEqual(StationDemand.tripsText(1_000_000, in: .traditionalChinese), "每日 1,000,000 人次")
        XCTAssertEqual(
            StationDemandKind.allCases.map { $0.title(in: .traditionalChinese) },
            ["住宅區", "辦公區", "購物中心", "景點"]
        )
        XCTAssertEqual(StationDemand(kind: .scenic, dailyTrips: 2_500).displayText(in: .traditionalChinese), "景點 · 每日 2,500 人次")
    }

    func testPastingKeepsTheTargetsTripsAndCopyNeedsDemand() async throws {
        try await MainActor.run {
            var world = try makeStations()
            try world.setStationDemand(alpha, to: StationDemand(kind: .office, dailyTrips: 2_000))
            try world.setStationDemand(beta, to: StationDemand(kind: .residential, dailyTrips: 7_000))
            let session = GameSession(world: world)

            session.select(GridPosition(x: 5, y: 0))
            session.pasteDemandToSelectedStation()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Copy a station's ridership first."))
            session.copySelectedStationDemand()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Gamma has no ridership to copy."))
            XCTAssertNil(session.demandClipboard)

            session.select(GridPosition(x: 1, y: 0))
            session.copySelectedStationDemand()
            XCTAssertEqual(session.demandClipboard, StationDemand(kind: .office, dailyTrips: 2_000))
            XCTAssertEqual(session.message?.text, "Copied Alpha's ridership: Office · 2,000 trips a day.")
            XCTAssertEqual(session.world, world, "copying never changes the world")

            session.select(GridPosition(x: 3, y: 0))
            session.pasteDemandToSelectedStation()
            XCTAssertEqual(session.world.stationDemand(of: beta), StationDemand(kind: .office, dailyTrips: 7_000), "Beta keeps its total")
            session.select(GridPosition(x: 5, y: 0))
            session.pasteDemandToSelectedStation()
            XCTAssertEqual(session.world.stationDemand(of: gamma), StationDemand(kind: .office, dailyTrips: 2_000), "Gamma had none")
        }
    }

    func testApplyingGivesEveryStationOfTheLinesTheKind() async throws {
        try await MainActor.run {
            var world = try makeStations()
            try world.createLine(named: "Main", stops: [alpha, beta])
            try world.createLine(named: "Branch", stops: [beta, gamma])
            try world.setStationDemand(beta, to: StationDemand(kind: .shopping, dailyTrips: 3_000))
            try world.setStationDemand(gamma, to: StationDemand(kind: .residential, dailyTrips: 9_000))
            let session = GameSession(world: world)

            session.select(GridPosition(x: 7, y: 0))
            session.applySelectedStationDemandToItsLines()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Delta has no ridership to apply."))
            session.setSelectedStationDemandKind(.scenic)
            session.applySelectedStationDemandToItsLines()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "No line calls at Delta."))

            session.select(GridPosition(x: 3, y: 0))
            session.applySelectedStationDemandToItsLines()
            XCTAssertEqual(session.message?.text, "Applied shopping to 2 lines, 3 stations.")
            XCTAssertEqual(session.world.stationDemand(of: alpha), StationDemand(kind: .shopping, dailyTrips: 3_000), "Alpha had none")
            XCTAssertEqual(session.world.stationDemand(of: gamma), StationDemand(kind: .shopping, dailyTrips: 9_000), "Gamma keeps its total")
            XCTAssertEqual(session.world.stationDemand(of: delta), StationDemand(kind: .scenic, dailyTrips: 10_000), "not on the lines")

            var direct = world
            try direct.setStationDemand(delta, to: StationDemand(kind: .scenic, dailyTrips: 10_000))
            try direct.setStationDemand(alpha, to: StationDemand(kind: .shopping, dailyTrips: 3_000))
            try direct.setStationDemand(gamma, to: StationDemand(kind: .shopping, dailyTrips: 9_000))
            XCTAssertEqual(session.world, direct, "the same commands applied to GameCore directly")

            let chinese = GameSession(world: world, language: .traditionalChinese)
            chinese.select(GridPosition(x: 3, y: 0))
            chinese.applySelectedStationDemandToItsLines()
            XCTAssertEqual(chinese.message?.text, "已套用購物中心到 2 條路線，共 3 座車站。")
        }
    }

    /// Alpha (residential, 1000) and Beta (office, 1000) on one line: all of
    /// Alpha's trips go to Beta and all of Beta's come back.
    func testTheFlowSumsThePairsByHour() throws {
        var world = try makeStations()
        try world.createLine(named: "Main", stops: [alpha, beta])
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try world.setStationDemand(beta, to: StationDemand(kind: .office, dailyTrips: 1_000))

        let flow = try XCTUnwrap(world.stationFlow(of: alpha))
        XCTAssertFalse(flow.isShape)
        // PEAK_FACTOR × residential out (morning) × office in (morning).
        XCTAssertEqual(flow.entries, [4, 4, 4, 4, 4, 4, 34, 111, 171, 111, 38, 31, 31, 32, 32, 33, 56, 56, 67, 56, 37, 38, 38, 4])
        // PEAK_FACTOR × office out (evening) × residential in (evening).
        XCTAssertEqual(flow.exits, [4, 4, 4, 4, 4, 4, 26, 55, 66, 55, 29, 30, 31, 31, 32, 34, 70, 110, 169, 110, 47, 39, 38, 4])
        XCTAssertEqual(flow.entries, world.hourlyDemand(from: alpha, to: beta))
        XCTAssertEqual(StationFlow.peakHour(of: flow.entries), 8)
        XCTAssertEqual(StationFlow.peakHour(of: flow.exits), 18)
        XCTAssertEqual(world.stationFlow(of: beta)?.entries, flow.exits)

        XCTAssertEqual(world.stationDemandPairs(of: alpha), [StationDemandPair(station: beta, outbound: 1_000, inbound: 1_000)])
        XCTAssertEqual(world.demandPairText(world.stationDemandPairs(of: alpha)[0], in: .english), "Beta · 1,000 there · 1,000 back")
        XCTAssertEqual(world.demandPairText(world.stationDemandPairs(of: alpha)[0], in: .traditionalChinese), "Beta · 去 1,000 · 回 1,000")
        XCTAssertNil(world.stationFlow(of: gamma))
        XCTAssertEqual(world.stationDemandPairs(of: gamma), [])
    }

    /// No line links Alpha: the hours share its own trips by its curve.
    func testAStationNoLineLinksShowsItsShape() throws {
        var world = try makeStations()
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        let flow = try XCTUnwrap(world.stationFlow(of: alpha))
        XCTAssertTrue(flow.isShape)
        XCTAssertEqual(flow.entries, [4, 4, 4, 4, 4, 5, 35, 91, 124, 91, 39, 36, 36, 37, 38, 39, 65, 65, 78, 65, 43, 44, 45, 4])
        XCTAssertEqual(flow.exits, [4, 4, 4, 4, 4, 4, 31, 64, 77, 64, 34, 35, 36, 37, 38, 39, 73, 91, 123, 91, 49, 45, 45, 4])
        XCTAssertEqual(flow.entries.reduce(0, +), 1_000)
        XCTAssertEqual(world.stationDemandPairs(of: alpha), [])
    }

    func testTheLedgerRowsReadTheAudit() throws {
        var world = try makeStations()
        try world.createLine(named: "Main", stops: [alpha, beta])
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        try world.setStationDemand(beta, to: StationDemand(kind: .office, dailyTrips: 1_000))
        world.setSpeed(.normal)
        try world.advance(ticks: 480)
        let ledger = world.passengerLedger(of: alpha)
        XCTAssertGreaterThan(ledger.released, 0)
        let rows = world.passengerLedgerRows(of: alpha, in: .english)
        XCTAssertEqual(rows.map(\.title), ["Released", "Waiting", "Riding", "Arrived", "Left a full station", "Gave up", "Left behind (times)"])
        XCTAssertEqual(rows.map(\.count), [ledger.released, ledger.waiting, ledger.riding, ledger.arrived, ledger.overflowed, ledger.abandoned, ledger.refused])
        XCTAssertEqual(rows[0].countText, Money(ledger.released).displayText)
        XCTAssertEqual(
            world.passengerLedgerRows(of: gamma, in: .traditionalChinese).map(\.title),
            ["釋出", "候車", "車上", "已抵達", "車站客滿離開", "放棄搭乘", "未能上車（次）"]
        )
        XCTAssertEqual(world.passengerLedgerRows(of: gamma, in: .english).map(\.count), [0, 0, 0, 0, 0, 0, 0])
    }
}

private extension GameSession {
    func selectedStationDemandKind(_ kind: StationDemandKind, at position: GridPosition) {
        select(position)
        setSelectedStationDemandKind(kind)
    }
}

private let alpha = StationID(rawValue: 1)
private let beta = StationID(rawValue: 2)
private let gamma = StationID(rawValue: 3)
private let delta = StationID(rawValue: 4)

/// Alpha (1,0), Beta (3,0), Gamma (5,0) and Delta (7,0), no track.
private func makeStations() throws -> GameWorld {
    var world = try makeWorld(width: 8, height: 4, balance: 100_000)
    for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
        try world.buildStation(named: name, at: TestLine.centre(x, 0))
    }
    return world
}
