import Foundation
import GameCore
import GamePresentation
import XCTest

/// Freight in the session and its text (decision 155): the commands go
/// through GameCore's, and the text is derived from the world.
@MainActor
final class FreightSessionTests: XCTestCase {
    private static let line = TestLine(tiles: 9, row: 1)
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)

    private static func world() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 9_216, height: 2_048), economy: GameEconomy(balance: 100_000_000, costs: testCosts)
        )
        try Self.line.build(in: &world)
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try Self.line.buildStation(named: name, beside: x, at: 0, in: &world)
        }
        try world.setLand([LandCell(row: 0, column: 0, use: .industrial, residents: 0, jobs: 100)])
        return world
    }

    func testANewGameHasFreightAndAnOldWorldDoesNot() throws {
        XCTAssertTrue(GameWorld.newGame().hasFreight)
        XCTAssertFalse(try Self.world().hasFreight)
        XCTAssertNil(try Self.world().freightYardText(at: Self.alpha, in: .english))
        XCTAssertNil(try Self.world().freightTotalsText(in: .english))
    }

    func testTheSessionBuildsAndRemovesAYardAndMakesALineFreight() throws {
        var world = try Self.world()
        world.enableFreight()
        try world.createLine(named: "Goods", stops: [Self.alpha, Self.beta])
        let session = GameSession(world: world)
        session.selectStation(Self.alpha)
        session.buildFreightYardAtSelectedStation()
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertNotNil(session.world.freightFacility(at: Self.alpha))
        XCTAssertEqual(session.world.freightYardText(at: Self.alpha, in: .english),
                       "0 t waiting (up to 2000 t)\nThe industry round it makes about 50 t a day.")
        XCTAssertEqual(session.world.freightYardText(at: Self.alpha, in: .traditionalChinese),
                       "待運 0 噸（最多 2000 噸）\n周圍的工業每天約產出 50 噸。")
        // The same command twice is refused, and says so.
        session.buildFreightYardAtSelectedStation()
        XCTAssertEqual(session.message?.kind, .failure)

        session.selectLine(LineID(rawValue: 1))
        session.setSelectedLineFreight(true)
        XCTAssertEqual(session.world.line(id: LineID(rawValue: 1))?.isFreight, true)
        XCTAssertEqual(session.world.freightLineText(LineID(rawValue: 1), in: .english), "Carrying 0 t of 0 t on 0 trains.")
        session.setSelectedLineFreight(false)
        XCTAssertNil(session.world.freightLineText(LineID(rawValue: 1), in: .english))

        session.removeFreightYardAtSelectedStation()
        XCTAssertNil(session.world.freightFacility(at: Self.alpha))
    }

    func testFreightIsRefusedInAGameWithoutIt() throws {
        let session = GameSession(world: try Self.world())
        session.selectStation(Self.alpha)
        session.buildFreightYardAtSelectedStation()
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.message?.text, GameError.freightNotEnabled.playerMessage(in: session.language))
    }

    func testTheFreightRevenueIsInTheStatementsAndTheFeedback() throws {
        func summary(freight: Int64) throws -> FinanceSummary {
            let json = """
            {"index": 0, "fareRevenue": 1000, "operatingCost": 100, "maintenanceCost": 0, "energyCost": 0, "staffCost": 0,
             "interestCost": 0, "depreciationCost": 0, "writeOffCost": 0, "capitalSpending": 0, "loanBorrowed": 0, "loanRepaid": 0,
             "freightRevenue": \(freight)}
            """
            return try JSONDecoder().decode(FinanceSummary.self, from: Data(json.utf8))
        }
        let without = try summary(freight: 0).incomeStatementRows(previous: nil, in: .english).map(\.title)
        XCTAssertFalse(without.contains("Freight"))
        let rows = try summary(freight: 400).incomeStatementRows(previous: nil, in: .english)
        XCTAssertEqual(Array(rows.map(\.title).prefix(2)), ["Fares", "Freight"])
        XCTAssertEqual(rows.first { $0.title == "Operating profit" }?.current, Money(1_300))
        XCTAssertTrue(CompanyAccounts.incomeItems.contains(.freightRevenue))
    }

    /// A freight train's load is its tons over its cars' tons, and it is
    /// left out of the passenger fleet's load; a yard's stock is on the
    /// station's tag.
    func testFreightLoadsAndTags() throws {
        var world = try Self.world()
        world.enableFreight()
        try world.createLine(named: "Goods", stops: [Self.alpha, Self.beta])
        try world.setLineFreight(LineID(rawValue: 1), to: true)
        let train = try world.purchaseTrain(named: "Freight").id
        try world.setTrainCars(train, to: 3)
        try world.assignTrain(train, to: LineID(rawValue: 1))
        XCTAssertTrue(world.isFreightTrain(train))
        XCTAssertEqual(world.trainLoadInfo(of: train)?.capacity, 120, "three cars of 40 t")
        XCTAssertNil(world.loadText(of: train, in: .english), "nothing aboard yet")
        XCTAssertNil(world.fleetLoadInfo(), "the only train is not on the track")

        let tag = StationTag(station: Self.alpha, name: "Alpha", location: PlanPoint(x: 0, y: 0), waiting: 12, lines: [], freight: 1_200)
        XCTAssertEqual(tag.waitingText(in: .english), "12 waiting · 1,200 t of freight")
        XCTAssertEqual(tag.waitingText(in: .traditionalChinese), "候車 12 人 · 待運 1,200 噸")
        let empty = StationTag(station: Self.alpha, name: "Alpha", location: PlanPoint(x: 0, y: 0), waiting: 0, lines: [], freight: 0)
        XCTAssertNil(empty.waitingText(in: .english))
    }

    /// Building materials (decision 156): a new game has them; the station
    /// panel's text and the session's command to send them.
    func testBuildingMaterialsText() throws {
        XCTAssertTrue(GameWorld.newGame().hasBuildingMaterials)
        var world = try Self.world()
        world.enableFreight()
        XCTAssertNil(world.materialsText(at: Self.alpha, in: .english))
        world.enableBuildingMaterials()
        XCTAssertEqual(world.materialsText(at: Self.alpha, in: .english),
                       "Building materials: 0 t (up to 5000 t); 60 t a day arrive by road.")
        XCTAssertEqual(world.materialsText(at: Self.alpha, in: .traditionalChinese),
                       "建材置場：0 噸（最多 5000 噸）；每天由公路運來 60 噸。")
        try world.buildFreightFacility(at: Self.alpha)
        let session = GameSession(world: world)
        session.selectStation(Self.alpha)
        session.setFreightProductAtSelectedStation(.materials)
        XCTAssertEqual(session.world.freightFacility(at: Self.alpha)?.product, .materials)
        XCTAssertEqual(session.message?.text, "Alpha's yard sends building materials.")
        XCTAssertEqual(CargoKind.materials.title(in: .traditionalChinese), "建材")
    }
}
