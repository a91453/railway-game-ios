import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The new game's ground on a real-world map (ARCHITECTURE decision 198):
/// real, as decision 124 reads it, or flat, where track is always level
/// and no grade or tunnel is needed; kept with the other new game options
/// and in the game's saves.
@MainActor
final class FlatGroundTests: XCTestCase {
    private static let grid: HeightGrid = {
        do {
            return try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    /// A mountainside in Nantou, east of Shuili.
    private static let mountainside = GeoAnchor(latitudeDegrees: 23.5103, longitudeDegrees: 120.8050)

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FlatGroundTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func launcher() -> GameLauncher {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.heights = Self.grid
        return launcher
    }

    // MARK: - The option

    func testTheGroundIsRealUnlessChosenFlat() {
        XCTAssertEqual(NewGameOptions().ground, .real)
        XCTAssertEqual(NewGameOptions.Ground.allCases.map { $0.title(in: .traditionalChinese) }, ["真實", "平坦"])
        XCTAssertEqual(NewGameOptions.Ground.allCases.map { $0.title(in: .english) }, ["Real", "Flat"])

        var options = NewGameOptions()
        XCTAssertFalse(options.summary(in: .traditionalChinese).contains("地形"), "the real ground is not a change")
        options.ground = .flat
        XCTAssertTrue(options.summary(in: .traditionalChinese).contains("已更改：實景地圖地形平坦。"))
        XCTAssertTrue(options.summary(in: .english).contains("Changed: flat ground on real-world maps."))
    }

    /// The options written before the ground was asked still read, as real
    /// ground, and keep the player's other choices and preferences.
    func testAnOlderPreferencesFileStillReads() throws {
        let older = Data("""
            {"firstGameCardDismissed":true,"hasLaunched":true,\
            "newGameOptions":{"buildingMaterials":false,"buysMap":true,"difficulty":"expert","outsideConnections":true,"seed":42},\
            "tutorialCompleted":true}
            """.utf8)
        let preferences = try JSONDecoder().decode(LauncherPreferences.self, from: older)
        XCTAssertTrue(preferences.hasLaunched)
        XCTAssertTrue(preferences.tutorialCompleted)
        XCTAssertEqual(preferences.newGameOptions.difficulty, .expert)
        XCTAssertFalse(preferences.newGameOptions.buildingMaterials)
        XCTAssertEqual(preferences.newGameOptions.seed, 42)
        XCTAssertEqual(preferences.newGameOptions.ground, .real)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try older.write(to: directory.appendingPathComponent(GameLauncher.preferencesFileName))
        let launcher = launcher()
        XCTAssertFalse(launcher.isFirstLaunch, "not read as a first launch")
        XCTAssertEqual(launcher.newGameOptions.difficulty, .expert)
        XCTAssertEqual(launcher.newGameOptions.ground, .real)

        // The flat ground is kept for the next launch.
        launcher.newGameOptions.ground = .flat
        XCTAssertEqual(self.launcher().newGameOptions.ground, .flat)
        var written = NewGameOptions()
        written.ground = .flat
        XCTAssertEqual(try JSONDecoder().decode(NewGameOptions.self, from: try JSONEncoder().encode(written)), written)
    }

    // MARK: - The game

    /// On real ground a new real-world game reads its ground; on flat
    /// ground it has none: 0 m everywhere, nothing to read before building.
    func testARealWorldGameOnFlatGroundHasNone() throws {
        let anchor = try XCTUnwrap(Self.mountainside)
        let launcher = launcher()
        launcher.startNewGame(at: anchor)
        XCTAssertEqual(launcher.session?.world.ground.isMapped, true, "real unless chosen flat")

        launcher.newGameOptions.ground = .flat
        launcher.startNewGame(at: anchor)
        let world = try XCTUnwrap(launcher.session?.world)
        XCTAssertEqual(world.geoAnchor, anchor)
        XCTAssertFalse(world.ground.isMapped)
        let step = GameWorld.newGameBounds.width / 8
        let points = stride(from: step / 2, to: GameWorld.newGameBounds.width, by: Int64.Stride(step)).flatMap { x in
            stride(from: step / 2, to: GameWorld.newGameBounds.height, by: Int64.Stride(step)).map { PlanPoint(x: x, y: $0) }
        }
        XCTAssertEqual(Set(points.compactMap(world.groundHeight(at:))), [0])
        XCTAssertEqual(world.missingGroundBlocks(under: points), [])

        launcher.startWholeTaiwan()
        XCTAssertEqual(launcher.session?.world.ground.isMapped, false, "the whole of Taiwan too")
    }

    /// Track across the mountainside is laid level on flat ground, with no
    /// tunnel, and stays so after the game is saved and continued.
    func testTrackOverTheHillsIsLevelAndStaysSoAfterASave() throws {
        let anchor = try XCTUnwrap(Self.mountainside)
        let launcher = launcher()
        launcher.newGameOptions.ground = .flat
        launcher.startNewGame(at: anchor)
        let session = try XCTUnwrap(launcher.session)
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let middle = GameWorld.newGameBounds.width / 2
        let start = PlanPoint(x: middle, y: middle), end = PlanPoint(x: middle + 32_768, y: middle)
        XCTAssertGreaterThan(abs(Self.grid.height(at: start, frame: frame) - Self.grid.height(at: end, frame: frame)), 20,
                             "the real ground climbs more than 20 m in 512 m")

        func buildLevel(_ session: GameSession, from start: PlanPoint, to end: PlanPoint) {
            session.selectTool(.network)
            session.tapNetwork(at: start, reach: 16)
            session.tapNetwork(at: end, reach: 16)
            XCTAssertNil(session.networkPreview?.problem)
            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
            let network = session.world.network
            XCTAssertTrue(network.nodes.allSatisfy { $0.position.z == 0 }, "level")
            XCTAssertFalse(network.edges.contains { $0.structure == .tunnel || $0.sections.contains { $0.kind != .surface } }, "no tunnel")
            XCTAssertFalse(session.world.ground.isMapped)
        }
        buildLevel(session, from: start, to: end)
        XCTAssertEqual(session.world.network.edges.count, 1)

        launcher.returnToStart()
        launcher.continueGame()
        let continued = try XCTUnwrap(launcher.session)
        XCTAssertFalse(continued.world.ground.isMapped, "flat in its save")
        XCTAssertEqual(continued.world.network.edges.count, 1)
        buildLevel(continued, from: end, to: PlanPoint(x: middle + 65_536, y: middle))
        XCTAssertEqual(continued.world.network.edges.count, 2)
    }

    // MARK: - The height layer

    /// The height layer shows the land as it is on flat ground too, and
    /// says the track is level whatever the heights.
    func testTheHeightLayerSaysTheTrackIsLevel() throws {
        let anchor = try XCTUnwrap(Self.mountainside)
        let flat = TerrainMap(world: GameWorld.newGame(anchor: anchor), heights: Self.grid)
        XCTAssertFalse(flat.isFlat)
        XCTAssertTrue(flat.tracksLevel)

        var real = GameWorld.newGame(anchor: anchor)
        try real.mapGround()
        XCTAssertFalse(TerrainMap(world: real, heights: Self.grid).tracksLevel)
        XCTAssertFalse(TerrainMap(world: real, heights: nil).tracksLevel)
        XCTAssertFalse(TerrainMap(world: GameWorld.newGame(), heights: Self.grid).tracksLevel, "a blank map is flat, not level ground")
    }
}
