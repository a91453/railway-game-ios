import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// DEBUG-BATCH: whether a player at a high speed, whose every tick is one
/// `advance(ticks: 1)` of two or ten game minutes, sees the same trains as
/// one played a minute at a time. Run only when asked
/// (`BATCH_CADENCE_REPORT=1`, `BATCH_CADENCE_ONLY=<name>`,
/// `BATCH_CADENCE_SIMPLE=1` for the bought lines without traffic control).
@MainActor
final class BatchCadenceReportTests: XCTestCase {
    private func wanted(_ name: String) throws {
        guard ProcessInfo.processInfo.environment["BATCH_CADENCE_REPORT"] != nil else {
            throw XCTSkip("Set BATCH_CADENCE_REPORT=1 to compare the cadences.")
        }
        if let only = ProcessInfo.processInfo.environment["BATCH_CADENCE_ONLY"], only != name {
            throw XCTSkip("Only \(only).")
        }
    }

    private var simple: Bool { ProcessInfo.processInfo.environment["BATCH_CADENCE_SIMPLE"] != nil }

    func testTheDemo() throws {
        try wanted("demo")
        try compare("demo", DemoWorld.make(in: .english))
    }

    func testTheGreenMountainLine() throws {
        try wanted("danhai")
        try compare("danhai", bought("ntdlrt:V"))
    }

    func testTheSanyingLine() throws {
        try wanted("sanying")
        try compare("sanying", bought("sanying:LB"))
    }

    func testTheAnkengLine() throws {
        try wanted("ankeng")
        try compare("ankeng", bought("ntalrt:K"))
    }

    func testTheTRADemo() throws {
        try wanted("tra")
        try compare("tra", TRADemoTests.opened.get())
    }

    func testTheHighSpeedDemo() throws {
        try wanted("hsr")
        try compare("hsr", HighSpeedDemoTests.opened.get())
    }

    private func bought(_ id: String) throws -> GameWorld {
        let session = try RealLineAcquisitionTests.game(round: id, side: 1 << 21, heights: true, rules: simple ? .simple : .realistic)
        guard let line = session.buyableRealLines.first(where: { $0.id == id }) else { throw XCTSkip("\(id) is not on sale") }
        let offer = session.realLineOffer(for: line)
        XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(offer.problem ?? session.message?.text ?? "")")
        return session.world
    }

    private struct Outcome: Equatable, CustomStringConvertible {
        var departures: Int64 = 0
        var trips: Int64 = 0
        var late: Int64 = 0
        var missed = 0
        var runs = 0
        var mostDeadlocked = 0
        var balance: Int64 = 0
        var fares: Int64 = 0

        var description: String {
            "departures \(departures), trips \(trips) late \(late), runs missed \(missed) of \(runs), most deadlocked \(mostDeadlocked), fares \(fares), balance \(balance)"
        }
    }

    private func run(_ opened: GameWorld, at speed: GameSpeed, ticks: Int = 1, until end: Int64, counting day: Int64) throws -> Outcome {
        var world = opened
        world.setSpeed(speed)
        var outcome = Outcome()
        while world.clock.now.seconds < end {
            try world.advance(ticks: ticks)
            outcome.mostDeadlocked = max(outcome.mostDeadlocked, world.deadlockedTrains().count)
        }
        for line in world.lines {
            for day in world.lineDays(line.id) {
                outcome.departures += day.tally.departures
                outcome.trips += day.tally.trips
                outcome.late += day.tally.lateTrips
                outcome.fares += day.tally.fareRevenue.amount
            }
            guard line.hasRuns else { continue }
            outcome.runs += line.runs.count { $0.runs(onDay: day) }
            outcome.missed += RunsNotSent.on(day, of: line, at: world.clock.now).count
        }
        outcome.balance = world.economy.balance.amount
        return outcome
    }

