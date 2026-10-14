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
}
