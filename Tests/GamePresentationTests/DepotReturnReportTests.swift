import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 535 (PR W): how the lines with runs and depots fare, run only
/// when asked (`DEPOT_RETURN_REPORT=1`, some minutes in a release build;
/// `DEPOT_RETURN_ONLY=<name>` for one (wenhu, tymc, tymc-old, tymc-rebuilt, danhai, ankeng, ankeng-added, sanying,
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
/// `jiji`, `neiwan`, `shenao`, `liujia`, `shalun`, `demo`, `realworld`;
/// HEALTH-112 `maokong`; HEALTH-114 `ferry-tamsui`, `ferry-gushan`; HEALTH-119 `klrt`),
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

    /// Skips unless asked for one of `names`.
    private func wanted(_ name: String, or other: String) throws {
        if (try? wanted(name)) == nil { try wanted(other) }
    }

    func testTheWenhuLine() throws {
        try wanted("wenhu")
        try report("wenhu", Self.resumed() ?? Self.bought("trtc:BR"))
    }

    /// Decision 556: the Taoyuan Airport MRT, on a map wide enough for it.
    func testTheTaoyuanAirportLine() throws {
        try wanted("tymc")
        try report("tymc", Self.resumed() ?? Self.bought("tymc:A", side: 1 << 22))
    }

    /// HEALTH-119: the Kaohsiung Circular Light Rail (decision 612), a ring.
    func testTheKaohsiungLightRail() throws {
        try wanted("klrt")
        try report("klrt", Self.resumed() ?? Self.bought("krtc:C"))
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

    /// Decision 605 (continued): the Taoyuan Airport MRT bought as it was
    /// before its expresses came, run a day, and at two in the morning
    /// left as it is (`tymc-old`) or rebuilt from the line's panel
    /// (`tymc-rebuilt`); played 51 hours from there.
    func testTheTaoyuanAirportLineBoughtBefore() throws {
        try wanted("tymc-old")
        let simple = ProcessInfo.processInfo.environment["DEPOT_RETURN_SIMPLE"] != nil
        let (session, _) = try Self.taoyuanAirportBoughtBefore(simple: simple)
        try report("tymc-old", session.world)
    }

    func testTheTaoyuanAirportLineRebuilt() throws {
        try wanted("tymc-rebuilt")
        let simple = ProcessInfo.processInfo.environment["DEPOT_RETURN_SIMPLE"] != nil
        let (session, id) = try Self.taoyuanAirportBoughtBefore(simple: simple)
        session.selectLine(id)
        XCTAssertTrue(session.rebuildRealLine(try XCTUnwrap(session.selectedLineRealRebuildOffer)), session.message?.text ?? "")
        try report("tymc-rebuilt", session.world)
    }

    /// The old line's first day, to two in the morning of the next.
    private static func taoyuanAirportBoughtBefore(simple: Bool) throws -> (session: GameSession, line: LineID) {
        let (session, id) = try RealLineRebuildTests.boughtAsBefore(rules: simple ? .simple : .realistic)
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.advance(ticks: 26 * 60)
            return ""
        })
        return (session, id)
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

    /// HEALTH-112: the Maokong Gondola demo (decision 574) as the
    /// screenshot scene makes it, a new game of Muzha with the gondola
    /// laid; it has no trains, so besides the usual report each day's
    /// riders and whether it stood still.
    func testTheMaokongDemo() throws {
        try wanted("maokong")
        let place = try XCTUnwrap(ScreenshotScene.maokong.place)
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude))
        var world = GameWorld.newGame(anchor: anchor)
        let stops = try XCTUnwrap(RealCableway.maokong.stops(in: world))
        _ = try world.createCableway(stops: stops, legMetres: RealCableway.maokong.legMetres, meetsNear: RealCableway.maokong.meetsNear(in: world))
        let played = try report("maokong", world)
        for cableway in played.cableways {
            let days = cableway.days.map { "day \($0.day) \($0.riders) riders\($0.closed ? " closed" : "")" }
            FileHandle.standardError.write(Data("DEPOT_RETURN maokong cableway \(cableway.id.rawValue): \(days.joined(separator: ", "))\n".utf8))
        }
        XCTAssertEqual(played.cableways.count, 1)
    }

    /// HEALTH-114: the two real ferries (decision 585) as the ferry mode
    /// lays them with its defaults (a boat every 15 minutes, two boats) on
    /// a new game where the screenshot scene stands, with the app's water;
    /// each day's riders and whether no boat sailed.
    func testTheFerries() throws {
        try wanted("ferry-tamsui", or: "ferry-gushan")
        let resources = BundledRealData.directory.deletingLastPathComponent()
        let grid = try WaterGrid(data: Data(contentsOf: resources.appendingPathComponent("RealWorld/taiwan_water.json")))
        for (name, ferry, scene) in [("ferry-tamsui", RealFerry.tamsuiBali, ScreenshotScene.tamsuiFerry),
                                     ("ferry-gushan", RealFerry.gushanCijin, ScreenshotScene.gushanFerry)] {
            guard (try? wanted(name)) != nil else { continue }
            let place = try XCTUnwrap(scene.place)
            let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude))
            let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
            var world = GameWorld.newGame(anchor: anchor, water: grid.cells(frame: frame, bounds: GameWorld.newGameBounds),
                                          steep: grid.steepCells(frame: frame, bounds: GameWorld.newGameBounds))
            let piers = try XCTUnwrap(ferry.piers(in: world), "\(name): no shore by a pier")
            _ = try world.createFerryRoute(piers: piers, legMetres: ferry.legMetres, service: .every(minutes: 15), boats: 2)
            let played = try report(name, world)
            for route in played.ferryRoutes {
                let days = route.days.map { "day \($0.day) \($0.riders) riders\($0.closed ? " closed" : "")" }
                FileHandle.standardError.write(Data("DEPOT_RETURN \(name) ferry \(route.id.rawValue): \(days.joined(separator: ", "))\n".utf8))
            }
            XCTAssertEqual(played.ferryRoutes.count, 1)
        }
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

    /// Decision 602: `DEPOT_RETURN_FROM=<file>` plays on from a world
    /// `DEPOT_RETURN_SAVE` wrote (`DEPOT_RETURN_SAVE_AT=<clock seconds>`),
    /// to `DEPOT_RETURN_UNTIL=<clock seconds>`, so a deadlock an hour into
    /// the second day is a command of minutes (diagnosing-bugs).
    static func resumed() throws -> GameWorld? {
        guard let path = ProcessInfo.processInfo.environment["DEPOT_RETURN_FROM"] else { return nil }
        return try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: URL(fileURLWithPath: path))).world
    }

    @discardableResult
    private func report(_ name: String, _ opened: GameWorld) throws -> GameWorld {
        var world = opened
        // The demos open under traffic control; with DEPOT_RETURN_SIMPLE
        // they play without, as the bought lines then do.
        // Decision 549: `DEPOT_RETURN_CONTROLLED=1` keeps it on under
        // simple rules too, as a new game has it.
        let environment = ProcessInfo.processInfo.environment
        GameWorld.followProbe = Int(environment["FOLLOW_PROBE"] ?? "") ?? 0 // DEBUG-TYMC4
        if environment["DEPOT_RETURN_SIMPLE"] != nil, environment["DEPOT_RETURN_CONTROLLED"] == nil { try world.setTrafficControl(false) }
        // Decision 618: the high-speed demo opens with realistic operation
        // off; `DEPOT_RETURN_REALISTIC=1` turns it on. (Traffic control
        // cannot be turned on with its sets out on the line;
        // `TrafficControlTimingReportTests` measures it on.)
        if environment["DEPOT_RETURN_REALISTIC"] != nil { world.setRealisticOperation(true) }
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
        var dumpedStuck = false
        let timetabled = world.lines.filter(\.hasRuns)
        let lines = timetabled.filter { !$0.depots.isEmpty }
        let ends = Set(lines.flatMap { [$0.stops.first, $0.stops.last].compactMap(\.self) })
        let start = world.clock.now.seconds
        // The day counted is the one before the day 51 hours on, as before;
        // played on until its runs past midnight have had their last chance
        // (decision 547's `RunsNotSent`).
        let counted = (start + 51 * 3_600) / GameTime.secondsPerDay - 1
        let until = environment["DEPOT_RETURN_UNTIL"].flatMap { Int64($0) }
        let end = until ?? max(start + 51 * 3_600, RunsNotSent.closed(day: counted, of: timetabled))
        var saveAt = environment["DEPOT_RETURN_SAVE_AT"].flatMap { Int64($0) }
        func clock(_ seconds: Int64) -> String {
            let minutes = seconds % GameTime.secondsPerDay / 60
            return String(format: "day %d %02d:%02d", seconds / GameTime.secondsPerDay, minutes / 60, minutes % 60)
        }
        var hour = start / 3_600
        // WENHU-LATE: `DEPOT_RETURN_LATE=1` counts the counted day's late
        // trips by the hour and the station where each ended (the trains
        // standing at their trip's last call as the count went up), so two
        // builds tell where the extra late trips are. A minute a tick only.
        let byHour = environment["DEPOT_RETURN_LATE"] != nil
        func lateOnCountedDay(_ world: GameWorld) -> Int64 {
            world.lines.reduce(0) { sum, line in sum + (world.lineDays(line.id).first { $0.day == counted }?.tally.lateTrips ?? 0) + ((world.clock.now.seconds - 1) / GameTime.secondsPerDay == counted ? world.lineAccounts?.records(of: line.id)?.pending.lateTrips ?? 0 : 0) }
        }
        var lateSoFar: Int64 = 0
        var lateBy: [String: Int] = [:]
        while world.clock.now.seconds < end {
            if let at = saveAt, world.clock.now.seconds >= at, let path = environment["DEPOT_RETURN_SAVE"] {
                try JSONEncoder().encode(SavedGame(world: world)).write(to: URL(fileURLWithPath: path))
                FileHandle.standardError.write(Data("DEPOT_RETURN \(label) saved \(clock(world.clock.now.seconds)) to \(path)\n".utf8))
                saveAt = nil
            }
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
            // `DEPOT_RETURN_STUCK_MIN=n`: the first deadlock of n trains or
            // more (each one with `DEPOT_RETURN_STUCK_ALL`): where each
            // stands, where it is bound, the way it wants and its timetable.
            if let least = Int(environment["DEPOT_RETURN_STUCK_MIN"] ?? ""), stuck.count >= least, !dumpedStuck || environment["DEPOT_RETURN_STUCK_ALL"] != nil, Set(stuck) != Set(lastStuck) {
                dumpedStuck = true
                var memo = GameWorld.DirectionMemo()
                let requests = world.deadlock(memo: &memo)
                func name(_ id: StationID) -> String { world.station(id: id)?.name ?? "?" }
                func hm(_ seconds: Int64) -> String { String(format: "%02d:%02d", seconds % GameTime.secondsPerDay / 3_600, seconds % 3_600 / 60) }
                var text = "DEPOT_RETURN \(label) stuck \(clock(world.clock.now.seconds)) \(requests.count)\n"
                for id in requests.keys.sorted() {
                    guard let request = requests[id], let train = world.train(id: id) else { continue }
                    let to: String = if case .travellingToStop(let s, _)? = request.candidate.execution { name(request.candidate.timetable[s].station) } else { "-" }
                    let edge: String = if case .onEdge(let t, let o)? = train.position { "\(t.edge)\(t.direction == .forward ? "+" : "-")@\(o)" } else { "-" }
                    let at = world.stationsStoppedAt(by: id).map(name).joined(separator: "/")
                    text += "  \(train.name) on \(edge) (\(at.isEmpty ? "line" : at)) departs \(request.departs) dead \(train.isDeadheading) exec \(String(describing: train.execution).prefix(50)) to \(to) via \(request.candidate.movement.edges.dropFirst(request.candidate.movement.cursor).prefix(12).map { "\($0)" }.joined(separator: ",")) timetable \(train.timetable.map { "\(name($0.station))@\(hm($0.departure.seconds))" }.joined(separator: " ").prefix(220))\n"
                }
                FileHandle.standardError.write(Data(text.utf8))
            }
            lastStuck = stuck
            if byHour, world.clock.now.seconds / GameTime.secondsPerDay == counted || world.clock.now.seconds / GameTime.secondsPerDay == counted + 1 {
                let lateNow = lateOnCountedDay(world)
                if lateNow > lateSoFar {
                    let now = world.clock.now.seconds
                    let ended = world.trains.compactMap { train -> String? in
                        guard let last = train.timetable.last, now - last.arrival.seconds > 300,
                              world.stationsStoppedAt(by: train.id).contains(last.station) else { return nil }
                        return "\(world.station(id: last.station)?.name ?? "?") \((now - last.arrival.seconds) / 60) min"
                    }
                    let at = ended.isEmpty ? "?" : ended.joined(separator: ", ")
                    let key = String(format: "%02d ", now % GameTime.secondsPerDay / 3_600) + (ended.first.map { String($0.split(separator: " ").first ?? "?") } ?? "?")
                    lateBy[key, default: 0] += Int(lateNow - lateSoFar)
                    FileHandle.standardError.write(Data("DEPOT_RETURN \(label) late \(clock(now)) +\(lateNow - lateSoFar): \(at)\n".utf8))
                    lateSoFar = lateNow
                }
            }
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
        for (key, count) in lateBy.sorted(by: { $0.key < $1.key }) {
            FileHandle.standardError.write(Data("DEPOT_RETURN \(label) late by hour \(key): \(count)\n".utf8))
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
        if environment["DEPOT_RETURN_STRICT"] != nil, until != nil {
            XCTAssertEqual(deadlocked, 0, "\(label): trains deadlocked, first \(deadlockedWhere)")
        } else if environment["DEPOT_RETURN_STRICT"] != nil {
            XCTAssertEqual(missed, 0, "\(label): runs not sent out")
            XCTAssertEqual(late, 0, "\(label): trips more than five minutes late")
            XCTAssertEqual(deadlocked, 0, "\(label): trains deadlocked, first \(deadlockedWhere)")
        }
        return world
    }
}
