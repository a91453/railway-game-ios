import GameCore
import GamePresentation
import XCTest

/// A refusal for want of cash (a TestFlight report: 「新建月台時不會獲取最新
/// 金錢數據」): it names what was refused, says the cash the player has and
/// what the whole command takes, in whole dollars as the cash shows them,
/// and goes once the cash covers it, rather than staying with out of date
/// figures while the game runs at speed.
@MainActor
final class InsufficientFundsTests: XCTestCase {
    // MARK: - A new station's platform on a grade

    private static let costs = ConstructionCosts(track: 100, station: 1_000, train: 5_000)
    private static let row: Int64 = 2_048

    /// 64 × 64 cells with ground climbing from 10 m to 15 m along the
    /// first block's columns, as `TerrainPresentationTests` has it, and
    /// track built along it from 16 m to 272 m in, on a grade.
    private func gradedTrack(balance: Int64) throws -> GameSession {
        var world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: Money(balance), costs: Self.costs),
            clock: GameClock(speed: .paused)
        )
        let side = GroundBlock.side
        let columns = [10, 15]
        let heights = (0..<side).flatMap { _ in (0..<side).map { Int16(columns[min($0, columns.count - 1)]) } }
        try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights)!])
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 1_024, y: Self.row), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 17_408, y: Self.row), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: 9_216, y: Self.row), reach: 16)
        return session
    }

    /// Enough cash to level the stretch but not for the station after it:
    /// GameCore refuses the station with the cash left after the
    /// levelling, part way through the command. The refusal says the cash
    /// the player has and what levelling and station take together, the
    /// price ✓ shows.
    func testANewStationsPlatformSaysTheCashThePlayerHasAndTheWholePrice() throws {
        let probe = try gradedTrack(balance: 100_000_000)
        let levelling = try XCTUnwrap(probe.networkPlatformLevelling?.cost)
        let spentOnTrack = 100_000_000 - probe.world.economy.balance.amount
        XCTAssertEqual(probe.networkPlatformCost, levelling + Self.costs.station, "✓ shows the station's price with the levelling")

        // The cash covers the levelling and half the station.
        let cash = levelling.amount + Self.costs.station.amount / 2
        let session = try gradedTrack(balance: spentOnTrack + cash)
        XCTAssertEqual(session.world.economy.balance, Money(cash))
        let before = session.world
        let total = levelling + Self.costs.station
        XCTAssertEqual(session.networkPlatformCost, total)

        session.stationName = "Dazhi"
        session.addNetworkPlatform()
        XCTAssertEqual(session.world, before, "all or nothing")
        let (required, available) = Money.shortfallTexts(required: total, available: Money(cash))
        XCTAssertEqual(
            session.message,
            StatusMessage(
                kind: .failure,
                text: "Not enough cash to build station “Dazhi” and its platform: it costs \(required) and you have \(available).",
                fundsNeeded: total
            )
        )
        XCTAssertEqual(available, Money(cash).moneyText, "the cash the player has, in whole dollars as the cash shows it")
    }

    // MARK: - The refusal goes once the cash covers it

    /// GameFeedbackTests' line: a train earning fares, settled each hour.
    private func earningWorld(balance: Int64) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: Money(balance), speed: .normal)
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
        return world
    }

    func testARefusalForWantOfCashGoesOnceTheCashCoversIt() throws {
        let setUp = 100_000_000 - (try earningWorld(balance: 100_000_000)).economy.balance.amount
        let session = GameSession(world: try earningWorld(balance: setUp + 4_000))
        let price = session.world.purchaseCost(of: nil, cars: 1)
        XCTAssertEqual(price, Money(5_000))

        session.purchaseTrain()
        XCTAssertEqual(
            session.message,
            StatusMessage(kind: .failure, text: "Not enough cash to buy a train: it costs $ 50 and you have $ 40.", fundsNeeded: price)
        )
        // Within the first hour nothing is settled: still short, and said.
        for _ in 0..<30 { session.advance(realElapsed: GameSession.tickInterval) }
        XCTAssertFalse(session.world.economy.canAfford(price))
        XCTAssertEqual(session.message?.fundsNeeded, price)
        // The hour's fares cover the train: the refusal is out of date.
        for _ in 0..<31 { session.advance(realElapsed: GameSession.tickInterval) }
        XCTAssertTrue(session.world.economy.canAfford(price), "the test needs the fares")
        XCTAssertNil(session.message)
    }

    // MARK: - The figures

    func testWholeDollarsUnlessRoundingHidesTheShortfall() {
        XCTAssertEqual(GameError.insufficientFunds(required: Money(20_000_000), available: Money(14_154_046)).playerMessage(in: .traditionalChinese),
                       "餘額不足：需要 $ 200,000，目前只有 $ 141,540。")
        XCTAssertEqual(GameError.insufficientFundsText(required: Money(1_000), available: Money(999), doing: "buy a train", in: .english),
                       "Not enough cash to buy a train: it costs $ 10.00 and you have $ 9.99.")
        XCTAssertEqual(GameError.insufficientFundsText(required: Money(20_000_000), available: Money(14_154_046), doing: "買列車", in: .traditionalChinese),
                       "餘額不足，無法買列車：需要 $ 200,000，目前只有 $ 141,540。")
    }
}
