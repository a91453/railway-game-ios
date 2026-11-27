import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1028 (RELAY-KAMOME-LINE): the Relay Kamome, JR Kyushu's
/// limited express from Hakata to Takeo-Onsen on the Kagoshima, Nagasaki
/// and Sasebo Lines, the game's first conventional JR line, its own system
/// (`jrkyushu`) on Japan's map so it is sold by itself: its data in the
/// map pack, its trains timed to the Kamome at Takeo-Onsen, and the line
/// bought alone and played through its day. Its day's lateness is the
/// checkup's (`TimetableCheckupAllBoughtTests.testRelayKamome`).
@MainActor
final class RelayKamomeTests: XCTestCase {
    static let id = "jrkyushu:RK"
    private static let stops = ["博多", "鳥栖", "新鳥栖", "佐賀", "江北", "武雄溫泉"]
    /// Enough for every line of Japan's map.
    static let everyLine = Money(1_000_000_000_000)

    /// Its six stations with their English names, on 1,067 mm track, 21
    /// trains each way; each down train comes in to Takeo-Onsen three
    /// minutes before a Kamome leaves, each up train leaves three minutes
    /// after one comes in (the timetable's standard transfer across the
    /// platform, assets-2 `docs/research/NISHI-KYUSHU-KAMOME-2026-11-26.md`).
    func testThePackHasTheLine() throws {
        XCTAssertEqual(FukuokaRailwaysTests.open.issues, [])
        let railways = try FukuokaRailwaysTests.railways()
        let lines = railways.lines.filter { $0.lineKey == "jrkyushu|RK" }
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.allSatisfy { $0.system.id == "jrkyushu" })
        let stations = railways.stations.filter { $0.system.id == "jrkyushu" }
        XCTAssertEqual(stations.map(\.chinese).sorted(), Self.stops.sorted())
        XCTAssertEqual(stations.first { $0.chinese == "武雄溫泉" }?.english, "Takeo-Onsen")
        XCTAssertEqual(stations.first { $0.chinese == "新鳥栖" }?.english, "Shin-Tosu")
        XCTAssertEqual(OverseasMap.map(ofSystem: "jrkyushu"), .fukuoka)

        let runs = try XCTUnwrap(railways.metroRuns[Self.id])
        XCTAssertEqual(runs.stops, Self.stops)
        let real = runs.runs.filter { !$0.positioning }
        XCTAssertEqual(real.count, 42)
        XCTAssertEqual(real.filter { $0.calls.first?.station == "博多" }.count, 21)
        XCTAssertTrue(real.allSatisfy { $0.passes.isEmpty && $0.calls.count == 6 }, "every train calls at every station")

        // Each down train's arrival at Takeo-Onsen three minutes before a
        // Kamome leaves for Nagasaki, each up train's departure three
        // minutes after one comes in.
        let kamome = try XCTUnwrap(railways.metroRuns[NishiKyushuShinkansenTests.id]).runs.filter { !$0.positioning }
        let leaves = Set(kamome.compactMap { $0.calls.first { $0.station == "武雄溫泉" }?.departure })
        let arrives = Set(kamome.compactMap { $0.calls.last { $0.station == "武雄溫泉" }?.arrival })
        for run in real {
            let takeo = try XCTUnwrap(run.calls.first { $0.station == "武雄溫泉" })
            if run.calls.first?.station == "博多" {
                XCTAssertTrue(leaves.contains(takeo.arrival + 180), "down \(takeo.arrival): a Kamome three minutes on")
            } else {
                XCTAssertTrue(arrives.contains(takeo.departure - 180), "up \(takeo.departure): a Kamome three minutes before")
            }
        }

        XCTAssertEqual(TrackGauge.ofRealLine(Self.id), .cape)
        let bundles = try FukuokaRailwaysTests.fukuoka().realLineListings.map { $0.bundle.lines.map(\.id) }
            .filter { $0.contains(Self.id) }
        XCTAssertEqual(bundles, [[Self.id]], "another system than the Shinkansen's: sold by itself")
    }

    /// Bought alone from a new game's land: five sets of six cars on
    /// 1,067 mm track, its six stations, and a whole day with every train
    /// sent and none in a deadlock.
    func testTheLineIsBoughtAloneAndRunsItsDay() throws {
        let session = try FukuokaRailwaysTests.fukuoka()
        let listing = try XCTUnwrap(session.realLineListings.first { $0.bundle.lines.map(\.id) == [Self.id] }, "sold by itself")
        XCTAssertTrue(listing.isBuyable)

        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id })
        XCTAssertEqual(real.cars, 6, "the 885 series' six")
        XCTAssertNil(real.trainType)
        let offer = session.realLineOffer(for: real)
        XCTAssertNil(offer.problem)
        let acquisition = try XCTUnwrap(offer.acquisition)
        XCTAssertEqual(acquisition.trains.count, 5)
        XCTAssertEqual(acquisition.cars, 6)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let bought = try XCTUnwrap(world.acquisition(of: Self.id))
        let line = try XCTUnwrap(world.line(id: try XCTUnwrap(bought.line)))
        XCTAssertFalse(line.isHighSpeed)
        XCTAssertEqual(line.stops.compactMap { world.station(id: $0)?.name }.sorted(), Self.stops.sorted())
        XCTAssertEqual(line.runs.count, 42)
        for id in line.trains {
            XCTAssertEqual(try XCTUnwrap(world.train(id: id)).cars, 6)
        }
        let track = Set(try XCTUnwrap(bought.track))
        XCTAssertEqual(Set(world.network.edges.filter { track.contains($0.id) }.map(\.gauge)), [.cape])

        var played = world
        var stuck = 0
        for _ in 0..<(24 * 60) {
            try played.advance(ticks: 1)
            if !played.deadlockedTrains().isEmpty { stuck += 1 }
        }
        XCTAssertEqual(stuck, 0, "minutes of the day with a deadlock")
        let after = try XCTUnwrap(played.line(id: line.id))
        XCTAssertEqual(zip(after.runs, after.runDays).filter { $0.1 != nil }.count, 42, "every run of the day sent")
    }
}
