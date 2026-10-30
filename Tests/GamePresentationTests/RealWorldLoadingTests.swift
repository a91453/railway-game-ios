import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 307: the loading screen of a real-world map: the place it
/// starts at, the lines and their trains, and the launcher building the
/// map off the main actor with the screen showing meanwhile.
final class RealWorldLoadingTests: XCTestCase {
    private let jiufen = GeoAnchor(latitudeDegrees: 25.11166, longitudeDegrees: 121.84507)!

    /// Place names with one settlement, Jiufen, and no townships.
    private func names() throws -> PlaceNames {
        let file: [String: Any] = [
            "scale": 100_000, "places": [[2_511_166, 12_184_507, "九份", "Jiufen"]], "wards": [] as [Any], "townships": [] as [Any],
        ]
        return try PlaceNames(data: JSONSerialization.data(withJSONObject: file))
    }

    func testThePlaceIsTheNearestName() throws {
        let names = try names()
        XCTAssertEqual(RealWorldLoading.placeName(near: jiufen, in: names, language: .english), "Jiufen")
        XCTAssertEqual(RealWorldLoading.placeName(near: jiufen, in: names, language: .traditionalChinese), "九份")
        // Far from any name, and with no names read: none.
        let kaohsiung = try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.64, longitudeDegrees: 120.30))
        XCTAssertNil(RealWorldLoading.placeName(near: kaohsiung, in: names, language: .english))
        XCTAssertNil(RealWorldLoading.placeName(near: jiufen, in: nil, language: .english))
    }

    func testTheRoutesStayInTheirSquare() {
        XCTAssertEqual(LoadingRoutes.routes.count, 3)
        for route in LoadingRoutes.routes {
            XCTAssertGreaterThan(route.length, 0.5)
            for station in route.stations {
                XCTAssertTrue((0 ... 1).contains(station.x) && (0 ... 1).contains(station.y))
            }
            XCTAssertEqual(route.point(at: 0), route.stations.first)
            XCTAssertEqual(route.point(at: 1), route.stations.last)
        }
        // Halfway along the line across is past its second station.
        let across = LoadingRoutes.routes[0]
        XCTAssertGreaterThan(across.point(at: 0.5).x, across.stations[1].x)
    }

    /// Each train runs to the end of its line and back at an even speed;
    /// with Reduce Motion it stands where it starts.
    func testTheTrainsRunThereAndBack() {
        let route = LoadingRoutes.routes[0]
        let seconds = LoadingRoutes.crossingSeconds
        XCTAssertEqual(LoadingRoutes.share(of: route, elapsed: 0, reduceMotion: false), route.start, accuracy: 1e-9)
        let toEnd = (1 - route.start) * seconds
        XCTAssertEqual(LoadingRoutes.share(of: route, elapsed: toEnd, reduceMotion: false), 1, accuracy: 1e-9)
        XCTAssertEqual(LoadingRoutes.share(of: route, elapsed: toEnd + seconds / 2, reduceMotion: false), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LoadingRoutes.share(of: route, elapsed: toEnd + seconds, reduceMotion: false), 0, accuracy: 1e-9)
        XCTAssertEqual(LoadingRoutes.share(of: route, elapsed: 2 * seconds, reduceMotion: false), route.start, accuracy: 1e-9)
        // An even speed: equal steps of time, equal steps along the line.
        let a = LoadingRoutes.share(of: route, elapsed: 0.5, reduceMotion: false)
        let b = LoadingRoutes.share(of: route, elapsed: 1.0, reduceMotion: false)
        XCTAssertEqual(b - a, a - route.start, accuracy: 1e-9)
        for elapsed in [0.0, 1.3, 7.9, 100] {
            XCTAssertEqual(
                LoadingRoutes.train(of: route, elapsed: elapsed, reduceMotion: true), route.point(at: route.start),
                "With Reduce Motion the trains stand still"
            )
        }
        // The three trains start at different places, so they never move
        // as one.
        XCTAssertEqual(Set(LoadingRoutes.routes.map(\.start)).count, 3)
    }

    // MARK: - The game launcher

    @MainActor
    private func launcher() -> (GameLauncher, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RealWorldLoadingTests-\(UUID().uuidString)", isDirectory: true)
        return (GameLauncher(library: SaveLibrary(directory: directory), language: .english), directory)
    }

    /// The map is built off the main actor with the loading screen
    /// showing, then the game opens on it, as ``startNewGame(at:)`` would.
    @MainActor
    func testTheLauncherShowsTheScreenWhileItBuilds() async throws {
        let (launcher, directory) = launcher()
        defer { try? FileManager.default.removeItem(at: directory) }
        launcher.placeNames = try names()
        let task = launcher.openRealWorldGame(at: jiufen)
        XCTAssertEqual(launcher.realWorldLoading, RealWorldLoading(place: "Jiufen", steps: [.layingOutMap]), "no people or heights here")
        XCTAssertNil(launcher.openRealWorldGame(at: jiufen), "one map at a time")
        XCTAssertNil(launcher.session, "still loading")
        await task?.value
        XCTAssertNil(launcher.realWorldLoading)
        let world = try XCTUnwrap(launcher.session?.world)
        XCTAssertEqual(world.geoAnchor, jiufen)

        let (direct, other) = self.launcher()
        defer { try? FileManager.default.removeItem(at: other) }
        direct.startNewGame(at: jiufen)
        XCTAssertEqual(direct.session?.world.bounds, world.bounds, "the same map startNewGame builds")
    }

    /// A game the player starts while it builds is not taken over by it.
    @MainActor
    func testAGameStartedWhileItBuildsStays() async throws {
        let (launcher, directory) = launcher()
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = launcher.openRealWorldGame(at: jiufen)
        launcher.openDemo()
        let simple = try XCTUnwrap(launcher.session?.world)
        await task?.value
        XCTAssertNil(launcher.realWorldLoading)
        XCTAssertEqual(launcher.session?.world, simple)
    }

    // MARK: - Steps and cancelling (decision 473)

    /// The bar moves only as steps finish (and, reading roads, as its
    /// tiles are read), never back, and says which step it is on.
    func testTheStepsCountWhatIsDone() {
        let start = RealWorldLoading(place: "Jiufen", steps: [.countingPeople, .layingOutMap, .shapingGround])
        XCTAssertEqual(start.fraction, 0)
        XCTAssertEqual(start.step, .countingPeople)
        XCTAssertTrue(start.showsProgress)
        XCTAssertEqual(start.stepLine(in: .english), "Step 1 of 3: Counting people and jobs")
        XCTAssertEqual(start.stepLine(in: .traditionalChinese), "第 1 步，共 3 步：計算人口與工作")
        let one = start.advanced()
        XCTAssertEqual(one.fraction, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(one.stepLine(in: .english), "Step 2 of 3: Laying out the map")
        XCTAssertEqual(one.percentText(), "33%")
        // A share of a step counts, but never goes back.
        XCTAssertEqual(one.counting(0.5).fraction, 1.5 / 3, accuracy: 1e-9)
        XCTAssertEqual(one.counting(0.5).counting(0.2).fraction, 1.5 / 3, accuracy: 1e-9)
        XCTAssertEqual(one.counting(7).fraction, 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(one.counting(0.5).advanced().fraction, 2.0 / 3, accuracy: 1e-9, "a finished step starts the next at none")
        let all = one.advanced().advanced().advanced()
        XCTAssertEqual(all.fraction, 1)
        XCTAssertEqual(all.step, .shapingGround, "the last step stays as the game opens")
        XCTAssertEqual(all.stepLine(in: .english), "Step 3 of 3: Shaping the ground")
        // One step: no counter, and a bar only where its share is counted.
        let roads = RealWorldLoading(place: nil, steps: [.readingRoads])
        XCTAssertEqual(roads.stepLine(in: .english), "Reading the roads")
        XCTAssertTrue(roads.showsProgress)
        XCTAssertFalse(RealWorldLoading(place: nil, steps: [.layingOutMap]).showsProgress)
        XCTAssertNil(RealWorldLoading(place: nil).stepLine(in: .english))
        XCTAssertEqual(RealWorldLoading(place: nil).fraction, 0)
        // Every step says what it does in both languages.
        for step in [LoadingStep.readingSave, .countingPeople, .layingOutMap, .layingLine, .shapingGround, .readingRoads] {
            XCTAssertNotEqual(step.text(in: .english), step.text(in: .traditionalChinese))
        }
    }

    func testTheButtonSaysWhereItGoesBack() {
        XCTAssertEqual(RealWorldLoading(place: nil).cancelTitle(in: .english), "Back to Start Screen")
        XCTAssertEqual(RealWorldLoading(place: nil).cancelTitle(in: .traditionalChinese), "回開始畫面")
        XCTAssertEqual(RealWorldLoading(place: nil, backTo: .game).cancelTitle(in: .english), "Back to Game")
        XCTAssertEqual(RealWorldLoading(place: nil, backTo: .game).cancelTitle(in: .traditionalChinese), "回到遊戲")
    }

    /// Cancelled, the screen goes at once, no game opens when the build
    /// ends, and another map can be opened straight away.
    @MainActor
    func testCancellingLeavesTheStartScreenAsItWas() async throws {
        let (launcher, directory) = launcher()
        defer { try? FileManager.default.removeItem(at: directory) }
        launcher.cancelLoading()
        XCTAssertNil(launcher.realWorldLoading, "nothing to cancel")
        let task = launcher.openRealWorldGame(at: jiufen)
        XCTAssertNotNil(launcher.realWorldLoading)
        launcher.cancelLoading()
        XCTAssertNil(launcher.realWorldLoading, "the screen goes at once")
        let again = launcher.openRealWorldGame(at: jiufen)
        XCTAssertNotNil(again, "another can be opened at once")
        launcher.cancelLoading()
        await task?.value
        await again?.value
        XCTAssertNil(launcher.session, "no game opened")
        XCTAssertNil(launcher.realWorldLoading)
        XCTAssertFalse(launcher.isOpeningADemo)
        // And one not cancelled still opens.
        await launcher.openRealWorldGame(at: jiufen)?.value
        XCTAssertEqual(launcher.session?.world.geoAnchor, jiufen)
    }

    /// The High Speed Rail, cancelled while its line is laid: the step
    /// shown is the one running, its flag is put back at once, and when
    /// the step ends no game opens and nothing is said to have failed.
    @MainActor
    func testCancellingTheHighSpeedRailWhileItIsLaid() async throws {
        let (launcher, directory) = launcher()
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = launcher.openHighSpeedDemo(railways: try HighSpeedDemoTests.railways())
        XCTAssertEqual(launcher.realWorldLoading?.steps, [.layingLine, .readingRoads])
        XCTAssertEqual(launcher.realWorldLoading?.stepLine(in: .english), "Step 1 of 2: Laying the line and its trains")
        XCTAssertEqual(launcher.realWorldLoading?.cancelTitle(in: .english), "Back to Start Screen")
        launcher.cancelLoading()
        XCTAssertFalse(launcher.isOpeningHighSpeedDemo)
        XCTAssertNil(launcher.realWorldLoading)
        await task?.value
        XCTAssertNil(launcher.session, "no game opened")
        XCTAssertNil(launcher.message, "and nothing said failed")
        XCTAssertNil(launcher.realWorldLoading)
    }

    /// A step is marked done when its work comes back, and none runs once
    /// the loading is stopped.
    @MainActor
    func testARunCountsItsStepsAndStopsWhenCancelled() async {
        let run = GameLauncher.LoadingRun(RealWorldLoading(place: nil, steps: [.layingOutMap, .shapingGround, .readingRoads]))
        var shown: [Int] = []
        run.publish = { shown.append($0.done) }
        let first = await run.step { meter in
            meter.share = 0.5
            return 1
        }
        XCTAssertEqual(first, 1)
        XCTAssertEqual(run.loading.done, 1)
        XCTAssertEqual(run.loading.stepShare, 0, "the next step starts at none")
        XCTAssertEqual(shown.last, 1)
        XCTAssertTrue(run.finishedElsewhere())
        XCTAssertEqual(run.loading.done, 2)
        XCTAssertEqual(shown, shown.sorted(), "it only goes forward")
        run.meter.cancel()
        let ran = LoadingMeter()
        let third = await run.step { _ in
            ran.cancel()
            return 3
        }
        XCTAssertNil(third)
        XCTAssertFalse(ran.isCancelled, "a step after cancelling does not run")
        XCTAssertEqual(run.loading.done, 2)
        XCTAssertFalse(run.finishedElsewhere())
    }

    /// Reading roads stops at its next tile once cancelled: none read.
    func testReadingRoadsStopsWhenCancelled() throws {
        let tiles = try BaseMapTiles(
            data: Data(contentsOf: Map3DRealTrainsTests.resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped)
        )
        let world = GameWorld.newGame(anchor: jiufen, balance: 1_000_000, eventSeed: 1, land: [])
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        // The blocks round the middle of the map, Jiufen.
        let middle = Int(world.bounds.width / Land.blockLength) / 2
        let blocks = Set((middle - 1 ... middle + 1).flatMap { row in (middle - 1 ... middle + 1).map { LandBlock(row: row, column: $0) } })
        let read = RealRoadCells.read(blocks: blocks, tiles: tiles, frame: frame, bounds: world.bounds)
        XCTAssertFalse(read.roads.isEmpty, "Jiufen has roads")
        let meter = LoadingMeter()
        _ = RealRoadCells.read(blocks: blocks, tiles: tiles, frame: frame, bounds: world.bounds, meter: meter)
        XCTAssertGreaterThan(meter.share, 0, "its share counted")
        let stopped = LoadingMeter()
        stopped.cancel()
        XCTAssertTrue(RealRoadCells.read(blocks: blocks, tiles: tiles, frame: frame, bounds: world.bounds, meter: stopped).roads.isEmpty)
    }
}

/// Decision 473 (landscape): the lines fit the height of an iPhone held
/// sideways and stay full size otherwise.
final class LoadingLayoutTests: XCTestCase {
    func testUprightKeepsTheFullSquare() {
        XCTAssertEqual(LoadingLayout.mapSide(height: 800, sideBySide: false), 220)
        XCTAssertEqual(LoadingLayout.mapSide(height: 300, sideBySide: false), 220)
    }

    func testSidewaysFitsTheHeight() {
        // An iPhone held sideways is about 390 points tall, less the bars.
        for height in stride(from: 150.0, through: 430.0, by: 10) {
            let side = LoadingLayout.mapSide(height: height, sideBySide: true)
            XCTAssertLessThanOrEqual(side, 220)
            XCTAssertGreaterThanOrEqual(side, 120)
            if height >= 152 {
                XCTAssertLessThanOrEqual(side + 2 * LoadingLayout.sideBySideMargin, height)
            }
        }
        XCTAssertEqual(LoadingLayout.mapSide(height: 350, sideBySide: true), 220)
        XCTAssertEqual(LoadingLayout.mapSide(height: 200, sideBySide: true), 168)
    }
}
