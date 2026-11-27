import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1030 (KYUSHU-SHINKANSEN-MINAMATA): the Kyushu Shinkansen on
/// south from Kumamoto to Shin-Minamata, a line of its own
/// (`kyushushinkansen:KS2`) beside Hakata–Kumamoto's: a new game buys the
/// two together, Hakata–Kumamoto first (decision 862, they share
/// Kumamoto); a game that already has Hakata–Kumamoto is sold the rest
/// and keeps what it has. Its depot is the real one at Tomiai, beside the
/// line 8 km south of Kumamoto (`RealLineDepotSite.tomiai`). Its day's
/// lateness is the checkup's
/// (`TimetableCheckupAllBoughtTests.testFukuokaShinkansen`).
@MainActor
final class KyushuShinkansenSouthTests: XCTestCase {
    static let id = "kyushushinkansen:KS2"
    private static let metre = Double(WorldCoordinate.unitsPerMetre)
    static let stops = ["熊本", "新八代", "新水俁"]

    /// Its three stations with their English names, 21 trains each way
    /// from Kumamoto (the temporary timetable of 2026-09-18 has 21 and
    /// 23), every one calling at all three; on Shinkansen track, its
    /// depot the real one at Tomiai; sold with Hakata–Kumamoto.
    func testThePackHasTheLine() throws {
        XCTAssertEqual(FukuokaRailwaysTests.open.issues, [])
        let railways = try FukuokaRailwaysTests.railways()
        XCTAssertFalse(railways.lines.filter { $0.lineKey == "kyushushinkansen|KS2" }.isEmpty)
        let stations = railways.stations.filter { $0.system.id == "kyushushinkansen" && Self.stops.contains($0.chinese) }
        XCTAssertEqual(Set(stations.map(\.chinese)), Set(Self.stops))
        XCTAssertEqual(stations.first { $0.chinese == "新八代" }?.english, "Shin-Yatsushiro")
        XCTAssertEqual(stations.first { $0.chinese == "新水俁" }?.english, "Shin-Minamata")

        let runs = try XCTUnwrap(railways.metroRuns[Self.id])
        XCTAssertEqual(runs.stops, Self.stops)
        let real = runs.runs.filter { !$0.positioning }
        XCTAssertEqual(real.count, 42)
        XCTAssertEqual(real.filter { $0.calls.first?.station == "熊本" }.count, 21)
        XCTAssertTrue(real.allSatisfy { $0.passes.isEmpty && $0.calls.count == 3 }, "every train calls at every station")
        XCTAssertEqual(runs.overnight, ["熊本": 3], "every set spends the night at Kumamoto's end, in the depot")
        XCTAssertEqual(runs.tracks["新水俁"], 2, "two tracks where the trains turn")

        XCTAssertEqual(TrackGauge.ofRealLine(Self.id), .shinkansen)
        XCTAssertEqual(RealLineDepotSite.sites(of: Self.id).map(\.chinese), ["熊本綜合車輛所"])
        XCTAssertEqual(RealLineDepotSite.sites(of: KyushuShinkansenTests.id).map(\.chinese), ["熊本車輛基地"], "Hakata–Kumamoto's as it was")

        let bundles = try FukuokaRailwaysTests.fukuoka().realLineListings.map { $0.bundle.lines.map(\.id) }
            .filter { $0.contains(Self.id) }
        XCTAssertEqual(bundles, [[KyushuShinkansenTests.id, Self.id]], "sold with Hakata–Kumamoto, which is laid first")
    }

    /// A new game buys the two together: Hakata–Kumamoto with its depot
    /// past Kumamoto as before, then the line south with three sets of
    /// eight high-speed cars and the Tomiai depot beside it; and a whole
    /// day with every train of both sent and none in a deadlock.
    func testANewGameBuysItWithHakataKumamoto() throws {
        let session = try FukuokaRailwaysTests.fukuoka(balance: RelayKamomeTests.everyLine)
        let listing = try XCTUnwrap(session.realLineListings.first { $0.bundle.lines.contains { $0.id == Self.id } })
        XCTAssertTrue(listing.isBuyable)
        let offer = session.realLineBundleOffer(for: listing.bundle)
        XCTAssertNil(offer.problem)
        let acquisitions = try XCTUnwrap(offer.acquisitions)
        XCTAssertEqual(acquisitions.map(\.realLine), [KyushuShinkansenTests.id, Self.id])
        XCTAssertEqual(acquisitions[0].depot?.name, "熊本車輛基地")
        XCTAssertEqual(acquisitions[1].depot?.name, "熊本綜合車輛所")
        XCTAssertEqual(acquisitions[1].depot?.platforms.count, 3)
        XCTAssertEqual(acquisitions[1].trains.count, 3)
        XCTAssertTrue(session.acquireRealLines(offer), session.message?.text ?? "")
        try Self.checkTheLine(in: session.world)
        try Self.playTheDay(session.world, lines: [KyushuShinkansenTests.id: 86, Self.id: 42])
    }

