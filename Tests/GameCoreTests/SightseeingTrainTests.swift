import Foundation
@testable import GameCore
import XCTest

/// Sightseeing trains (ARCHITECTURE decision 286): a train of a sightseeing
/// type (the Hai-Feng, the Blue Train) whose line calls at a station within
/// 800 m of a sight adds half a star to it, however many call; the Ming-Ri
/// (decision 286, later) adds a whole star, and the most any of them adds is
/// what counts. Every expectation is worked out by hand from the rules.
final class SightseeingTrainTests: XCTestCase {
    private let home = StationID(rawValue: 1), foot = StationID(rawValue: 2), far = StationID(rawValue: 3), beyond = StationID(rawValue: 4)
    private let sight = AttractionID(rawValue: 1)

    /// `TourismHotelTests`' world: Home and Foot with a plain train, a
    /// 3-star town 15.6 m from Foot (Home is 328 m from it), and Far and
    /// Beyond, 1.08 and 1.40 km from it, on a line of their own.
    private func world() throws -> (GameWorld, main: LineID, other: LineID) {
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: GameEconomy(balance: 1_000_000_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        try world.buildStation(named: "Home", at: PlanPoint(x: 10_000, y: 32_768))
        try world.buildStation(named: "Foot", at: PlanPoint(x: 30_000, y: 32_768))
        try world.buildStation(named: "Far", at: PlanPoint(x: 120_000, y: 32_768))
        try world.buildStation(named: "Beyond", at: PlanPoint(x: 100_000, y: 32_768))
        let main = try world.createLine(named: "Main", stops: [home, foot]).id
        let other = try world.createLine(named: "Other", stops: [beyond, far]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: main)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 0))
        try world.setStationDemand(foot, to: StationDemand(kind: .scenic, dailyTrips: 0))
        world.setOutsideConnections(true)
        world.setTourism([Attraction(id: sight, name: "x", englishName: "x", point: PlanPoint(x: 31_000, y: 32_768), kind: .town, baseStars: 300)])
        return (world, main, other)
    }

    /// Buys a train of `type` and puts it on `line`.
    @discardableResult
    private func train(_ world: inout GameWorld, _ type: TrainType, on line: LineID) throws -> TrainID {
        let id = try world.purchaseTrain(named: type.rawValue).id
        try world.setTrainType(id, to: type)
        try world.assignTrain(id, to: line)
        return id
    }

    func testTheSightseeingTypes() {
        XCTAssertEqual(TrainType.allCases.filter(\.isSightseeing), [.haiFeng, .blueTrain, .shanLan, .mingRi])
        XCTAssertEqual(TrainType.allCases.map(\.sightseeingStars), Array(repeating: 0, count: 17) + [50, 50, 50, 100])
        XCTAssertEqual(TrainType.blueTrain.ratedCapacityPerCar, 50)
        XCTAssertEqual(TrainType.blueTrain.doorsPerCar, 2)
        XCTAssertEqual(TrainType.blueTrain.performance, .r100ChuKuang)
        XCTAssertFalse(TrainType.blueTrain.isHighSpeed)
        XCTAssertTrue(TrainType.offered.contains(.blueTrain), "offered in a world without an era")
        // Decision 286, later: the Shan-Lan is the Hai-Feng's sister, the
        // same EMU500 rebuild, with the same numbers.
        XCTAssertEqual(TrainType.shanLan.ratedCapacityPerCar, TrainType.haiFeng.ratedCapacityPerCar)
        XCTAssertEqual(TrainType.shanLan.doorsPerCar, TrainType.haiFeng.doorsPerCar)
        XCTAssertEqual(TrainType.shanLan.performance, TrainType.haiFeng.performance)
        XCTAssertEqual(TrainType.shanLan.spec.pricing, TrainType.haiFeng.spec.pricing)
        XCTAssertEqual(TrainType.shanLan.spec.carLength, TrainType.haiFeng.spec.carLength)
        XCTAssertTrue(TrainType.offered.contains(.shanLan), "offered in a world without an era")
        // Decision 286, later: the Ming-Ri, an E500 and its luxury coaches,
        // 26 seats a coach (415 seats in 16 coaches), 110 km/h.
        XCTAssertEqual(TrainType.mingRi.ratedCapacityPerCar, 26)
        XCTAssertEqual(TrainType.mingRi.doorsPerCar, 2)
        XCTAssertEqual(TrainType.mingRi.performance, .mingRi)
        XCTAssertEqual(TrainPerformance.mingRi, TrainPerformance(acceleration: 2481, braking: 2600, topSpeed: 110))
        XCTAssertEqual(TrainType.mingRi.spec.pricing, RollingStockPricing(firstDollars: 400_000, carDollars: 55_000, operatingPermille: 1_400))
        XCTAssertEqual(TrainType.mingRi.spec.carLength, TrainType.blueTrain.spec.carLength)
        XCTAssertFalse(TrainType.mingRi.isHighSpeed)
        XCTAssertTrue(TrainType.offered.contains(.mingRi), "offered in a world without an era")
    }

    /// The E500 Chu-Kuang's sum (``TrainPerformance/e500ChuKuang``) with
    /// five coaches for eight and the coaches' 110 km/h: 280 kN to 50 km/h,
    /// then 3,888 kW, 96 t and five 42 t coaches, 44.3 seconds.
    func testTheMingRiStartsAsItsLighterSetWould() {
        func seconds(coaches: Double, to kmh: Double) -> Double {
            let mass = (96 + 42 * coaches) * 1_000, force = 280_000.0, power = 3_888_000.0
            let corner = power / force, top = kmh / 3.6
            return corner * mass / force + mass * (top * top - corner * corner) / (2 * power)
        }
        XCTAssertEqual(Int64((120 / seconds(coaches: 8, to: 120) * 1_000).rounded()), TrainPerformance.e500ChuKuang.acceleration)
        XCTAssertEqual(Int64((110 / seconds(coaches: 5, to: 110) * 1_000).rounded()), TrainPerformance.mingRi.acceleration)
    }

    func testASightseeingTrainCallingNearASightAddsHalfAStar() throws {
        var (world, main, _) = try world()
        let attraction = try XCTUnwrap(world.attraction(id: sight))
        XCTAssertEqual(world.stars(of: attraction), 300)
        XCTAssertFalse(world.hasSightseeingTrain(near: attraction))
        try train(&world, .blueTrain, on: main)
        XCTAssertTrue(world.hasSightseeingTrain(near: attraction))
        XCTAssertEqual(world.stars(of: attraction), 350)
        // However many call, half a star.
        try train(&world, .haiFeng, on: main)
        XCTAssertEqual(world.stars(of: attraction), 350)
    }

    func testTheMingRiAddsAWholeStarAndTheMostCounts() throws {
        var (world, main, _) = try world()
        let attraction = try XCTUnwrap(world.attraction(id: sight))
        try train(&world, .haiFeng, on: main)
        XCTAssertEqual(world.sightseeingTrainStars(near: attraction), 50)
        XCTAssertEqual(world.stars(of: attraction), 350)
        let id = try train(&world, .mingRi, on: main)
        XCTAssertEqual(world.sightseeingTrainStars(near: attraction), 100)
        XCTAssertEqual(world.stars(of: attraction), 400, "the Ming-Ri's star, not both")
        try world.unassignTrain(id)
        XCTAssertEqual(world.stars(of: attraction), 350)
    }

    func testTheMingRiOnAnotherLineThatCallsNearTheSight() throws {
        var (world, main, _) = try world()
        let attraction = try XCTUnwrap(world.attraction(id: sight))
        try train(&world, .blueTrain, on: main)
        // The Ming-Ri on a line of its own that stops at Far and then Foot.
        let tour = try world.createLine(named: "Tour", stops: [far, foot]).id
        try train(&world, .mingRi, on: tour)
        XCTAssertEqual(world.stars(of: attraction), 400)
        XCTAssertEqual(world.sightseeingTrainStars(near: try XCTUnwrap(world.attraction(id: sight))), 100)
    }

    func testOtherTypesAddNothing() throws {
        var (world, main, _) = try world()
        try train(&world, .r100ChuKuang, on: main)
        try train(&world, .emu3000, on: main)
        XCTAssertEqual(world.stars(of: try XCTUnwrap(world.attraction(id: sight))), 300)
    }

    func testATrainOnALineThatDoesNotCallNearTheSightAddsNothing() throws {
        var (world, _, other) = try world()
        // Beyond is 69,000 units (1.08 km) from the sight, Far 1.40 km: beyond 800 m.
        try train(&world, .blueTrain, on: other)
        XCTAssertEqual(world.stars(of: try XCTUnwrap(world.attraction(id: sight))), 300)
    }

    func testABoughtTrainOnNoLineAddsNothing() throws {
        var (world, main, _) = try world()
        let id = try train(&world, .blueTrain, on: main)
        try world.unassignTrain(id)
        XCTAssertEqual(world.stars(of: try XCTUnwrap(world.attraction(id: sight))), 300)
    }

    func testTheTouristsAndThePlanFollowTheTrain() throws {
        var (world, main, _) = try world()
        XCTAssertEqual(world.touristsExpected(at: sight, onDay: 0), 240)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 240)
        let id = try train(&world, .blueTrain, on: main)
        // 3.5 stars: 3,250 potential, a Monday: 3,250 × 0.6 × 0.2 = 390.
        XCTAssertEqual(world.touristsExpected(at: sight, onDay: 0), 390)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 390, "the plan is worked out again")
        try world.unassignTrain(id)
        XCTAssertEqual(world.dailyDemand(from: home, to: foot), 240)
    }

    func testWithAHotelAndAShopStarsStopAtFive() throws {
        var (world, main, _) = try world()
        world.setTourism([Attraction(id: sight, name: "x", englishName: "x", point: PlanPoint(x: 31_000, y: 32_768), kind: .town, baseStars: 450)])
        try world.placeBuilding(.hotel, at: PlanPoint(x: 31_000, y: 32_768 - 6_000))
        try train(&world, .blueTrain, on: main)
        XCTAssertEqual(world.stars(of: try XCTUnwrap(world.attraction(id: sight))), 500)
    }

    func testTheBlueTrainSavesAndLoadsByItsCode() throws {
        var (world, main, _) = try world()
        let id = try train(&world, .blueTrain, on: main)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.train(id: id)?.type, .blueTrain)
        XCTAssertEqual(loaded.stars(of: try XCTUnwrap(loaded.attraction(id: sight))), 350)
    }
}
