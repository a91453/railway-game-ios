import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1041 (KUMAMOTO-TRAM): the Kumamoto City Tram's Lines A and B
/// on Fukuoka's map, street trams bought as a light rail to the operator's
/// timetable (its GTFS, CC BY 2.1 JP): sold together, A first and B from
/// Karashimacho, where they part; on standard gauge under 600 V wires, at
/// 40 km/h, with the real Ōe depot beside Line A and the Kami-Kumamoto
/// depot past Line B's end. Its day's lateness is the checkup's
/// (`TimetableCheckupAllBoughtTests.testKumamotoTram`).
@MainActor
final class KumamotoTramTests: XCTestCase {
    static let a = "kumamotocity:A", b = "kumamotocity:B"

    /// Line A's 26 stops and Line B's 28, the operator's every trip of
    /// the day (481 and 265 a week's worth of days apart, with the empty
    /// runs to and from the depots), each line's trams overnight in its
    /// depot; Line A's trips that turn at Kumamoto-Ekimae run on to
    /// Tasakibashi; sold together, on standard gauge, each with its depot.
    func testThePackHasTheLines() throws {
        let railways = try FukuokaRailwaysTests.railways()
        let lineA = try XCTUnwrap(railways.metroRuns[Self.a])
        XCTAssertEqual(lineA.stops.count, 26)
        XCTAssertEqual(lineA.stops.first, "健軍町")
        XCTAssertEqual(lineA.stops.last, "田崎橋")
        XCTAssertEqual(lineA.runs.filter { !$0.positioning }.count, 481)
        XCTAssertEqual(lineA.overnight, ["交通局前": 22], "every tram of Line A stands overnight in the Ōe depot, beside Kōtsūkyoku-mae")
        XCTAssertFalse(lineA.runs.contains { !$0.positioning && ($0.calls.first?.station == "熊本站前" || $0.calls.last?.station == "熊本站前") },
                       "the trips turning at Kumamoto-Ekimae run on to Tasakibashi")
        let lineB = try XCTUnwrap(railways.metroRuns[Self.b])
        XCTAssertEqual(lineB.stops.count, 28)
        XCTAssertEqual(lineB.stops.last, "上熊本")
        XCTAssertEqual(lineB.runs.filter { !$0.positioning }.count, 265)
        let fromKarashimacho = try XCTUnwrap(railways.metroRuns["\(Self.b) after \(Self.a)"])
        XCTAssertEqual(fromKarashimacho.stops.first, "辛島町", "after Line A, from where they part")
        XCTAssertEqual(fromKarashimacho.stops.count, 10)
        XCTAssertEqual(fromKarashimacho.overnight, ["上熊本": 9])

        for id in [Self.a, Self.b] {
            XCTAssertEqual(TrackGauge.ofRealLine(id), .standard, id)
        }
        XCTAssertEqual(RealLineDepotSite.sites(of: Self.a).map(\.chinese), ["大江車庫"])
        XCTAssertEqual(RealLineDepotSite.sites(of: Self.b).map(\.chinese), ["上熊本車庫"])
        let bundles = try FukuokaRailwaysTests.fukuoka().realLineListings.map { $0.bundle.lines.map(\.id) }
            .filter { $0.contains(Self.a) || $0.contains(Self.b) }
        XCTAssertEqual(bundles, [[Self.a, Self.b]], "sold together, Line A laid first")
    }

    /// A new game begun round Kumamoto buys the two together: Line A with 22 trams and the Ōe
    /// depot's 22 tracks, Line B from Karashimacho with 9 trams and the
    /// Kami-Kumamoto depot's 9; every track of both on standard gauge;
    /// and a whole day with every run of both sent and no deadlock of more
    /// than one tram or past four minutes.
    func testANewGameBuysThemTogether() throws {
        let session = try FukuokaRailwaysTests.fukuoka(start: 2, balance: RelayKamomeTests.everyLine)
        let listing = try XCTUnwrap(session.realLineListings.first { $0.bundle.lines.contains { $0.id == Self.a } })
        XCTAssertTrue(listing.isBuyable)
        let offer = session.realLineBundleOffer(for: listing.bundle)
        XCTAssertNil(offer.problem, offer.problemText(in: .traditionalChinese) ?? "")
        let acquisitions = try XCTUnwrap(offer.acquisitions)
        XCTAssertEqual(acquisitions.map(\.realLine), [Self.a, Self.b])
        XCTAssertEqual(acquisitions.map { $0.depot?.name }, ["大江車庫", "上熊本車庫"])
        XCTAssertEqual(acquisitions.map { $0.depot?.platforms.count }, [22, 9])
        XCTAssertEqual(acquisitions.map(\.trains.count), [22, 9])
        XCTAssertTrue(session.acquireRealLines(offer), session.message?.text ?? "")

        let world = session.world
        for id in [Self.a, Self.b] {
            let bought = try XCTUnwrap(world.acquisition(of: id))
            let line = try XCTUnwrap(world.line(id: try XCTUnwrap(bought.line)))
            XCTAssertEqual(line.depots.count, 1, id)
            let track = Set(try XCTUnwrap(bought.track))
            XCTAssertEqual(Set(world.network.edges.filter { track.contains($0.id) }.map(\.gauge)), [.standard], id)
        }
        let lineA = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: Self.a)?.line)))
        let lineB = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: Self.b)?.line)))
        let karashimacho = try XCTUnwrap(lineB.stops.first { world.station(id: $0)?.name == "辛島町" })
        XCTAssertTrue([lineB.stops.first, lineB.stops.last].contains(karashimacho), "Line B ends at Karashimacho")
        XCTAssertTrue(lineA.stops.contains(karashimacho), "Line B ends at Line A's Karashimacho")
        XCTAssertEqual(lineB.stops.count, 10)

        // A tram turning back between the ends, or one standing at an end
        // between runs, holds the next one a while: on 2026-11-27, 21 such
        // minutes in the day, each with one tram, the longest 4 in a row,
        // each cleared by itself (decision 1041 §4,
        // KUMAMOTO-TRAM-MINUTE-DEADLOCKS).
        var played = world
        var stuck = 0, longest = 0, most = 0
        for _ in 0..<(24 * 60) {
            try played.advance(ticks: 1)
            let locked = played.deadlockedTrains().count
            stuck = locked > 0 ? stuck + 1 : 0
            longest = max(longest, stuck)
            most = max(most, locked)
        }
        XCTAssertLessThanOrEqual(longest, 4, "minutes in a row with a deadlock")
        XCTAssertLessThanOrEqual(most, 1, "trams in a deadlock at once")
        for id in [Self.a, Self.b] {
            let line = try XCTUnwrap(played.line(id: try XCTUnwrap(played.acquisition(of: id)?.line)))
            let due = line.runs.filter { $0.runs(onDay: 0) && $0.fits(onDay: 0) }.count
            XCTAssertGreaterThan(due, 0, id)
            XCTAssertEqual(zip(line.runs, line.runDays).filter { $0.1 != nil }.count, due, "\(id): every run of the day sent")
        }
    }
}
