import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 844: the worlds the timetable checkup plays (``TimetableCheckup``),
/// each a game a player opens and buys real lines in, under a new game's
/// rules (simple, traffic control on) or the realistic ones.
@MainActor
enum TimetableCheckupWorlds {
    /// A Taiwan line bought in a game round it (as the depot reports buy
    /// it, ``DepotReturnReportTests/bought(_:rules:side:)``).
    static func taiwan(_ id: String, rules: NewGameRules) throws -> GameWorld {
        // The Taoyuan Airport MRT needs a map wide enough for it (decision 556).
        try DepotReturnReportTests.bought(id, rules: rules, side: id == "tymc:A" ? 1 << 22 : 1 << 21)
    }

    /// Hong Kong's MTR lines `ids` (`"SIL"`, ...) bought on its map.
    static func hongKong(_ ids: [String], rules: NewGameRules) throws -> GameWorld {
        try DepotReturnReportTests.hongKongBought(ids, rules: rules)
    }

    /// Both of Rovaniemi's lines, bought on its map as the launcher opens
    /// it (decision 809's order).
    static func rovaniemi() throws -> GameWorld {
        let session = try RovaniemiRailwaysTests.rovaniemi()
        for id in ["vr:KJA", "vr:MUL"] {
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, "\(id) on sale")
            let offer = session.realLineOffer(for: line)
            XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(offer.problem ?? session.message?.text ?? "")")
        }
        return session.world
    }

    /// Plays `world` a minute a tick and checks game day `day` against
    /// `budget`: `main`'s numbers, so any figure over it is a change for
    /// the worse. Prints the lines' results either way, and a note when a
    /// figure fell below the budget (lower it).
    static func check(_ name: String, _ opened: GameWorld, day: Int64, windows: [Range<Int64>]? = nil,
                      until: Int64? = nil, budget: TimetableCheckup.Budget,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        var world = opened
        world.setSpeed(.normal)
        let started = Date()
        let results = try TimetableCheckup.play(&world, day: day, windows: windows, until: until)
        let measured = TimetableCheckup.measured(results)
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        var text = "TIMETABLE_CHECKUP \(name) day \(day) (from clock \(opened.clock.now.seconds) s) in \(seconds) s: \(measured)\n"
        for result in results {
            text += "  \(result)\n"
            // `TIMETABLE_CHECKUP_RUNS=1`: which runs (their index in the
            // line's runs), to tell a run not sent from the same run sent late.
            if ProcessInfo.processInfo.environment["TIMETABLE_CHECKUP_RUNS"] != nil {
                let late = result.lateOutOfDepot.map { "\($0) (\((result.lateness[$0] ?? 0) / 60) min)" }.joined(separator: ", ")
                text += "    not sent: \(result.notSent.sorted()); late out of a depot: \(late)\n"
                text += "    late: \(result.late.map { "\($0) (\(result.lateness[$0]! / 60) min, due \(result.starts[$0].map { String(format: "%02d:%02d", $0 % 86_400 / 3_600, $0 % 3_600 / 60) } ?? "?"))" }.joined(separator: ", "))\n"
            }
        }
        let over = TimetableCheckup.overBudget(measured, budget)
        if over.isEmpty, measured.notSent < budget.notSent || measured.late < budget.late
            || measured.lateOutOfDepot < budget.lateOutOfDepot || measured.peakGapMinutes < budget.peakGapMinutes {
            text += "  better than the budget (\(budget)): lower it in its map's file in CheckupBudgets/\n"
        }
        FileHandle.standardError.write(Data(text.utf8))
        XCTAssertTrue(results.contains { $0.runs > 0 }, "\(name): no timetabled run looked at", file: file, line: line)
        XCTAssertEqual(results.reduce(0) { $0 + $1.unmatched }, 0, "\(name): sent runs whose train was not found", file: file, line: line)
        XCTAssertEqual(over, [], "\(name) day \(day): worse than main (decision 844). \(text)", file: file, line: line)
    }
}

