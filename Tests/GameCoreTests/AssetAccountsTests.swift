import Foundation
@testable import GameCore
import XCTest

/// Phase 7a (ARCHITECTURE decision 85): what each track edge, station, train
/// and car cost, written down straight-line over its life every managed
/// midnight, written off when removed, the balance sheet and the year-end
/// closing. Every expectation is worked out by hand, in cents.
final class AssetAccountsTests: XCTestCase {
    /// Track $90 a 16 m, so the 128 m edge is $720; a station $7,200; a
    /// train $3,600; a car $360. Over 20 years (7200 days) the edge is
    /// written down 10 cents a day and the station 100; over 10 years (3600
    /// days) the train 100 and two cars 20.
    private static let costs = ConstructionCosts(track: 9_000, station: 720_000, train: 360_000, car: 36_000)
    private static let start = Money(10_000_000)

    private func world(managed: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 16_384, height: 8_192), economy: GameEconomy(balance: Self.start, costs: Self.costs),
            clock: GameClock(speed: .normal)
        )
        if managed { world.setEconomyMode(.management) }
        return world
    }

    /// An edge 8192 units long, a station and a train of three cars.
    private func build(_ world: inout GameWorld) throws -> (edge: TrackEdgeID, station: StationID, train: TrainID) {
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 4_096))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 4_096))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let station = try world.buildStation(named: "West", at: PlanPoint(x: 2_048, y: 2_048)).id
        let train = try world.purchaseTrain(named: "T1").id
        try world.setTrainCars(train, to: 3)
        return (edge, station, train)
    }

    func testPurchasesAreRecordedAtTheirCostAndPaidAsInvesting() throws {
        var world = try world()
        let (edge, station, train) = try build(&world)
        XCTAssertEqual(world.accounts.assets.map(\.kind), [.track, .station, .train, .cars])
        XCTAssertEqual(world.accounts.assets.map(\.owner), [edge.networkNumber!, station.rawValue, train.rawValue, train.rawValue])
        XCTAssertEqual(world.accounts.assets.map(\.cost), [72_000, 720_000, 360_000, 72_000])
        XCTAssertEqual(world.accounts.assets.last?.cars, 2)

        let sheet = world.balanceSheet()
        XCTAssertEqual(sheet.cash, Self.start - Money(1_224_000))
        XCTAssertEqual(sheet.track, AssetClassBalance(cost: 72_000, depreciation: .zero))
        XCTAssertEqual(sheet.stations, AssetClassBalance(cost: 720_000, depreciation: .zero))
        XCTAssertEqual(sheet.rollingStock, AssetClassBalance(cost: 432_000, depreciation: .zero))
        // Buying turns cash into assets: what the company is worth stays.
        XCTAssertEqual(sheet.equity, Self.start)
        XCTAssertEqual(world.unrecordedAssetCount(), 0)

        let today = world.financeReport(.day).current
        XCTAssertEqual(today.capitalSpending, 1_224_000)
        XCTAssertEqual(today.investingCashFlow, -1_224_000)
        XCTAssertEqual(today.netCashFlow, -1_224_000)
        XCTAssertEqual(today.netProfit, .zero, "a purchase is no loss")
        XCTAssertNil(world.accountsProblem())
    }

    func testEveryManagedMidnightWritesTheAssetsDown() throws {
        var world = try world()
        _ = try build(&world)
        // Midnight is settled at the start of the minute from it.
        try world.advance(ticks: 1_441)
        XCTAssertEqual(world.accounts.assets.map(\.depreciation), [10, 100, 100, 20])
        XCTAssertEqual(world.accounts.assets.map(\.days), [1, 1, 1, 1])
        let yesterday = world.financeReport(.day).previous
        XCTAssertEqual(yesterday.depreciationCost, 230)
        XCTAssertEqual(yesterday.netProfit, -230)
        XCTAssertEqual(yesterday.operatingCashFlow, .zero, "depreciation pays no cash")
        let sheet = world.balanceSheet()
        XCTAssertEqual(sheet.fixedAssets, Money(1_224_000 - 230))
        XCTAssertEqual(sheet.equity, Self.start - Money(230))
        XCTAssertEqual(sheet.totalAssets, sheet.loan + sheet.equity)
        XCTAssertNil(world.accountsProblem())

        // A day split into many calls writes down the same.
        var stepped = try self.world()
        _ = try build(&stepped)
        for _ in 0..<1_441 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(stepped, world)
    }

    func testAnAssetIsWrittenDownToNothingOverItsLifeAndNoFurther() {
        var record = AssetRecord(kind: .train, owner: 1, acquired: .zero, cost: 1_000)
        var total = Money.zero
        var charges: [Money] = []
        for _ in 0..<3_600 {
            let charge = record.depreciateOneDay()
            total = total + charge
            charges.append(charge)
        }
        XCTAssertEqual(total, 1_000)
        XCTAssertEqual(record.bookValue, .zero)
        // floor(1000 × d ÷ 3600): the first cent on day 4 (1000·4/3600 = 1.11).
        XCTAssertEqual(Array(charges.prefix(4)), [0, 0, 0, 1])
        XCTAssertEqual(record.depreciateOneDay(), .zero)
        XCTAssertEqual(record.days, 3_600)
    }

    func testFreePlayRecordsNothingAndCountsWhatIsUnrecorded() throws {
        var world = try world(managed: false)
        _ = try build(&world)
        XCTAssertEqual(world.accounts.assets, [])
        XCTAssertEqual(world.unrecordedAssetCount(), 3, "the edge, the station and the train")
        world.setEconomyMode(.management)
        _ = try world.buildStation(named: "East", at: PlanPoint(x: 8_192, y: 2_048))
        XCTAssertEqual(world.accounts.assets.map(\.kind), [.station])
        XCTAssertEqual(world.unrecordedAssetCount(), 3)
        try world.advance(ticks: 1_441)
        XCTAssertEqual(world.financeReport(.day).previous.depreciationCost, 100)
        XCTAssertNil(world.accountsProblem())
    }

    func testASplitEdgeSharesItsCostAndDepreciationByLength() throws {
        var world = try world()
        let (edge, _, _) = try build(&world)
        try world.advance(ticks: 1_441)
        let node = try world.splitTrackEdge(edge, at: 2_048)
        XCTAssertNotNil(world.network.node(node))
        let track = world.accounts.assets.filter { $0.kind == .track }
        XCTAssertEqual(track.map(\.owner), [2, 3])
        // 72000 × 2048 / 8192 = 18000; 10 × 2048 / 8192 = 2.5, so 2.
        XCTAssertEqual(track.map(\.cost), [18_000, 54_000])
        XCTAssertEqual(track.map(\.depreciation), [2, 8])
        XCTAssertEqual(track.map(\.days), [1, 1])
        XCTAssertNil(world.accountsProblem())

        // The next day: floor(18000·2/7200) = 5, 3 more; floor(54000·2/7200)
        // = 15, 7 more: 10, as the whole edge.
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.accounts.assets.filter { $0.kind == .track }.map(\.depreciation), [5, 15])
        XCTAssertEqual(world.financeReport(.day).previous.depreciationCost, 230)
    }

    func testRemovalWritesOffWhatIsLeftOnTheBooks() throws {
        var world = try world()
        let (edge, station, train) = try build(&world)
        try world.advance(ticks: 1_441)
        let cash = world.economy.balance

        try world.removeStation(station)
        try world.removeTrackEdge(edge)
        // One of the two cars: half the record's cost, 36000, and half its
        // depreciation, 10.
        try world.setTrainCars(train, to: 2)
        XCTAssertEqual(world.economy.balance, cash, "nothing is refunded")
        XCTAssertEqual(world.accounts.assets.map(\.kind), [.train, .cars])
        XCTAssertEqual(world.accounts.assets.last?.cars, 1)
        XCTAssertEqual(world.accounts.assets.last?.cost, 36_000)
        XCTAssertEqual(world.accounts.assets.last?.depreciation, 10)
        let today = world.financeReport(.day).current
        XCTAssertEqual(today.writeOffCost, Money(719_900 + 71_990 + 35_990))
        XCTAssertEqual(today.netProfit, .zero - today.writeOffCost)
        XCTAssertEqual(world.balanceSheet().equity, Self.start - Money(230) - today.writeOffCost)
        XCTAssertNil(world.accountsProblem())

        // The last added car goes, then nothing is left to write off.
        try world.setTrainCars(train, to: 1)
        XCTAssertEqual(world.accounts.assets.map(\.kind), [.train])
        try world.setTrainCars(train, to: 2)
        XCTAssertEqual(world.accounts.assets.map(\.cars), [0, 1])
    }

    func testLoansAreFinancingCashFlows() throws {
        var world = try world()
        try world.borrow(Money(30_000_000))
        try world.repayLoan(Money(10_000_000))
        let today = world.financeReport(.day).current
        XCTAssertEqual(today.loanBorrowed, 30_000_000)
        XCTAssertEqual(today.loanRepaid, 10_000_000)
        XCTAssertEqual(today.financingCashFlow, 20_000_000)
        XCTAssertEqual(today.netProfit, .zero)
        let sheet = world.balanceSheet()
        XCTAssertEqual(sheet.loan, 20_000_000)
        XCTAssertEqual(sheet.equity, Self.start, "borrowing leaves the company worth the same")
    }

    func testTheYearClosesAtItsLastMidnightWithItsStatementsAndBalanceSheet() throws {
        var world = try world()
        _ = try build(&world)
        try world.borrow(CompanyAccounts.loanStep)
        // The day before the year ends: nothing closed yet.
        try world.advance(ticks: 359 * 1_440 + 1)
        XCTAssertEqual(world.accounts.years, [])
        try world.advance(ticks: 1_440)
        let closed = try XCTUnwrap(world.accounts.years.first)
        XCTAssertEqual(world.accounts.years.count, 1)
        XCTAssertEqual(closed.year, 0)
        // 360 days of 230 cents, and $14 interest a day.
        XCTAssertEqual(closed.income.depreciationCost, 82_800)
        XCTAssertEqual(closed.income.interestCost, Money(360 * 1_400))
        XCTAssertEqual(closed.income.capitalSpending, 1_224_000)
        XCTAssertEqual(closed.income.loanBorrowed, CompanyAccounts.loanStep)
        XCTAssertEqual(closed.income.netProfit, Money(-82_800 - 504_000))
        XCTAssertEqual(closed.income.netCashFlow, Money(-1_224_000 - 504_000) + CompanyAccounts.loanStep)
        XCTAssertEqual(closed.closing, world.balanceSheet())
        XCTAssertEqual(closed.closing.cash, Self.start + CompanyAccounts.loanStep - Money(1_224_000 + 504_000))
        XCTAssertEqual(closed.closing.fixedAssets, Money(1_224_000 - 82_800))
        XCTAssertEqual(closed.closing.equity, Self.start + Money(closed.income.netProfit.amount))
        XCTAssertNil(world.accountsProblem())

        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
    }

    func testSavesWithoutAssetsAreUnchangedAndBadRecordsAreRefused() throws {
        let empty = try world()
        let plain = String(decoding: try JSONEncoder().encode(empty), as: UTF8.self)
        XCTAssertFalse(plain.contains(#""assets""#))

        var world = try world()
        _ = try build(&world)
        try world.advance(ticks: 1_441)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = String(decoding: try encoder.encode(world), as: UTF8.self)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8)), world)
        let station = #"{"acquired":0,"cost":720000,"days":1,"depreciation":100,"kind":"station","owner":1}"#
        XCTAssertTrue(text.contains(station))
        for broken in [
            #"{"acquired":0,"cost":720000,"days":1,"depreciation":100,"kind":"station","owner":9}"#,
            #"{"acquired":0,"cost":720000,"days":1,"depreciation":720001,"kind":"station","owner":1}"#,
            #"{"acquired":0,"cost":720000,"days":7201,"depreciation":100,"kind":"station","owner":1}"#,
            #"{"acquired":999999999,"cost":720000,"days":1,"depreciation":100,"kind":"station","owner":1}"#,
            #"{"acquired":0,"cars":1,"cost":720000,"days":1,"depreciation":100,"kind":"station","owner":1}"#,
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(text.replacingOccurrences(of: station, with: broken).utf8)), broken)
        }
        // More cars on the books than the train has added.
        let cars = #""cars":2,"cost":72000"#
        XCTAssertTrue(text.contains(cars))
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(text.replacingOccurrences(of: cars, with: #""cars":3,"cost":72000"#).utf8)))
    }
}
