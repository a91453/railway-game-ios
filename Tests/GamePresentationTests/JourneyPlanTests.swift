import GameCore
import GamePresentation
import XCTest

/// Decision 423: the options for riding from one station to another, from
/// the routes and fares GameCore gives the passengers.
final class JourneyPlanTests: XCTestCase {
    // One straight edge east along y = 50,000, with a station 100,000 units
    // (about 1.6 km, beyond the walk between stations) from the next.
    private static let edge = TrackEdgeID.edge(1)

    private struct Network {
        var world: GameWorld
        let alpha: StationID, beta: StationID, gamma: StationID, delta: StationID
    }

    /// Alpha, Beta, Gamma and Delta along one edge, a management company;
    /// no lines yet.
    private func network() throws -> Network {
        var world = try makeWorld(width: 600_000, height: 100_000, balance: 100_000_000)
        let start = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 50_000))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 420_000, y: 50_000))
        try world.buildTrackEdge(from: start, to: end)
        var ids: [StationID] = []
        for (index, name) in ["Alpha", "Beta", "Gamma", "Delta"].enumerated() {
            let x = Int64(20_000 + index * 100_000)
            let station = try world.buildStation(named: name, at: PlanPoint(x: x, y: 51_000)).id
            try world.addTrackPlatform(station, on: Self.edge, from: x - 2_000, to: x + 2_000)
            ids.append(station)
        }
        world.setEconomyMode(.management)
        return Network(world: world, alpha: ids[0], beta: ids[1], gamma: ids[2], delta: ids[3])
    }

    /// A line with trains in service all day.
    @discardableResult
    private func addLine(_ name: String, stops: [StationID], to world: inout GameWorld) throws -> LineID {
        let line = try world.createLine(named: name, stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        return line
    }

    // MARK: - Direct

    func testADirectRideHasOneLegItsMinutesAndTheGameFare() throws {
        var net = try network()
        let line = try addLine("Coast Line", stops: [net.alpha, net.beta], to: &net.world)
        let plan = JourneyPlan(world: net.world, from: net.alpha, to: net.beta)
        XCTAssertNil(plan.absence)
        XCTAssertNil(plan.message(in: .english))
        let option = try XCTUnwrap(plan.options.first)
        XCTAssertEqual(option.transfers, 0)
        XCTAssertEqual(option.legs.map(\.line), [line])
        XCTAssertEqual(option.legs.map(\.lineName), ["Coast Line"])
        XCTAssertEqual(option.legs.map(\.fromName), ["Alpha"])
        XCTAssertEqual(option.legs.map(\.toName), ["Beta"])
        XCTAssertEqual(option.legs[0].text, "Coast Line: Alpha → Beta")
        XCTAssertFalse(option.legs[0].walksFromPrevious)
        XCTAssertGreaterThan(option.rideMinutes, 0)
        XCTAssertGreaterThan(option.waitMinutes, 0)
        XCTAssertEqual(option.transferMinutes, 0)
        XCTAssertEqual(option.walkMinutes, 0)
        XCTAssertEqual(option.totalMinutes, option.rideMinutes + option.waitMinutes)
        // The same routes and fares the passengers get.
        let route = try XCTUnwrap(net.world.passengerRoutes(from: net.alpha, to: net.beta).first)
        XCTAssertEqual(option.totalMinutes, route.totalMinutes)
        XCTAssertEqual(option.fare, net.world.tripFare(from: net.alpha, to: net.beta))
        XCTAssertEqual(option.fare, FareRules.standardFare, "the standard flat fare until the player sets one")
        XCTAssertEqual(option.fareText, "$ 5.00")
        XCTAssertEqual(option.transfersText(in: .english), "Direct")
        XCTAssertEqual(option.transfersText(in: .traditionalChinese), "直達")
        XCTAssertEqual(option.totalText(in: .english), "\(option.totalMinutes) min")
        XCTAssertEqual(option.linesText, "Coast Line")
    }

    func testTheFareFollowsTheFareRulesAndFreePlayHasNone() throws {
        var net = try network()
        try addLine("Coast Line", stops: [net.alpha, net.beta], to: &net.world)
        try net.world.setFareRules(.flat(Money(800)))
        var option = try XCTUnwrap(JourneyPlan(world: net.world, from: net.alpha, to: net.beta).options.first)
        XCTAssertEqual(option.fare, Money(800))
        XCTAssertEqual(option.fareText, "$ 8.00")

        net.world.setEconomyMode(.free)
        option = try XCTUnwrap(JourneyPlan(world: net.world, from: net.alpha, to: net.beta).options.first)
        XCTAssertNil(option.fare, "nobody pays in free play")
        XCTAssertNil(option.fareText)
    }

    // MARK: - One transfer

    func testAChangeBetweenTwoLinesIsOneTransferWithItsMinutes() throws {
        var net = try network()
        let first = try addLine("First", stops: [net.alpha, net.beta], to: &net.world)
        let second = try addLine("Second", stops: [net.beta, net.gamma], to: &net.world)
        let plan = JourneyPlan(world: net.world, from: net.alpha, to: net.gamma)
        let option = try XCTUnwrap(plan.options.first)
        XCTAssertEqual(option.transfers, 1)
        XCTAssertEqual(option.legs.map(\.line), [first, second])
        XCTAssertEqual(option.legs.map(\.fromName), ["Alpha", "Beta"])
        XCTAssertEqual(option.legs.map(\.toName), ["Beta", "Gamma"])
        XCTAssertEqual(option.legs.map(\.walksFromPrevious), [false, false], "the change is at Beta")
        XCTAssertGreaterThan(option.transferMinutes, 0)
        XCTAssertEqual(option.totalMinutes, option.rideMinutes + option.waitMinutes + option.transferMinutes + option.walkMinutes)
        XCTAssertEqual(option.transfersText(in: .english), "1 transfer")
        XCTAssertEqual(option.transfersText(in: .traditionalChinese), "轉乘 1 次")
        XCTAssertEqual(option.linesText, "First → Second")
        // The fare is for Alpha to Gamma, not a fare for each ride.
        XCTAssertEqual(option.fare, net.world.tripFare(from: net.alpha, to: net.gamma))
        XCTAssertTrue(option.breakdownText(in: .english).contains("changing"))
        XCTAssertTrue(option.breakdownText(in: .traditionalChinese).contains("轉乘 \(option.transferMinutes) 分"))
        XCTAssertEqual(plan.options.count, 1, "no other way")
        XCTAssertEqual(Set(plan.options.map(\.id)).count, plan.options.count)
    }

    func testAJourneyAlsoReadsTheOtherWayAndHoldsAtMostThreeOptions() throws {
        var net = try network()
        try addLine("First", stops: [net.alpha, net.beta], to: &net.world)
        try addLine("Second", stops: [net.beta, net.gamma], to: &net.world)
        // A second way from Alpha to Gamma and a third.
        try addLine("Direct", stops: [net.alpha, net.gamma], to: &net.world)
        try addLine("Express", stops: [net.alpha, net.gamma], to: &net.world)
        let plan = JourneyPlan(world: net.world, from: net.gamma, to: net.alpha)
        XCTAssertLessThanOrEqual(plan.options.count, 3)
        XCTAssertGreaterThanOrEqual(plan.options.count, 2)
        XCTAssertEqual(plan.options.map(\.totalMinutes), plan.options.map(\.totalMinutes).sorted(), "quickest first")
        XCTAssertEqual(plan.options.first?.legs.first?.fromName, "Gamma")
        XCTAssertEqual(plan.options.first?.legs.last?.toName, "Alpha")
    }

    // MARK: - Nothing to show

    func testStationsNoLineJoinsHaveNoOptionAndASentenceInBothLanguages() throws {
        var net = try network()
        try addLine("Coast Line", stops: [net.alpha, net.beta], to: &net.world)
        let plan = JourneyPlan(world: net.world, from: net.alpha, to: net.delta)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.absence, .noRoute)
        XCTAssertNotNil(plan.message(in: .english))
        XCTAssertNotNil(plan.message(in: .traditionalChinese))

        // A line with no trains in service takes nobody anywhere.
        try net.world.setLineTrainsInService(try XCTUnwrap(net.world.lines.first).id, to: .none)
        XCTAssertEqual(JourneyPlan(world: net.world, from: net.alpha, to: net.beta).absence, .noRoute)
    }

    func testTheSameStationAnUnknownOneAndNoLinesAreNamed() throws {
        let net = try network()
        let same = JourneyPlan(world: net.world, from: net.alpha, to: net.alpha)
        XCTAssertTrue(same.isEmpty)
        XCTAssertEqual(same.absence, .sameStation)

        let unknown = JourneyPlan(world: net.world, from: net.alpha, to: StationID(rawValue: 99))
        XCTAssertEqual(unknown.absence, .unknownStation)

        let noLines = JourneyPlan(world: net.world, from: net.alpha, to: net.beta)
        XCTAssertTrue(noLines.isEmpty)
        XCTAssertEqual(noLines.absence, .noLines)

        for absence in JourneyPlan.Absence.allCases {
            XCTAssertFalse(absence.text(in: .english).isEmpty, "\(absence)")
            XCTAssertFalse(absence.text(in: .traditionalChinese).isEmpty, "\(absence)")
            XCTAssertNotEqual(absence.text(in: .english), absence.text(in: .traditionalChinese), "\(absence)")
        }
        XCTAssertEqual(noLines.message(in: .english), JourneyPlan.Absence.noLines.text(in: .english))
    }

    func testAnEmptyWorldHasNoStationsToPlanBetween() {
        let plan = JourneyPlan(world: .newGame(), from: StationID(rawValue: 1), to: StationID(rawValue: 2))
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.absence, .unknownStation)
    }
}

