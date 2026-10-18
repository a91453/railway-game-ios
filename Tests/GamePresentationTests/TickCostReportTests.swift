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
