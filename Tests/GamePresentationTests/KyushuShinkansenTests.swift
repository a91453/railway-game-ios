import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// SHINKANSEN-SALE (decision 975): the Kyushu Shinkansen from Hakata to
/// Kumamoto, the second system of Japan's map, on sale by itself: its
/// data in the map pack, the line bought alone from a new game's land,
/// and its day. Bought with the subway's lines, in either order, its
/// Hakata stands on its viaduct over theirs
/// (`SharedStationLayoutTests.testTheKyushuShinkansensHakataStandsOverTheSubways`);
/// its day's lateness is the checkup's
/// (`TimetableCheckupAllBoughtTests.testFukuokaShinkansen`).
@MainActor
final class KyushuShinkansenTests: XCTestCase {
    static let id = "kyushushinkansen:KS"
    private static let metre = Double(WorldCoordinate.unitsPerMetre)
    private static let stops = ["博多", "新鳥栖", "久留米", "筑後船小屋", "新大牟田", "新玉名", "熊本"]
    /// Decision 995: each station's real platforms, from its 駅構造
    /// (Japanese Wikipedia, 2026-11-25): its tracks, islands and side
    /// platforms. Hakata 島式 3 面 6 線, Shin-Tosu 島式 2 面 4 線,
    /// Chikugo-Funagoya 単式 1 面 1 線＋島式 1 面 2 線, Kumamoto 島式 2 面 4 線,
    /// the others 相対式 2 面 2 線.
    static let real: [String: (tracks: Int, islands: Int, sides: Int)] = [
        "博多": (6, 3, 0), "新鳥栖": (4, 2, 0), "久留米": (2, 0, 2), "筑後船小屋": (3, 1, 1),
        "新大牟田": (2, 0, 2), "新玉名": (2, 0, 2), "熊本": (4, 2, 0),
    ]

    /// Japan's map has two systems, the subway's first; the Shinkansen's
    /// one line, its seven stations from Hakata to Kumamoto with their
    /// English names, 43 trains each way from the Kumamoto end; decision
    /// 995, each station's tracks as the real one's: six at Hakata, four
    /// at Shin-Tosu, three at Chikugo-Funagoya, four at Kumamoto (its
    /// depot holds the sets its platforms do not), two at the others.
    func testThePackHasTheLine() throws {
        XCTAssertEqual(OverseasMap.fukuoka.systems, ["fksubway", "kyushushinkansen"])
        XCTAssertEqual(OverseasMap.map(ofSystem: "kyushushinkansen"), .fukuoka)
        XCTAssertEqual(OverseasMap.map(ofSystem: "fksubway"), .fukuoka)
        XCTAssertNil(OverseasMap.map(ofSystem: "thsr_sched"), "Taiwan's are on no overseas map")
        for map in OverseasMap.allCases {
            XCTAssertEqual(map.systems.first, map.system, "\(map)")
        }

        XCTAssertEqual(FukuokaRailwaysTests.open.issues, [])
        let railways = try FukuokaRailwaysTests.railways()
        XCTAssertEqual(railways.lines.filter { $0.system.id == "kyushushinkansen" }.map(\.lineKey), ["kyushushinkansen|KS"])
        let stations = railways.stations.filter { $0.system.id == "kyushushinkansen" }
        XCTAssertEqual(stations.map(\.chinese).sorted(), Self.stops.sorted())
        XCTAssertEqual(stations.first { $0.chinese == "博多" }?.english, "Hakata")
        XCTAssertEqual(stations.first { $0.chinese == "熊本" }?.english, "Kumamoto")
        XCTAssertTrue(stations.allSatisfy { $0.english != nil })

        let runs = try XCTUnwrap(railways.metroRuns[Self.id])
        XCTAssertEqual(runs.stops, Self.stops)
        XCTAssertEqual(runs.runs.filter { !$0.positioning }.count, 86)
        XCTAssertEqual(runs.runs.filter { !$0.positioning && $0.calls.first?.station == "博多" }.count, 43)
        XCTAssertTrue(runs.runs.allSatisfy { $0.passes.isEmpty && $0.calls.count == 7 }, "every train calls at every station")
        XCTAssertEqual(runs.tracks, ["博多": 6, "新鳥栖": 4, "久留米": 1, "筑後船小屋": 3, "新大牟田": 1, "新玉名": 1, "熊本": 4])
        XCTAssertEqual(runs.overnight, ["熊本": 8], "every set spends the night at the depot's end")

        XCTAssertEqual(TrackGauge.ofRealLine(Self.id), .shinkansen)
        XCTAssertEqual(RealLineDepotSite.sites(of: Self.id).map(\.chinese), ["熊本車輛基地"])
    }

