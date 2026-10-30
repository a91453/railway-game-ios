import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The bug hunt for hangs before the public beta
/// (docs/research/BUGHUNT_HANG_2026-10-30.md): the largest games the app
/// opens, run at the fastest speed for `HANG_REPORT` days (1 to 30), a
/// tick at a time as the game loop runs them, and what each tick costs, at
/// its longest and in the 99th percentile, with the deadlocks at the end;
/// then what saving and loading the game cost. Run on request, in a
/// release build:
///
///     HANG_REPORT=3 swift test -c release -Xswiftc -enable-testing \
///       --filter HangReportTests
@MainActor
final class HangReportTests: XCTestCase {
    private func days() throws -> Int {
        guard let value = ProcessInfo.processInfo.environment["HANG_REPORT"] else {
            throw XCTSkip("set HANG_REPORT=<days> to time the largest games at the fastest speed")
        }
        return try XCTUnwrap(Int(value).flatMap { (1...30).contains($0) ? $0 : nil }, "HANG_REPORT is 1 to 30 days")
    }

    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    /// Runs `world` at the fastest speed for `days` days and prints the
    /// ticks' cost.
    private func time(_ name: String, _ start: GameWorld, days: Int, trafficControl: Bool? = nil) throws -> [String] {
        var world = start
        if let trafficControl {
            do { try world.setTrafficControl(trafficControl) } catch { return ["| \(name) | not run: \(error) |"] }
        }
        world.setSpeed(.fast)
        let clock = ContinuousClock()
        var ticks: [(time: GameTime, ms: Double)] = []
        for _ in 0..<(days * 144) {
            let spent = try clock.measure { try world.advance(ticks: 1) }
            ticks.append((world.clock.now, Self.ms(spent)))
        }
        let sorted = ticks.map(\.ms).sorted()
        let p99 = sorted[min(sorted.count - 1, sorted.count * 99 / 100)]
        let deadlocked = clock.measure { _ = world.deadlockedTrains() }
        var rows = [
            String(
                format: "| %@ | %d | %d | %d | %@ | %.1f | %.1f | %.1f | %d | %d | %d | %.1f |",
                name, world.stations.count, world.lines.count, world.trains.count, world.isTrafficControlEnabled ? "on" : "off",
                sorted.reduce(0, +) / Double(sorted.count), p99, sorted.last ?? 0,
                sorted.filter { $0 > 100 }.count, sorted.filter { $0 > 1_000 }.count,
                world.deadlockedTrains().count, Self.ms(deadlocked)
            ),
        ]
        for tick in ticks.sorted(by: { $0.ms > $1.ms }).prefix(3) {
            rows.append(String(format: "|   costliest: day %lld %@ | | | | | | | %.1f | | | | |", tick.time.seconds / GameTime.secondsPerDay, tick.time.clockText, tick.ms))
        }
        // Saving and loading, as the save library does them.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HangReport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        var entry: SaveLibrary.Entry?
        let save = try clock.measure { entry = try library.save(world, as: .manual, at: Date()) }
        let saved = try XCTUnwrap(entry)
        let load = try clock.measure { _ = try library.load(saved) }
        rows.append(String(format: "|   save %.0f ms, load %.0f ms | | | | | | | | | | | |", Self.ms(save), Self.ms(load)))
        print(rows.joined(separator: "\n"))
        return rows
    }

