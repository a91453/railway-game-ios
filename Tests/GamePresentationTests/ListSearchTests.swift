import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 184: searching the station, line and train lists
/// by name, and filtering the lines to those losing money or carrying
/// freight.
final class ListSearchTests: XCTestCase {
    func testANameMatchesWhateverTheCaseWidthOrTheWayTaiIsWritten() {
        XCTAssertTrue(ListSearch("").matches(["Anything"]))
        XCTAssertTrue(ListSearch("   ").matches(["Anything"]))
        XCTAssertFalse(ListSearch("  ").isActive)
        XCTAssertTrue(ListSearch("taipei").matches(["Taipei Main"]))
        XCTAssertTrue(ListSearch(" MAIN ").matches(["Taipei Main"]))
        XCTAssertTrue(ListSearch("ＴＡＩ").matches(["Taipei"]), "full-width letters")
        XCTAssertTrue(ListSearch("臺北").matches(["台北車站"]))
        XCTAssertTrue(ListSearch("台北").matches(["臺北"]))
        XCTAssertTrue(ListSearch("cafe").matches(["Café"]))
        XCTAssertTrue(ListSearch("橋").matches(["Banqiao", "板橋"]), "any of the names")
        XCTAssertFalse(ListSearch("高雄").matches(["台北", "Taipei"]))
    }

    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)
    private static let gamma = StationID(rawValue: 3)

    private func world(accounts: Bool = true) throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("臺中", 5)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        try world.createLine(named: "Short", stops: [Self.alpha, Self.beta])
        try world.createLine(named: "Long", stops: [Self.alpha, Self.beta, Self.gamma])
        world.setEconomyMode(.management)
        world.setLineAccounts(accounts)
        world.setSpeed(.normal)
        return world
    }

    func testStationsAndLinesByName() throws {
        let world = try world()
        XCTAssertEqual(world.stations(matching: ListSearch("a")).map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(world.stations(matching: ListSearch("台中")).map(\.id), [Self.gamma])
        XCTAssertEqual(world.stations(matching: ListSearch()).count, 3)

        XCTAssertEqual(world.lines(world.lines, matching: ListSearch("long")).map(\.name), ["Long"])
        XCTAssertEqual(world.lines(world.lines, matching: ListSearch("台中")).map(\.name), ["Long"], "a stop's name finds the line")
        XCTAssertEqual(world.lines(world.lines, matching: ListSearch("beta")).map(\.name), ["Short", "Long"], "in the order given")
        XCTAssertEqual(world.lines(world.lines.reversed(), matching: ListSearch()).map(\.name), ["Long", "Short"])
    }

    func testTheFilters() throws {
        var world = try world()
        XCTAssertEqual(world.lineFilters, [.all, .losing], "no freight line")
        XCTAssertEqual(try self.world(accounts: false).lineFilters, [.all])
        XCTAssertEqual(world.lines(world.lines, matching: ListSearch(), filter: .losing), [], "no record of yesterday yet")
        XCTAssertEqual(world.lines(world.lines, matching: ListSearch(), filter: .freight), [])

        // A day on: no trains, so no fares, and both lines lose money.
        try world.advance(ticks: 1_440 + 120)
        XCTAssertEqual(world.lines(world.lines, matching: ListSearch(), filter: .losing).map(\.name), ["Short", "Long"])
        XCTAssertEqual(world.lines(world.lines, matching: ListSearch("sh"), filter: .losing).map(\.name), ["Short"])

        for filter in LineFilter.allCases {
            XCTAssertFalse(filter.displayName(in: .english).isEmpty)
        }
        XCTAssertEqual(LineFilter.losing.displayName(in: .traditionalChinese), "只看虧損")
        XCTAssertEqual(LineFilter.freight.displayName(in: .traditionalChinese), "只看貨運")
    }

    func testTrainsByTheirNameOrTheirLines() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        let train = try XCTUnwrap(world.trains.first)
        let line = try XCTUnwrap(world.lines.first)
        try world.renameLine(line.id, to: "藍線")
        XCTAssertEqual(world.trains(world.trains, matching: ListSearch("藍")).map(\.id), [train.id])
        XCTAssertEqual(world.trains(world.trains, matching: ListSearch(train.name.uppercased())).map(\.id), [train.id])
        XCTAssertEqual(world.trains(world.trains, matching: ListSearch("no such")), [])
        XCTAssertEqual(world.trains(world.trains, matching: ListSearch()).map(\.id), [train.id])
    }
}
