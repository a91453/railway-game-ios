import GameCore
@testable import GamePresentation
import XCTest

/// Decision 224 (2A): the train types as a showroom.
final class RollingStockCatalogTests: XCTestCase {
    func testTheShowroomHasEveryOfferedTypeOnceInItsFamily() {
        let world = DemoWorld.make(in: .english)
        let catalog = RollingStockCatalog(world: world)
        XCTAssertEqual(Set(catalog.entries.map(\.type)), Set(world.offeredTrainTypes))
        XCTAssertEqual(catalog.entries.count, world.offeredTrainTypes.count)
        for entry in catalog.entries {
            XCTAssertEqual(entry.family, RollingStockCatalog.Family(entry.type))
            XCTAssertEqual(entry.card, world.trainTypeCard(entry.type))
            XCTAssertEqual(entry.doorsPerCar, entry.type.doorsPerCar)
        }
        XCTAssertEqual(catalog.families, RollingStockCatalog.Family.allCases.filter { family in catalog.entries.contains { $0.family == family } })
    }

    func testTheArrowsGoRoundAFamily() throws {
        let catalog = RollingStockCatalog(world: DemoWorld.make(in: .english))
        for family in catalog.families {
            let types = catalog.entries(of: family).map(\.type)
            guard types.count > 1, let first = types.first, let last = types.last else { continue }
            XCTAssertEqual(catalog.next(after: last), first)
            XCTAssertEqual(catalog.previous(before: first), last)
            XCTAssertEqual(catalog.next(after: first), types[1])
        }
    }

    func testATrainsFiguresAreTheWorldsPrices() {
        let world = DemoWorld.make(in: .english)
        let train = RollingStockCatalog.train(.a, cars: 4, in: world)
        XCTAssertEqual(train.riders, TrainType.a.ratedCapacityPerCar * 4)
        XCTAssertEqual(train.price, world.purchaseCost(of: .a, cars: 4))
        XCTAssertEqual(train.daily, world.dailyRunningCost(of: .a, cars: 4))
        XCTAssertEqual(RollingStockCatalog.train(.a, cars: 99, in: world).riders, TrainType.a.ratedCapacityPerCar * Int64(Train.maximumCars))
    }

    func testTheFamiliesNames() {
        XCTAssertEqual(RollingStockCatalog.Family.allCases.map { $0.title(in: .traditionalChinese) }, ["捷運", "鐵路", "高鐵", "特殊"])
        XCTAssertEqual(RollingStockCatalog.Family(.emu3000), .railway)
        XCTAssertEqual(RollingStockCatalog.Family(.highSpeed), .highSpeed)
    }

    /// BH8 P2-1: a car given no width or height (0/0 before) or a height
    /// of 0 (a width over 0 before) has one window; `Int` of the NaN or
    /// infinity it divided out to stopped the app.
    func testACarWithNoSizeYetHasOneWindow() {
        XCTAssertEqual(RollingStockCatalog.sideWindows(width: 0, height: 0), 1)
        XCTAssertEqual(RollingStockCatalog.sideWindows(width: 40, height: 0), 1)
        XCTAssertEqual(RollingStockCatalog.sideWindows(width: -1, height: -0.45), 1)
        XCTAssertEqual(RollingStockCatalog.sideWindows(width: .nan, height: 10), 1)
        XCTAssertEqual(RollingStockCatalog.sideWindows(width: .infinity, height: 10), 1)
        XCTAssertEqual(RollingStockCatalog.sideWindows(width: 40, height: 0.001), 100)
    }

    func testACarHasAsManyWindowsAsFitAtSevenTenthsOfItsHeight() {
        XCTAssertEqual(RollingStockCatalog.sideWindows(width: 70, height: 20), 5)
        XCTAssertEqual(RollingStockCatalog.sideWindows(width: 13, height: 20), 1)
        XCTAssertEqual(RollingStockCatalog.sideWindows(width: 33, height: 14.85), 3)
    }

