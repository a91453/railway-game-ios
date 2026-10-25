import GameCore
@testable import GamePresentation
import XCTest

/// Decision 416: the network's flow report: the lines by the reference's
/// flow dashboard metrics, the fullest sections, and the demand the
/// network leaves unmet, read from the world.
final class NetworkFlowReportTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)
    private static let gamma = StationID(rawValue: 3)

    /// Three stations far apart (no walk between them), Alpha 1,000 trips
    /// a day, Beta 3,000 and Gamma 2,000.
    private func threeStations() throws -> GameWorld {
        var world = try makeWorld(width: 400_000, height: 100_000, balance: 100_000)
        for (name, x) in [("Alpha", 20_000), ("Beta", 150_000), ("Gamma", 300_000)] {
            try world.buildStation(named: name, at: PlanPoint(x: Int64(x), y: 50_000))
        }
        for (id, trips) in [(Self.alpha, 1_000), (Self.beta, 3_000), (Self.gamma, 2_000)] {
            try world.setStationDemand(id, to: StationDemand(kind: .residential, dailyTrips: Int64(trips)))
        }
        return world
    }

    // MARK: - Empty

    func testAnEmptyNetworkReportsNothing() {
        let report = NetworkFlowReport(world: .newGame())
        XCTAssertTrue(report.isEmpty)
        XCTAssertFalse(report.hasPlan)
        XCTAssertEqual(report.lines(sortedBy: .ridership), [])
        for kind in NetworkFlowReport.UnmetKind.allCases {
            XCTAssertEqual(report.unmet(kind), [], "\(kind)")
            XCTAssertFalse(kind.emptyText(in: .traditionalChinese).isEmpty)
        }
    }

    // MARK: - Lines

    func testLinesSortByTheChosenMetricWithTiesByLine() {
        func row(_ id: Int, riders: Int64, metres: Int64, trains: Int) -> NetworkFlowReport.LineRow {
            .init(line: LineID(rawValue: id), name: "L\(id)", ridership: riders,
                  length: metres * WorldCoordinate.unitsPerMetre, peakTrains: trains)
        }
        let report = NetworkFlowReport(lines: [
            row(1, riders: 500, metres: 10_000, trains: 4),
            row(2, riders: 900, metres: 2_000, trains: 4),
            row(3, riders: 900, metres: 30, trains: 2),
        ])
        XCTAssertEqual(report.lines(sortedBy: .ridership).map(\.line.rawValue), [2, 3, 1], "a tie goes to the lower line")
        XCTAssertEqual(report.lines(sortedBy: .ridership, descending: false).map(\.line.rawValue), [1, 2, 3])
        XCTAssertEqual(report.lines(sortedBy: .length).map(\.line.rawValue), [1, 2, 3])
        XCTAssertEqual(report.lines(sortedBy: .peakTrains).map(\.line.rawValue), [1, 2, 3])
        // 900 riders over 2 km is 450 a km; 30 m is under the reference's
        // 0.05 km, so no intensity, sorted as 0.
        XCTAssertEqual(report.lines(sortedBy: .intensity).map(\.line.rawValue), [2, 1, 3])
        XCTAssertEqual(report.lines[1].intensity ?? 0, 450, accuracy: 1e-9)
        XCTAssertNil(report.lines[2].intensity)
        XCTAssertEqual(report.lines[2].valueText(.intensity, in: .english), "—")
        XCTAssertEqual(report.lines[1].valueText(.intensity, in: .traditionalChinese), "450 人次／公里")
        XCTAssertEqual(report.lines[0].valueText(.length, in: .english), "10.0 km")
        XCTAssertEqual(report.lines[0].valueText(.peakTrains, in: .english), "4 trains")
    }

    func testAPlayedLineHasALengthAndPeakTrains() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let line = try XCTUnwrap(world.lines.first)
        let rows = NetworkFlowReport(world: world).lines
        XCTAssertEqual(rows.map(\.line), [line.id])
        XCTAssertGreaterThan(rows[0].length, 0)
        XCTAssertGreaterThanOrEqual(rows[0].peakTrains, 1)
        XCTAssertEqual(rows[0].ridership, 0, "no day has closed yet")
    }

    // MARK: - Sections

    func testSectionsRankTheFullestFirstAtTheirFullestHour() throws {
        let edge = try XCTUnwrap(DemoWorld.make(in: .english).network.edges.first).id
        let piece = SectionFlow.Piece(edge: edge, start: 0, end: 10, forward: true)
        func section(_ from: Int, loads: [Int: Int64], capacity: Int64) -> SectionFlow.Section {
            var hourly = Array(repeating: Int64(0), count: 24)
            for (hour, load) in loads { hourly[hour] = load }
            return SectionFlow.Section(
                pieces: [piece], from: StationID(rawValue: from), to: StationID(rawValue: from + 1), lines: [LineID(rawValue: 1)],
                loads: hourly, capacities: Array(repeating: capacity, count: 24))
        }
        let flow = SectionFlow(sections: [
            section(1, loads: [8: 50, 18: 80], capacity: 100), // 80% at 18:00
            section(3, loads: [7: 120, 9: 120], capacity: 100), // 120%, the earlier hour
            section(5, loads: [8: 10], capacity: 0), // riders and no trains
            section(7, loads: [:], capacity: 100), // nobody
            section(9, loads: [8: 160], capacity: 200), // 80% too, more riders
        ], hasPlan: true)
        let rows = NetworkFlowReport.sectionRows(of: flow)
        XCTAssertEqual(rows.map(\.section), [2, 1, 4, 0], "no trains first, then by percent, then by load; nobody left out")
        XCTAssertEqual(rows[1].hour, 7)
        XCTAssertEqual(rows[1].percent, 120)
        XCTAssertTrue(rows[1].isOverloaded)
        XCTAssertEqual(rows[3].hour, 18)
        XCTAssertEqual(rows[3].dailyLoad, 130)
        XCTAssertFalse(rows[3].isOverloaded)
        XCTAssertNil(rows[0].percent)
        XCTAssertTrue(rows[0].isOverloaded)
        XCTAssertEqual(NetworkFlowReport.valueText(of: rows[1], in: .traditionalChinese), "07:00 · 120 人／運能 100（120%）")
        XCTAssertEqual(NetworkFlowReport.valueText(of: rows[0], in: .english), "08:00 · 10 riders, no trains")
    }

    func testAPlayedDemoRanksItsSections() throws {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 60)
        let report = NetworkFlowReport(world: world)
        XCTAssertTrue(report.hasPlan)
        XCTAssertFalse(report.sections.isEmpty)
        XCTAssertLessThanOrEqual(report.sections.count, NetworkFlowReport.rowsShown)
        XCTAssertTrue(report.sections.allSatisfy { $0.load > 0 && $0.dailyLoad >= $0.load })
    }

    // MARK: - Unmet demand

    func testPairsNoLineJoinsAreRankedByTheTripsTheyWouldShare() throws {
        var world = try threeStations()
        try world.createLine(named: "Main", stops: [Self.alpha, Self.beta])
        let rows = NetworkFlowReport(world: world).unmet(.unconnected)
        // Beta to Gamma: 3,000 × 2,000 / 3,000 = 2,000, back 2,000 × 3,000 /
        // 4,000 = 1,500. Alpha to Gamma: 1,000 × 2,000 / 5,000 = 400, back
        // 2,000 × 1,000 / 4,000 = 500.
        XCTAssertEqual(rows.map { [$0.from, $0.to] }, [[Self.beta, Self.gamma], [Self.alpha, Self.gamma]])
        XCTAssertEqual(rows.map(\.people), [3_500, 900])
        XCTAssertTrue(rows.allSatisfy(\.bothWays))
        XCTAssertEqual(rows[0].title(in: world), "Beta ↔ Gamma")
        XCTAssertEqual(rows[0].valueText(in: .traditionalChinese), "每天約 3,500 人次")
    }

    func testAChangeOfTrainsJoinsStationsOnlyInANetworkGame() throws {
        var world = try threeStations()
        try world.createLine(named: "West", stops: [Self.alpha, Self.beta])
        try world.createLine(named: "East", stops: [Self.beta, Self.gamma])
        XCTAssertEqual(NetworkFlowReport(world: world).unmet(.unconnected).map(\.to), [Self.gamma],
                       "without changes of train Alpha and Gamma are apart")
        world.setPassengerRoutingMode(.network)
        XCTAssertEqual(NetworkFlowReport(world: world).unmet(.unconnected), [])
    }

    func testFreightLinesAndClosedStationsDoNotCount() throws {
        var world = try threeStations()
        world.enableFreight()
        let freight = try world.createLine(named: "Goods", stops: [Self.alpha, Self.beta, Self.gamma])
        try world.setLineFreight(freight.id, to: true)
        XCTAssertEqual(NetworkFlowReport(world: world).unmet(.unconnected).count, 3, "a freight line carries nobody")
        XCTAssertEqual(NetworkFlowReport(world: world).lines, [], "nor is it listed")
        try world.setStationOperationMode(Self.gamma, to: .closed)
        XCTAssertEqual(NetworkFlowReport(world: world).unmet(.unconnected).map { [$0.from, $0.to] }, [[Self.alpha, Self.beta]])
    }

    func testTiesGoToTheLowerStationThenTheLowerDestination() {
        func row(_ from: Int, _ to: Int, _ people: Int64) -> NetworkFlowReport.UnmetRow {
            .init(kind: .lost, from: StationID(rawValue: from), to: StationID(rawValue: to), people: people,
                  bothWays: false, longestWaitMinutes: nil)
        }
        let ranked = NetworkFlowReport.ranked([row(3, 1, 50), row(2, 9, 50), row(2, 4, 50), row(7, 1, 80)])
        XCTAssertEqual(ranked.map { [$0.from.rawValue, $0.to.rawValue] }, [[7, 1], [2, 4], [2, 9], [3, 1]])
        let many = (1...30).map { row($0, 99, Int64($0)) }
        XCTAssertEqual(NetworkFlowReport.ranked(many).count, NetworkFlowReport.rowsShown)
        XCTAssertEqual(NetworkFlowReport.ranked(many).first?.people, 30)
    }

    func testThoseWaitingHalfAnHourForATrainThatDoesNotComeAreListed() throws {
        var world = try threeStations()
        try world.createLine(named: "Main", stops: [Self.alpha, Self.beta])
        try world.setStationDemand(Self.alpha, to: StationDemand(kind: .residential, dailyTrips: 100_000))
        world.setSpeed(.normal)
        try world.advance(ticks: 20)
        XCTAssertFalse(world.waitingPassengers(at: Self.alpha).isEmpty, "the line has no train: they wait")
        XCTAssertEqual(NetworkFlowReport(world: world).unmet(.waiting), [], "not half an hour yet")
        try world.advance(ticks: 30)
        let rows = NetworkFlowReport(world: world).unmet(.waiting)
        XCTAssertEqual(rows.first?.from, Self.alpha)
        XCTAssertEqual(rows.first?.to, Self.beta)
        XCTAssertGreaterThanOrEqual(rows.first?.longestWaitMinutes ?? 0, 30)
        XCTAssertFalse(rows.first?.bothWays ?? true)
        XCTAssertTrue(rows.first?.valueText(in: .english).hasSuffix("min") ?? false)
    }

    func testTheReportLeavesTheWorldAlone() throws {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 60)
        let before = world
        _ = NetworkFlowReport(world: world)
        XCTAssertEqual(world, before)
    }

    // MARK: - On the map

    func testThePairsRegionHoldsBothStationsWithAMargin() throws {
        let world = try threeStations()
        let region = try XCTUnwrap(NetworkFlowReport.region(from: Self.gamma, to: Self.alpha, in: world))
        XCTAssertLessThan(region.minX, 20_000)
        XCTAssertGreaterThan(region.maxX, 300_000)
        XCTAssertLessThan(region.minY, 50_000)
        XCTAssertGreaterThan(region.maxY, 50_000)
        XCTAssertNil(NetworkFlowReport.region(from: Self.alpha, to: StationID(rawValue: 99), in: world))
    }

    @MainActor
    func testTappingARowAsksTheMapToShowThePair() throws {
        let session = GameSession(world: try threeStations())
        session.lookOver(from: Self.alpha, to: Self.gamma)
        let request = try XCTUnwrap(session.cameraRequest)
        XCTAssertEqual(request.location, PlanPoint(x: 160_000, y: 50_000))
        XCTAssertNotNil(request.region)
    }

    @MainActor
    func testTheLinesPanelOffersTheReportOnceALineIsMade() throws {
        var world = try threeStations()
        XCTAssertFalse(GameSession(world: world).showsNetworkFlowReport, "nothing to analyse yet")
        try world.createLine(named: "Main", stops: [Self.alpha, Self.beta])
        XCTAssertTrue(GameSession(world: world).showsNetworkFlowReport)
    }

    func testTheHelpGuideSaysWhereTheReportIs() {
        XCTAssertTrue(HelpGuide.entries(matching: "路網分析").contains { $0.id == "networkFlow" })
        XCTAssertTrue(HelpGuide.entries(matching: "unmet demand").contains { $0.id == "networkFlow" })
    }
}
