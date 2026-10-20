import GameCore
import GamePresentation
import XCTest

/// The economy panel's first card (City Transport Manager study 4.12, step
/// M0): today's fares, running costs and result, to the last full hour,
/// read from the hours settled so far, the same books the lines' first-day
/// row (#834) is a breakdown of.
@MainActor
final class TodayAccountTests: XCTestCase {
    /// A new game of simple rules with one line between its first two
    /// towns, opened with its train (decision 264), as a player would.
    private func runningGame() throws -> GameSession {
        var world = GameWorld.newGame(rules: .simple)
        world.setTourism(nil)
        let towns = Land.townCentres(seed: 1, in: world.bounds)
        let from = towns[0], to = towns[1]
        let platform = Int64(4) * world.platformCarLength
        let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
        let span = (dx * dx + dy * dy).squareRoot()
        func along(_ point: PlanPoint, _ metres: Double) -> WorldCoordinate {
            WorldCoordinate(x: point.x + Int64(dx / span * metres), y: point.y + Int64(dy / span * metres))
        }
        let start = try world.buildTrackNode(at: along(from, -Double(platform)))
        let end = try world.buildTrackNode(at: along(to, Double(platform)))
        let main = try world.buildTrackEdge(from: start, to: end)
        let length = world.trackEdge(main)?.length ?? 0
        let a = try world.buildStation(named: "A", at: from).id
        try world.addTrackPlatform(a, on: main, from: platform / 2, to: platform + platform / 2)
        let b = try world.buildStation(named: "B", at: to).id
        try world.addTrackPlatform(b, on: main, from: length - platform - platform / 2, to: length - platform / 2)
        let session = GameSession(world: world, language: .english)
        for stop in [a, b] {
            session.selectStation(stop)
            session.addSelectedStationToLineDraft()
        }
        session.createLineFromDraft()
        XCTAssertEqual(session.world.lines.first?.trains.count, 1, "the line opens with its train")
        return session
    }

    /// Runs `world` on to `minute` past `hour` of its next day.
    private func advance(_ world: inout GameWorld, toHour hour: Int64, minute: Int64 = 20) throws {
        let day = world.clock.now.seconds / GameTime.secondsPerDay + 1
        let target = day * GameTime.secondsPerDay + hour * GameTime.secondsPerHour + minute * GameTime.secondsPerMinute
        try world.advance(ticks: Int((target - world.clock.now.seconds) / GameTime.secondsPerMinute))
        XCTAssertEqual(world.clock.now.seconds, target)
    }

    func testTodayRunsToTheLastFullHourAndAddsUp() throws {
        var world = try runningGame().world
        try advance(&world, toHour: 14)
        let today = try XCTUnwrap(world.todayAccount())
        XCTAssertEqual(today.throughHour, 14)

        // The hours settled today, as the ledger wrote them.
        let day = world.clock.now.seconds / GameTime.secondsPerDay
        let account = try XCTUnwrap(world.accounts.days.first { $0.day == day })
        XCTAssertEqual(today.fareRevenue, account.fareRevenue)
        XCTAssertEqual(today.runningCost, account.operatingCost + account.maintenanceCost)
        XCTAssertGreaterThan(today.fareRevenue.amount, 0, "the line carried someone by 14:00")
        XCTAssertGreaterThan(today.runningCost.amount, 0)
        XCTAssertEqual(account.staffCost, .zero, "the day's staff are paid at midnight")
        XCTAssertEqual(account.energyCost, .zero, "and its energy")

        // The lines' first-day rows (#834) are a breakdown of the same hours.
        let lines = world.lineReports().compactMap(\.today)
        XCTAssertEqual(lines.reduce(Money.zero) { $0 + $1.fareRevenue }, today.fareRevenue)
        XCTAssertEqual(lines.reduce(Money.zero) { $0 + $1.cost }, today.runningCost)
        XCTAssertEqual(today.result, today.fareRevenue - today.runningCost)
    }

    func testTheCardsWords() throws {
        let today = TodayAccount(throughHour: 9, fareRevenue: Money(123_400), runningCost: Money(150_000))
        XCTAssertEqual(today.title(in: .english), "Today, to 09:00")
        XCTAssertEqual(today.title(in: .traditionalChinese), "今天（截至 09:00）")
        XCTAssertEqual(today.rows(in: .english).map(\.title), ["Fares", "Running costs", "Result"])
        XCTAssertEqual(today.rows(in: .english).map(\.value), ["$ 1,234", "-$ 1,500", "-$ 266"])
        XCTAssertEqual(today.rows(in: .traditionalChinese).map(\.title), ["票收", "營運成本", "結果"])
        XCTAssertEqual(today.note(in: .traditionalChinese), "每個整點入帳。人事、電費與其他每天的費用在午夜支付。")

        let gain = TodayAccount(throughHour: 18, fareRevenue: Money(500_000), runningCost: Money(120_000))
        XCTAssertEqual(gain.rows(in: .english).last?.value, "+$ 3,800")
        XCTAssertEqual(gain.title(in: .english), "Today, to 18:00")
    }

    /// Between midnight and one o'clock none of today's hours is settled:
    /// the card says so instead of three zeros.
    func testBeforeTheFirstHourIsSettled() throws {
        var world = try runningGame().world
        try advance(&world, toHour: 0, minute: 30)
        let today = try XCTUnwrap(world.todayAccount())
        XCTAssertFalse(today.hasSettledHours)
        XCTAssertEqual(today.fareRevenue, .zero, "yesterday's last hour belongs to yesterday")
        XCTAssertEqual(today.title(in: .traditionalChinese), "今天")
        XCTAssertTrue(today.rows(in: .english).isEmpty)
        XCTAssertEqual(today.note(in: .traditionalChinese), "今天還沒有入帳：票收和營運成本每個整點入帳一次。")
    }

    /// Free play charges no fares and pays nothing: no card.
    func testFreePlayHasNoCard() throws {
        var world = try runningGame().world
        world.setEconomyMode(.free)
        XCTAssertNil(world.todayAccount())
    }
}