    private func compare(_ name: String, _ opened: GameWorld) throws {
        var opened = opened
        if simple { try opened.setTrafficControl(false) }
        // To the start of a day and two days on, and on until the second
        // day's runs past midnight have gone (MISSRUN), so both days close.
        let day = GameTime.secondsPerDay
        let second = opened.clock.now.seconds / day + 2
        let end = RunsNotSent.closed(day: second, of: opened.lines.filter(\.hasRuns))
        // The game loop's cadences (one tick a call), then an hour a call
        // at 600x, as the long tests run.
        for (speed, ticks) in [(GameSpeed.normal, 1), (.double, 1), (.fast, 1), (.normal, 60)] {
            let started = Date()
            let outcome = try run(opened, at: speed, ticks: ticks, until: end, counting: second)
            FileHandle.standardError.write(Data("BATCH_CADENCE \(name)\(simple ? " simple" : "") \(speed)\(ticks > 1 ? " ×\(ticks) a call" : ""): \(outcome); \(String(format: "%.0f", Date().timeIntervalSince(started))) s\n".utf8))
        }
    }

    /// MISSRUN: each run of the second day that sent no train, with every
    /// train of its line at its first departure and at its last chance
    /// (`BATCH_CADENCE_EXPLAIN=1` with `BATCH_CADENCE_ONLY=<name>`; a
    /// minute a call).
    func testWhyRunsWereMissed() throws {
        guard ProcessInfo.processInfo.environment["BATCH_CADENCE_EXPLAIN"] != nil,
              let only = ProcessInfo.processInfo.environment["BATCH_CADENCE_ONLY"]
        else { throw XCTSkip("Set BATCH_CADENCE_EXPLAIN=1 and BATCH_CADENCE_ONLY=<name>.") }
        var opened: GameWorld
        switch only {
        case "danhai": opened = try bought("ntdlrt:V")
        case "ankeng": opened = try bought("ntalrt:K")
        case "sanying": opened = try bought("sanying:LB")
        case "tra": opened = try TRADemoTests.opened.get()
        case "hsr": opened = try HighSpeedDemoTests.opened.get()
        default: opened = DemoWorld.make(in: .english)
        }
        if simple { try opened.setTrafficControl(false) }
        opened.setSpeed(.normal)
        let day = GameTime.secondsPerDay
        let second = opened.clock.now.seconds / day + 2
        let end = RunsNotSent.closed(day: second, of: opened.lines.filter(\.hasRuns))
        var world = opened
        while world.clock.now.seconds < end { try world.advance(ticks: 1) }
        func clock(_ seconds: Int64) -> String {
            let minutes = (seconds % day) / 60
            return "\(minutes / 60):\(minutes % 60 < 10 ? "0" : "")\(minutes % 60)"
        }
        func name(_ world: GameWorld, _ id: StationID) -> String { world.station(id: id)?.name ?? "\(id.rawValue)" }
        let missed = world.lines.filter(\.hasRuns).flatMap { line in
            RunsNotSent.on(second, of: line, at: world.clock.now).map { (line: line.id, run: $0, start: line.runs[$0].start(onDay: second)) }
        }.sorted { $0.start < $1.start }
        var log = "BATCH_CADENCE_EXPLAIN \(only)\(simple ? " simple" : ""): \(missed.count) runs not sent out on day \(second)\n"
        var replay = opened
        for miss in missed {
            for probe in [miss.start, miss.start + LineRun.latestDispatch] {
                while replay.clock.now.seconds < probe { try replay.advance(ticks: 1) }
                let line = try XCTUnwrap(replay.line(id: miss.line))
                let run = line.runs[miss.run]
                log += "@ \(clock(probe)) \(line.name) run \(miss.run) \(name(replay, line.stops[run.from]))→\(name(replay, line.stops[run.to])) at \(clock(miss.start)):\n"
                for id in line.trains {
                    guard let train = replay.train(id: id) else { continue }
                    let stopped = replay.stationsStoppedAt(by: id).map { name(replay, $0) }
                    let trip = train.timetable.first.map { "\(name(replay, $0.station)) \(clock($0.departure.seconds))→\(name(replay, train.timetable.last!.station))" } ?? "none"
                    log += "   train \(id.rawValue): \(train.execution.map { "\($0)" } ?? "idle") at \(stopped), trip \(trip)\(train.isDeadheading ? " empty" : "")\n"
                }
            }
        }
        FileHandle.standardError.write(Data(log.utf8))
    }
}