    private static let header = [
        "| Game | Stations | Lines | Trains | Control | Mean ms | p99 ms | Longest ms | >100 ms | >1 s | Deadlocked | deadlockedTrains() ms |",
        "| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]

    func testTheDemosAtTheFastestSpeed() throws {
        let days = try days()
        var rows = Self.header
        let hsr = try MapFrameCostReportTests.highSpeedSession().world
        rows += try time("High Speed Rail", hsr, days: days)
        rows += try time("High Speed Rail, no control", hsr, days: days, trafficControl: false)
        let yilan = try TRADemoTests.opened.get()
        rows += try time("Yilan Line", yilan, days: days)
        rows += try time("Yilan Line, control on", yilan, days: days, trafficControl: true)
        print(rows.joined(separator: "\n"))
    }

    /// A real line's card (decision 315): what laying out each city
    /// opening's lines takes, and, decision 497, what the tap that now lays
    /// it out off the main actor holds the main actor for.
    func testWhatARealLineOfferTakes() throws {
        _ = try days()
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let clock = ContinuousClock()
        var rows = ["| Opening | Line | Offer ms | Tap on the main actor ms |", "| --- | --- | ---: | ---: |"]
        for city in AcquisitionReportTests.cities {
            let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: city.latitude, longitudeDegrees: city.longitude))
            let world = GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
                population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
            ))
            let session = GameSession(world: world, language: .english)
            session.population = data.population
            session.places = data.places
            session.water = data.water
            session.heights = data.heights
            session.coverage = data.coverage
            session.railways = data.railways
            for line in session.buyableRealLines {
                let spent = clock.measure { _ = session.realLineOffer(for: line) }
                // Decision 497: what the tap itself now holds the main actor for.
                let tap = clock.measure { session.offerRealLine(line) }
                session.closeRealLineOffer()
                rows.append(String(format: "| %@ | %@ | %.0f | %.1f |", city.name, line.id, Self.ms(spent), Self.ms(tap)))
            }
        }
        print(rows.joined(separator: "\n"))
    }

    /// The fixed frame test's game (decision 421): Taipei with 20 real
    /// lines, as the demo mode lays them.
    func testTwentyRealLinesAtTheFastestSpeed() async throws {
        let days = try days()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HangReport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.loadRealWorldData { Map3DOpenEveryStartTests.data }.value
        let clock = ContinuousClock()
        var opened: GameSession?
        let lay = await clock.measure { opened = await launcher.openFrameTimeBench(lines: 20) }
        let world = try XCTUnwrap(opened).world
        var rows = ["Laying 20 lines: \(lay)"] + Self.header
        rows += try time("Taipei 20 lines", world, days: days)
        rows += try time("Taipei 20 lines, control on", world, days: days, trafficControl: true)
        print(rows.joined(separator: "\n"))
    }

    /// The owner's 97.1 report (decision 497, P2-2): going back to the
    /// start screen takes longer the more saves there are. What writing
    /// the high-speed demo's autosave takes, what reading the list takes
    /// with 5, 20 and 50 such saves (the first read of a library, then
    /// again with nothing changed), and how long Back to Start takes from
    /// the tap to the start screen, and holds the main actor for.
    func testWhatTheSaveListTakes() async throws {
        _ = try days()
        let world = try MapFrameCostReportTests.highSpeedSession().world
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HangReport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = ContinuousClock()
        var entry: SaveLibrary.Entry?
        let save = try clock.measure { entry = try SaveLibrary(directory: directory).save(world, as: .manual, at: Date()) }
        let saved = try XCTUnwrap(entry)
        let file = directory.appendingPathComponent(saved.id)
        let bytes = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        var rows = [
            String(format: "Saving the high-speed demo: %.0f ms, %.1f MB", Self.ms(save), Double(bytes) / 1_048_576),
            "| Saves | First read ms | Read again ms |", "| ---: | ---: | ---: |",
        ]
        var count = 1
        for target in [5, 20, 50] {
            while count < target {
                try FileManager.default.copyItem(at: file, to: directory.appendingPathComponent("save-copy-\(count).json"))
                count += 1
            }
            let library = SaveLibrary(directory: directory)
            var listed = 0
            let first = clock.measure { listed = library.entries().count }
            let again = clock.measure { listed = library.entries().count }
            XCTAssertEqual(listed, target)
            rows.append(String(format: "| %d | %.0f | %.0f |", target, Self.ms(first), Self.ms(again)))
        }
        // Back to Start with the 50 saves, the list already read once.
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        launcher.refresh()
        await launcher.load(saved)?.value
        XCTAssertNotNil(launcher.session)
        var leaving: Task<Void, Never>?
        let start = clock.now
        let tap = clock.measure { leaving = launcher.returnToStartInBackground() }
        await leaving?.value
        let whole = clock.now - start
        XCTAssertNil(launcher.session)
        rows.append(String(format: "Back to Start with 50 saves: the tap holds the main actor %.1f ms, the start screen comes after %.0f ms", Self.ms(tap), Self.ms(whole)))
        print(rows.joined(separator: "\n"))
    }
}
