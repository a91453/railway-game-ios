import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 194: the line card's fares and four costs over the
/// report's days, and why a line that lost money over them did: at most
/// two of four reasons, each with its figure. One scenario a reason, none
/// without the line accounts' records, none for a line that made money,
/// and the panel's memo working it out for a command or a game day only.
@MainActor
final class LineLossDiagnosisTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)
    private static let short = LineID(rawValue: 1)

    // MARK: Worlds

    /// `BalanceReportTests`' first line: three stations through the first
    /// town on 448 m of track and one train of four cars, running all day.
    /// The stations stand too close for many to ride (decision 137), so its
    /// one train runs back and forth nearly empty and loses money.
    private func firstLine() throws -> GameWorld {
        var world = GameWorld.newGame()
        let tile = Int64(1_024)
        let cars = 4
        let platform = Int64(cars) * Train.carLength
        let x = GameWorld.newGameBounds.width / 2 - 16 * tile, y = GameWorld.newGameBounds.height / 2
        let west = try world.buildTrackNode(at: WorldCoordinate(x: x + 2 * tile, y: y))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: x + 30 * tile, y: y))
        let edge = try world.buildTrackEdge(from: west, to: east)
        var stops: [StationID] = []
        for middle in [tile + platform / 2, 14 * tile, 27 * tile - platform / 2] {
            let station = try world.buildStation(named: "S\(stops.count)", at: PlanPoint(x: x + 2 * tile + middle, y: y)).id
            try world.addTrackPlatform(station, on: edge, from: middle - platform / 2, to: middle + platform / 2)
            stops.append(station)
        }
        let line = try world.createLine(named: "Line 1", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Train 1").id
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: tile + platform))
        try world.setTrainContinuation(train, along: [], stoppingAt: tile + platform)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        return world
    }

    /// Decision 137's line that pays: the first town to the second (seed
    /// 1, 5.4 km), one train of four cars.
    private func lineBetweenTwoTowns() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        return try newGameLine(through: [towns[0], towns[1]])
    }

    /// Alpha and Beta with a line between them and no train, managed.
    private func lineWithoutTrains(accounts: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        try world.createLine(named: "Short", stops: [Self.alpha, Self.beta])
        world.setEconomyMode(.management)
        world.setLineAccounts(accounts)
        world.setSpeed(.normal)
        return world
    }

    /// A line of 12 stops and 3 trains of 4 cars over 30 days that none of
    /// the four reasons fits: a train every 30 minutes each way, trips
    /// taking on 108 thousandths of a train's room, its fullest departures
    /// 60% full, no empty running, and fares twice what the trains cost to
    /// keep. Each scenario changes what it is about.
    private func measures(
        boardings: Int64 = 300_000, deadhead: Int64 = 0, peak: Int64 = 600
    ) -> LineLossMeasures {
        LineLossMeasures(
            days: 30, fareRevenue: Money(150_000_000), boardings: boardings, departures: 23_760,
            trainDistance: 1_000_000, deadheadDistance: deadhead, peakLoadSum: peak * 30, trains: 3,
            seatsPerTrain: 1_280, trainKeepPerDay: Money(1_238_400), legsPerTrip: 11, serviceMinutes: 1_080
        )
    }

    /// A diagnosis of `measures` whose costs come to `cost` (all running
    /// the line), so it lost money when `cost` is more than its fares.
    private func diagnosis(_ measures: LineLossMeasures, cost: Money) -> LineLossDiagnosis {
        LineLossDiagnosis(
            line: Self.short, days: Int(measures.days), fareRevenue: measures.fareRevenue,
            operatingCost: cost, maintenanceCost: .zero, energyCost: .zero, staffCost: .zero, measures: measures
        )
    }

    // MARK: The four reasons

    func testTheFirstLineLosesMoneyRunningNearlyEmptyAndNothingElse() throws {
        var world = try firstLine()
        try world.advance(ticks: 1 + 3 * 1_440)
        let report = try XCTUnwrap(world.lineReport(Self.short))
        let diagnosis = try XCTUnwrap(world.lineLossDiagnosis(Self.short))

        // The report's days, its fares and its costs, item by item.
        XCTAssertEqual(diagnosis.days, 3)
        XCTAssertEqual(diagnosis.days, report.days.count)
        XCTAssertEqual(diagnosis.fareRevenue, report.totalFares)
        XCTAssertEqual(diagnosis.totalCost, report.totalCost)
        let tallies = world.lineDays(Self.short).filter { day in report.days.contains { $0.day == day.day } }.map(\.tally)
        XCTAssertEqual(diagnosis.cost(.operating), tallies.reduce(.zero) { $0 + $1.operatingCost })
        XCTAssertEqual(diagnosis.cost(.maintenance), tallies.reduce(.zero) { $0 + $1.maintenanceCost })
        XCTAssertEqual(diagnosis.cost(.energy), tallies.reduce(.zero) { $0 + $1.energyCost })
        XCTAssertEqual(diagnosis.cost(.staff), tallies.reduce(.zero) { $0 + $1.staffCost })
        XCTAssertTrue(diagnosis.isLosing)

        // Each departure ($75) carries some 13 riders ($5 each) on a train
        // of 1,280: the one reason. One train is not too many, a train
        // every 9 minutes is not far apart, and nothing runs empty.
        XCTAssertEqual(diagnosis.reasons.map(\.kind), [.lowLoad])
        guard case let .lowLoad(permille) = diagnosis.reasons.first else { return XCTFail("\(diagnosis.reasons)") }
        XCTAssertLessThan(permille, 20)
        XCTAssertEqual(diagnosis.measures.trains, 1)
        XCTAssertEqual(diagnosis.measures.headwayMinutes, 9)
        XCTAssertEqual(diagnosis.measures.emptyRunPermille, 0)
        XCTAssertNil(diagnosis.noReasonText(in: .english))
        XCTAssertEqual(diagnosis.reasons.first?.title(in: .traditionalChinese), "載客率低")
        XCTAssertTrue(try XCTUnwrap(diagnosis.reasons.first?.detail(in: .traditionalChinese)).contains("只佔列車定員的 1%"))

        // The bars: the fares first, then the four costs; operating, the
        // largest, is the longest.
        let bars = diagnosis.bars(in: .traditionalChinese)
        XCTAssertEqual(bars.map(\.id), ["fares", "operating", "maintenance", "energy", "staff"])
        XCTAssertEqual(bars.map(\.title), ["票收", "營運", "保養", "能源", "人事"])
        XCTAssertEqual(bars.first { $0.id == "operating" }?.permille, 1_000)
        XCTAssertTrue(bars.allSatisfy { $0.permille >= 0 && $0.permille <= 1_000 })
        XCTAssertEqual(bars[0].text, "票收 \(diagnosis.fareRevenue.moneyText)")
    }

    func testTooManyTrainsForTheRiders() throws {
        // The line between two towns, which makes money with its one train,
        // given 60 more of four cars it does not run: they cost their keep
        // all the same (decision 180) and the line loses money.
        var world = try lineBetweenTwoTowns()
        world.economy.earn(Money(10_000_000_000))
        for index in 0..<60 {
            let train = try world.purchaseTrain(named: "Spare \(index)").id
            try world.setTrainCars(train, to: 4)
            try world.assignTrain(train, to: Self.short)
        }
        try world.advance(ticks: 1 + 2 * 1_440)
        let diagnosis = try XCTUnwrap(world.lineLossDiagnosis(Self.short))
        XCTAssertTrue(diagnosis.isLosing)
        // Its trips are as full as ever, a train every 12 minutes: the one
        // reason is the trains.
        XCTAssertEqual(diagnosis.reasons.map(\.kind), [.tooManyTrains])
        guard case let .tooManyTrains(trains, riders) = diagnosis.reasons.first else { return XCTFail("\(diagnosis.reasons)") }
        XCTAssertEqual(trains, 61)
        XCTAssertEqual(riders, diagnosis.measures.boardings / (61 * 2))
        XCTAssertLessThan(diagnosis.fareRevenue.amount, LineLossDiagnosis.trainKeepMultiple * diagnosis.measures.trainKeepPerDay.amount * 2)
        XCTAssertTrue(try XCTUnwrap(diagnosis.reasons.first?.detail(in: .traditionalChinese)).hasPrefix("61 列車平均每列每天只載"))
    }

    func testTrainsTooFarApartAndFull() {
        // A train every 30 minutes each way, the fullest leaving 95% full.
        let full = measures(peak: 950)
        XCTAssertEqual(full.headwayMinutes, 30)
        let losing = diagnosis(full, cost: Money(200_000_000))
        XCTAssertTrue(losing.isLosing)
        XCTAssertEqual(losing.reasons, [.longHeadway(minutes: 30, peakPermille: 950)])
        XCTAssertEqual(losing.reasons.first?.title(in: .traditionalChinese), "班距太長")
        XCTAssertEqual(losing.reasons.first?.detail(in: .traditionalChinese),
                       "每個方向約 30 分鐘才一班，最擠的一班坐滿 95%：月台上的人等不到車。試著加開列車。")
        // As far apart, but with room on board: riders are not left behind.
        XCTAssertEqual(LineLossDiagnosis.reasons(for: measures(peak: 899)), [])
    }

    func testTooMuchEmptyRunning() {
        // Three tenths of the kilometres run empty.
        let empty = measures(deadhead: 300_000)
        let losing = diagnosis(empty, cost: Money(200_000_000))
        XCTAssertEqual(losing.reasons, [.emptyRuns(permille: 300)])
        XCTAssertEqual(losing.reasons.first?.title(in: .traditionalChinese), "空車回送太多")
        XCTAssertEqual(losing.reasons.first?.detail(in: .english),
                       "30% of the trains' kilometres run empty, paid for like the rest. Stop trains at the line's ends.")
        // A fifth is the threshold; under it, none.
        XCTAssertEqual(LineLossDiagnosis.reasons(for: measures(deadhead: 199_999)), [])
        XCTAssertEqual(LineLossDiagnosis.reasons(for: measures(deadhead: 200_000)), [.emptyRuns(permille: 200)])
    }

    // MARK: When there is no card, or no reason

    func testWithoutRecordsThereIsNoCard() throws {
        var off = try lineWithoutTrains(accounts: false)
        try off.advance(ticks: 2 * 1_440)
        XCTAssertNil(off.lineLossDiagnosis(Self.short), "no line accounts")

        var today = try lineWithoutTrains()
        try today.advance(ticks: 600)
        XCTAssertNil(today.lineLossDiagnosis(Self.short), "no completed day yet")

        var free = try lineWithoutTrains()
        free.setEconomyMode(.free)
        try free.advance(ticks: 2 * 1_440)
        XCTAssertNil(free.lineLossDiagnosis(Self.short), "free mode records nothing")

        XCTAssertNil(today.lineLossDiagnosis(LineID(rawValue: 9)), "no such line")
    }

    func testAFreightLineHasNoCard() throws {
        var world = try lineWithoutTrains()
        try world.advance(ticks: 1_440 + 10)
        XCTAssertNotNil(world.lineLossDiagnosis(Self.short))
        world.enableFreight()
        try world.setLineFreight(Self.short, to: true)
        XCTAssertNil(world.lineLossDiagnosis(Self.short), "its fares are not the line's")
    }

    func testALineWhoseTrainsDidNotRunSaysSo() throws {
        var world = try lineWithoutTrains()
        try world.advance(ticks: 1_440 + 10)
        let diagnosis = try XCTUnwrap(world.lineLossDiagnosis(Self.short))
        XCTAssertTrue(diagnosis.isLosing, "its stations cost money")
        XCTAssertEqual(diagnosis.fareRevenue, .zero)
        XCTAssertEqual(diagnosis.reasons, [])
        XCTAssertEqual(diagnosis.noReasonText(in: .traditionalChinese), "這段期間沒有列車開出：車站與路線的成本照付。")
    }

    func testALineThatMakesMoneyShowsNoReason() throws {
        var world = try lineBetweenTwoTowns()
        try world.advance(ticks: 1 + 2 * 1_440)
        let diagnosis = try XCTUnwrap(world.lineLossDiagnosis(Self.short))
        XCTAssertFalse(diagnosis.isLosing)
        XCTAssertEqual(diagnosis.reasons, [])
        XCTAssertNil(diagnosis.noReasonText(in: .english))
        XCTAssertEqual(diagnosis.bars(in: .english).first?.permille, 1_000, "the fares are the longest bar")
        // Nor would the figures, asked without the loss.
        XCTAssertEqual(LineLossDiagnosis.reasons(for: diagnosis.measures), [])
    }

    func testOnlyALosingLineGetsReasons() {
        let full = measures(peak: 950)
        XCTAssertEqual(diagnosis(full, cost: Money(100_000_000)).reasons, [], "fares $1.5M, costs $1M")
        XCTAssertEqual(diagnosis(full, cost: Money(150_000_000)).reasons, [], "breaking even is not losing")
        XCTAssertEqual(diagnosis(full, cost: Money(150_000_100)).reasons.map(\.kind), [.longHeadway])
        let none = diagnosis(measures(), cost: Money(200_000_000))
        XCTAssertEqual(none.reasons, [])
        XCTAssertEqual(none.noReasonText(in: .english)?.hasPrefix("None of the usual four"), true)
    }

    func testTheWorstTwoAreShownFirst() {
        // Empty running at 600 thousandths (three times its threshold),
        // trips taking on 36 (2.8 times under) and trains every 30 minutes
        // leaving 95% full (one and a half times over): the two worst.
        let three = measures(boardings: 100_000, deadhead: 600_000, peak: 950)
        XCTAssertEqual(three.tripFillPermille, 36)
        XCTAssertEqual(LineLossDiagnosis.reasons(for: three).count, LineLossDiagnosis.shownReasons)
        let reasons = diagnosis(three, cost: Money(200_000_000)).reasons
        XCTAssertEqual(reasons, [.emptyRuns(permille: 600), .lowLoad(permille: 36)])
    }

    // MARK: Text

    func testEveryReasonReadsInBothLanguages() {
        let reasons: [LineLossReason] = [
            .tooManyTrains(trains: 4, ridersPerTrain: 1_234), .longHeadway(minutes: 25, peakPermille: 1_040),
            .emptyRuns(permille: 250), .lowLoad(permille: 4),
        ]
        XCTAssertEqual(reasons.map(\.kind), LineLossReason.Kind.allCases)
        for reason in reasons {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                XCTAssertFalse(reason.title(in: language).isEmpty)
                XCTAssertFalse(reason.detail(in: language).isEmpty)
            }
        }
        XCTAssertTrue(reasons[0].detail(in: .traditionalChinese).contains("1,234 人次"))
        XCTAssertTrue(reasons[1].detail(in: .english).contains("104% full"))
        XCTAssertTrue(reasons[3].detail(in: .traditionalChinese).contains("不到 1%"))
        XCTAssertEqual(LineLossDiagnosis.percentText(9, in: .english), "under 1%")
        XCTAssertEqual(LineLossDiagnosis.percentText(10, in: .english), "1%")
        XCTAssertEqual(LineLossDiagnosis.percentText(104, in: .traditionalChinese), "10%")
        XCTAssertEqual(LineLossDiagnosis.percentText(105, in: .traditionalChinese), "11%")
        for cost in LineCost.allCases {
            XCTAssertFalse(cost.title(in: .english).isEmpty)
            XCTAssertFalse(cost.title(in: .traditionalChinese).isEmpty)
        }
        let one = diagnosis(measures(), cost: .zero)
        XCTAssertEqual(LineLossDiagnosis(line: Self.short, days: 1, fareRevenue: .zero, operatingCost: .zero, maintenanceCost: .zero,
                                         energyCost: .zero, staffCost: .zero, measures: measures()).spanText(in: .english),
                       "Fares and costs, last 1 day")
        XCTAssertEqual(one.spanText(in: .traditionalChinese), "票收與成本（最近 30 天）")
    }

    // MARK: The panel's memo

    func testTheMemoWorksItOutForACommandOrANewDayOnly() throws {
        var world = try firstLine()
        world.setSpeed(.normal)
        // Day 1, 23:40: one completed day.
        try world.advance(ticks: 1 + 1_440 + 23 * 60 + 40)
        let session = GameSession(world: world)
        session.selectLine(Self.short)
        let memo = LineLossMemo()
        XCTAssertEqual(memo.diagnosis(Self.short, of: session), session.world.lineLossDiagnosis(Self.short))
        XCTAssertEqual(memo.workedOut, 1)
        XCTAssertEqual(memo.diagnosis(Self.short, of: session)?.days, 1)

        // Game time on the same day: read back, not worked out again.
        for _ in 1...15 {
            session.advance(realElapsed: GameSession.tickInterval)
            XCTAssertEqual(memo.diagnosis(Self.short, of: session), session.world.lineLossDiagnosis(Self.short))
        }
        XCTAssertEqual(memo.workedOut, 1, "fifteen ticks, one day")

        // A command: worked out again.
        session.setSelectedLineColor(LineColor.presets[0])
        XCTAssertEqual(memo.diagnosis(Self.short, of: session), session.world.lineLossDiagnosis(Self.short))
        XCTAssertEqual(memo.workedOut, 2)

        // Midnight exactly: the report counts day 1 already, but its last
        // hour, energy and staff are settled at the start of the next
        // minute, so neither the diagnosis nor the memo counts it yet.
        for _ in 1...4 {
            session.advance(realElapsed: GameSession.tickInterval)
            _ = memo.diagnosis(Self.short, of: session)
        }
        XCTAssertEqual(session.world.clock.now.seconds % GameTime.secondsPerDay, 0, "the test needs midnight exactly")
        XCTAssertEqual(session.world.lineReport(Self.short)?.days.count, 2)
        XCTAssertEqual(session.world.lineLossDiagnosis(Self.short)?.days, 1)
        XCTAssertEqual(memo.diagnosis(Self.short, of: session)?.days, 1)
        XCTAssertEqual(memo.workedOut, 2)

        // A minute on, day 1 is settled: worked out again, a day longer, and
        // read back for the rest of the day.
        session.advance(realElapsed: GameSession.tickInterval)
        XCTAssertEqual(memo.diagnosis(Self.short, of: session)?.days, 2)
        XCTAssertEqual(memo.workedOut, 3)
        for _ in 1...10 {
            session.advance(realElapsed: GameSession.tickInterval)
            XCTAssertEqual(memo.diagnosis(Self.short, of: session), session.world.lineLossDiagnosis(Self.short))
        }
        XCTAssertEqual(memo.workedOut, 3)
        let settled = try XCTUnwrap(session.world.lineLossDiagnosis(Self.short))
        let report = try XCTUnwrap(session.world.lineReport(Self.short))
        XCTAssertEqual(settled.totalCost, report.totalCost, "a settled day is the report's")

        // Another line, or another session, is its own.
        XCTAssertNil(memo.diagnosis(LineID(rawValue: 9), of: session))
        XCTAssertEqual(memo.workedOut, 4)
        let other = GameSession(world: session.world)
        XCTAssertEqual(memo.diagnosis(Self.short, of: other), other.world.lineLossDiagnosis(Self.short))
        XCTAssertEqual(memo.workedOut, 5)
    }
}
