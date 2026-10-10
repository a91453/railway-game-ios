import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Item 1a ②: the app's real-world data (the population and places grids
/// and the real railways) is read off the main actor at launch. Until it
/// has been, the launcher says it is loading and has none of it; then all
/// of it arrives at once, to the launcher and to a game already being
/// played. A file that cannot be read is listed, as before.
@MainActor
final class RealWorldDataLoadTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RealWorldDataLoadTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The app's files from the repository, where the app bundles them
    /// flat: `Resources/RealWorld/` and `Resources/RealRailways/`.
    nonisolated static func file(_ name: String, _ ext: String) throws -> Data {
        let realWorld = BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/\(name).\(ext)")
        if FileManager.default.fileExists(atPath: realWorld.path) {
            return try Data(contentsOf: realWorld)
        }
        return try BundledRealData.file(name, ext)
    }

    private static let taipei = GeoAnchor(latitudeDegrees: 25.047882, longitudeDegrees: 121.517219)

    func testTheBundledDataLoadsWithoutIssues() throws {
        let data = RealWorldData.load(file: Self.file)
        XCTAssertEqual(data.issues, [])
        XCTAssertNotNil(data.population)
        XCTAssertNotNil(data.places)
        XCTAssertNotNil(data.water)
        XCTAssertNotNil(data.heights)
        XCTAssertNotNil(data.coverage)
        XCTAssertNotNil(data.railways?.stationData?.overtakeTracks)
    }

    /// A grid that cannot be read is listed and left out, keeping the
    /// rest; the railways' optional files still fail on their own (#171).
    func testAFileThatCannotBeReadIsListedAndTheRestLoads() throws {
        let data = RealWorldData.load { name, ext in
            switch name {
            case "taiwan_population": throw RealRailways.ResourceError.missing("\(name).\(ext)")
            case "tra_overtake_tracks": return Data("not json".utf8)
            default: return try Self.file(name, ext)
            }
        }
        XCTAssertEqual(data.issues.map(\.file), ["taiwan_population.json", "tra_overtake_tracks.json"])
        XCTAssertNil(data.population)
        XCTAssertNotNil(data.places)
        XCTAssertNotNil(data.railways?.stationData)
        XCTAssertNil(data.railways?.stationData?.overtakeTracks)

        let broken = RealWorldData.load { name, ext in
            name == "track_lines" ? Data("[]".utf8) : try Self.file(name, ext)
        }
        XCTAssertNil(broken.railways, "no map files, no railways")
        XCTAssertNotNil(broken.population)
        XCTAssertEqual(broken.issues.map(\.file), ["track_lines.geojson, track_stations.geojson, station_names.json"])
    }

    /// Nothing of the data is there until it all is; a blank game started
    /// meanwhile (or one continued) gets it when it arrives.
    func testTheDataArrivesAllAtOnceAfterTheLaunch() async throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        XCTAssertFalse(launcher.isLoadingRealWorldData, "not asked for yet")
        let load = launcher.loadRealWorldData { RealWorldData.load(file: Self.file) }
        // The read is off the main actor and comes back to it, which this
        // test holds until it awaits: nothing has arrived yet.
        XCTAssertTrue(launcher.isLoadingRealWorldData)
        XCTAssertNil(launcher.population)
        XCTAssertNil(launcher.places)
        XCTAssertNil(launcher.railways)
        XCTAssertEqual(launcher.realWorldIssues, [])

        launcher.startNewGame()
        let session = try XCTUnwrap(launcher.session, "a blank game does not wait for the data")
        XCTAssertNil(session.railways)

        await load.value
        XCTAssertFalse(launcher.isLoadingRealWorldData)
        XCTAssertNotNil(launcher.population)
        XCTAssertNotNil(launcher.places)
        XCTAssertNotNil(launcher.railways)
        XCTAssertEqual(launcher.realWorldIssues, [])
        XCTAssertTrue(launcher.session === session, "the same game goes on")
        XCTAssertNotNil(session.population)
        XCTAssertNotNil(session.places)
        XCTAssertNotNil(session.railways)
    }

    /// Once the data is there, a real-world game gets its people, off its
    /// water (decision 105), with their real coverage (decision 147), and
    /// the real-world demo can open.
    func testARealWorldGameAfterTheLoadHasItsPeople() async throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        await launcher.loadRealWorldData { RealWorldData.load(file: Self.file) }.value
        let anchor = try XCTUnwrap(Self.taipei)
        launcher.startNewGame(at: anchor)
        let population = try XCTUnwrap(launcher.population)
        let water = try XCTUnwrap(launcher.water)
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        let imported = LandImport.cells(population: population, places: launcher.places, water: water, frame: frame, bounds: GameWorld.newGameBounds)
        let expected = try XCTUnwrap(launcher.coverage).covering(try XCTUnwrap(imported), frame: frame)
        XCTAssertEqual(launcher.session?.world.land.cells, expected)
        XCTAssertEqual(launcher.session?.world.terrain, Terrain(
            water: water.cells(frame: frame, bounds: GameWorld.newGameBounds), steep: water.steepCells(frame: frame, bounds: GameWorld.newGameBounds)
        ))
        XCTAssertTrue(launcher.session?.water != nil)
        XCTAssertNotNil(launcher.session?.railways)

        launcher.returnToStart()
        launcher.openRealWorldDemo(railways: try XCTUnwrap(launcher.railways))
        XCTAssertEqual(launcher.session?.world.geoAnchor, RealWorldDemo.anchor)
    }

    /// The data is read once: a second call (another window) waits for
    /// the first read rather than starting its own.
    func testTheDataIsReadOnce() async throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let first = RealDataLoadIssue(file: "first.json", reason: "first")
        let firstLoad = launcher.loadRealWorldData { RealWorldData(population: nil, places: nil, railways: nil, issues: [first]) }
        let secondLoad = launcher.loadRealWorldData {
            RealWorldData(population: nil, places: nil, railways: nil, issues: [RealDataLoadIssue(file: "second.json", reason: "second")])
        }
        XCTAssertEqual(firstLoad, secondLoad)
        await secondLoad.value
        XCTAssertEqual(launcher.realWorldIssues, [first])
        XCTAssertFalse(launcher.isLoadingRealWorldData)
        XCTAssertNil(launcher.railways, "nothing could be read: the demo stays closed")
    }
}