/// Decision 844: the pull request checkup, Hong Kong's part. The parts
/// of a day where the timetable has gone wrong before, a new game's rules
/// (simple, traffic control on), counted on the first day: the South
/// Island Line's morning peak (HK-PEAK-CONTROL) and the Tung Chung Line's
/// first morning out of Siu Ho Wan (TCL-DAWN), the runs from 05:00 to
/// 09:30, played to 10:00. About a minute of a debug build. Every line's
/// whole second day, under both rules, is ``TimetableCheckupFullTests``,
/// nightly. The budgets are `main`'s numbers on 2026-11-18 (`2cd9c94`);
/// the sessions fixing those bugs lower them. Decision 849 (the home
/// signal) took Hong Kong's from 16 runs not sent, 101 late and a peak
/// gap of 26 minutes: 15 of the 16 are now sent, 17 of them late (the
/// worst 14 minutes on the South Island Line, where it was 30).
@MainActor
final class TimetableCheckupTests: XCTestCase {
    /// The first day's runs from 05:00 to 09:30, played to 10:00.
    static let morning: [Range<Int64>] = [5 * 3_600 ..< 9 * 3_600 + 1_800]
    static let untilTen: Int64 = 10 * 3_600

    func testHongKongMorning() throws {
        try TimetableCheckupWorlds.check(
            "hk-sil-tcl simple", TimetableCheckupWorlds.hongKong(["SIL", "TCL"], rules: .simple), day: 0,
            windows: Self.morning, until: Self.untilTen,
            budget: .init(notSent: 1, late: 118, lateOutOfDepot: 6, peakGapMinutes: 19)
        )
    }

    /// EAL-LMC-PEAK-GAP (decision 881, later): the East Rail Line's Lok
    /// Ma Chau branch, its whole second day against the nightly budget,
    /// some 15 s. A change to how a train takes another berth of a
    /// terminus moved its evening peak, and only the nightly run played
    /// the line: one stretch of 7 km with a throat at each end and no
    /// depot, it shows first what a line with a depot hides.
    func testTheLokMaChauBranchDay() throws {
        let name = "hk EAL_LMC simple"
        try TimetableCheckupWorlds.check(
            name, TimetableCheckupWorlds.hongKong(["EAL_LMC"], rules: .simple), day: 1,
            budget: XCTUnwrap(TimetableCheckupFullTests.budgets[name])
        )
    }
}

/// Decision 844: the pull request checkup, Taiwan's part (a class of its
/// own so CI can deal it to another job than Hong Kong's): the Taoyuan
/// Airport MRT's first morning out of its two depots (DEPOT-DAWN-QUEUE),
/// the runs from 05:00 to 07:00 played to 07:30, and the Sanying Line's
/// morning as ``TimetableCheckupTests`` plays Hong Kong's. About a minute.
/// Decision 881's later part (SANYING-0632) moved the Sanying Line's
/// morning from 5 runs late, 1 late out of a depot and a peak gap of
/// +6 min to 7, none and +5: the train at Yingtao Fude due at 06:32 no
/// longer waits 24 minutes for an empty run from the depot bound there
/// (a run counted on time, as it was sent when due), and the three runs
/// after it, 06:38 to 06:50, leave 6 to 9 minutes late instead.
@MainActor
final class TimetableCheckupTaiwanTests: XCTestCase {
    func testTheTaoyuanAirportLineDawn() throws {
        try TimetableCheckupWorlds.check(
            "tymc simple", TimetableCheckupWorlds.taiwan("tymc:A", rules: .simple), day: 0,
            windows: [5 * 3_600 ..< 7 * 3_600], until: 7 * 3_600 + 1_800,
            budget: .init(notSent: 4, late: 8, lateOutOfDepot: 2, peakGapMinutes: 0)
        )
    }

    func testTheSanyingLineMorning() throws {
        try TimetableCheckupWorlds.check(
            "sanying simple", TimetableCheckupWorlds.taiwan("sanying:LB", rules: .simple), day: 0,
            windows: TimetableCheckupTests.morning, until: TimetableCheckupTests.untilTen,
            budget: .init(notSent: 0, late: 7, lateOutOfDepot: 0, peakGapMinutes: 5)
        )
    }
}

