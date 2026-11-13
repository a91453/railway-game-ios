import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// A save of the whole-Taiwan map with real lines laid and their trains
/// running, to time with `SaveTickCostReportTests` when no player's save
/// is at hand (docs/research/TICK_L1_2026-11-13.md). Run on request:
///
///     REAL_MAP_SAVE=/tmp/taiwan.json REAL_MAP_SYSTEMS=tra+hsr REAL_MAP_HOURS=4 \
///       swift test --skip-build --filter RealMapSaveReportTests
///
/// - `REAL_MAP_SAVE`: where the save is written.
/// - `REAL_MAP_SYSTEMS`: `hsr`, `tra` or `tra+hsr` (the default): the High
///   Speed Rail as its demo lays it, the Taiwan Railway's scheduled lines
///   as "lay the real lines" lays them over the whole map.
/// - `REAL_MAP_HOURS`: the hours played before saving, from the demo's
///   start, so the trains are out on the lines (default 3).
/// - `REAL_MAP_BLOCKS=1`: block sections on.
///
/// The world is the one decision 706's `CoachReportTests` measures; it is
/// not a player's save and asserts nothing.
@MainActor
final class RealMapSaveReportTests: XCTestCase {
    func testWritingASaveOfTheWholeMap() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["REAL_MAP_SAVE"] else {
            throw XCTSkip("set REAL_MAP_SAVE=<path> to write a save of the whole-Taiwan map with its real lines")
        }
        let systems = environment["REAL_MAP_SYSTEMS"] ?? "tra+hsr"
        let hours = Int(environment["REAL_MAP_HOURS"] ?? "") ?? 3
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let railways = try XCTUnwrap(data.railways)
        func note(_ text: String) { FileHandle.standardError.write(Data("REALMAP \(text)\n".utf8)) }
        var world: GameWorld
        if systems.contains("hsr") {
            world = try HighSpeedDemo.make(
                in: .english, railways: railways, population: data.population, places: data.places, water: data.water, heights: data.heights
            )
        } else {
            world = HighSpeedDemo.newWorld(paying: Money(0), eventSeed: 1)
            try world.mapGround()
        }
        world.setUnlimitedFunds(true)
        if systems.contains("tra") {
            let session = GameSession(world: world, language: .english)
            session.railways = railways
            session.population = data.population
            session.places = data.places
            session.water = data.water
            session.heights = data.heights
            session.news.isDemo = true
            let began = Date()
            let laid = await session.layDemoRealLines(in: WorldRegion(bounds: world.bounds), routes: .max, anyWidth: true) {
                $0.system.id == "tra_sched"
            }
            note("laid \(laid.map { "\($0.lines) lines, \($0.stations) stations, \($0.missed) missed" } ?? "nothing") in "
                + "\(Int(Date().timeIntervalSince(began))) s: \(session.message?.text ?? "")")
            session.refreshTransfers()
            world = session.world
        }
        if environment["REAL_MAP_BLOCKS"] != nil { world.setBlockSections(true) }
        note("stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count), traffic control \(world.isTrafficControlEnabled), "
            + "block sections \(world.blockSections), \(world.clock.now.clockText)")
        world.setSpeed(.normal)
        let clock = ContinuousClock()
        for hour in 0..<hours {
            let took = try clock.measure { for _ in 0..<60 { try world.advance(ticks: 1) } }
            let placed = world.trains.count { $0.position != nil }
            let moving = world.trains.count { $0.execution != nil }
            note("hour \(hour + 1): \(world.clock.now.clockText), \(took.components.seconds) s, placed \(placed), with a service \(moving)")
        }
        try SaveLibrary.encode(world, at: Date(timeIntervalSince1970: 0)).write(to: URL(fileURLWithPath: path))
        note("wrote \(path)")
    }
}
