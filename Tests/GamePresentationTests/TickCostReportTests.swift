import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// What a tick costs at 600×, split between GameCore's step and what the
/// session does after it (#791's review: in the UI tests, a new game with
/// fifteen trains bought ran 14 game minutes in 9 s at 600×, a tick about
/// every 0.6 s instead of every 0.1 s). Run on request:
///
///     TICK_REPORT=300 swift test --filter TickCostReportTests
///
/// `TICK_REPORT` is the ticks to time (1 to 10,000).
@MainActor
final class TickCostReportTests: XCTestCase {
    func testWhatATickCosts() throws {
        guard let value = ProcessInfo.processInfo.environment["TICK_REPORT"] else {
            throw XCTSkip("set TICK_REPORT=<ticks> to time the ticks")
        }
        let ticks = try XCTUnwrap(Int(value).flatMap { (1...10_000).contains($0) ? $0 : nil }, "TICK_REPORT is 1 to 10,000 ticks")
        var rows = ["| Game | Ticks | GameCore ms/tick | Session ms/tick | Of which after the step |", "| --- | ---: | ---: | ---: | ---: |"]
        for (name, world) in Self.games() {
            let session = GameSession(world: world)
            session.setSpeed(.normal)
            // Warm the caches a game has once it runs.
            session.advance(realElapsed: GameSession.tickInterval)
            var core = Duration.zero, total = Duration.zero
            let clock = ContinuousClock()
            for _ in 0..<ticks {
                let world = session.world
                core += try clock.measure { _ = try GameSession.advanced(world, by: 1, listening: false) }
                total += clock.measure { session.advance(realElapsed: GameSession.tickInterval) }
            }
            func ms(_ duration: Duration) -> String {
                String(format: "%.2f", Double(duration.components.attoseconds) / 1e15 / Double(ticks) + Double(duration.components.seconds) * 1_000 / Double(ticks))
            }
            rows.append("| \(name) | \(ticks) | \(ms(core)) | \(ms(total)) | \(ms(total - core)) |")
        }
        print(rows.joined(separator: "\n"))
    }

    /// What the train panel and the map read of the session on every
    /// render, in the UI test's game with its last train selected.
    func testWhatARenderReads() throws {
        guard let value = ProcessInfo.processInfo.environment["TICK_REPORT"] else {
            throw XCTSkip("set TICK_REPORT=<renders> to time what a render reads")
        }
        let renders = try XCTUnwrap(Int(value).flatMap { (1...10_000).contains($0) ? $0 : nil })
        var rows = ["| Game | Read | ms each |", "| --- | --- | ---: |"]
        for (name, world) in Self.games() {
            let session = GameSession(world: world)
            session.setSpeed(.normal)
            session.advance(realElapsed: GameSession.tickInterval)
            if let last = session.world.trains.last { session.selectTrain(last.id) }
            let train = session.selectedTrainID ?? TrainID(rawValue: 1)
            let reads: [(String, () -> Void)] = [
                ("selectionText", { _ = session.selectionText() }),
                ("trainMenuChoices", { _ = session.trainMenuChoices }),
                ("trainTypeMenuChoices", { _ = session.trainTypeMenuChoices(for: train) }),
                ("trainPathStatusText", { _ = session.trainPathStatusText(of: train) }),
                ("routeWaitText", { _ = session.routeWaitText(of: train) }),
                ("lineMenuChoices", { _ = session.lineMenuChoices }),
                ("offersLineMenu", { _ = session.offersLineMenu(for: train) }),
                ("LineMap(world:)", { _ = LineMap(world: session.world) }),
                ("StationLabels(world:)", { _ = StationLabels(world: session.world) }),
                ("MiniMap(world:)", { _ = MiniMap(world: session.world) }),
            ]
            let clock = ContinuousClock()
            for (label, read) in reads {
                let spent = clock.measure { for _ in 0..<renders { read() } }
                let ms = (Double(spent.components.seconds) * 1_000 + Double(spent.components.attoseconds) / 1e15) / Double(renders)
                rows.append("| \(name) | \(label) | \(String(format: "%.3f", ms)) |")
            }
        }
        print(rows.joined(separator: "\n"))
    }

