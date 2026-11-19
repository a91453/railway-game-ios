import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 844's later note (TIMETABLE-CHECKUP-ALL): the worlds
/// ``TimetableCheckupFullTests`` did not play. That class buys each line
/// with a timetable alone in a game; a line bought alone cannot show what
/// happens where two of a player's lines meet. So the lines on sale of a
/// map that **share a station** (and so track, platforms or a depot's
/// approach) are also bought together, under a new game's rules and the
/// realistic ones: on Taiwan the two Danhai light rails and the Liujia
/// and Neiwan lines (Zhuzhong), in Rovaniemi its two lines (also each
/// alone, which nothing played); Hong Kong's three on one track to the
/// airport are ``TimetableCheckupFullTests``'s. Lines that share nothing
/// are played alone only (owner, 2026-11-18: a whole map bought at once
/// costs a nightly job each and showed nothing a line alone does not).
/// Nightly and by hand (`TIMETABLE_CHECKUP=1`; ci.yml's timetable-checkup
/// jobs), each world's whole second day; `TIMETABLE_CHECKUP_ONLY=<name>`
/// plays one (`taiwan ntdlrt:V+ntdlrt:VB simple`,
/// `rovaniemi vr:KJA realistic`, ...).
///
/// Decision 862: those lines are now sold together, so the groups are
/// the game's own bundles (``GameSession/realLineBundles``), and each is
/// bought as a player buys it, in one purchase, in the order the game
/// lays it. The other order, and a line of a group alone, is what a game
/// saved before decision 862 may hold (one line bought then, the rest
/// since), still played, bought one line at a time.
///
/// A line added to a map that shares a station with another is played
/// with it without a change here, and `testEveryLineOnSaleIsPlayed`
/// (always run, a few seconds) is red when a map sells a line no world
/// buys alone, or has a group of lines sharing a station that no world
/// buys together.
@MainActor
final class TimetableCheckupAllBoughtTests: XCTestCase {
    private static let rules: [(String, NewGameRules)] = [("simple", .simple), ("realistic", .realistic)]

    /// `main`'s numbers for each world (2026-11-18), as
    /// ``TimetableCheckupFullTests/budgets``: a world not listed must have
    /// none of any. The sessions fixing a bug lower its world's numbers.
    /// The Liujia line's three late runs under the realistic rules are
    /// its own (`tra:LIUJIA realistic`, LIUJIA-LATE), the same with the
    /// Neiwan line bought; under a new game's rules it has none since
    /// decision 849 (measured again on `main` `5a1efcf`), as alone.
    /// Decision 885 (SHALUN-ONE-ISLAND): the Blue Coast Line's trains
    /// run from Hongshulin on the Green Mountain Line's track, and those
    /// toward Fisherman's Wharf share Binhai Shalun's south platform
    /// track with the Green Mountain Line's trains toward Hongshulin
    /// (the game has no level crossing), so some wait there: none not
    /// sent, the latest 19 minutes behind (measured 2026-11-19).
    /// GRADE-CROSSING-SHALUN (decision 885, later): those toward the
    /// wharf now stop on the north face and cross the Green Mountain
    /// Line's track west of the station on the flat, and wait there no
    /// more. Of the 11 runs still late under a new game's rules, 10 leave
    /// Hongshulin late, both lines' (HONGSHULIN-TURN); 4 under the
    /// realistic rules; none late out of the depot (measured 2026-11-19).
    /// FUKUOKA-OPEN: Fukuoka's three lines, bought together, as measured
    /// when its map opened (2026-11-19, Release): every run sent, but the
    /// Nanakuma Line's turns at its ends at 3 min 15 s run up to 15
    /// minutes late (126 or 127 runs), and the Kuko Line's peak gap at
    /// Fukuoka Airport is 10 minutes against 3.3 (60 runs late under a new
    /// game's rules, 3 under the realistic ones); the Hakozaki Line has
    /// none. FUKUOKA-LATE lowers them.
    /// Decision 890 (FUKUOKA-LATE): the home signal at the Kuko Line's
    /// ends, its trains late 0 (were 60 and 3) and its peak gap 7.0 and
    /// 6.0 minutes; the Nanakuma Line's are its trains too few for its
    /// peak (two more run it on time, but its ends have no tracks for
    /// them: FUKUOKA-NANAKUMA-FLEET).
    static let budgets: [String: TimetableCheckup.Budget] = [
        "fukuoka fksubway:K+fksubway:H+fksubway:N simple": .init(notSent: 0, late: 127, lateOutOfDepot: 0, peakGapMinutes: 4),
        "fukuoka fksubway:K+fksubway:H+fksubway:N realistic": .init(notSent: 0, late: 126, lateOutOfDepot: 0, peakGapMinutes: 4),
        "taiwan ntdlrt:V+ntdlrt:VB simple": .init(notSent: 0, late: 11, lateOutOfDepot: 0, peakGapMinutes: 10),
        "taiwan ntdlrt:V+ntdlrt:VB realistic": .init(notSent: 0, late: 4, lateOutOfDepot: 0, peakGapMinutes: 5),
        "taiwan tra:LIUJIA+tra:NEIWAN realistic": .init(notSent: 0, late: 3, lateOutOfDepot: 0, peakGapMinutes: 0),
        "taiwan tra:NEIWAN+tra:LIUJIA realistic": .init(notSent: 0, late: 3, lateOutOfDepot: 0, peakGapMinutes: 0),
    ]

