import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 535 (PR W): how the lines with runs and depots fare, run only
/// when asked (`DEPOT_RETURN_REPORT=1`, some minutes in a release build;
/// `DEPOT_RETURN_ONLY=<name>` for one (wenhu, tymc, danhai, ankeng, ankeng-added, sanying,
/// tra, hsr), `DEPOT_RETURN_SIMPLE=1` with traffic control off,
/// and `DEPOT_RETURN_CONTROLLED=1` as well to keep it on). Each is played from where it opens or is bought
/// for 51 hours, minute by minute (HEALTH-110: `DEPOT_RETURN_FAST=1` at the
/// top speed instead, ten minutes a tick, as a player at fast forward
/// plays), and says how many of its second day's
/// runs were not sent out, how many empty runs went into a depot and came
/// out of one, about how far the empty runs drove, the most trains in a
/// deadlock and the most trains that stood at an end station at once. The
/// numbers are in the decision. HEALTH-110 added every line on sale and
/// the other demos (`danhai-blue`, `xinbeitou`, `xiaobitan`, `pingxi`,
/// `jiji`, `neiwan`, `shenao`, `liujia`, `shalun`, `demo`, `realworld`),
/// the second day's late trips, and where and when the most trains stood
/// deadlocked; a line without runs or depots reports only those.
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

    func testTheBlueCoastLine() throws {
        try wanted("danhai-blue")
        try report("danhai-blue", Self.bought("ntdlrt:VB"))
    }

    func testTheXinbeitouBranch() throws {
        try wanted("xinbeitou")
        try report("xinbeitou", Self.bought("trtc:R_XBT"))
    }

    func testTheXiaobitanBranch() throws {
        try wanted("xiaobitan")
        try report("xiaobitan", Self.bought("trtc:G_XBT"))
    }

    /// The Taiwan Railway branch lines on sale (decision 315).
    func testTheBranchLines() throws {
        for network in ["PINGXI", "JIJI", "NEIWAN", "SHENAO", "LIUJIA", "SHALUN"] {
            let name = network.lowercased()
            guard (try? wanted(name)) != nil else { continue }
            try report(name, Self.bought("tra:\(network)"))
        }
    }

    func testTheDemo() throws {
        try wanted("demo")
        try report("demo", DemoWorld.make(in: .english))
    }

    func testTheRealWorldDemo() throws {
        try wanted("realworld")
        let railways = try BundledRealData.railways()
        let resources = BundledRealData.directory.deletingLastPathComponent()
        let heights = try HeightGrid(data: Data(contentsOf: resources.appendingPathComponent("RealWorld/taiwan_heights.dat")))
        let water = try WaterGrid(data: Data(contentsOf: resources.appendingPathComponent("RealWorld/taiwan_water.json")))
        let frame = RealWorldFrame(anchor: RealWorldDemo.anchor, bounds: GameWorld.newGameBounds)
        try report("realworld", RealWorldDemo.make(
            in: .english, railways: railways, water: water.cells(frame: frame, bounds: GameWorld.newGameBounds),
            steep: water.steepCells(frame: frame, bounds: GameWorld.newGameBounds), heights: heights
        ))
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
        // The Taiwan Railway branch lines are found by their network alone.
        let round = id.hasPrefix("tra:") ? String(id.dropFirst(4)) : id
        let session = try RealLineAcquisitionTests.game(round: round, side: side, heights: true, rules: rules ?? (simple ? .simple : .realistic))
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
        // HEALTH-110: a minute a tick, or ten at the top speed.
        let fast = environment["DEPOT_RETURN_FAST"] != nil
        world.setSpeed(fast ? .fast : .normal)
        let label = "\(name)\(fast ? " fast" : "")"
        let started = Date()
        var into: Set<String> = [], outOf: Set<String> = []
        // The empty runs' length: what each had still to go, along the
        // edges ahead of it, when first seen.
        var empty: [String: Int64] = [:]
        var standing: [StationID: Int] = [:]
        var deadlocked = 0
        var deadlockedWhere = ""
        // HEALTH-110: the samples (minutes, or ten-minute ticks) with any
        // train deadlocked, to tell one cleared at once from one that stays.
        var deadlockedSamples = 0
        var lastStuck: [TrainID] = []
        let timetabled = world.lines.filter(\.hasRuns)
        let lines = timetabled.filter { !$0.depots.isEmpty }
        let ends = Set(lines.flatMap { [$0.stops.first, $0.stops.last].compactMap(\.self) })
        let start = world.clock.now.seconds
        // The day counted is the one before the day 51 hours on, as before;
        // played on until its runs past midnight have had their last chance
        // (decision 547's `RunsNotSent`).
        let counted = (start + 51 * 3_600) / GameTime.secondsPerDay - 1
        let end = max(start + 51 * 3_600, RunsNotSent.closed(day: counted, of: timetabled))
        func clock(_ seconds: Int64) -> String {
            let minutes = seconds % GameTime.secondsPerDay / 60
            return String(format: "day %d %02d:%02d", seconds / GameTime.secondsPerDay, minutes / 60, minutes % 60)
        }
        var hour = start / 3_600
        while world.clock.now.seconds < end {
            try world.advance(ticks: 1)
            let stuck = world.deadlockedTrains()
            if !stuck.isEmpty { deadlockedSamples += 1 }
            // `DEPOT_RETURN_EPISODES=1`: each deadlock as it begins and ends.
            if environment["DEPOT_RETURN_EPISODES"] != nil, Set(stuck) != Set(lastStuck) {
                let names = stuck.compactMap { id -> String? in
                    guard let train = world.train(id: id) else { return nil }
                    let at = world.stationsStoppedAt(by: id).compactMap { world.station(id: $0)?.name }.joined(separator: "/")
                    return "\(train.name) at \(at.isEmpty ? "line" : at)"
                }
                FileHandle.standardError.write(Data("DEPOT_RETURN \(label) deadlock \(clock(world.clock.now.seconds)): \(names.isEmpty ? "cleared" : names.joined(separator: "; "))\n".utf8))
            }
            lastStuck = stuck
            if stuck.count > deadlocked {
                deadlocked = stuck.count
                let places = stuck.compactMap { id -> String? in
                    guard let train = world.train(id: id) else { return nil }
                    let at = world.stationsStoppedAt(by: id).compactMap { world.station(id: $0)?.name }
                    if !at.isEmpty { return "\(train.name) at \(at.joined(separator: "/"))" }
                    let next = train.timetable.first { $0.arrival > world.clock.now }.flatMap { world.station(id: $0.station)?.name }
                    return "\(train.name) toward \(next ?? "?")"
                }
                deadlockedWhere = "\(clock(world.clock.now.seconds)): \(places.joined(separator: "; "))"
            }
            if world.clock.now.seconds / 3_600 >= hour + 6 {
                hour = world.clock.now.seconds / 3_600
                FileHandle.standardError.write(Data("DEPOT_RETURN \(label) hour \(hour - start / 3_600): deadlocked now \(stuck.count), \(String(format: "%.0f", Date().timeIntervalSince(started))) s\n".utf8))
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
        var missed = 0, runs = 0
        for line in timetabled {
            let ran = try XCTUnwrap(world.line(id: line.id))
            runs += ran.runs.count { $0.runs(onDay: counted) }
            let notSent = RunsNotSent.on(counted, of: ran, at: world.clock.now)
            missed += notSent.count
            // Decision 552: each run not sent out, from where, to where
            // and when it was due to leave.
            for index in notSent {
                let run = ran.runs[index]
                let leaves = run.start(onDay: counted) % GameTime.secondsPerDay
                let names = [run.from, run.to].map { ran.stops.indices.contains($0) ? world.station(id: ran.stops[$0])?.name ?? "?" : "?" }
                FileHandle.standardError.write(Data(String(format: "DEPOT_RETURN \(label): not sent \(names[0]) to \(names[1]) at %02d:%02d\n", leaves / 3_600, leaves % 3_600 / 60).utf8))
            }
        }
        // The counted day's trips and those more than five minutes late
        // at their last call (decision 207), on every line.
        var trips: Int64 = 0, late: Int64 = 0
        for line in world.lines {
            guard let day = world.lineDays(line.id).first(where: { $0.day == counted }) else { continue }
            trips += day.tally.trips
            late += day.tally.lateTrips
        }
        let most = standing.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\(world.station(id: $0.key)?.name ?? "?") \($0.value)" }.joined(separator: ", ")
        let emptyKilometres = empty.values.reduce(0, +) / Int64(WorldCoordinate.unitsPerMetre) / 1_000
        let seconds = String(format: "%.0f", Date().timeIntervalSince(started))
        var summary = "DEPOT_RETURN \(label): second day \(missed) of \(runs) runs not sent out; \(late) of \(trips) trips late; "
        summary += "\(into.count) empty runs into a depot, \(outOf.count) out, \(emptyKilometres) km empty in all; "
        summary += "most standing at the ends: \(most); most deadlocked \(deadlocked)"
        if deadlocked > 0 { summary += " (first \(deadlockedWhere); deadlocked in \(deadlockedSamples) \(fast ? "ten-minute ticks" : "minutes"))" }
        summary += "; \(lines.count) of \(world.lines.count) lines with runs and depots; \(seconds) s\n"
        FileHandle.standardError.write(Data(summary.utf8))
        // `DEPOT_RETURN_STRICT=1`: fails on a run not sent out, a late trip or a deadlock,
        // so a finding is a command that turns red (diagnosing-bugs).
        if environment["DEPOT_RETURN_STRICT"] != nil {
            XCTAssertEqual(missed, 0, "\(label): runs not sent out")
            XCTAssertEqual(late, 0, "\(label): trips more than five minutes late")
            XCTAssertEqual(deadlocked, 0, "\(label): trains deadlocked, first \(deadlockedWhere)")
        }
    }
}
