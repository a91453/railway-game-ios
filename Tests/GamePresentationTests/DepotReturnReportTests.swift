import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 535 (PR W): how the lines with runs and depots fare, run only
/// when asked (`DEPOT_RETURN_REPORT=1`, some minutes in a release build;
/// `DEPOT_RETURN_ONLY=<name>` for one (wenhu, tymc, danhai, ankeng, ankeng-added, sanying,
/// tra, hsr), `DEPOT_RETURN_SIMPLE=1` with traffic control off,
/// and `DEPOT_RETURN_CONTROLLED=1` as well to keep it on). Each is played from where it opens or is bought
/// for 51 hours, minute by minute, and says how many of its second day's
/// runs were not sent out, how many empty runs went into a depot and came
/// out of one, about how far the empty runs drove, the most trains in a
/// deadlock and the most trains that stood at an end station at once. The
/// numbers are in the decision.
@MainActor
final class DepotReturnReportTests: XCTestCase {
    private func wanted(_ name: String) throws {
        guard ProcessInfo.processInfo.environment["DEPOT_RETURN_REPORT"] != nil else {
            throw XCTSkip("Set DEPOT_RETURN_REPORT=1 to measure the depots (decision 535).")
        }
        if let only = ProcessInfo.processInfo.environment["DEPOT_RETURN_ONLY"], only != name {
            throw XCTSkip("Only \(only).")
        }
    }

    func testTheWenhuLine() throws {
        try wanted("wenhu")
        try report("wenhu", Self.bought("trtc:BR"))
    }

    /// Decision 556: the Taoyuan Airport MRT, on a map wide enough for it.
    func testTheTaoyuanAirportLine() throws {
        try wanted("tymc")
        try report("tymc", Self.bought("tymc:A", side: 1 << 22))
    }

    func testTheGreenMountainLine() throws {
        try wanted("danhai")
        try report("danhai", Self.bought("ntdlrt:V"))
    }

    func testTheAnkengLRT() throws {
        try wanted("ankeng")
        try report("ankeng", Self.bought("ntalrt:K"))
    }