    /// Decision 915: the full-screen catalog's list, by family and order.
    func testTheListKeepsAFamilyAndOrdersIt() {
        let world = DemoWorld.make(in: .english)
        let catalog = RollingStockCatalog(world: world)
        let all = catalog.listed(family: nil, order: .family, cars: 4, affordableOnly: false, in: world)
        XCTAssertEqual(all.map(\.type), catalog.entries.map(\.type))
        let railway = catalog.listed(family: .railway, order: .family, cars: 4, affordableOnly: false, in: world)
        XCTAssertEqual(railway, catalog.entries(of: .railway))

        let byPrice = catalog.listed(family: nil, order: .price, cars: 4, affordableOnly: false, in: world)
        let prices = byPrice.map { RollingStockCatalog.train($0.type, cars: 4, in: world).price.amount }
        XCTAssertEqual(prices, prices.sorted())
        XCTAssertEqual(Set(byPrice.map(\.type)), Set(catalog.entries.map(\.type)))

        let byCapacity = catalog.listed(family: nil, order: .capacity, cars: 4, affordableOnly: false, in: world).map(\.card.capacityPerCar)
        XCTAssertEqual(byCapacity, byCapacity.sorted(by: >))
        let bySpeed = catalog.listed(family: nil, order: .speed, cars: 4, affordableOnly: false, in: world).map(\.card.topSpeed)
        XCTAssertEqual(bySpeed, bySpeed.sorted(by: >))
        let byHour = catalog.listed(family: nil, order: .hourlyCost, cars: 4, affordableOnly: false, in: world)
            .map { RollingStockCatalog.train($0.type, cars: 4, in: world).hourly.amount }
        XCTAssertEqual(byHour, byHour.sorted())
    }

    /// Decision 915: ties keep the menu's order, so the list does not
    /// shuffle types of one price.
    func testTiesKeepTheMenusOrder() {
        let world = DemoWorld.make(in: .english)
        let catalog = RollingStockCatalog(world: world)
        let menu = catalog.entries.map(\.type)
        let byCapacity = catalog.listed(family: nil, order: .capacity, cars: 4, affordableOnly: false, in: world)
        for (a, b) in zip(byCapacity, byCapacity.dropFirst()) where a.card.capacityPerCar == b.card.capacityPerCar {
            XCTAssertLessThan(menu.firstIndex(of: a.type)!, menu.firstIndex(of: b.type)!)
        }
    }

    func testOnlyAffordableLeavesOutWhatTheCompanyCannotPayFor() {
        let world = DemoWorld.make(in: .english)
        let catalog = RollingStockCatalog(world: world)
        let affordable = catalog.listed(family: nil, order: .family, cars: 8, affordableOnly: true, in: world)
        for entry in catalog.entries {
            let price = RollingStockCatalog.train(entry.type, cars: 8, in: world).price
            XCTAssertEqual(affordable.contains(entry), world.economy.canAfford(price), "\(entry.type)")
        }
    }

    func testTheArrowsGoRoundTheList() {
        let world = DemoWorld.make(in: .english)
        let list = RollingStockCatalog(world: world).listed(family: nil, order: .price, cars: 4, affordableOnly: false, in: world)
        guard let first = list.first, let last = list.last, list.count > 1 else { return XCTFail("No list") }
        XCTAssertEqual(RollingStockCatalog.step(in: list, from: last.type, by: 1), first.type)
        XCTAssertEqual(RollingStockCatalog.step(in: list, from: first.type, by: -1), last.type)
        XCTAssertNil(RollingStockCatalog.step(in: Array(list.prefix(1)), from: first.type, by: 1))
    }

    func testTheOrdersNames() {
        XCTAssertEqual(RollingStockCatalog.Order.allCases.map { $0.title(in: .traditionalChinese) }, ["類別", "價格", "每節人數", "最高速度", "每小時成本"])
    }
}