    /// A game that bought Hakata–Kumamoto before this line was on sale
    /// (bought here by itself, as it was sold then) keeps it as it is and
    /// is sold the line south by itself, which shares its Kumamoto.
    func testAGameWithHakataKumamotoIsSoldTheRest() throws {
        let session = try FukuokaRailwaysTests.fukuoka(balance: RelayKamomeTests.everyLine)
        let first = try XCTUnwrap(session.buyableRealLines.first { $0.id == KyushuShinkansenTests.id })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: first)), session.message?.text ?? "")
        let before = session.world
        let kumamoto = try XCTUnwrap(before.stations.first { $0.name == "熊本" && !before.network.platforms(of: $0.id).isEmpty })
        let tracks = before.network.platforms(of: kumamoto.id).map(\.edge)

        let listing = try XCTUnwrap(session.realLineListings.first { $0.bundle.lines.contains { $0.id == Self.id } })
        XCTAssertEqual(listing.bundle.lines.map(\.id), [Self.id], "the rest of the group, by itself")
        let offer = session.realLineBundleOffer(for: listing.bundle)
        XCTAssertNil(offer.problem)
        XCTAssertEqual(offer.acquisitions?.first?.depot?.name, "熊本綜合車輛所")
        XCTAssertTrue(session.acquireRealLines(offer), session.message?.text ?? "")

        let world = session.world
        let south = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: Self.id)?.line)))
        XCTAssertTrue(south.stops.contains(kumamoto.id), "Kumamoto shared")
        XCTAssertTrue(Set(world.network.platforms(of: kumamoto.id).map(\.edge)).isSuperset(of: tracks), "Hakata–Kumamoto's platforms kept")
        let north = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: KyushuShinkansenTests.id)?.line)))
        XCTAssertEqual(north, try XCTUnwrap(before.line(id: north.id)), "Hakata–Kumamoto unchanged")
        try Self.checkTheLine(in: world)
        try Self.playTheDay(world, lines: [KyushuShinkansenTests.id: 86, Self.id: 42])
    }

    /// The line south as bought: high-speed, its three stations on the
    /// viaduct with 200 m platforms, two tracks at Shin-Yatsushiro and
    /// Shin-Minamata, three sets of eight cars and the Tomiai depot's
    /// three tracks.
    static func checkTheLine(in world: GameWorld) throws {
        let bought = try XCTUnwrap(world.acquisition(of: id))
        let line = try XCTUnwrap(world.line(id: try XCTUnwrap(bought.line)))
        XCTAssertTrue(line.isHighSpeed)
        XCTAssertEqual(Set(line.stops.compactMap { world.station(id: $0)?.name }), Set(stops))
        XCTAssertEqual(line.trains.count, 3)
        for train in line.trains {
            XCTAssertEqual(try XCTUnwrap(world.train(id: train)).cars, 8)
        }
        XCTAssertEqual(line.depots.compactMap { world.station(id: $0)?.name }, ["熊本綜合車輛所"])
        XCTAssertEqual(world.network.platforms(of: try XCTUnwrap(line.depots.first)).count, 3)
        let track = Set(try XCTUnwrap(bought.track))
        XCTAssertEqual(Set(world.network.edges.filter { track.contains($0.id) }.map(\.gauge)), [.shinkansen])
        for stop in line.stops {
            let name = try XCTUnwrap(world.station(id: stop)?.name)
            let platforms = world.network.platforms(of: stop)
            if name != "熊本" {
                XCTAssertEqual(platforms.count, 2, name)
            }
            for platform in platforms {
                XCTAssertEqual(Double(platform.end - platform.start) / metre, 200, accuracy: 0.5, name)
            }
            let over = SharedStationLayoutTests.overGround(stop, in: world)
            XCTAssertTrue(over.allSatisfy { $0 > 8 && $0 < 30 }, "\(name): on the viaduct, \(over) m over the ground")
        }
    }

    /// A whole day: every run of `lines` sent, no minute with a train in
    /// a deadlock.
    static func playTheDay(_ world: GameWorld, lines: [String: Int]) throws {
        var played = world
        var stuck = 0
        for _ in 0..<(24 * 60) {
            try played.advance(ticks: 1)
            if !played.deadlockedTrains().isEmpty { stuck += 1 }
        }
        XCTAssertEqual(stuck, 0, "minutes of the day with a deadlock")
        for (id, runs) in lines {
            let line = try XCTUnwrap(played.line(id: try XCTUnwrap(played.acquisition(of: id)?.line)))
            XCTAssertEqual(zip(line.runs, line.runDays).filter { $0.1 != nil }.count, runs, "\(id): every run of the day sent")
        }
    }
}