    /// What reading the app's real-world data costs, once, and what
    /// happens on the main actor when the launcher installs it.
    func testWhatTheRealWorldLoadCosts() async throws {
        guard ProcessInfo.processInfo.environment["TICK_REPORT"] != nil else {
            throw XCTSkip("set TICK_REPORT to time the real-world load")
        }
        let clock = ContinuousClock()
        var data: RealWorldData?
        let read = clock.measure { data = RealWorldData.load(file: RealWorldDataLoadTests.file) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let loaded = try XCTUnwrap(data)
        let install = await clock.measure { await launcher.loadRealWorldData { loaded }.value }
        print("| Read | \(read) |\n| Install on the main actor | \(install) |")
    }

    /// Decision 330: the owner's iPad on the Yilan Line (the TRA demo) at
    /// 6000× showed the step after a tick on the main thread at 45.7 ms a
    /// second, the longest 44.8 ms, and a frame of 114 ms. Plays the demo
    /// as the game loop does (each tick worked out off the main actor,
    /// put in place on it) for `TICK_REPORT_YILAN` ticks (1 to 10,000; a
    /// day is 144) and prints, piece by piece, what the step after a tick
    /// spends on average and at its longest, on the ticks that cross
    /// midnight and on the rest, and the costliest ticks. Run on request:
    ///
    ///     TICK_REPORT_YILAN=432 swift test -c release -Xswiftc -enable-testing \
    ///       --filter TickCostReportTests/testWhatTheStepAfterATickCostsOnTheYilanLine
    func testWhatTheStepAfterATickCostsOnTheYilanLine() async throws {
        guard let value = ProcessInfo.processInfo.environment["TICK_REPORT_YILAN"] else {
            throw XCTSkip("set TICK_REPORT_YILAN=<ticks> to time the step after a tick on the Yilan Line")
        }
        let ticks = try XCTUnwrap(Int(value).flatMap { (1...10_000).contains($0) ? $0 : nil }, "TICK_REPORT_YILAN is 1 to 10,000 ticks")
        let session = GameSession(world: try TRADemoTests.opened.get())
        session.playSound = { _ in }
        session.setSpeed(.fast)
        let report = try await Self.timeTheLoop(of: session, ticks: ticks)
        print(report.joined(separator: "\n"))
    }

    /// `ticks` of `session`'s game loop, one at a time, with the frame
    /// meter on: each piece of the step after a tick, and the world it
    /// replaced let go, in milliseconds.
    static func timeTheLoop(of session: GameSession, ticks: Int) async throws -> [String] {
        let meter = FrameCostMeter.shared
        meter.isOn = true
        defer { meter.isOn = false }
        _ = meter.frame(at: 0)
        struct Tick {
            var time: GameTime
            var midnight: Bool
            var parts: [FrameCostPart: Double]
        }
        var timed: [Tick] = []
        for index in 0..<ticks {
            guard let tick = session.beginLoopTick() else { break }
            let day = session.world.clock.now.seconds / GameTime.secondsPerDay
            let outcome = await tick.work()
            XCTAssertTrue(session.finish(tick, with: outcome))
            let releasing = ContinuousClock.now
            _ = consume tick
            meter.record(.release, since: releasing)
            // A window a tick long: one tick's parts.
            let reading = try XCTUnwrap(meter.frame(at: Double(index + 1)))
            timed.append(Tick(
                time: session.world.clock.now, midnight: session.world.clock.now.seconds / GameTime.secondsPerDay > day,
                parts: Dictionary(uniqueKeysWithValues: reading.parts.map { ($0.part, $0.longestMilliseconds) })
            ))
        }
        let parts = FrameCostPart.allCases.filter { part in timed.contains { $0.parts[part] != nil } }
        var rows = ["| Part | Ticks | Mean ms | Longest ms | Midnight mean | Midnight longest |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
        for part in parts {
            func stats(_ ticks: [Tick]) -> (mean: Double, longest: Double) {
                let values = ticks.map { $0.parts[part] ?? 0 }
                return (values.reduce(0, +) / Double(max(1, values.count)), values.max() ?? 0)
            }
            let all = stats(timed), midnight = stats(timed.filter(\.midnight))
            rows.append(String(
                format: "| %@%@ | %d | %.2f | %.2f | %.2f | %.2f |", part.parent == nil ? "" : "· ", part.title(in: .english), timed.count,
                all.mean, all.longest, midnight.mean, midnight.longest
            ))
        }
        rows.append("\nCostliest steps after a tick:")
        for tick in timed.sorted(by: { ($0.parts[.afterStep] ?? 0) > ($1.parts[.afterStep] ?? 0) }).prefix(8) {
            let pieces = parts.filter { $0.parent == .afterStep }.compactMap { part in
                tick.parts[part].flatMap { $0 >= 0.5 ? String(format: "%@ %.1f", part.title(in: .english), $0) : nil }
            }
            rows.append(String(
                format: "- day %lld %@: after %.1f ms (%@), tick %.1f, release %.1f", tick.time.seconds / GameTime.secondsPerDay,
                tick.time.clockText, tick.parts[.afterStep] ?? 0, pieces.joined(separator: ", "), tick.parts[.step] ?? 0, tick.parts[.release] ?? 0
            ))
        }
        return rows
    }

    /// The UI test's game (a blank new game, fifteen trains bought), and
    /// the two demo maps.
    static func games() -> [(String, GameWorld)] {
        var blank = GameWorld.newGame(balance: NewGameOptions().startingBalance)
        NewGameOptions().apply(to: &blank)
        for index in 1...15 {
            _ = try? blank.purchaseTrain(named: "Train \(index)")
        }
        return [("New game, 15 trains", blank), ("Simple demo", DemoWorld.make(in: .english))]
    }
}
