import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 820 (PERF-3D-FIRST): how long a save's first 3D scene takes to
/// build, step by step, from the files the app reads for it. A report,
/// not a check: it runs only with `MAP3D_BUILD_SAVE` naming a save file
/// (the player's own, never in the repository). Time it in release, as
/// the phone runs it:
///
///     MAP3D_BUILD_SAVE=/path/to/save.json swift test -c release -Xswiftc -enable-testing \
///         --filter Map3DSceneBuildTimeReportTests
///
/// `MAP3D_BUILD_FOCUS=x,y` (metres from the map's west and north edges)
/// builds round that point instead of the save's busiest station,
/// `MAP3D_BUILD_AT=latitude,longitude` round that place, and
/// `MAP3D_BUILD_MIDDLE=1` round the map's middle;
/// `MAP3D_BUILD_RUNS` builds it that many times (the first is reported
/// apart: it reads the files' pages in).
final class Map3DSceneBuildTimeReportTests: XCTestCase {
    private struct File: Decodable {
        let game: SavedGame
    }

    func testReportOfASave() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["MAP3D_BUILD_SAVE"] else { throw XCTSkip("set MAP3D_BUILD_SAVE to a save file") }
        let world = try JSONDecoder().decode(File.self, from: Data(contentsOf: URL(fileURLWithPath: path))).game.world
        let clock = ContinuousClock()
        @Sendable func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
        }

        // What the app reads (`Map3DSceneCache.task`), from the same files.
        let started = clock.now
        let resources = Map3DRealTrainsTests.resources, base = resources.appendingPathComponent("BaseMap")
        let overseas = OverseasMap.allCases.filter { OverseasMaps.open.contains($0) }
        let cities = overseas.compactMap { city in HongKongRailwaysTests.pack(city).map { (city, $0) } }
        let packs = cities.map(\.1)
        let grounds = try cities.map { try OverseasGround(city: $0.0, pack: $0.1) }
        let ground = grounds.first { $0.holds(world) }
        let tiles = try BaseMapTiles(data: Data(contentsOf: base.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped),
                                     cities: grounds.compactMap(\.baseMap))
        let city = CityTileArea.areas(in: base.appendingPathComponent("city"))
        let footprints = try FootprintTiles(data: Data(contentsOf: base.appendingPathComponent("taiwan_buildings.pmtiles"), options: .alwaysMapped),
                                            cities: packs.compactMap(\.buildingsFile).map { try Data(contentsOf: $0, options: .alwaysMapped) })
        let heights = try ground?.heights ?? HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        let landCover = try LandCoverGrid(data: RealWorldDataLoadTests.file("taiwan_landcover", "dat"))
        let temples = try RealTemples(data: Data(contentsOf: base.appendingPathComponent("taiwan_temples.json")))
        var land = try RealNoBuildLand(data: RealWorldDataLoadTests.file("taiwan_no_build", "json"))
        land.airfields = try RealAirfields(data: Data(contentsOf: base.appendingPathComponent("taiwan_airfields.json")))
        for pack in packs {
            if let own = pack.noBuildLand(airfields: true) { land = land.adding(own) }
        }
        let railways = Map3DRealTrainsTests.railways
        let read = clock.now
        let snapshot = world.railwaySnapshot(), skyline = CitySkyline(world: world)
        let bands = Map3DLineBands(world: world, palette: .standard)
        let worked = clock.now

        // The busiest station: the most others within 3 km.
        let metre = Double(WorldCoordinate.unitsPerMetre)
        var focus: (x: Double, y: Double)?
        if let given = environment["MAP3D_BUILD_FOCUS"]?.split(separator: ",").compactMap({ Double($0) }), given.count == 2 {
            focus = (given[0] * metre, given[1] * metre)
        } else if let given = environment["MAP3D_BUILD_AT"]?.split(separator: ",").compactMap({ Double($0) }), given.count == 2,
                  let frame = RealWorldFrame(world: world) {
            let at = frame.worldPosition(latitude: given[0], longitude: given[1])
            focus = (at.x, at.y)
        } else if environment["MAP3D_BUILD_MIDDLE"] != nil {
            focus = nil
        } else {
            let stations = world.stations.map { (x: Double($0.point.x), y: Double($0.point.y)) }
            focus = stations.max { a, b in
                stations.filter { abs($0.x - a.x) < 3_000 * metre && abs($0.y - a.y) < 3_000 * metre }.count
                    < stations.filter { abs($0.x - b.x) < 3_000 * metre && abs($0.y - b.y) < 3_000 * metre }.count
            }
        }
        print("MAP3D-BUILD save: \(world.stations.count) stations, \(world.network.edges.count) edges, \(world.trains.count) trains, "
            + "focus \(focus.map { "\(Int($0.x / metre)),\(Int($0.y / metre))" } ?? "the middle")")
        print("MAP3D-BUILD read \(String(format: "%.2f", seconds(read - started))) s, snapshot and skyline \(String(format: "%.2f", seconds(worked - read))) s")

        // Linux: the process's memory now and at its peak (`/proc`).
        func memory() -> String {
            let status = (try? String(contentsOfFile: "/proc/self/status", encoding: .utf8)) ?? ""
            return status.split(separator: "\n").filter { $0.hasPrefix("VmRSS") || $0.hasPrefix("VmHWM") }
                .map { $0.split(whereSeparator: \.isWhitespace).dropFirst().first.map { "\((Int($0) ?? 0) >> 10) MB" } ?? "" }
                .joined(separator: " now, peak ")
        }
        print("MAP3D-BUILD memory before building: \(memory())")
        let runs = max(1, Int(environment["MAP3D_BUILD_RUNS"] ?? "") ?? 1)
        // `MAP3D_BUILD_WITH_PACK=1`: the model pack made on another thread
        // as the scene starts, as the app makes it when a pinch rests near
        // the 3D map (decision 546); `=wait` and the scene first asks for
        // the pack, as it did before decision 820.
        let withPack = environment["MAP3D_BUILD_WITH_PACK"]
        if withPack != nil {
            Thread.detachNewThread {
                let begun = clock.now
                let count = Map3DModelPack.standard.models.count
                print("MAP3D-BUILD pack beside the scene: \(count) models in \(String(format: "%.2f", seconds(clock.now - begun))) s")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        for run in 1...runs {
            let begun = clock.now
            if withPack == "wait" { _ = Map3DModelPack.standard.models.count }
            let scene = Map3DScene(world: world, snapshot: snapshot, skyline: skyline, focus: focus, baseMap: tiles, cityTiles: city,
                                   footprints: footprints, heights: heights, landCover: landCover, lineBands: bands, railways: railways,
                                   temples: temples, noBuild: land)
            let took = seconds(clock.now - begun)
            print("MAP3D-BUILD run \(run): \(scene.chunks.count) chunks, \(scene.triangleCount) triangles, built in \(String(format: "%.2f", took)) s, "
                + "memory \(memory())")
            var summed: [(step: String, seconds: Double)] = []
            for (step, time) in scene.steps {
                if let at = summed.firstIndex(where: { $0.step == step }) { summed[at].seconds += time } else { summed.append((step, time)) }
            }
            for (step, time) in summed.sorted(by: { $0.seconds > $1.seconds }) where time >= 0.005 {
                print("MAP3D-BUILD   \(String(format: "%6.2f", time)) s  \(String(format: "%4.1f", 100 * time / took)) %  \(step)")
            }
        }
    }

    /// How long the model pack takes beside the recipes alone
    /// (`MAP3D_BUILD_PACK=1`), the part the scene's catalog of models needs.
    func testReportOfThePack() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_BUILD_PACK"] != nil else { throw XCTSkip("set MAP3D_BUILD_PACK=1") }
        let clock = ContinuousClock()
        func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
        }
        var begun = clock.now
        let recipes = Map3DModelPack(styles: Map3DTrainStyle.all, baked: false)
        print("MAP3D-BUILD recipes: \(recipes.models.count) models in \(String(format: "%.2f", seconds(clock.now - begun))) s")
        begun = clock.now
        let catalog = Map3DModelCatalog.standard
        print("MAP3D-BUILD catalog: \(catalog.names.count) models in \(String(format: "%.2f", seconds(clock.now - begun))) s")
        begun = clock.now
        let pack = Map3DModelPack(styles: Map3DTrainStyle.all)
        print("MAP3D-BUILD pack: \(pack.models.count) models in \(String(format: "%.2f", seconds(clock.now - begun))) s")
    }
}
