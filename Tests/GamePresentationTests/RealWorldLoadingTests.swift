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
        XCTAssertEqual(launcher.realWorldLoading, RealWorldLoading(place: "Jiufen"))
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
}
