import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1029 (SANYO-SHINKANSEN-KOKURA): the Sanyo Shinkansen, JR
/// West's, from Hakata to Kokura, its own system (`sanyoshinkansen`) on
/// Japan's map so it is sold by itself: its data in the map pack and the
/// line bought alone and played through its day. Its day's lateness is the
/// checkup's (`TimetableCheckupAllBoughtTests.testSanyoShinkansen`); its
/// Hakata beside the Kyushu Shinkansen's,
/// `SharedStationLayoutTests.testTheSanyoShinkansenStandsBesideTheKyushuShinkansen`.
@MainActor
final class SanyoShinkansenTests: XCTestCase {
    static let id = "sanyoshinkansen:SY"
    private static let stops = ["博多", "小倉"]

    /// Its two stations with their English names, 69 trains each way
    /// between them, on standard-gauge track; another system than the
    /// Kyushu Shinkansen's, so sold by itself.
    func testThePackHasTheLine() throws {
        XCTAssertEqual(FukuokaRailwaysTests.open.issues, [])
        let railways = try FukuokaRailwaysTests.railways()
        let lines = railways.lines.filter { $0.lineKey == "sanyoshinkansen|SY" }
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.allSatisfy { $0.system.id == "sanyoshinkansen" })
        let stations = railways.stations.filter { $0.system.id == "sanyoshinkansen" }
        XCTAssertEqual(stations.map(\.chinese).sorted(), Self.stops.sorted())
        XCTAssertEqual(stations.first { $0.chinese == "小倉" }?.english, "Kokura")
        XCTAssertEqual(OverseasMap.map(ofSystem: "sanyoshinkansen"), .fukuoka)

        let runs = try XCTUnwrap(railways.metroRuns[Self.id])
        XCTAssertEqual(runs.stops, Self.stops)
        let real = runs.runs.filter { !$0.positioning }
        XCTAssertEqual(real.count, 138)
        XCTAssertEqual(real.filter { $0.calls.first?.station == "博多" }.count, 69)
        XCTAssertTrue(real.allSatisfy { $0.calls.count == 2 })

        XCTAssertEqual(TrackGauge.ofRealLine(Self.id), .shinkansen)
        let bundles = try FukuokaRailwaysTests.fukuoka().realLineListings.map { $0.bundle.lines.map(\.id) }
            .filter { $0.contains(Self.id) }
        XCTAssertEqual(bundles, [[Self.id]], "another system than the Kyushu Shinkansen's: sold by itself")
    }

    /// Bought alone from a new game's land: its sets of sixteen
    /// high-speed cars on standard-gauge track, its two stations, and a
    /// whole day with every train sent and none in a deadlock.
    func testTheLineIsBoughtAloneAndRunsItsDay() throws {
        let session = try FukuokaRailwaysTests.fukuoka()
        let listing = try XCTUnwrap(session.realLineListings.first { $0.bundle.lines.map(\.id) == [Self.id] }, "sold by itself")
        XCTAssertTrue(listing.isBuyable)

        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id })
        XCTAssertEqual(real.cars, 16, "the N700S's and the 700 series' sixteen")
        XCTAssertEqual(real.trainType, .highSpeed)
        let offer = session.realLineOffer(for: real)
        XCTAssertNil(offer.problem)
        let acquisition = try XCTUnwrap(offer.acquisition)
        XCTAssertNil(acquisition.depot, "no depot: the real one is down the Kyushu Shinkansen's tracks")
        XCTAssertEqual(acquisition.cars, 16)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let bought = try XCTUnwrap(world.acquisition(of: Self.id))
        let line = try XCTUnwrap(world.line(id: try XCTUnwrap(bought.line)))
        XCTAssertTrue(line.isHighSpeed)
        XCTAssertEqual(line.stops.compactMap { world.station(id: $0)?.name }.sorted(), Self.stops.sorted())
        XCTAssertEqual(line.runs.count, 138)
        for id in line.trains {
            XCTAssertEqual(try XCTUnwrap(world.train(id: id)).cars, 16)
        }
        let track = Set(try XCTUnwrap(bought.track))
        XCTAssertEqual(Set(world.network.edges.filter { track.contains($0.id) }.map(\.gauge)), [.shinkansen])

        var played = world
        var stuck = 0
        for _ in 0..<(24 * 60) {
            try played.advance(ticks: 1)
            if !played.deadlockedTrains().isEmpty { stuck += 1 }
        }
        XCTAssertEqual(stuck, 0, "minutes of the day with a deadlock")
        let after = try XCTUnwrap(played.line(id: line.id))
        XCTAssertEqual(zip(after.runs, after.runDays).filter { $0.1 != nil }.count, 138, "every run of the day sent")
    }
}