    /// Decision 557: the Ankeng LRT bought as it was before its depot came
    /// with it, run a day, the depot then added from the line's panel at
    /// two in the morning; played 51 hours from there.
    func testTheAnkengLRTWithItsDepotAdded() throws {
        try wanted("ankeng-added")
        let simple = ProcessInfo.processInfo.environment["DEPOT_RETURN_SIMPLE"] != nil
        let (session, id) = try RealLineDepotAdditionTests.ankengBoughtWithoutItsDepot(rules: simple ? .simple : .realistic)
        // A day of the old line; the depot added at two in the morning.
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.advance(ticks: 26 * 60)
            return ""
        })
        session.selectLine(id)
        XCTAssertTrue(session.addRealDepot(try XCTUnwrap(session.selectedLineRealDepotOffer)), session.message?.text ?? "")
        try report("ankeng-added", session.world)
    }

    func testTheSanyingLine() throws {
        try wanted("sanying")
        try report("sanying", Self.bought("sanying:LB"))
    }

    func testTheTRADemo() throws {
        try wanted("tra")
        try report("tra", TRADemoTests.opened.get())
    }

    func testTheHighSpeedDemo() throws {
        try wanted("hsr")
        try report("hsr", HighSpeedDemoTests.opened.get())
    }

    /// A game round real line `id` with it bought, under realistic rules
    /// (simple with `DEPOT_RETURN_SIMPLE`), or under `rules`.
    static func bought(_ id: String, rules: NewGameRules? = nil, side: Int64 = 1 << 21) throws -> GameWorld {
        let simple = ProcessInfo.processInfo.environment["DEPOT_RETURN_SIMPLE"] != nil
        let session = try RealLineAcquisitionTests.game(round: id, side: side, heights: true, rules: rules ?? (simple ? .simple : .realistic))
        guard let line = session.buyableRealLines.first(where: { $0.id == id }) else {
            throw XCTSkip("\(id) is not on sale")
        }
        let offer = session.realLineOffer(for: line)
        XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(offer.problem ?? session.message?.text ?? "")")
        return session.world
    }

    private func report(_ name: String, _ opened: GameWorld) throws {
        var world = opened
        // The demos open under traffic control; with DEPOT_RETURN_SIMPLE
        // they play without, as the bought lines then do.
        // Decision 549: `DEPOT_RETURN_CONTROLLED=1` keeps it on under
        // simple rules too, as a new game has it.
        let environment = ProcessInfo.processInfo.environment
        if environment["DEPOT_RETURN_SIMPLE"] != nil, environment["DEPOT_RETURN_CONTROLLED"] == nil { try world.setTrafficControl(false) }
        let started = Date()
        var into: Set<String> = [], outOf: Set<String> = []
        // The empty runs' length: what each had still to go, along the
        // edges ahead of it, when first seen.
        var empty: [String: Int64] = [:]
        var standing: [StationID: Int] = [:]
        var deadlocked = 0
        let lines = world.lines.filter { $0.hasRuns && !$0.depots.isEmpty }
        let ends = Set(lines.flatMap { [$0.stops.first, $0.stops.last].compactMap(\.self) })
        for minute in 0..<(51 * 60) {
            try world.advance(ticks: 1)
            let stuck = world.deadlockedTrains().count
            deadlocked = max(deadlocked, stuck)
            if minute % 360 == 359 {
                FileHandle.standardError.write(Data("DEPOT_RETURN \(name) hour \(minute / 60 + 1): deadlocked now \(stuck), \(String(format: "%.0f", Date().timeIntervalSince(started))) s\n".utf8))
            }
            for line in lines {
                for id in line.trains {
                    guard let train = world.train(id: id), train.isDeadheading,
                          let first = train.timetable.first, let last = train.timetable.last else { continue }
                    let key = "\(id.rawValue) \(first.departure.seconds)"
                    if empty[key] == nil {
                        empty[key] = train.movement.edges.dropFirst(train.movement.cursor).reduce(0) { $0 + (world.network.edge($1)?.length ?? 0) }
                    }
                    if line.depots.contains(last.station) { into.insert(key) }
                    if line.depots.contains(first.station) { outOf.insert(key) }
                }
            }
            for end in ends {
                let count = world.trains.count { world.stationsStoppedAt(by: $0.id).contains(end) }
                standing[end] = max(standing[end] ?? 0, count)
            }
        }
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        var missed = 0, runs = 0
        for line in lines {
            let ran = try XCTUnwrap(world.line(id: line.id))
            let yesterday = zip(ran.runs, ran.runDays).filter { run, _ in run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 }
            runs += yesterday.count
            missed += yesterday.count { _, day in (day ?? -1) < today - 1 }
            // Decision 552: each run not sent out, from where, to where
            // and when it was due to leave.
            for (run, day) in yesterday where (day ?? -1) < today - 1 {
                let leaves = run.times.first.map { $0.departure % GameTime.secondsPerDay } ?? 0
                let names = [run.from, run.to].map { ran.stops.indices.contains($0) ? world.station(id: ran.stops[$0])?.name ?? "?" : "?" }
                FileHandle.standardError.write(Data(String(format: "DEPOT_RETURN \(name): not sent \(names[0]) to \(names[1]) at %02d:%02d\n", leaves / 3_600, leaves % 3_600 / 60).utf8))
            }
        }
        let most = standing.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\(world.station(id: $0.key)?.name ?? "?") \($0.value)" }.joined(separator: ", ")
        FileHandle.standardError.write(Data(
            ("DEPOT_RETURN \(name): second day \(missed) of \(runs) runs not sent out; \(into.count) empty runs into a depot, "
                + "\(outOf.count) out, \(empty.values.reduce(0, +) / Int64(WorldCoordinate.unitsPerMetre) / 1_000) km empty in all; most standing at the ends: \(most); most deadlocked \(deadlocked); "
                + "\(String(format: "%.0f", Date().timeIntervalSince(started))) s\n").utf8
        ))
    }
}