    /// The lines on sale in `session` that share a station with another,
    /// in groups, each in the order it is laid, the groups sorted by
    /// their first line: the game's bundles of more than one line
    /// (decision 862; two lines are in one group when a stop of one has
    /// the name of a stop of the other, in the same railway system, or a
    /// third line joins them).
    static func sharingGroups(in session: GameSession) -> [[String]] {
        session.realLineBundles.filter { !$0.isSingle }.map { $0.lines.map(\.id) }.sorted { $0[0] < $1[0] }
    }

    /// Buys the bundle of `session` whose lines are `ids`, in one
    /// purchase, as a player does (decision 862).
    static func buyTogether(_ ids: [String], in session: GameSession, file: StaticString = #filePath, line: UInt = #line) throws {
        let bundle = try XCTUnwrap(session.realLineBundles.first { $0.lines.map(\.id) == ids }, "\(ids) sold together", file: file, line: line)
        let offer = session.realLineBundleOffer(for: bundle)
        XCTAssertTrue(
            session.acquireRealLines(offer), "\(ids) not bought: \(offer.problemText(in: .traditionalChinese) ?? session.message?.text ?? "")",
            file: file, line: line
        )
    }

    // MARK: - The games

    private static func session(_ opened: GameWorld, rules: NewGameRules) throws -> GameSession {
        var world = opened
        var options = NewGameOptions()
        options.rules = rules
        options.apply(to: &world)
        try world.mapGround()
        return GameSession(world: world, language: .traditionalChinese)
    }

    /// A game on the whole of Taiwan, as the launcher starts it.
    static func wholeTaiwan(rules: NewGameRules) throws -> GameSession {
        let session = try session(GameWorld.newWholeTaiwanGame(balance: Money(1_000_000_000_000)), rules: rules)
        session.railways = try BundledRealData.railways()
        session.heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        return session
    }

    /// A game on Hong Kong's map, as the launcher starts it.
    static func hongKong(rules: NewGameRules) throws -> GameSession {
        let ground = try HongKongMapTests.ground()
        let session = try session(GameWorld.newOverseasGame(ground, balance: Money(1_000_000_000_000)), rules: rules)
        session.railways = try HongKongRailwaysTests.railways()
        session.population = ground.population
        session.water = ground.water
        session.heights = ground.heights
        return session
    }

    /// A game on Rovaniemi's map, as the launcher starts it.
    static func rovaniemi(rules: NewGameRules) throws -> GameSession {
        let ground = try RovaniemiRailwaysTests.ground()
        let session = try session(GameWorld.newOverseasGame(ground, balance: Money(1_000_000_000_000)), rules: rules)
        session.railways = try RovaniemiRailwaysTests.railways()
        session.population = ground.population
        session.water = ground.water
        session.heights = ground.heights
        return session
    }

    /// A game on Fukuoka's map, as the launcher starts it (FUKUOKA-OPEN).
    static func fukuoka(rules: NewGameRules) throws -> GameSession {
        let ground = try FukuokaRailwaysTests.ground()
        let session = try session(GameWorld.newOverseasGame(ground, balance: Money(1_000_000_000_000)), rules: rules)
        session.railways = try FukuokaRailwaysTests.railways()
        session.population = ground.population
        session.water = ground.water
        session.heights = ground.heights
        return session
    }