/// Decision 844: the whole checkup, nightly and by hand
/// (`TIMETABLE_CHECKUP=1`; ci.yml's timetable-checkup jobs): every line
/// with a real timetable on sale, bought alone in a game (Hong Kong's
/// three lines on one track to the airport also together), played from
/// the start a minute a tick to the end of its second day, under a new
/// game's rules and the realistic ones; the second day, after a night of
/// trains going into depots, counted whole. `TIMETABLE_CHECKUP_ONLY=<name>`
/// plays one world (`tymc:A simple`, `hk SIL realistic`, ...).
@MainActor
final class TimetableCheckupFullTests: XCTestCase {
    /// `TIMETABLE_CHECKUP_ONLY` names one world; `TIMETABLE_CHECKUP_RULES`
    /// (`simple` or `realistic`) keeps the worlds of one rule, so ci.yml
    /// plays the two in jobs of their own. Rovaniemi's game, under the
    /// launcher's rules, goes with `simple`.
    private func wanted(_ name: String) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if let only = environment["TIMETABLE_CHECKUP_ONLY"] { return only == name }
        if let rules = environment["TIMETABLE_CHECKUP_RULES"] {
            return name.hasSuffix(" \(rules)") || (rules == "simple" && !name.hasSuffix(" realistic"))
        }
        return true
    }

    private func full() throws {
        guard ProcessInfo.processInfo.environment["TIMETABLE_CHECKUP"] != nil else {
            throw XCTSkip("Set TIMETABLE_CHECKUP=1 for every line's whole day (decision 844; nightly in ci.yml).")
        }
    }

    private static let rules: [(String, NewGameRules)] = [("simple", .simple), ("realistic", .realistic)]

    /// The budgets of every line's whole day alone, one file a map in
    /// `CheckupBudgets/` (decision 910).
    static let budgets = TimetableCheckupBudgets.full

    private func check(_ name: String, _ world: @autoclosure () throws -> GameWorld) throws {
        guard wanted(name) else { return }
        let opened: GameWorld
        do { opened = try world() } catch let skip as XCTSkip {
            // A line with a timetable that is not on sale in its game.
            FileHandle.standardError.write(Data("TIMETABLE_CHECKUP \(name) not played: \(skip)\n".utf8))
            return
        }
        try TimetableCheckupWorlds.check(name, opened, day: 1, budget: Self.budgets[name] ?? .init())
    }

    /// The metro and light rail lines of Taiwan with timetables. (The
    /// Blue Coast Line's timetable for when the Green Mountain Line is
    /// already bought, `ntdlrt:VB after ntdlrt:V`, is not a line on sale
    /// of its own; `DanhaiBothLinesDayTests` plays the two.)
    /// Fukuoka's lines are not Taiwan's: they are played on their own
    /// map, bought together (`TimetableCheckupAllBoughtTests.testFukuokaLines`).
    func testTaiwanMetroLines() throws {
        try full()
        let ids = try BundledRealData.railways().metroRuns.keys.filter {
            !$0.hasPrefix("hkmtr:") && !$0.hasPrefix("vr:") && !$0.hasPrefix("fksubway:") && !$0.contains(" after ")
        }.sorted()
        for id in ids {
            for (label, rules) in Self.rules { try check("\(id) \(label)", TimetableCheckupWorlds.taiwan(id, rules: rules)) }
        }
    }

    /// The Taiwan Railway branch lines on sale (decision 315).
    func testTaiwanBranchLines() throws {
        try full()
        for network in try BundledRealData.railways().branchRuns.keys.sorted() {
            for (label, rules) in Self.rules { try check("tra:\(network) \(label)", TimetableCheckupWorlds.taiwan("tra:\(network)", rules: rules)) }
        }
    }

    /// Hong Kong's lines with timetables, each alone, and the three on one
    /// track to the airport together.
    func testHongKongLines() throws {
        try full()
        let runs = try HongKongRailwaysTests.railways().metroRuns.keys.filter { $0.hasPrefix("hkmtr:") }.map { String($0.dropFirst(6)) }.sorted()
        for (label, rules) in Self.rules {
            for id in runs { try check("hk \(id) \(label)", TimetableCheckupWorlds.hongKong([id], rules: rules)) }
            try check("hk TCL+AEL+DRL \(label)", TimetableCheckupWorlds.hongKong(["TCL", "AEL", "DRL"], rules: rules))
        }
    }

    func testRovaniemiLines() throws {
        try full()
        try check("rovaniemi", TimetableCheckupWorlds.rovaniemi())
    }
}
