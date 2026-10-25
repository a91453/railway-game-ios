import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// HANDOFF §5 (#1257: on the CI Simulator the High Speed Rail demo's
/// first map held the main thread 28 to 58 s). What opening the demo
/// works out off the main actor and what on it, as
/// ``GameLauncher/openHighSpeedDemo(railways:)`` and `begin` do, and what
/// the 2D map works out on it for its first draw. Linux cannot time
/// SwiftUI's drawing; it times the work the map hands it. The roads of the
/// demo's 2,489 blocks of land, read in `begin` on the main actor, took
/// 11.5 s of a debug build here before they were read with the build.
/// Run on request (a debug build, as the Simulator's, or `-c release`):
///
///     HSR_FIRST_MAP_REPORT=1 swift test --filter HighSpeedFirstMapReportTests
@MainActor
final class HighSpeedFirstMapReportTests: XCTestCase {
    func testWhatOpeningTheDemoDoesOnTheMainActor() throws {
        guard ProcessInfo.processInfo.environment["HSR_FIRST_MAP_REPORT"] != nil else {
            throw XCTSkip("set HSR_FIRST_MAP_REPORT=1 to time what opening the High Speed Rail demo does on the main actor")
        }
        let clock = ContinuousClock()
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways)
        let baseMap = try BaseMapTiles(
            data: Data(contentsOf: Map3DRealTrainsTests.resources.appendingPathComponent("BaseMap/taiwan.pmtiles"), options: .alwaysMapped)
        )
        var built: GameWorld?
        let make = clock.measure {
            built = try? HighSpeedDemo.make(
                in: .traditionalChinese, railways: railways, population: data.population, places: data.places, water: data.water,
                coverage: data.coverage, heights: data.heights
            )
        }
        var world = try XCTUnwrap(built)
        let roads = clock.measure { world = GameLauncher.readingRoads(of: world, baseMap: baseMap) }
        var rows = [
            "land blocks \(world.landBlocks?.count ?? 0), their roads read \(world.roads?.readBlocks.count ?? 0)",
            "",
            "| What | Where | ms |", "| --- | --- | --: |",
            "| HighSpeedDemo.make | off the main actor | \(LongGameCostReportTests.ms(make)) |",
            "| GameLauncher.readingRoads | off the main actor | \(LongGameCostReportTests.ms(roads)) |",
        ]
        // `begin`'s work, in its order.
        var session: GameSession?
        rows.append("| GameSession.init | main | \(LongGameCostReportTests.ms(clock.measure { session = GameSession(world: world, language: .traditionalChinese) })) |")
        let started = try XCTUnwrap(session)
        started.population = data.population
        started.places = data.places
        started.water = data.water
        started.heights = data.heights
        started.coverage = data.coverage
        started.baseMap = baseMap
        started.railways = railways
        rows.append("| readLandRoundStations | main | \(LongGameCostReportTests.ms(clock.measure { started.readLandRoundStations() })) |")
        rows.append("| worldToSave | main | \(LongGameCostReportTests.ms(clock.measure { _ = started.worldToSave })) |")
        // The 2D map's first draw (`MapView`): on the main actor, but for
        // the line map, which it works out off it.
        let now = started.world
        rows.append("| trafficOverlay | main | \(LongGameCostReportTests.ms(clock.measure { _ = started.trafficOverlay })) |")
        rows.append("| TrainMotion | main | \(LongGameCostReportTests.ms(clock.measure { _ = TrainMotion(world: now, time: 0) })) |")
        rows.append("| MapLayers.waitingPassengerCounts | main | \(LongGameCostReportTests.ms(clock.measure { _ = MapLayers.waitingPassengerCounts(in: now) })) |")
        if let population = data.population, let frame = RealWorldFrame(world: now) {
            rows.append("| PopulationHeatmap | main | \(LongGameCostReportTests.ms(clock.measure { _ = PopulationHeatmap(grid: population, frame: frame) })) |")
        }
        rows.append("| LineMap, StationLabels, MiniMap | off the main actor | \(LongGameCostReportTests.ms(clock.measure { _ = (LineMap(world: now), StationLabels(world: now), MiniMap(world: now)) })) |")
        print(rows.joined(separator: "\n"))
    }
}
