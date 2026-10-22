import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 194, later: the line card's one-tap fixes, each a
/// command the log keeps that changes the world as it says (and, refused,
/// leaves it as it was), and the station master naming the line that loses
/// most and why.
@MainActor
final class LineLossFixesTests: XCTestCase {
    private static let line = LineID(rawValue: 1)

    // MARK: Worlds

    /// Decision 137's line between the first two towns (seed 1), one train
    /// of four cars, with money to spend.
    private func lineBetweenTwoTowns(money: Int64 = 10_000_000_000) throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        world.economy.earn(Money(money))
        return world
    }

    /// The same line given `spare` more trains it does not run, which cost
    /// their keep all the same: too many trains, over two settled days. Two
    /// stations more, off the line, so it is not a short first railway
    /// (decision 177's advice comes first on one).
    private func tooManyTrains(spare: Int = 60) throws -> GameWorld {
        var world = try lineBetweenTwoTowns()
        for index in 0..<spare {
            let train = try world.purchaseTrain(named: "Spare \(index)").id
            try world.setTrainCars(train, to: 4)
            try world.assignTrain(train, to: Self.line)
        }
        for (index, x) in [Int64(1_000), 2_000].enumerated() {
            try world.buildStation(named: "Far \(index)", at: PlanPoint(x: x, y: 1_000))
        }
        try world.advance(ticks: 1 + 2 * 1_440)
        return world
    }

    private func editNames(_ session: GameSession) -> [String] {
        session.commandLog.entries.compactMap { entry in
            if case .command(.edit(let edit)) = entry.action { return edit.name }
            return nil
        }
    }

    // MARK: Too many trains

    func testTakingATrainOffTheLine() throws {
        let world = try tooManyTrains()
        XCTAssertEqual(world.lineLossDiagnosis(Self.line)?.reasons.map(\.kind), [.tooManyTrains])
        let last = try XCTUnwrap(world.line(id: Self.line)?.assignedTrains.last)
        let fix = try XCTUnwrap(world.lineLossFix(.tooManyTrains, on: Self.line))
        XCTAssertEqual(fix, .takeOffTrain(last, name: "Spare 59"))
        XCTAssertEqual(fix.kind, .tooManyTrains)
        XCTAssertEqual(fix.cost, .zero)

        let session = GameSession(world: world)
        session.applyLineLossFix(fix, to: Self.line)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world.line(id: Self.line)?.assignedTrains.count, 60)
        XCTAssertNil(session.world.assignedLine(of: last))
        XCTAssertNotNil(session.world.train(id: last), "still the player's")
        XCTAssertEqual(editNames(session).last, "unassignTrain")

        // Again: it is off the line already, so refused, the world as it was.
        let before = session.world
        session.applyLineLossFix(fix, to: Self.line)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, before)
        XCTAssertEqual(session.commandLog.entries.last?.refused, true)
    }

    func testTheSelectedTrainIsTakenOffTheSameWay() throws {
        let session = GameSession(world: try lineBetweenTwoTowns())
        let train = try XCTUnwrap(session.world.line(id: Self.line)?.trains.first)
        session.selectTrain(train)
        session.unassignSelectedTrain()
        XCTAssertNil(session.world.assignedLine(of: train))
        XCTAssertEqual(session.message?.text, "Took \(session.world.train(id: train)!.name) off its line. A trip under way is finished.")
    }

    func testOneTrainIsNotTakenOff() throws {
        XCTAssertNil(try lineBetweenTwoTowns().lineLossFix(.tooManyTrains, on: Self.line))
    }

    // MARK: Trains too far apart

    func testRunningMoreTrainsBuysWhatTheShorterHeadwayLacks() throws {
        var world = try lineBetweenTwoTowns()
        // Under traffic control the single track holds one train (decision
        // 62), and no fix is offered: a shorter headway cannot be run.
        XCTAssertEqual(world.lineMaximumTrains(Self.line), 1)
        XCTAssertNil(world.lineLossFix(.longHeadway, on: Self.line))
        try world.setTrafficControl(false)
        let roundTrip = try XCTUnwrap(world.lineJourney(Self.line)?.roundTripMinutes)
        let fix = try XCTUnwrap(world.lineLossFix(.longHeadway, on: Self.line))
        // One train: a train every round trip, at every level it runs.
        let headway = try XCTUnwrap(LineLossFix.headways.last { $0 < roundTrip })
        let plan = try XCTUnwrap(world.lineStaffingPlan(Self.line, headway: headway, type: nil, cars: 4))
        guard case let .runMoreTrains(minutes, targets, buying, cost, _, cars) = fix else { return XCTFail("\(fix)") }
        XCTAssertEqual(minutes, headway)
        XCTAssertEqual(buying, plan.trains - 1)
        XCTAssertGreaterThan(buying, 0)
        XCTAssertEqual(cars, 4, "as the line's train")
        XCTAssertEqual(cost, Money(plan.pricePerTrain.amount * Int64(buying)))

        let session = GameSession(world: world)
        session.applyLineLossFix(fix, to: Self.line)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let line = try XCTUnwrap(session.world.line(id: Self.line))
        XCTAssertEqual(line.trains.count, plan.trains)
        XCTAssertEqual(line.targetHeadways, targets)
        XCTAssertEqual(targets.peak, headway)
        XCTAssertEqual(session.world.economy.balance, world.economy.balance - cost)
        XCTAssertEqual(editNames(session).last, "addLineTrains")
    }

    func testRunningMoreTrainsWithoutTheMoneyIsOffAndRefused() throws {
        var world = try lineBetweenTwoTowns(money: 0)
        try world.setTrafficControl(false)
        world.economy.settle(Money(-world.economy.balance.amount))
        let fix = try XCTUnwrap(world.lineLossFix(.longHeadway, on: Self.line))
        XCTAssertFalse(world.economy.canAfford(fix.cost))
        XCTAssertEqual(fix.shortOfMoneyText(in: .traditionalChinese), "錢不夠：需要 \(fix.cost.moneyText)。")

        let session = GameSession(world: world)
        session.applyLineLossFix(fix, to: Self.line)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, world)
        XCTAssertEqual(session.commandLog.entries.last?.refused, true)
    }

    // MARK: Trains run nearly empty

    func testRunningLessOftenLengthensTheHeadwayAStep() throws {
        let world = try lineBetweenTwoTowns()
        let roundTrip = try XCTUnwrap(world.lineJourney(Self.line)?.roundTripMinutes)
        let fix = try XCTUnwrap(world.lineLossFix(.lowLoad, on: Self.line))
        let headway = try XCTUnwrap(LineLossFix.headways.first { $0 > roundTrip })
        XCTAssertEqual(fix, .runLessOften(headway: headway, targets: TargetHeadways(peak: headway, offPeak: headway, low: headway)))

        let session = GameSession(world: world)
        session.applyLineLossFix(fix, to: Self.line)
        XCTAssertEqual(session.world.line(id: Self.line)?.targetHeadways.peak, headway)
        XCTAssertEqual(session.world.lineHeadway(Self.line, at: .peak), headway)
        XCTAssertEqual(editNames(session).last, "setLineTargets")
        // A step further each time, until the last.
        let next = try XCTUnwrap(session.world.lineLossFix(.lowLoad, on: Self.line))
        guard case .runLessOften(let longer, _) = next else { return XCTFail("\(next)") }
        XCTAssertGreaterThan(longer, headway)

        // Refused (the line is gone): the world as it was.
        session.selectLine(Self.line)
        session.removeSelectedLine()
        let before = session.world
        session.applyLineLossFix(fix, to: Self.line)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, before)
    }

    func testEmptyRunningHasNoButton() throws {
        XCTAssertNil(try lineBetweenTwoTowns().lineLossFix(.emptyRuns, on: Self.line))
    }

    /// Decision 209: empty running on a line with a depot moves it to a
    /// depot nearer the line's ends, and with none nearer keeps the trains
    /// at the ends; each is the command the log keeps.
    func testEmptyRunningToADepotMovesItOrKeepsTheTrainsAtTheEnds() throws {
        var world = try lineBetweenTwoTowns()
        let first = try XCTUnwrap(world.line(id: Self.line)?.stops.first.flatMap { world.station(id: $0) })
        let far = try world.buildStation(named: "Far Depot", at: PlanPoint(x: first.point.x + 40_000, y: first.point.y)).id
        try world.setStationDepot(far, to: true)
        try world.setLineDepot(Self.line, to: far)
        XCTAssertEqual(world.lineLossFix(.emptyRuns, on: Self.line), .keepTrainsAtEnds(depots: ["Far Depot"]))
        let near = try world.buildStation(named: "Near Depot", at: PlanPoint(x: first.point.x + 2_000, y: first.point.y)).id
        try world.setStationDepot(near, to: true)
        let fix = try XCTUnwrap(world.lineLossFix(.emptyRuns, on: Self.line))
        XCTAssertEqual(fix, .useNearerDepot(near, name: "Near Depot"))
        XCTAssertEqual(fix.kind, .emptyRuns)
        XCTAssertEqual(fix.title(in: .traditionalChinese), "改用機廠「Near Depot」")
        let session = GameSession(world: world)
        session.applyLineLossFix(fix, to: Self.line)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world.line(id: Self.line)?.depot, near)
        XCTAssertEqual(session.world.line(id: Self.line)?.depots, [near, far], "the far one stays, for trains already in it")
        XCTAssertEqual(session.world.lineLossFix(.emptyRuns, on: Self.line), .keepTrainsAtEnds(depots: ["Near Depot", "Far Depot"]))
        session.applyLineLossFix(.keepTrainsAtEnds(depots: ["Near Depot", "Far Depot"]), to: Self.line)
        XCTAssertNil(session.world.line(id: Self.line)?.depot)
        XCTAssertEqual(editNames(session), ["setLineDepots", "setLineDepot"])
        XCTAssertNil(session.world.lineLossFix(.emptyRuns, on: Self.line))
    }

    /// Decision 221: a line with several depots keeps them all when a
    /// nearer one is added, and keeping the trains at the ends names every
    /// depot it stops using (the PR #627–#646 review).
    func testALineWithSeveralDepotsKeepsThemWhenANearerOneIsAdded() throws {
        var world = try lineBetweenTwoTowns()
        let first = try XCTUnwrap(world.line(id: Self.line)?.stops.first.flatMap { world.station(id: $0) })
        let east = try world.buildStation(named: "East Depot", at: PlanPoint(x: first.point.x + 40_000, y: first.point.y)).id
        let west = try world.buildStation(named: "West Depot", at: PlanPoint(x: first.point.x - 40_000, y: first.point.y)).id
        for depot in [east, west] { try world.setStationDepot(depot, to: true) }
        try world.setLineDepots(Self.line, to: [east, west])
        XCTAssertEqual(world.lineLossFix(.emptyRuns, on: Self.line), .keepTrainsAtEnds(depots: ["East Depot", "West Depot"]))
        XCTAssertEqual(
            LineLossFix.keepTrainsAtEnds(depots: ["East Depot", "West Depot"]).question(on: "Main", in: .traditionalChinese),
            "要讓「Main」的列車不再進出機廠「East Depot」「West Depot」嗎？列車改在路線兩端過夜，不用空車來回，但整天都要付能源與人事費。"
        )
        // Nearer than either.
        let near = try world.buildStation(named: "Near Depot", at: PlanPoint(x: first.point.x + 2_000, y: first.point.y)).id
        try world.setStationDepot(near, to: true)
        let fix = try XCTUnwrap(world.lineLossFix(.emptyRuns, on: Self.line))
        XCTAssertEqual(fix, .useNearerDepot(near, name: "Near Depot"))
        let session = GameSession(world: world)
        session.applyLineLossFix(fix, to: Self.line)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.line(id: Self.line)?.depots, [near, east, west])
        XCTAssertEqual(session.world.lineLossFix(.emptyRuns, on: Self.line), .keepTrainsAtEnds(depots: ["Near Depot", "East Depot", "West Depot"]))
    }

    func testTheMemoKeepsAFixForEachReason() throws {
        let session = GameSession(world: try tooManyTrains())
        let memo = LineLossMemo()
        XCTAssertEqual(memo.fixes(Self.line, of: session), [.tooManyTrains: session.world.lineLossFix(.tooManyTrains, on: Self.line)!])
        XCTAssertEqual(memo.workedOut, 1)
    }

    // MARK: Words

    func testEveryFixReadsInBothLanguages() {
        let train = LineLossFix.takeOffTrain(TrainID(rawValue: 3), name: "列車 3")
        let more = LineLossFix.runMoreTrains(headway: 10, targets: TargetHeadways(peak: 10), buying: 2, cost: Money(9_000), type: nil, cars: 1)
        let free = LineLossFix.runMoreTrains(headway: 10, targets: TargetHeadways(peak: 10), buying: 0, cost: .zero, type: nil, cars: 1)
        let less = LineLossFix.runLessOften(headway: 30, targets: TargetHeadways(peak: 30))
        XCTAssertEqual(train.title(in: .traditionalChinese), "撤下一列")
        XCTAssertEqual(train.title(in: .english), "Take off a train")
        XCTAssertEqual(more.title(in: .traditionalChinese), "加開 2 列 · \(Money(9_000).moneyText)")
        XCTAssertEqual(more.title(in: .english), "Add 2 trains · \(Money(9_000).moneyText)")
        XCTAssertEqual(free.title(in: .traditionalChinese), "班距縮短到 10 分")
        XCTAssertEqual(less.title(in: .traditionalChinese), "班距拉長到 30 分")
        XCTAssertEqual(less.title(in: .english), "A train every 30 min")
        for fix in [train, more, free, less] {
            XCTAssertTrue(fix.question(on: "藍線", in: .traditionalChinese).contains("「藍線」"))
            XCTAssertTrue(fix.question(on: "Blue", in: .english).contains("Blue"))
            XCTAssertFalse(fix.question(on: "Blue", in: .english).contains("「"))
        }
        XCTAssertEqual(LineLossReason.Kind.lowLoad.title(in: .traditionalChinese), "載客率低")
    }

    // MARK: The station master

    func testTheStationMasterNamesTheLineThatLosesMostAndWhy() throws {
        let world = try tooManyTrains()
        let advice = try XCTUnwrap(StationMasterAdvice(world: world))
        XCTAssertEqual(advice, .lineLosing(line: Self.line, name: "Line 1", reason: .tooManyTrains))
        XCTAssertEqual(advice.line, Self.line)
        XCTAssertTrue(advice.isWorry)
        XCTAssertEqual(advice.text(in: .traditionalChinese), "「Line 1」虧錢，主要是車太多：撤下一列試試。點一下打開路線。")
        XCTAssertEqual(advice.text(in: .english), "Line 1 loses money, mostly: too many trains. Try taking one off. Tap to open it.")
        XCTAssertEqual(advice.newsEntry?.target, .line(Self.line.rawValue))
        XCTAssertEqual(world.worstLosingLine()?.loss, Money(-(world.lineLossDiagnosis(Self.line)?.profit.amount ?? 0)))
        // Free play has no money to lose.
        var free = world
        free.setEconomyMode(.free)
        XCTAssertNil(free.worstLosingLine())
    }

    func testEachReasonSaysWhatToTry() {
        let said = LineLossReason.Kind.allCases.map {
            StationMasterAdvice.lineLosing(line: Self.line, name: "藍線", reason: $0).text(in: .traditionalChinese)
        }
        XCTAssertEqual(said, [
            "「藍線」虧錢，主要是車太多：撤下一列試試。點一下打開路線。",
            "「藍線」虧錢，主要是班距太長：加開列車試試。點一下打開路線。",
            "「藍線」虧錢，主要是空車回送太多：讓列車停在路線兩端試試。點一下打開路線。",
            "「藍線」虧錢，主要是載客率低：拉長班距試試。點一下打開路線。",
        ])
    }

    func testWithoutALosingLineItSaysNothingOfIt() throws {
        var world = try lineBetweenTwoTowns()
        for (index, x) in [Int64(1_000), 2_000].enumerated() {
            try world.buildStation(named: "Far \(index)", at: PlanPoint(x: x, y: 1_000))
        }
        try world.advance(ticks: 1 + 2 * 1_440)
        XCTAssertEqual(world.lineLossDiagnosis(Self.line)?.isLosing, false)
        XCTAssertNil(world.worstLosingLine())
        XCTAssertNil(StationMasterAdvice(world: world)?.line)
    }

    func testTheUrgentWorriesComeFirst() throws {
        var world = try tooManyTrains()
        world.economy.settle(Money(-world.economy.balance.amount - 1))
        XCTAssertEqual(StationMasterAdvice(world: world), .inDebt)
    }

    func testTheSessionWorksTheLineOutForACommandOrANewDayOnly() throws {
        var world = try tooManyTrains()
        world.setSpeed(.normal)
        let session = GameSession(world: world)
        XCTAssertEqual(session.worstLosingLine, world.worstLosingLine())
        XCTAssertEqual(session.worstLosingLineWorkedOut, 1)
        for _ in 1...10 {
            session.advance(realElapsed: GameSession.tickInterval)
            _ = session.worstLosingLine
        }
        XCTAssertEqual(session.worstLosingLineWorkedOut, 1, "ten minutes of one day")
        session.selectLine(Self.line)
        session.setSelectedLineColor(LineColor.presets[0])
        XCTAssertEqual(session.worstLosingLine, session.world.worstLosingLine())
        XCTAssertEqual(session.worstLosingLineWorkedOut, 2)
    }

    /// Decision 330: the game loop works the station master's advice out
    /// with the tick, off the main actor, and the news, the advice and
    /// the losing line kept come out as when the main actor works it out
    /// after each tick: every hour, over a midnight (the losing line
    /// worked out again) and a command (the kept one no longer answering).
    func testTheLoopWorksTheAdviceOutOffTheMainActorAsTheMainActorDoes() async throws {
        var world = try tooManyTrains()
        world.setSpeed(.fast)
        let stepped = GameSession(world: world)
        let looped = GameSession(world: world)
        var worked = 0
        for index in 0..<200 {
            if index == 120 {
                for session in [stepped, looped] {
                    session.selectLine(Self.line)
                    session.setSelectedLineColor(LineColor.presets[1])
                }
            }
            stepped.advance(realElapsed: GameSession.tickInterval)
            let tick = try XCTUnwrap(looped.beginLoopTick())
            let outcome = await tick.work()
            if case .success(let step) = outcome, let advice = step.advice {
                worked += 1
                XCTAssertEqual(advice.advice, StationMasterAdvice(world: step.world), "tick \(index)")
            }
            XCTAssertTrue(looped.finish(tick, with: outcome))
            XCTAssertEqual(looped.world, stepped.world, "tick \(index)")
            XCTAssertEqual(looped.news, stepped.news, "tick \(index)")
            XCTAssertEqual(looped.newsWatch.adviceDays, stepped.newsWatch.adviceDays, "tick \(index)")
            XCTAssertEqual(looped.worstLosingLineWorkedOut, stepped.worstLosingLineWorkedOut, "tick \(index)")
        }
        // An hour is six ticks at 6000×: every one of them worked out off
        // the main actor.
        XCTAssertEqual(worked, 200 / 6 + 1)
        XCTAssertTrue(looped.news.items.contains { $0.english?.hasPrefix("Line 1 loses money") == true })
        // The first, a midnight and the colour changed.
        XCTAssertEqual(looped.worstLosingLineWorkedOut, 3)
        XCTAssertEqual(looped.worstLosingLine, looped.world.worstLosingLine())
    }
}