// MARK: - The station panel's rows (decision 423, second step)

extension JourneyPlanTests {
    func testADirectRowIsThreeLinesInBothLanguages() throws {
        var net = try network()
        try addLine("Coast Line", stops: [net.alpha, net.beta], to: &net.world)
        let option = try XCTUnwrap(JourneyPlan(world: net.world, from: net.alpha, to: net.beta).options.first)
        let english = option.rows(in: .english)
        XCTAssertEqual(english.headline, "\(option.totalMinutes) min · Direct · $ 5.00")
        XCTAssertEqual(english.lines, "Coast Line")
        XCTAssertEqual(english.breakdown, "\(option.rideMinutes) min riding · \(option.waitMinutes) min waiting")
        XCTAssertEqual(english.legs.map(\.text), ["Coast Line: Alpha → Beta"])
        XCTAssertEqual(english.legs.map(\.walkText), [nil])
        XCTAssertEqual(english.spoken, "\(english.headline), Coast Line, \(english.breakdown)")
        let chinese = option.rows(in: .traditionalChinese)
        XCTAssertEqual(chinese.headline, "\(option.totalMinutes) 分鐘 · 直達 · $ 5.00")
        XCTAssertEqual(chinese.breakdown, "乘車 \(option.rideMinutes) 分 · 等車 \(option.waitMinutes) 分")
    }