    /// Buys the lines on sale in `session` whose ids `wanted` holds (every
    /// one when `nil`), in the order of their ids, looking at the list
    /// again after each: a line sharing its first stations with one just
    /// bought is then sold from where they part.
    static func buy(_ wanted: Set<String>? = nil, in session: GameSession, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        var bought: [String] = []
        var refused: Set<String> = []
        while let next = session.buyableRealLines.sorted(by: { $0.id < $1.id }).first(where: {
            !refused.contains($0.id) && (wanted?.contains($0.id) ?? true)
        }) {
            let offer = session.realLineOffer(for: next)
            if session.acquireRealLine(offer) {
                bought.append(next.id)
            } else {
                refused.insert(next.id)
                XCTFail("\(next.id) not bought: \(offer.problem ?? session.message?.text ?? "")", file: file, line: line)
            }
        }
        return bought
    }

    // MARK: - What is on sale against what is played

    /// The lines on sale of each map (the game's list) and the lines the
    /// checkup's single-line worlds buy: every line a player can buy is
    /// bought alone in a world of ``TimetableCheckupFullTests`` or here,
    /// and (by `buy(in:)` buying whatever is on sale) with the rest of
    /// its map. Red when a map sells a line the checkup does not know.
    func testEveryLineOnSaleIsPlayed() throws {
        let railways = try BundledRealData.railways()
        // What TimetableCheckupFullTests' three Taiwan and Hong Kong tests
        // buy alone, by the same rule they list them with.
        let taiwanAlone = Set(railways.metroRuns.keys.filter { !$0.hasPrefix("hkmtr:") && !$0.hasPrefix("vr:") && !$0.contains(" after ") })
            .union(railways.branchRuns.keys.map { "tra:\($0)" })
        let hongKongAlone = Set(try HongKongRailwaysTests.railways().metroRuns.keys.filter { $0.hasPrefix("hkmtr:") })
        let rovaniemiAlone: Set<String> = ["vr:KJA", "vr:MUL"]

        let taiwan = Set(try Self.wholeTaiwan(rules: .simple).buyableRealLines.map(\.id))
        let hongKong = Set(try Self.hongKong(rules: .simple).buyableRealLines.map(\.id))
        let rovaniemi = Set(try Self.rovaniemi(rules: .simple).buyableRealLines.map(\.id))
        let fukuoka = Set(try Self.fukuoka(rules: .simple).buyableRealLines.map(\.id))
        let text = "TIMETABLE_CHECKUP on sale: Taiwan \(taiwan.sorted()), Hong Kong \(hongKong.sorted()), Rovaniemi \(rovaniemi.sorted()), Fukuoka \(fukuoka.sorted())\n"
        FileHandle.standardError.write(Data(text.utf8))
        XCTAssertEqual(taiwan.count, 15)
        XCTAssertEqual(hongKong.count, 6)
        XCTAssertEqual(rovaniemi.count, 2)
        XCTAssertEqual(taiwan.subtracting(taiwanAlone), [], "Taiwan lines on sale no world buys alone")
        XCTAssertEqual(hongKong.subtracting(hongKongAlone), [], "Hong Kong lines on sale no world buys alone")
        XCTAssertEqual(rovaniemi.subtracting(rovaniemiAlone), [], "Rovaniemi lines on sale no world buys alone")
        // FUKUOKA-OPEN: Fukuoka's three lines share Hakata and
        // Nakasu-Kawabata, so they are only ever sold together (decision
        // 862, older than the map's opening: no save holds one alone);
        // `testFukuokaLines` plays them together.
        XCTAssertEqual(fukuoka, ["fksubway:K", "fksubway:H", "fksubway:N"])
    }

    /// The groups of lines sharing a station on each map, and the worlds
    /// that buy each together: Taiwan's are bought as worked out
    /// (`testTaiwanLinesSharingAStation`), so only their number is pinned;
    /// Hong Kong's is ``TimetableCheckupFullTests``'s `hk TCL+AEL+DRL`,
    /// Rovaniemi's is `testRovaniemiEachLineAndBoth`'s.
    func testEveryGroupSharingAStationIsPlayed() throws {
        let taiwan = Self.sharingGroups(in: try Self.wholeTaiwan(rules: .simple))
        let hongKong = Self.sharingGroups(in: try Self.hongKong(rules: .simple))
        let rovaniemi = Self.sharingGroups(in: try Self.rovaniemi(rules: .simple))
        let fukuoka = Self.sharingGroups(in: try Self.fukuoka(rules: .simple))
        FileHandle.standardError.write(Data("TIMETABLE_CHECKUP sharing a station: Taiwan \(taiwan), Hong Kong \(hongKong), Rovaniemi \(rovaniemi), Fukuoka \(fukuoka)\n".utf8))
        XCTAssertEqual(taiwan, [["ntdlrt:V", "ntdlrt:VB"], ["tra:LIUJIA", "tra:NEIWAN"]])
        XCTAssertEqual(hongKong, [["hkmtr:TCL", "hkmtr:AEL", "hkmtr:DRL"]], "TimetableCheckupFullTests plays hk TCL+AEL+DRL, in this order")
        XCTAssertEqual(rovaniemi, [["vr:KJA", "vr:MUL"]])
        XCTAssertEqual(fukuoka.map(Set.init), [["fksubway:K", "fksubway:H", "fksubway:N"]], "testFukuokaLines plays them")
    }