    /// A high-speed set's platform is as long as the train with real car
    /// lengths; every other line's as it was, a car more than its trains
    /// at the standard car's length.
    func testAHighSpeedPlatformIsAsLongAsItsTrain() {
        let car = Train.carLength
        for type in [TrainType?.none, .a, .b, .c] {
            for real in [false, true] {
                XCTAssertEqual(RealBranchLine.platformLength(cars: 6, of: type, real: real), 7 * car, "\(String(describing: type)) \(real)")
            }
        }
        XCTAssertEqual(RealBranchLine.platformLength(cars: 8, of: .highSpeed, real: false), 9 * car)
        XCTAssertEqual(RealBranchLine.platformLength(cars: 8, of: .highSpeed, real: true), 200 * WorldCoordinate.unitsPerMetre, "eight 25 m cars")
    }

    /// Bought alone from a new game's four tiles in the north-west: the
    /// row in the list, the seven tiles along it bought with it, its
    /// seven stations up on the viaduct, 200 m platforms, the depot past
    /// Kumamoto, eight sets of eight high-speed cars on Shinkansen track,
    /// and a whole day with every train sent and none in a deadlock.
    /// Decision 995: each station's platforms drawn on the 3D map as the
    /// real one's stand (``Self/real``).
    func testTheLineIsBoughtAloneAndRunsItsDay() throws {
        let session = try FukuokaRailwaysTests.fukuoka()
        let listing = try XCTUnwrap(session.realLineListings.first { $0.bundle.lines.map(\.id) == [Self.id] }, "sold by itself")
        XCTAssertTrue(listing.isBuyable)
        XCTAssertEqual(Double(listing.metres), 4_609, accuracy: 50, "Hakata, from the middle of the first land")
        XCTAssertEqual(session.world.mapExpansion?.owned.count, 4)

        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id })
        XCTAssertEqual(real.cars, 8, "the N700's eight")
        XCTAssertEqual(real.trainType, .highSpeed)
        let offer = session.realLineOffer(for: real)
        XCTAssertNil(offer.problem)
        let acquisition = try XCTUnwrap(offer.acquisition)
        XCTAssertEqual(acquisition.trains.count, 8)
        XCTAssertEqual(acquisition.cars, 8)
        XCTAssertEqual(acquisition.trainType, .highSpeed)
        XCTAssertEqual(acquisition.tiles?.count, 7, "the tiles under the line the company does not own yet")
        XCTAssertEqual(acquisition.depot?.name, "熊本車輛基地")
        XCTAssertEqual(acquisition.depot?.platforms.count, 8)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        XCTAssertEqual(world.mapExpansion?.owned.count, 11)
        let bought = try XCTUnwrap(world.acquisition(of: Self.id))
        let line = try XCTUnwrap(world.line(id: try XCTUnwrap(bought.line)))
        XCTAssertTrue(line.isHighSpeed, "high-speed fares and long trips (decision 168)")
        XCTAssertEqual(line.stops.compactMap { world.station(id: $0)?.name }.sorted(), Self.stops.sorted())
        XCTAssertEqual(line.trains.count, 8)
        XCTAssertEqual(line.runs.count, 86)
        XCTAssertEqual(line.depots.compactMap { world.station(id: $0)?.name }, ["熊本車輛基地"])
        for id in line.trains {
            let train = try XCTUnwrap(world.train(id: id))
            XCTAssertEqual(train.type, .highSpeed, train.name)
            XCTAssertEqual(train.cars, 8, train.name)
        }
        let track = Set(try XCTUnwrap(bought.track))
        XCTAssertEqual(Set(world.network.edges.filter { track.contains($0.id) }.map(\.gauge)), [.shinkansen])

        // Every station on the real viaduct, its platforms 200 m long.
        var tracks: [String: Int] = [:]
        for stop in line.stops {
            let name = try XCTUnwrap(world.station(id: stop)?.name)
            let platforms = world.network.platforms(of: stop)
            tracks[name] = platforms.count
            for platform in platforms {
                XCTAssertEqual(Double(platform.end - platform.start) / Self.metre, 200, accuracy: 0.5, name)
            }
            let over = SharedStationLayoutTests.overGround(stop, in: world)
            XCTAssertTrue(over.allSatisfy { $0 > 8 && $0 < 30 }, "\(name): on the viaduct, \(over) m over the ground")
        }
        XCTAssertEqual(tracks, Self.real.mapValues(\.tracks))
        // Decision 995: the islands and side platforms the 3D map draws.
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
        let depot = try XCTUnwrap(line.depots.first)
        XCTAssertEqual(world.network.platforms(of: depot).count, 8)

        // Its day: every run sent, no minute with a train in a deadlock.
        var played = world
        var stuck = 0
        for _ in 0..<(24 * 60) {
            try played.advance(ticks: 1)
            if !played.deadlockedTrains().isEmpty { stuck += 1 }
        }
        XCTAssertEqual(stuck, 0, "minutes of the day with a deadlock")
        let after = try XCTUnwrap(played.line(id: line.id))
        XCTAssertEqual(zip(after.runs, after.runDays).filter { $0.1 != nil }.count, 86, "every run of the day sent")
    }
}
