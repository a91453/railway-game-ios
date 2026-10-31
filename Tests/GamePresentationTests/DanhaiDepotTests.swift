import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 489: Danhai's Green Mountain Line is bought with the Danhai
/// depot past Kanding, where the real line runs on into it. Its thirteen
/// trains end the day at Kanding, more than the game's end lays tracks
/// for; they stand in the depot overnight and run out empty for the
/// morning's first runs, so the line is on sale: alone, and before the
/// Blue Coast Line, which is then bought from Binhai Shalun, where they
/// part, laid beside it there; and after it (decision 493), bought whole
/// beside it. Each played two real days under simple and realistic rules:
/// every run sent out, no train in a deadlock and none held for long.
@MainActor
final class DanhaiDepotTests: XCTestCase {
    func testTheLineIsBoughtWithItsRealDepot() throws {
        let session = try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "ntdlrt:V" }, "the Green Mountain Line on sale")
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        let depot = try XCTUnwrap(acquisition.depot)
        XCTAssertEqual(depot.platforms.count, RealLineDepotSite.danhai.sidings)
        XCTAssertEqual(acquisition.trains.count, 13)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let station = try XCTUnwrap(world.stations.first(where: \.isDepot))
        XCTAssertEqual(station.name, "淡海機廠")
        let bought = try XCTUnwrap(world.lines.first)
        XCTAssertEqual(bought.depots, [station.id])
        // Where the real one is: within 300 m of the real yard's middle.
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let site = RealLineDepotSite.danhai
        let real = WorldVector(frame.worldPosition(
            latitude: (site.yard.start.latitude + site.yard.end.latitude) / 2, longitude: (site.yard.start.longitude + site.yard.end.longitude) / 2
        ))
        let away = (WorldVector(station.location) - real).length / RealLineAcquisition.metre
        FileHandle.standardError.write(Data("Danhai depot \(Int(away)) m from the real yard's middle\n".utf8))
        XCTAssertLessThan(away, 300)
        // Overnight: nine in the depot, as the real one stables, the rest
        // at Hongshulin.
        func standing(at id: StationID) -> Int { world.trains.count { world.stationsStoppedAt(by: $0.id).contains(id) } }
        XCTAssertEqual(standing(at: station.id), 9)
        let hongshulin = try XCTUnwrap(world.stations.first { $0.name == "紅樹林" && bought.stops.contains($0.id) })
        XCTAssertEqual(standing(at: hongshulin.id), 4)
    }

    /// Decision 493: after the Blue Coast Line too, bought whole from
    /// Hongshulin with its depot, laid beside the Blue Coast Line's track
    /// to Binhai Shalun, where they part, and its platforms at the stations
    /// they share joining the Blue Coast Line's.
    func testTheGreenMountainLineIsBoughtWholeAfterTheBlueCoastLine() throws {
        let session = try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true)
        let coast = try XCTUnwrap(session.buyableRealLines.first { $0.id == "ntdlrt:VB" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: coast)), session.message?.text ?? "")
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "ntdlrt:V" }, "the Green Mountain Line on sale")
        XCTAssertEqual(line.after, "ntdlrt:VB")
        XCTAssertEqual(line.stops.first, "紅樹林")
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        XCTAssertEqual(acquisition.depot?.platforms.count, RealLineDepotSite.danhai.sidings)
        XCTAssertEqual(acquisition.trains.count, 13)
        let stations = session.world.stations.count
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        // Nine stations shared, Hongshulin to Binhai Shalun: only the
        // two beyond and the depot are new.
        let world = session.world
        XCTAssertEqual(world.stations.count, stations + 3)
        let coastLine = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: "ntdlrt:VB")?.line)))
        let green = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: "ntdlrt:V")?.line)))
        XCTAssertEqual(Set(green.stops).intersection(coastLine.stops).count, 9)
        let depot = try XCTUnwrap(world.stations.first(where: \.isDepot))
        func standing(at id: StationID) -> Int { world.trains.count { world.stationsStoppedAt(by: $0.id).contains(id) } }
        XCTAssertEqual(standing(at: depot.id), 9)
    }

    /// Decision 528 (BUGHUNT_BUILD P3-5): a real line bought and removed
    /// is on sale again, the track it left taken up and laid again, and
    /// runs as bought; removing it says its track and stations stay
    /// until then. A line of the player's own says only what it sells.
    func testABoughtLineRemovedIsBoughtAgain() throws {
        let session = try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true)
        let green = try XCTUnwrap(session.buyableRealLines.first { $0.id == "ntdlrt:V" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: green)), session.message?.text ?? "")
        let bought = try XCTUnwrap(session.world.acquisition(of: "ntdlrt:V")?.line)
        XCTAssertTrue(session.lineRemovalText(bought).hasPrefix("它的 13 列車會一起賣掉"))
        XCTAssertTrue(session.lineRemovalText(bought).hasSuffix("這條線是買來的，刪掉後可以再買回來；軌道與車站會留著。"))
        let stations = session.world.stations.count, edges = session.world.network.edges.count

        let ownStops = Array(try XCTUnwrap(session.world.line(id: bought)?.stops).prefix(2))
        session.selectLine(bought)
        session.removeSelectedLine()
        XCTAssertNil(session.world.line(id: bought), session.message?.text ?? "")
        XCTAssertNil(session.world.acquisition(of: "ntdlrt:V"))
        XCTAssertEqual(session.world.network.edges.count, edges, "its track stays")
        var world = session.world
        let again = session
        let line = try XCTUnwrap(again.buyableRealLines.first { $0.id == "ntdlrt:V" }, "the Green Mountain Line on sale again")
        let offer = again.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        let clearing = try XCTUnwrap(acquisition.clearing, "the track it left taken up")
        XCTAssertGreaterThan(clearing.edges.count, 0)
        XCTAssertEqual(clearing.stations.count, 1, "its old depot")
        XCTAssertTrue(again.acquireRealLine(offer), again.message?.text ?? "")
        XCTAssertNotNil(again.world.acquisition(of: "ntdlrt:V"))
        // Its stations are the ones it left (the depot built again).
        XCTAssertEqual(again.world.stations.count, stations)
        XCTAssertEqual(again.world.trains.count, 13)

        let own = try world.createLine(named: "自己的線", stops: ownStops)
        let mine = GameSession(world: world, language: .english)
        XCTAssertEqual(mine.lineRemovalText(own.id), "The line has no trains.")
    }

    /// `ids` bought in turn on a game round the Green Mountain Line under
    /// `rules`, then played to three in the morning of the third day,
    /// hour by hour: no train in a deadlock at any hour, none more than
    /// half an hour behind its timetable, and every run of each line's
    /// second day sent out.
    static func buyAndRun(_ ids: [String], rules: NewGameRules) throws {
        let session = try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true, rules: rules)
        for id in ids {
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, "\(id) on sale after \(ids)")
            let offer = session.realLineOffer(for: line)
            XCTAssertNil(offer.problem, "\(id) after \(ids): \(offer.problem ?? "")")
            XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(session.message?.text ?? "")")
        }
        var world = session.world
        let started = Date()
        var deadlocked = 0, late: Int64 = 0
        for _ in 0..<51 {
            try world.advance(ticks: 60)
            deadlocked = max(deadlocked, world.deadlockedTrains().count)
            late = max(late, world.trains.compactMap { world.lateness(of: $0.id) }.max() ?? 0)
        }
        let label = "\(ids.joined(separator: " then ")) (\(rules))"
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        var report: [String] = []
        for id in ids {
            let ran = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: id)?.line)))
            let missed = zip(ran.runs, ran.runDays).filter { run, day in
                run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
            }
            XCTAssertEqual(missed.count, 0, "\(label): \(id) runs not sent out yesterday: \(missed.count) of \(ran.runs.count)")
            report.append("\(id) \(ran.trains.count) trains, \(ran.runs.count) runs, \(missed.count) missed")
        }
        XCTAssertEqual(deadlocked, 0, label)
        XCTAssertLessThanOrEqual(late, 30 * GameTime.secondsPerMinute, label)
        FileHandle.standardError.write(Data(
            "\(label): \(report.joined(separator: "; ")); most deadlocked \(deadlocked), most late \(late / 60) min; 51 hours in \(String(format: "%.1f", Date().timeIntervalSince(started))) s\n".utf8
        ))
    }
}

