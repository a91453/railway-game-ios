import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The owner's 111.1 report (DIAG-HANG): on a real-world map round
/// Kaohsiung's Xiaogang airport, managed, 8 stations, 2 lines, about day
/// 12, the device recorded 77 freezes of some 760 ms and a few of 1.5 to
/// 16 s. What the game does on the main actor there, played as the game
/// loop plays it (each tick worked out off the main actor, then
/// ``GameSession/finish(_:with:)`` on it), at each speed, with each part
/// the loop times; then the other main-actor work that comes round
/// periodically or on a tap: the periodic autosave's look at the world,
/// the problem report's line, the save list. Run on request:
///
///     DIAG_HANG=12 swift test -c release -Xswiftc -enable-testing \
///       --filter XiaogangHangReportTests
@MainActor
final class XiaogangHangReportTests: XCTestCase {
    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    /// Two lines of four stations 700 m apart round the airport, a train on each.
    static func xiaogang(data: RealWorldData) throws -> GameWorld {
        // Kaohsiung International Airport, Xiaogang.
        let anchor = try XCTUnwrap(GeoAnchor(latitude: 225_770_000, longitude: 1_203_500_000))
        var options = NewGameOptions()
        options.funds = .unlimited
        var world = GameLauncher.newWorld(
            at: anchor, options: options,
            data: .init(population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights)
        )
        let tile = try XCTUnwrap(world.mapExpansion?.owned.first)
        let metre = WorldCoordinate.unitsPerMetre, length = MapExpansion.tileLength
        let minX = Int64(tile.column) * length, minY = Int64(tile.row) * length
        for line in 0..<2 {
            let y = minY + length / 2 + Int64(line) * 1_200 * metre
            let points = (0..<4).map { PlanPoint(x: minX + 1_000 * metre + Int64($0) * 700 * metre, y: y) }
            world = try LineBuilder.line(through: points, in: world, carLength: world.platformCarLength)
        }
        GameSession.readLand(roundStationsOf: &world, population: data.population, places: data.places, water: data.water)
        // Managed, as the owner's game.
        world.setEconomyMode(.management)
        return world
    }

    func testWhatTheMainActorDoesRoundXiaogang() async throws {
        guard let value = ProcessInfo.processInfo.environment["DIAG_HANG"], let days = Int(value), (1...30).contains(days) else {
            throw XCTSkip("set DIAG_HANG=<days> to time the Xiaogang game")
        }
        let data = Map3DOpenEveryStartTests.data
        let clock = ContinuousClock()
        let world = try Self.xiaogang(data: data)
        print("DIAG-HANG world: stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count)")
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        session.coverage = data.coverage
        session.railways = data.railways
        session.setSpeed(.fast)
        let meter = FrameCostMeter.shared
        meter.keepsFrameParts = true
        var finishes: [(day: Int64, clock: String, ms: Double)] = []
        let target = Int64(days) * GameTime.secondsPerDay
        while session.world.clock.now.seconds < target {
            guard let tick = session.beginLoopTick() else { break }
            let outcome = await tick.work()
            let spent = clock.measure { session.finish(tick, with: outcome) }
            let now = session.world.clock.now
            finishes.append((now.seconds / GameTime.secondsPerDay, now.clockText, Self.ms(spent)))
            if case .failure(let error) = outcome { XCTFail("\(error)"); break }
        }
        let sorted = finishes.map(\.ms).sorted()
        print(String(
            format: "DIAG-HANG finish on the main actor: %d ticks, mean %.2f ms, p99 %.2f ms, longest %.1f ms, >250 ms %d",
            sorted.count, sorted.reduce(0, +) / Double(max(1, sorted.count)), sorted[min(sorted.count - 1, sorted.count * 99 / 100)],
            sorted.last ?? 0, sorted.filter { $0 > 250 }.count
        ))
        for tick in finishes.sorted(by: { $0.ms > $1.ms }).prefix(12) {
            print(String(format: "DIAG-HANG   costliest: day %lld %@ %.1f ms", tick.day, tick.clock, tick.ms))
        }
        // The periodic autosave's look at the world (every 15 minutes), as
        // when paused: the world unchanged since the last one.
        let saved = session.worldToSave
        let same = session.worldToSave
        print(String(format: "DIAG-HANG worldToSave == unchanged: %.1f ms", Self.ms(clock.measure { _ = saved == same })))
        print(String(format: "DIAG-HANG problemReportGame: %.1f ms", Self.ms(clock.measure { _ = session.problemReportGame })))
        // Saving, as Save Game does, and the list read after it.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DiagHang-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        var bytes = 0
        let save = try clock.measure { bytes = try SaveLibrary.encode(saved, news: session.news, at: Date()).count }
        print(String(format: "DIAG-HANG encode the save: %.0f ms, %d bytes", Self.ms(save), bytes))
        for index in 0..<10 { _ = try library.save(saved, as: .manual, at: Date(timeIntervalSince1970: Double(index))) }
        print(String(format: "DIAG-HANG save list of 10, headers kept: %.1f ms", Self.ms(clock.measure { _ = library.entries() })))
        let fresh = SaveLibrary(directory: directory)
        print(String(format: "DIAG-HANG save list of 10, no header kept: %.1f ms", Self.ms(clock.measure { _ = fresh.entries() })))
        let log = session.commandLog
        var logBytes = 0
        let logSpent = try clock.measure {
            logBytes = try CommandLogReport(log: log, world: saved, version: "0", build: "0", data: [:]).encoded().count
        }
        print(String(format: "DIAG-HANG command log report: %.0f ms, %d bytes", Self.ms(logSpent), logBytes))
    }
}
