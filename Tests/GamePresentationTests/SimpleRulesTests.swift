import Foundation
import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 258: a new game's rules, simple (the app's
/// default) or realistic (every rule a new game had before).
final class SimpleRulesTests: XCTestCase {
    /// Simple turns off the rules a new player need not learn first and
    /// keeps the rest: traffic control, flexible dispatch, keeping left,
    /// real car lengths, the holidays, the sights and the city's requests.
    func testSimpleRulesTurnTheRealisticOnesOff() {
        let simple = GameWorld.newGame(eventSeed: 5, rules: .simple)
        XCTAssertFalse(simple.blockSections)
        XCTAssertFalse(simple.curveSpeedLimits)
        XCTAssertFalse(simple.realisticOperation)
        XCTAssertFalse(simple.doorCrowding)
        XCTAssertFalse(simple.rollingStockEconomics)
        XCTAssertNotEqual(simple.freight?.buildingMaterials, true)
        XCTAssertEqual(simple.disruptions?.level, .light, "the holidays stay")
        XCTAssertNil(simple.disruptions?.seed, "with no weather, typhoons or fuel spells")

        XCTAssertTrue(simple.isTrafficControlEnabled)
        XCTAssertTrue(simple.flexDispatch)
        XCTAssertTrue(simple.keepLeft)
        XCTAssertTrue(simple.realCarLengths)
        XCTAssertNotNil(simple.tourism)
        XCTAssertNotNil(simple.cityRequests)
        XCTAssertEqual(simple.accounts.mode, .management)
    }

    /// Realistic is the new game as it was, and the default of
    /// ``GameWorld/newGame(anchor:bounds:balance:eventSeed:land:water:steep:buysMap:rules:)``,
    /// so its other callers and tests keep their worlds.
    func testRealisticRulesAreTheNewGameAsItWas() {
        let realistic = GameWorld.newGame(eventSeed: 5, rules: .realistic)
        XCTAssertEqual(realistic, GameWorld.newGame(eventSeed: 5))
        XCTAssertTrue(realistic.blockSections)
        XCTAssertTrue(realistic.curveSpeedLimits)
        XCTAssertTrue(realistic.realisticOperation)
        XCTAssertTrue(realistic.doorCrowding)
        XCTAssertTrue(realistic.rollingStockEconomics)
        XCTAssertEqual(realistic.freight?.buildingMaterials, true)
        XCTAssertEqual(realistic.disruptions?.seed, 5)
    }

    /// The rules a world plays by are read from its switches: what the
    /// settings show for the game being played.
    func testAWorldsRulesAreReadFromItsSwitches() {
        XCTAssertEqual(NewGameRules(of: GameWorld.newGame(rules: .simple)), .simple)
        XCTAssertEqual(NewGameRules(of: GameWorld.newGame(rules: .realistic)), .realistic)
        XCTAssertEqual(NewGameRules(of: GameWorld(bounds: .standard, economy: GameEconomy(balance: .zero))), .simple, "a world with none of them")
        var one = GameWorld.newGame(rules: .simple)
        one.setCurveSpeedLimits(true)
        XCTAssertEqual(NewGameRules(of: one), .realistic)
        XCTAssertEqual(NewGameRules.allCases.map { $0.title(in: .traditionalChinese) }, ["簡單", "寫實"])
        XCTAssertEqual(NewGameRules.allCases.map { $0.title(in: .english) }, ["Simple", "Realistic"])
    }

    /// The options default to simple, options kept before the rules were
    /// asked included; simple has no building materials or weather whatever
    /// the other options say.
    func testTheOptionsDefaultToSimpleRules() throws {
        XCTAssertEqual(NewGameOptions().rules, .simple)
        let older = Data(#"{"buildingMaterials":true,"difficulty":"expert"}"#.utf8)
        let read = try JSONDecoder().decode(NewGameOptions.self, from: older)
        XCTAssertEqual(read.rules, .simple)
        var written = NewGameOptions()
        written.rules = .realistic
        XCTAssertEqual(try JSONDecoder().decode(NewGameOptions.self, from: JSONEncoder().encode(written)), written)

        var expert = NewGameOptions()
        expert.difficulty = .expert
        var world = GameWorld.newGame(eventSeed: 9)
        expert.apply(to: &world)
        XCTAssertEqual(world.disruptions?.level, .standard)
        XCTAssertNil(world.disruptions?.seed)
        XCTAssertNotEqual(world.freight?.buildingMaterials, true)
        XCTAssertFalse(world.realisticOperation)
        XCTAssertTrue(expert.summary(in: .english).contains("no weather or typhoons"))
        XCTAssertTrue(expert.summary(in: .traditionalChinese).contains("沒有天氣與颱風"))
    }

    /// The start screen's new game is simple unless the options say
    /// realistic.
    @MainActor
    func testTheStartScreensNewGameIsSimpleUnlessChosenRealistic() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SimpleRulesTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        var options = launcher.newGameOptions
        options.buysMap = false
        launcher.newGameOptions = options
        launcher.startNewGame()
        XCTAssertEqual(NewGameRules(of: try XCTUnwrap(launcher.session?.world)), .simple)

        launcher.returnToStart()
        options.rules = .realistic
        launcher.newGameOptions = options
        launcher.startNewGame()
        let realistic = try XCTUnwrap(launcher.session?.world)
        XCTAssertEqual(NewGameRules(of: realistic), .realistic)
        XCTAssertNotNil(realistic.disruptions?.seed)
    }

    /// A simple game is saved and loaded back with its rules: they are the
    /// world's own switches, in every save.
    func testASimpleGameLoadsBackWithItsRules() throws {
        var world = try newGameLine(through: Array(Land.townCentres(seed: 1, in: GameWorld.newGameBounds).prefix(2)), in: .newGame(rules: .simple))
        try world.advance(ticks: 300)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(NewGameRules(of: loaded), .simple)
    }

    /// Decision 46's measure under simple rules: the first line from the
    /// first town to the second (seed 1) costs what it does under realistic
    /// rules less the realistic train's price, and pays for itself in
    /// about five days, as there.
    func testUnderSimpleRulesALineBetweenTwoTownsPaysForItselfInAboutFiveDays() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]], in: .newGame(rules: .simple))
        world.setTourism(nil)
        let cost = GameWorld.startingBalance - world.economy.balance
        XCTAssertLessThan(cost.amount * 2, GameWorld.startingBalance.amount, "with more than half the money to spare")

        try world.advance(ticks: 1 + 2 * 1_440)
        let day = world.financeReport(.day).previous
        XCTAssertGreaterThan(day.operatingProfit, .zero)
        let payback = Double(cost.amount) / Double(day.operatingProfit.amount)
        XCTAssertTrue((3...10).contains(payback), "pays for itself in \(payback) days")
    }
}
