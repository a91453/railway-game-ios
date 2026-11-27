import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1029 (SANYO-SHINKANSEN-KOKURA): the Sanyo Shinkansen, JR
/// West's, from Hakata to Kokura, its own system (`sanyoshinkansen`) on
/// Japan's map so it is sold by itself: its data in the map pack and the
/// line bought alone and played through its day. Its day's lateness is the
/// checkup's (`TimetableCheckupAllBoughtTests.testSanyoShinkansen`).
/// SANYO-HAKATA-SHARED (decision 1032): sold once the Kyushu Shinkansen is
/// bought, its trains at that line's Hakata platforms,
/// `SharedStationLayoutTests.testTheSanyoShinkansenStandsAtTheKyushuShinkansensPlatforms`.
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

    /// SANYO-HAKATA-SHARED (decision 1032): on sale once the Kyushu
    /// Shinkansen is the company's, its trains running onto that line's
    /// track at Hakata and standing at its platforms there: the four east
    /// of the two the Kyushu Shinkansen's own trains take (the real
    /// tracks 13 to 16 beside 11 and 12), each holding the sixteen cars.
    /// Its sets of sixteen high-speed cars on standard-gauge track, two
    /// of them overnight at Hakata, and a whole day of both lines with
    /// every train sent and none in a deadlock. The Kyushu Shinkansen
    /// cannot be removed while it runs on its track.
    func testTheLineRunsOntoTheKyushuShinkansensHakata() throws {
        let session = try FukuokaRailwaysTests.fukuoka(balance: RelayKamomeTests.everyLine)
        XCTAssertNotNil(session.realLineListings.first { $0.bundle.lines.map(\.id) == [Self.id] }, "sold by itself")
        let first = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id })
        XCTAssertEqual(session.realLineOffer(for: first).problem, "這條線的列車開進九州新幹線的軌道、停在它的月台，要先買九州新幹線。")

        _ = try SharedStationLayoutTests.buy([KyushuShinkansenTests.id], on: session)
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
        let kyushu = try XCTUnwrap(world.acquisition(of: KyushuShinkansenTests.id))
        let line = try XCTUnwrap(world.line(id: try XCTUnwrap(bought.line)))
        let kyushuLine = try XCTUnwrap(world.line(id: try XCTUnwrap(kyushu.line)))
        XCTAssertTrue(line.isHighSpeed)
        XCTAssertEqual(line.stops.compactMap { world.station(id: $0)?.name }.sorted(), Self.stops.sorted())
        XCTAssertEqual(line.runs.count, 138)
        for id in line.trains {
            XCTAssertEqual(try XCTUnwrap(world.train(id: id)).cars, 16)
        }
        let track = Set(try XCTUnwrap(bought.track)), kyushuTrack = Set(try XCTUnwrap(kyushu.track))
        XCTAssertEqual(Set(world.network.edges.filter { track.contains($0.id) }.map(\.gauge)), [.shinkansen])

        // One Hakata, the Kyushu Shinkansen's, its six platforms all on
        // that line's track and as long as sixteen cars.
        let hakata = try XCTUnwrap(world.stations.first { $0.name == "博多" }?.id)
        XCTAssertEqual(world.stations.filter { $0.name == "博多" }.count, 1)
        XCTAssertTrue(line.stops.contains(hakata) && kyushuLine.stops.contains(hakata))
        let platforms = world.network.platforms(of: hakata)
        XCTAssertEqual(platforms.count, 6, "the real tracks 11 to 16")
        let length = RealBranchLine.platformLength(cars: 16, of: .highSpeed, real: world.realCarLengths)
        for platform in platforms {
            XCTAssertTrue(kyushuTrack.contains(platform.edge), "no platform of its own")
            XCTAssertGreaterThanOrEqual(platform.end - platform.start, length)
        }
        // Its trains at four of them, none the Kyushu Shinkansen's own.
        let own = Set(kyushuLine.routePreferences.filter { $0.to == kyushuLine.stops.firstIndex(of: hakata) }.flatMap { [$0.platform] + $0.alternates }.map(\.edge))
        let at = line.routePreferences.filter { line.stops[$0.to] == hakata }
        XCTAssertEqual(at.count, 1)
        let taken = Set(at.flatMap { [$0.platform] + $0.alternates }.map(\.edge))
        XCTAssertEqual(taken.count, 4, "the real tracks 13 to 16")
        XCTAssertTrue(taken.isDisjoint(with: own), "not the Kyushu Shinkansen's own")
        XCTAssertTrue(taken.isSubset(of: Set(platforms.map(\.edge))))
        let standing = line.trains.filter { id in
            guard case .onEdge(let traversal, _)? = world.train(id: id)?.position else { return false }
            return taken.contains(traversal.edge)
        }
        XCTAssertEqual(standing.count, 2, "two overnight at Hakata")
        XCTAssertNotNil(session.lineRemovalRefusal(kyushuLine.id), "the Kyushu Shinkansen not removed under it")

        var played = world
        var stuck = 0
        for _ in 0..<(24 * 60) {
            try played.advance(ticks: 1)
            if !played.deadlockedTrains().isEmpty { stuck += 1 }
        }
        // At most the one minute at night when the last train in finds
        // the track it is to stop at taken by a train standing there
        // overnight, and is moved to another of its four (decision 278).
        XCTAssertLessThanOrEqual(stuck, 1, "minutes of the day with a deadlock")
        for id in [line.id, kyushuLine.id] {
            let after = try XCTUnwrap(played.line(id: id))
            XCTAssertEqual(zip(after.runs, after.runDays).filter { $0.1 != nil }.count, after.runs.count, "every run of the day sent")
        }
    }
}
