import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 428: a game saved without roads turns them on from the bus
/// tool, and then runs buses; the tutorial and the lessons cannot, and a
/// real-world map whose land came all at once has no roads to read.
@MainActor
final class RoadsTurnOnTests: XCTestCase {
    /// `SaveFixtures/`, at the repository root.
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SaveFixtures", isDirectory: true)

    private func fixture(_ name: String) throws -> GameWorld {
        try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent(name))).world
    }

    /// A save as a build before decision 400 wrote it: `world` with no
    /// `"roads"` key.
    private func savedBeforeRoads(_ world: GameWorld) throws -> GameWorld {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: world))) as? [String: Any])
        var inner = try XCTUnwrap(json["world"] as? [String: Any])
        inner["roads"] = nil
        json["world"] = inner
        return try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: json)).world
    }

    /// The cell a point lies in.
    private func cell(of point: PlanPoint) -> CellPosition {
        CellPosition(row: Int(point.y / Land.cellLength), column: Int(point.x / Land.cellLength))
    }

    /// Turns the roads on in `session`, then opens a bus route from a
    /// station built on the road cell `at` to a stop on the road beside it,
    /// and checks the game saves and reads back as it is.
    private func turnOnAndRunABus(_ session: GameSession, at middle: CellPosition, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNil(session.world.roads, file: file, line: line)
        XCTAssertFalse(session.allowsBusTool, "no routes without roads", file: file, line: line)
        XCTAssertTrue(session.allows(ConstructionTool.bus), "the tool is there, to turn them on", file: file, line: line)
        XCTAssertEqual(session.roadsOffer, .available, file: file, line: line)

        session.turnOnRoads()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "", file: file, line: line)
        let roads = try XCTUnwrap(session.world.roads, file: file, line: line)
        XCTAssertTrue(roads.cells.contains(middle), "\(middle)", file: file, line: line)
        XCTAssertTrue(session.allowsBusTool, file: file, line: line)
        XCTAssertNil(session.roadsOffer, file: file, line: line)

        let station = try session.performEdit { world throws(GameError) in try world.buildStation(named: "Bus", at: middle.middle) }
        let stop = try XCTUnwrap(
            [(0, 1), (1, 0), (0, -1), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)]
                .map { CellPosition(row: middle.row + $0.0, column: middle.column + $0.1) }
                .first { session.world.roads?.cells.contains($0) == true },
            "a road beside the station", file: file, line: line
        )
        let outcome = session.perform(.createBusRoute(station.id, stops: [.init(stop)], service: .every(minutes: 15), buses: 1)) { _, _, _ in "" }
        XCTAssertNotNil(outcome, session.message?.text ?? "", file: file, line: line)
        XCTAssertEqual(session.world.busRoutes.count, 1, file: file, line: line)

        let saved = try JSONEncoder().encode(SavedGame(world: session.world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: saved).world, session.world, "saved and read back", file: file, line: line)
    }

    // MARK: - Blank maps

    /// A blank map bought tile by tile (version 40): its town seed is
    /// kept, but the fixture's land was laid by hand, not drawn from it,
    /// so the seed's towns are not there and the world's middle is taken;
    /// the tile it bought gets its towns' roads from the seed, as when it
    /// was bought with roads on.
    func testABoughtBlankMapsSaveGetsItsTownsRoads() throws {
        let world = try fixture("v40-map-expansion.json")
        let seed = try XCTUnwrap(world.mapExpansion?.townSeed)
        let middle = PlanPoint(x: world.bounds.width / 2, y: world.bounds.height / 2)
        XCTAssertNotEqual(world.startingTowns(), Land.townCentres(seed: seed, in: world.bounds))
        XCTAssertEqual(world.startingTowns(), [middle])
        let session = GameSession(world: world)
        try turnOnAndRunABus(session, at: cell(of: middle))
        let roads = try XCTUnwrap(session.world.roads)
        let tiles = roads.towns.map { MapExpansion.tile(ofCellRow: $0.row, column: $0.column) }
        XCTAssertEqual(Set(tiles), Set(try XCTUnwrap(world.mapExpansion?.owned)), "each tile owned has towns with roads")
        XCTAssertEqual(roads.towns.first, cell(of: middle))
        XCTAssertGreaterThan(roads.towns.count, 1)
    }

    /// A blank map whose save keeps no seed (version 12's towns): the
    /// world's middle, where every blank map's first town is.
    func testABlankMapWithNoSeedStartsAtTheWorldsMiddle() throws {
        let world = try fixture("v12-land-towns.json")
        let middle = PlanPoint(x: world.bounds.width / 2, y: world.bounds.height / 2)
        XCTAssertEqual(world.startingTowns(), [middle])
        XCTAssertNotNil(world.land.cell(row: cell(of: middle).row, column: cell(of: middle).column), "the town is there")
        try turnOnAndRunABus(GameSession(world: world), at: cell(of: middle))
    }

    /// A new game's seed, kept by its demand events, finds its towns; a
    /// seed whose towns have no land is passed over.
    func testTheSeedIsTheOneWhoseTownsAreThere() throws {
        var world = try savedBeforeRoads(GameWorld.newGame(eventSeed: 42))
        XCTAssertNil(world.roads)
        XCTAssertEqual(world.startingTowns(), Land.townCentres(seed: 42, in: world.bounds))
        world.setDemandEvents(seed: 7)
        XCTAssertEqual(world.startingTowns(), Land.townCentres(seed: 42, in: world.bounds), "the weather's seed is 42 still")
        let session = GameSession(world: world)
        try turnOnAndRunABus(session, at: cell(of: Land.townCentres(seed: 42, in: world.bounds)[0]))
        // The same roads a new game of that seed starts with.
        XCTAssertEqual(session.world.roads?.towns, GameWorld.newGame(eventSeed: 42).roads?.towns)
    }

    // MARK: - Real-world maps

    /// A real-world map whose land is read as it is needed: the base map's
    /// roads of its land, read in the same edit.
    func testARealMapsSaveReadsTheBaseMapsRoads() throws {
        var world = GameWorld.newWholeTaiwanGame()
        let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
        let position = frame.worldPosition(latitude: 25.0478, longitude: 121.5170)
        let taipei = PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
        _ = try world.buildStation(named: "Taipei", at: taipei)
        let session = GameSession(world: try savedBeforeRoads(world))
        try CommandLogReplay.realWorld.install(
            RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true), in: session
        )
        session.readLandRoundStations()
        XCTAssertNil(session.world.roads)
        XCTAssertNotNil(session.world.landBlocks)
        XCTAssertEqual(session.roadsOffer, .available)

        session.turnOnRoads()
        let roads = try XCTUnwrap(session.world.roads)
        XCTAssertEqual(roads.towns, [], "a real map's roads are the base map's")
        XCTAssertEqual(roads.readBlocks, Set(try XCTUnwrap(session.world.landBlocks)), "every block of its land read")
        XCTAssertGreaterThan(roads.cells.count, 1_000, "Taipei's streets")
        XCTAssertTrue(session.allowsBusTool)

        // The same edit replays to the same world.
        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.9", build: "90", data: [:]).encoded()
        )
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world, session.world)
    }

    /// A real-world map whose land came all at once, or none (version 4's
    /// demo): no roads to read, so the tool says so and offers nothing.
    func testARealMapWithItsLandAllThereHasNoRoadsToRead() throws {
        let world = try fixture("v4-real-world-demo-90-minutes.json")
        XCTAssertNotNil(world.geoAnchor)
        XCTAssertNil(world.landBlocks)
        let session = GameSession(world: world)
        XCTAssertTrue(session.allows(ConstructionTool.bus))
        XCTAssertEqual(session.roadsOffer, .unreadable)
        session.turnOnRoads()
        XCTAssertEqual(session.world, world)
        XCTAssertEqual(session.message?.text, RoadsOffer.unreadable.text(in: .english))
    }

    /// Every committed save without roads: a blank map's turn on round
    /// the towns it began with; a real-world map's land of version 4 came
    /// with it, so it has none to read.
    func testEverySaveWithoutRoadsTurnsThemOnOrSaysWhyNot() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path).filter { $0.hasSuffix(".json") }.sorted()
        var turnedOn = 0
        for name in names {
            let world = try fixture(name)
            guard world.roads == nil else { continue }
            let session = GameSession(world: world)
            if world.geoAnchor != nil {
                XCTAssertEqual(session.roadsOffer, .unreadable, name)
                continue
            }
            XCTAssertEqual(session.roadsOffer, .available, name)
            session.turnOnRoads()
            let roads = try XCTUnwrap(session.world.roads, name)
            XCTAssertEqual(Array(roads.towns.prefix(world.startingTowns().count)), world.startingTowns().map(cell(of:)), name)
            turnedOn += 1
        }
        XCTAssertGreaterThan(turnedOn, 70)
    }

    // MARK: - Refused

    func testTheTutorialAndTheLessonsCannotTurnThemOn() throws {
        let tutorial = GameSession(world: try savedBeforeRoads(.newGame()), language: .english)
        tutorial.startTutorial()
        XCTAssertNotNil(tutorial.tutorial)
        var before = tutorial.world
        XCTAssertNil(before.roads)
        XCTAssertNil(tutorial.roadsOffer)
        XCTAssertFalse(tutorial.allows(ConstructionTool.bus))
        tutorial.turnOnRoads()
        XCTAssertEqual(tutorial.world, before)
        XCTAssertEqual(tutorial.message?.kind, .failure)

        let lesson = GameSession(world: try savedBeforeRoads(GameWorld.newGame(lesson: Lesson.all[2])), language: .english)
        XCTAssertNotNil(lesson.lesson)
        before = lesson.world
        XCTAssertNil(lesson.roadsOffer)
        XCTAssertFalse(lesson.allows(ConstructionTool.bus))
        lesson.turnOnRoads()
        XCTAssertEqual(lesson.world, before)
        XCTAssertEqual(lesson.message?.text, "Roads can't be turned on in the tutorial or a lesson.")
    }

    /// A game with roads: GameCore refuses, nothing changes, and the
    /// refusal is logged.
    func testAGameWithRoadsIsRefused() throws {
        let world = GameWorld.newGame()
        let roads = try XCTUnwrap(world.roads)
        var other = world
        XCTAssertEqual(Result { () throws(GameError) in try other.turnOnRoads(towns: [PlanPoint(x: 0, y: 0)]) }.failure, .roadsEnabled)
        XCTAssertEqual(other, world)
        let session = GameSession(world: world, language: .english)
        XCTAssertNil(session.roadsOffer)
        session.turnOnRoads()
        XCTAssertEqual(session.world.roads, roads)
        XCTAssertEqual(session.message?.text, GameError.roadsEnabled.playerMessage(in: .english))
        XCTAssertEqual(session.commandLog.entries.last?.refused, true)
    }

    // MARK: - The command log

    func testTheEditIsWrittenAndReadBackAndReplays() throws {
        let edits: [PlayerCommand.Edit] = [.turnOnRoads(towns: [PlanPoint(x: 1_024, y: 2_048), PlanPoint(x: 0, y: 64)]), .turnOnRoads(towns: [])]
        for edit in edits {
            XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.Edit.self, from: JSONEncoder().encode(edit)), edit)
            XCTAssertEqual(edit.name, "turnOnRoads")
        }
        let session = GameSession(world: try fixture("v12-land-towns.json"))
        session.turnOnRoads()
        session.advance(ticks: 10)
        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.9", build: "90", data: [:]).encoded()
        )
        XCTAssertTrue(report.entries.contains { $0.action == .command(.edit(.turnOnRoads(towns: session.world.startingTowns()))) })
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world, session.world)
    }

    // MARK: - Words

    func testTheToolSaysWhatTheButtonDoesInBothLanguages() {
        for offer in [RoadsOffer.available, .unreadable] {
            XCTAssertNotEqual(offer.text(in: .english), offer.text(in: .traditionalChinese))
        }
        XCTAssertEqual(RoadsOffer.available.text(in: .traditionalChinese), "這個存檔還沒有道路。打開後，城鎮的路會慢慢長向車站，就能開公車。")
        XCTAssertTrue(HelpGuide.entries(matching: "道路 公車").contains { $0.id == "roadsAndBuses" })
        XCTAssertTrue(HelpGuide.entries(matching: "road bus").contains { $0.id == "roadsAndBuses" })
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
