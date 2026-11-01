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

    private func run(_ opened: GameWorld, at speed: GameSpeed, hours: Int64) throws -> Outcome {
        var world = opened
        world.setSpeed(speed)
        let end = world.clock.now.seconds + hours * GameTime.secondsPerHour
        var outcome = Outcome()
        while world.clock.now.seconds < end {
            try world.advance(ticks: 1)
            outcome.mostDeadlocked = max(outcome.mostDeadlocked, world.deadlockedTrains().count)
        }
        for line in world.lines {
            for day in world.lineAccounts?.lineDays(line.id) ?? [] {
                outcome.departures += day.tally.departures
                outcome.trips += day.tally.trips
                outcome.late += day.tally.lateTrips
                outcome.fares += day.tally.fareRevenue.amount
            }
            guard line.hasRuns else { continue }
            let today = world.clock.now.seconds / GameTime.secondsPerDay
            let yesterday = zip(line.runs, line.runDays).filter { run, _ in run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 }
            outcome.runs += yesterday.count
            outcome.missed += yesterday.count { _, day in (day ?? -1) < today - 1 }
        }
        outcome.balance = world.economy.balance.amount
        return outcome
    }

    private func compare(_ name: String, _ opened: GameWorld) throws {
        var opened = opened
        if simple { try opened.setTrafficControl(false) }
        // To the start of a day and two days on, so both days close.
        let day = GameTime.secondsPerDay
        let hours = (2 * day + day - opened.clock.now.seconds % day) / GameTime.secondsPerHour
        var outcomes: [(GameSpeed, Outcome)] = []
        for speed in [GameSpeed.normal, .double, .fast] {
            let started = Date()
            let outcome = try run(opened, at: speed, hours: hours)
            outcomes.append((speed, outcome))
            FileHandle.standardError.write(Data("BATCH_CADENCE \(name)\(simple ? " simple" : "") \(speed): \(outcome); \(String(format: "%.0f", Date().timeIntervalSince(started))) s\n".utf8))
        }
    }
}