    func testFreePlayRowHasNoFare() throws {
        var net = try network()
        try addLine("Coast Line", stops: [net.alpha, net.beta], to: &net.world)
        net.world.setEconomyMode(.free)
        let option = try XCTUnwrap(JourneyPlan(world: net.world, from: net.alpha, to: net.beta).options.first)
        XCTAssertEqual(option.rows(in: .english).headline, "\(option.totalMinutes) min · Direct")
    }

    func testARowWithAChangeAndAWalkSaysWhereToWalk() throws {
        var net = try network()
        // Beta and Gamma are 100,000 units apart; the lines meet at neither,
        // so the passenger walks only if GameCore lets them. Build the case
        // where a transfer group joins two stations on foot.
        try addLine("First", stops: [net.alpha, net.beta], to: &net.world)
        try addLine("Second", stops: [net.gamma, net.delta], to: &net.world)
        _ = try net.world.linkTransfer(net.beta, net.gamma)
        let plan = JourneyPlan(world: net.world, from: net.alpha, to: net.delta)
        let option = try XCTUnwrap(plan.options.first)
        XCTAssertEqual(option.transfers, 1)
        let english = option.rows(in: .english)
        XCTAssertEqual(english.lines, "First → Second")
        XCTAssertEqual(english.legs.map(\.walkText), [nil, "Walk to Gamma"])
        XCTAssertEqual(option.rows(in: .traditionalChinese).legs.map(\.walkText), [nil, "步行到 Gamma站"])
        XCTAssertTrue(english.headline.contains("1 transfer"))
        XCTAssertTrue(english.breakdown.contains("walking"))
    }

