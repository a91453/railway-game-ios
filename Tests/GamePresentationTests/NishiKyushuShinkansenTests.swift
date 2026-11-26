import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 998 (NISHI-KYUSHU-SALE): the Nishi-Kyushu Shinkansen from
/// Takeo-Onsen to Nagasaki, the Kyushu Shinkansen's system's second line
/// on Japan's map (decision 997 took in Nagasaki Prefecture), on sale by
/// itself: its data in the map pack, the line bought alone from a game
/// begun round Nagasaki, and its day. Its day's lateness is the
/// checkup's (`TimetableCheckupAllBoughtTests.testNishiKyushuShinkansen`).
@MainActor
final class NishiKyushuShinkansenTests: XCTestCase {
    static let id = "kyushushinkansen:NK"
    private static let metre = Double(WorldCoordinate.unitsPerMetre)
    private static let stops = ["武雄溫泉", "嬉野溫泉", "新大村", "諫早", "長崎"]
    /// Each station's real platforms, from its 駅構造 (Japanese Wikipedia,
    /// 2026-11-26): Nagasaki 島式 2 面 4 線, the others two tracks with a
    /// platform beside each (Takeo-Onsen's each shared with the Relay
    /// Kamome across it, the game laying the Shinkansen's side).
    static let real: [String: (tracks: Int, islands: Int, sides: Int)] = [
        "武雄溫泉": (2, 0, 2), "嬉野溫泉": (2, 0, 2), "新大村": (2, 0, 2), "諫早": (2, 0, 2), "長崎": (4, 2, 0),
    ]

    /// The system's second line, its five stations with their English
    /// names, 21 trains each way from the Nagasaki end, where every set
    /// spends the night; Takeo-Onsen's two tracks and Nagasaki's four as
    /// the real ones'.
    func testThePackHasTheLine() throws {
        XCTAssertEqual(FukuokaRailwaysTests.open.issues, [])
        let railways = try FukuokaRailwaysTests.railways()
        let lines = railways.lines.filter { $0.lineKey == "kyushushinkansen|NK" }
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines.allSatisfy { $0.system.id == "kyushushinkansen" })
        let stations = railways.stations.filter { $0.system.id == "kyushushinkansen" && Self.stops.contains($0.chinese) }
        XCTAssertEqual(stations.map(\.chinese).sorted(), Self.stops.sorted())
        XCTAssertEqual(stations.first { $0.chinese == "武雄溫泉" }?.english, "Takeo-Onsen")
        XCTAssertEqual(stations.first { $0.chinese == "長崎" }?.english, "Nagasaki")

        let runs = try XCTUnwrap(railways.metroRuns[Self.id])
        XCTAssertEqual(runs.stops, Self.stops)
        XCTAssertEqual(runs.runs.filter { !$0.positioning }.count, 42)
        XCTAssertEqual(runs.runs.filter { !$0.positioning && $0.calls.first?.station == "長崎" }.count, 21)
        XCTAssertTrue(runs.runs.allSatisfy { $0.passes.isEmpty && $0.calls.count == 5 }, "every train calls at every station")
        XCTAssertEqual(runs.tracks, ["武雄溫泉": 2, "嬉野溫泉": 1, "新大村": 1, "諫早": 1, "長崎": 4])
        XCTAssertEqual(runs.overnight, ["長崎": 3], "every set spends the night at Nagasaki")

        XCTAssertEqual(TrackGauge.ofRealLine(Self.id), .shinkansen)
        let bundles = try FukuokaRailwaysTests.fukuoka().realLineListings.map { $0.bundle.lines.map(\.id) }
            .filter { $0.contains { $0.hasPrefix("kyushushinkansen:") } }
        XCTAssertEqual(Set(bundles), [["kyushushinkansen:KS"], [Self.id]], "no station shared: each sold by itself")
    }

    /// Bought alone from a new game's four tiles round Nagasaki (decision
    /// 997): six sets of six N700S cars on Shinkansen track, its five
    /// stations' platforms 150 m and as many as the real ones, and a whole
    /// day with every train sent and none in a deadlock.
    func testTheLineIsBoughtAloneAndRunsItsDay() throws {
        let session = try FukuokaRailwaysTests.fukuoka(start: 3)
        let listing = try XCTUnwrap(session.realLineListings.first { $0.bundle.lines.map(\.id) == [Self.id] }, "sold by itself")
        XCTAssertTrue(listing.isBuyable)

        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id })
        XCTAssertEqual(real.cars, 6, "the N700S Kamome's six")
        XCTAssertEqual(real.trainType, .highSpeed)
        let offer = session.realLineOffer(for: real)
        XCTAssertNil(offer.problem)
        let acquisition = try XCTUnwrap(offer.acquisition)
        XCTAssertEqual(acquisition.trains.count, 3)
        XCTAssertEqual(acquisition.cars, 6)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let bought = try XCTUnwrap(world.acquisition(of: Self.id))
        let line = try XCTUnwrap(world.line(id: try XCTUnwrap(bought.line)))
        XCTAssertTrue(line.isHighSpeed)
        XCTAssertEqual(line.stops.compactMap { world.station(id: $0)?.name }.sorted(), Self.stops.sorted())
        XCTAssertEqual(line.runs.count, 42)
        for id in line.trains {
            let train = try XCTUnwrap(world.train(id: id))
            XCTAssertEqual(train.type, .highSpeed, train.name)
            XCTAssertEqual(train.cars, 6, train.name)
        }
        let track = Set(try XCTUnwrap(bought.track))
        XCTAssertEqual(Set(world.network.edges.filter { track.contains($0.id) }.map(\.gauge)), [.shinkansen])

        var tracks: [String: Int] = [:]
        for stop in line.stops {
            let name = try XCTUnwrap(world.station(id: stop)?.name)
            let platforms = world.network.platforms(of: stop)
            tracks[name] = platforms.count
            for platform in platforms {
                XCTAssertEqual(Double(platform.end - platform.start) / Self.metre, 150, accuracy: 0.5, name)
            }
        }
        XCTAssertEqual(tracks, Self.real.mapValues(\.tracks))
        let snapshot = world.railwaySnapshot()
        for stop in line.stops {
            let station = try XCTUnwrap(world.station(id: stop))
            let frame = Map3DScene.frame(world: world, focus: (x: Double(station.location.x), y: Double(station.location.y)))
            var builder = Map3DScene.Builder(originX: frame.originX, originY: frame.originY, region: frame.region, world: world)
            _ = builder.addTrack(snapshot)
            builder.addPlatforms(snapshot)
            let laid = builder.state.platforms.laidPlatforms.filter { $0.station == stop }
            let drawn = (islands: laid.count { $0.island } / 2, sides: laid.count { !$0.island })
            let real = try XCTUnwrap(Self.real[station.name])
            XCTAssertEqual(laid.count, real.tracks, "\(station.name): a platform beside every track")
            XCTAssertTrue(drawn == (real.islands, real.sides), "\(station.name): \(drawn) drawn, \(real) real")
        }

        // Its day: every run sent, no minute with a train in a deadlock.
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