/// Decision 489: the Green Mountain Line alone, two real days under each
/// rule (some 80 s each, debug); a class of its own so CI can put it in a
/// shard with room (`.github/scripts/swift-shards.sh`).
@MainActor
final class DanhaiGreenLineDayTests: XCTestCase {
    func testTheGreenMountainLineAloneRunsTwoRealDays() throws {
        for rules in [NewGameRules.simple, .realistic] {
            try DanhaiDepotTests.buyAndRun(["ntdlrt:V"], rules: rules)
        }
    }
}

/// Decision 489: the Green Mountain Line, then the Blue Coast Line from
/// Binhai Shalun, two real days under each rule (some 120 s each, debug).
@MainActor
final class DanhaiBothLinesDayTests: XCTestCase {
    func testTheBlueCoastLineAfterTheGreenMountainLineRunsTwoRealDays() throws {
        for rules in [NewGameRules.simple, .realistic] {
            try DanhaiDepotTests.buyAndRun(["ntdlrt:V", "ntdlrt:VB"], rules: rules)
        }
    }
}

/// Decision 493: the Blue Coast Line, then the Green Mountain Line bought
/// whole beside it, two real days under simple rules (some 330 s, debug);
/// a class for each rule so CI can put them in two shards.
@MainActor
final class DanhaiBlueThenGreenSimpleDayTests: XCTestCase {
    func testTheGreenMountainLineAfterTheBlueCoastLineRunsTwoRealDays() throws {
        try DanhaiDepotTests.buyAndRun(["ntdlrt:VB", "ntdlrt:V"], rules: .simple)
    }
}

/// Decision 493: the same under realistic rules.
@MainActor
final class DanhaiBlueThenGreenRealisticDayTests: XCTestCase {
    func testTheGreenMountainLineAfterTheBlueCoastLineRunsTwoRealDays() throws {
        try DanhaiDepotTests.buyAndRun(["ntdlrt:VB", "ntdlrt:V"], rules: .realistic)
    }
}