    func testAChineseStationNameThatEndsInStationGetsNoSecondOne() {
        XCTAssertEqual(JourneyPlan.Option.walkText(to: "台北車站", in: .traditionalChinese), "步行到 台北車站")
        XCTAssertEqual(JourneyPlan.Option.walkText(to: "台北", in: .traditionalChinese), "步行到 台北站")
        XCTAssertEqual(JourneyPlan.Option.walkText(to: "Taipei", in: .english), "Walk to Taipei")
    }

    func testNoRouteHasASentenceAndNoRows() throws {
        var net = try network()
        try addLine("Coast Line", stops: [net.alpha, net.beta], to: &net.world)
        let plan = JourneyPlan(world: net.world, from: net.alpha, to: net.delta)
        XCTAssertTrue(plan.options.isEmpty)
        XCTAssertEqual(plan.message(in: .english), JourneyPlan.Absence.noRoute.text(in: .english))
        XCTAssertEqual(JourneyPlan.findingText(in: .english), "Finding routes…")
        XCTAssertEqual(JourneyPlan.findingText(in: .traditionalChinese), "正在找路線…")
    }

    private func choices(_ world: GameWorld) -> [MenuChoice<StationID>] {
        world.stations.map { MenuChoice(id: $0.id, title: $0.name) }
    }

    func testDestinationsAreTheOtherStationsByNameAndCanBeSearched() throws {
        let net = try network()
        let all = choices(net.world)
        XCTAssertEqual(JourneyPlan.destinations(among: all, from: net.gamma).map(\.title), ["Alpha", "Beta", "Delta"])
        XCTAssertEqual(JourneyPlan.destinations(among: all, from: nil).map(\.title), ["Alpha", "Beta", "Delta", "Gamma"])
        XCTAssertEqual(JourneyPlan.destinations(among: all, from: net.gamma, matching: ListSearch("et")).map(\.title), ["Beta"])
        XCTAssertTrue(JourneyPlan.destinations(among: all, from: net.gamma, matching: ListSearch("zzz")).isEmpty)
    }

    func testNumbersInStationNamesSortByValue() throws {
        var world = try makeWorld(width: 600_000, height: 100_000, balance: 100_000_000)
        for (index, name) in ["Stop 10", "Stop 2", "Stop 1"].enumerated() {
            _ = try world.buildStation(named: name, at: PlanPoint(x: Int64(20_000 + index * 100_000), y: 51_000))
        }
        XCTAssertEqual(JourneyPlan.destinations(among: choices(world), from: nil).map(\.title), ["Stop 1", "Stop 2", "Stop 10"])
    }

    func testThePlanIsWorkedOutAgainOnlyWhenWhatItReadsChanges() throws {
        var net = try network()
        let line = try addLine("Coast Line", stops: [net.alpha, net.beta], to: &net.world)
        let before = JourneyPlan.Inputs(world: net.world, from: net.alpha, to: net.beta)
        XCTAssertEqual(before, JourneyPlan.Inputs(world: net.world, from: net.alpha, to: net.beta))
        XCTAssertNotEqual(before, JourneyPlan.Inputs(world: net.world, from: net.alpha, to: net.gamma))
        XCTAssertNotEqual(before, JourneyPlan.Inputs(world: net.world, from: net.beta, to: net.alpha))
        // Fewer trains, a new fare and a new line each change the options.
        var fewer = net.world
        try fewer.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        XCTAssertNotEqual(before, JourneyPlan.Inputs(world: fewer, from: net.alpha, to: net.beta))
        var dearer = net.world
        try dearer.setFareRules(.flat(Money(800)))
        XCTAssertNotEqual(before, JourneyPlan.Inputs(world: dearer, from: net.alpha, to: net.beta))
        var more = net.world
        try addLine("Second", stops: [net.beta, net.gamma], to: &more)
        XCTAssertNotEqual(before, JourneyPlan.Inputs(world: more, from: net.alpha, to: net.beta))
    }
}