    // MARK: - The whole days

    private func wanted(_ name: String) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if let only = environment["TIMETABLE_CHECKUP_ONLY"] { return only == name }
        if let rules = environment["TIMETABLE_CHECKUP_RULES"] { return name.hasSuffix(" \(rules)") }
        return true
    }

    private func full() throws {
        guard ProcessInfo.processInfo.environment["TIMETABLE_CHECKUP"] != nil else {
            throw XCTSkip("Set TIMETABLE_CHECKUP=1 for every map's lines bought together (decision 844; nightly in ci.yml).")
        }
    }

    private func check(_ name: String, _ world: @autoclosure () throws -> GameWorld) throws {
        guard wanted(name) else { return }
        try TimetableCheckupWorlds.check(name, try world(), day: 1, budget: Self.budgets[name] ?? .init())
    }

    /// Taiwan's lines on sale that share a station, each group bought in
    /// a game round its first line: together, as it is sold (decision
    /// 862), and the other way round one line at a time, as a game saved
    /// before it may have them (the second line bought is laid beside the
    /// first, or sold from where they part: decisions 400, 493, 848).
    func testTaiwanLinesSharingAStation() throws {
        try full()
        let groups = Self.sharingGroups(in: try Self.wholeTaiwan(rules: .simple))
        XCTAssertFalse(groups.isEmpty)
        for group in groups {
            for (ids, together) in [(group, true), (Array(group.reversed()), false)] {
                for (label, rules) in Self.rules {
                    let name = "taiwan \(ids.joined(separator: "+")) \(label)"
                    try check(name, {
                        let round = ids[0].hasPrefix("tra:") ? String(ids[0].dropFirst(4)) : ids[0]
                        let session = try RealLineAcquisitionTests.game(round: round, side: 1 << 21, heights: true, rules: rules)
                        if together {
                            try Self.buyTogether(ids, in: session)
                        } else {
                            for id in ids { XCTAssertEqual(Self.buy([id], in: session), [id], name) }
                        }
                        return session.world
                    }())
                }
            }
        }
    }

    /// Rovaniemi's lines each alone and both, under both rules
    /// (``TimetableCheckupFullTests/testRovaniemiLines`` plays the two
    /// together under the rules a world has before a new game's are set):
    /// together as they are sold (decision 862); the other order and each
    /// alone as a game saved before it may have them.
    func testRovaniemiEachLineAndBoth() throws {
        try full()
        for (label, rules) in Self.rules {
            for ids in [["vr:KJA"], ["vr:MUL"], ["vr:KJA", "vr:MUL"], ["vr:MUL", "vr:KJA"]] {
                let name = "rovaniemi \(ids.joined(separator: "+")) \(label)"
                try check(name, {
                    let session = try Self.rovaniemi(rules: rules)
                    if ids == ["vr:KJA", "vr:MUL"] {
                        try Self.buyTogether(ids, in: session)
                    } else {
                        for id in ids { XCTAssertEqual(Self.buy([id], in: session), [id], name) }
                    }
                    return session.world
                }())
            }
        }
    }

    /// FUKUOKA-OPEN: Fukuoka's three lines, sold together (they share
    /// Hakata and Nakasu-Kawabata), bought as a player buys them, under
    /// both rules.
    func testFukuokaLines() throws {
        try full()
        let ids = Self.sharingGroups(in: try Self.fukuoka(rules: .simple)).first ?? []
        XCTAssertEqual(ids.count, 3)
        for (label, rules) in Self.rules {
            let name = "fukuoka \(ids.joined(separator: "+")) \(label)"
            try check(name, {
                let session = try Self.fukuoka(rules: rules)
                try Self.buyTogether(ids, in: session)
                return session.world
            }())
        }
    }
}
