import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The real lines the demo mode lays (decision 351) have trains running on
/// them, whatever the system: a line of each, laid by itself.
@MainActor
final class DemoRealLinesEverySystemTests: XCTestCase {
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// The demo game the app opens on the real map (`GameLauncher`): the
    /// whole of Taiwan, its ground read from the real heights.
    private func taiwan() throws -> GameSession {
        let data = Self.data
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.639532, longitudeDegrees: 120.302559))
        let world = GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
            population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights,
            placeNames: data.placeNames
        ), demo: true)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = data.railways
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        session.coverage = data.coverage
        session.news.isDemo = true
        return session
    }

    private static let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)

    /// The view holding `stations` of `system` and 2 km round them.
    private func view(round stations: [String], of system: String, in world: GameWorld) throws -> WorldRegion {
        let points = try stations.map { try BundledRealData.point(try BundledRealData.station($0, in: system).coordinate, in: world) }
        let xs = points.map { Double($0.x) }, ys = points.map { Double($0.y) }, reach = 2_000 * metre
        return WorldRegion(
            minX: try XCTUnwrap(xs.min()) - reach, minY: try XCTUnwrap(ys.min()) - reach,
            maxX: try XCTUnwrap(xs.max()) + reach, maxY: try XCTUnwrap(ys.max()) + reach
        )
    }

    /// Kaohsiung's metro by itself, the whole of it (COACH-HEALTH,
    /// 2026-11-12: 3 lines, 74 stations and not one train): every line
    /// laid has trains on the track.
    func testKaohsiungsMetroHasTrains() async throws {
        let session = try taiwan()
        let railways = try XCTUnwrap(session.railways)
        let stations = railways.stops.filter { $0.key.hasPrefix("krtc|") }.flatMap { $0.value.map(\.chinese) }
        let view = try view(round: stations, of: "krtc", in: session.world)
        let outcome = await session.layDemoRealLines(in: view, routes: .max, anyWidth: true) { $0.system.id == "krtc" }
        XCTAssertGreaterThanOrEqual(outcome?.lines ?? 0, 3, session.message?.text ?? "")
        try assertEveryLineRuns(in: session.world, "krtc")
    }

    /// A line of each system of the bundled railways, its first stations:
    /// laid by itself, it has trains on the track.
    func testALineOfEachSystemHasTrains() async throws {
        let railways = try BundledRealData.railways()
        var keys: [String: String] = [:]
        for key in railways.stops.keys.sorted() {
            let system = String(key.split(separator: "|")[0])
            if keys[system] == nil { keys[system] = key }
        }
        XCTAssertEqual(
            Set(keys.keys), ["tra_sched", "thsr_sched", "afr_sched", "mrt", "tymc", "ntdlrt", "ntalrt", "sanying", "krtc", "tmrt", "hkmtr"],
            "every system of the bundled railways"
        )
        // Hong Kong's MTR is not on Taiwan's map: its lines are laid on its
        // own (`HongKongMapTests`).
        for (system, key) in keys.sorted(by: { $0.key < $1.key }) where system != OverseasMap.hongKong.system {
            let session = try taiwan()
            let stations = try XCTUnwrap(railways.stops[key]).prefix(4).map(\.chinese)
            let view = try view(round: Array(stations), of: system, in: session.world)
            let outcome = await session.layDemoRealLines(in: view, routes: .max, anyWidth: true) { $0.lineKey == key }
            XCTAssertGreaterThanOrEqual(outcome?.lines ?? 0, 1, "\(key): \(session.message?.text ?? "")")
                try assertEveryLineRuns(in: session.world, key)
        }
    }

    /// Every line of `world` has trains assigned, each standing on the
    /// track.
    private func assertEveryLineRuns(in world: GameWorld, _ what: String, file: StaticString = #filePath, line at: UInt = #line) throws {
        XCTAssertFalse(world.lines.isEmpty, what, file: file, line: at)
        for line in world.lines {
            XCTAssertFalse(line.assignedTrains.isEmpty, "\(what): \(line.name) has no train", file: file, line: at)
            for id in line.assignedTrains {
                let train = try XCTUnwrap(world.train(id: id), file: file, line: at)
                XCTAssertNotNil(train.position, "\(what): \(train.name) of \(line.name) stands on the track", file: file, line: at)
            }
        }
    }
}
