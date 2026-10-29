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
/// part, laid beside it there. Each played two real days under simple and
/// realistic rules: every run sent out, no train in a deadlock and none
/// held for long.
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

    /// Not after the Blue Coast Line: bought from Binhai Shalun, where they
    /// part, its trips cut there would stand eleven trains at once at that
    /// end (`extract_metro_runs.py`), and the game's ends lay at most
    /// seven tracks (docs/HANDOFF.md).
    func testTheGreenMountainLineIsNotOnSaleAfterTheBlueCoastLine() throws {
        let session = try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true)
        let coast = try XCTUnwrap(session.buyableRealLines.first { $0.id == "ntdlrt:VB" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: coast)), session.message?.text ?? "")
        XCTAssertFalse(session.buyableRealLines.contains { $0.id == "ntdlrt:V" })
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
