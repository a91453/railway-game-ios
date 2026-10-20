import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 298: on a real-world map with real transfers on, a
/// station within 450 m of a real one brings the people changing there,
/// its transfer points worked out from the real place's systems and TRA
/// grade after every edit.
@MainActor
final class RealTransfersTests: XCTestCase {
    /// A real-world game round the real station `name` of `system`, with
    /// real transfers on and the railways, and that station's point.
    private func makeSession(at name: String, in system: String = "tra_sched", transfers: Bool = true) throws -> (GameSession, PlanPoint) {
        let real = try BundledRealData.station(name, in: system)
        var world = GameWorld.newGame(anchor: try XCTUnwrap(real.anchor))
        world.setRealTransfers(transfers)
        let at = try BundledRealData.point(real.coordinate, in: world)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        return (session, at)
    }

    func testAPlacesPointsFollowItsRealRiders() throws {
        let (session, taipei) = try makeSession(at: "臺北")
        let railways = try XCTUnwrap(session.railways)
        let ridership = try XCTUnwrap(railways.ridership)
        let place = try XCTUnwrap(session.nearestRealStation(to: taipei))
        let tra = try XCTUnwrap(place.stations.first { $0.system.id == "tra_sched" })
        let hsr = try XCTUnwrap(place.stations.first { $0.system.id == "thsr_sched" })
        // 2025's averages (tools/real-ridership/): 63,307 and 47,192 a day.
        XCTAssertEqual(ridership.riders(of: tra, data: railways.stationData), 63_307)
        XCTAssertEqual(ridership.riders(of: hsr, data: railways.stationData), 47_192)
        XCTAssertEqual(GameSession.transferPoints(of: tra, data: railways.stationData, ridership: ridership), 63)
        XCTAssertEqual(GameSession.transferPoints(of: hsr, data: railways.stationData, ridership: ridership), 47)
        // The place's systems add up, at most the most a station takes.
        let total = place.stations.reduce(into: [String: Int64]()) { bySystem, station in
            let points = GameSession.transferPoints(of: station, data: railways.stationData, ridership: ridership)
            bySystem[station.system.id] = max(bySystem[station.system.id] ?? 0, points)
        }.values.reduce(0, +)
        XCTAssertEqual(GameSession.transferPoints(of: place, data: railways.stationData, ridership: ridership), min(total, TransferDemand.maximumPoints))
        XCTAssertEqual(GameSession.transferPoints(of: place, data: railways.stationData, ridership: ridership), TransferDemand.maximumPoints)

        // A quiet TRA station alone is at least 1.
        let (other, houtong) = try makeSession(at: "猴硐")
        let small = try XCTUnwrap(other.nearestRealStation(to: houtong))
        XCTAssertEqual(small.systems.map(\.id), ["tra_sched"])
        let riders = try XCTUnwrap(ridership.riders(of: small.stations[0], data: railways.stationData))
        XCTAssertEqual(GameSession.transferPoints(of: small, data: railways.stationData, ridership: ridership), max(1, Int64((Double(riders) / 1_000).rounded())))

        // Without a file, a station's system or grade decides.
        XCTAssertEqual(GameSession.transferPoints(of: hsr, data: railways.stationData), 20)
        XCTAssertEqual(GameSession.transferPoints(of: tra, data: railways.stationData), 14, "a special-class TRA station")
    }

    func testTheOtherMetrosPointsFollowTheirRiders() throws {
        let railways = try BundledRealData.railways()
        let ridership = try XCTUnwrap(railways.ridership)
        func points(_ name: String, _ system: String) throws -> Int64 {
            GameSession.transferPoints(of: try BundledRealData.station(name, in: system), data: railways.stationData, ridership: ridership)
        }
        // Taichung Metro, 2025's seven months of exits (tools/real-ridership/):
        // 8,436 and 5,791 a day, where a metro with no file has 3.
        XCTAssertEqual(ridership.riders(of: try BundledRealData.station("高鐵臺中站", in: "tmrt"), data: railways.stationData), 8_436)
        XCTAssertEqual(try points("高鐵臺中站", "tmrt"), 8)
        XCTAssertEqual(try points("市政府", "tmrt"), 6)
        XCTAssertEqual(try points("九張犁", "tmrt"), 1)
        // New Taipei Metro's light rails, where one with no file has 1.
        XCTAssertEqual(try points("紅樹林", "ntdlrt"), 8)
        XCTAssertEqual(try points("十四張", "ntalrt"), 3)
        // The Circular Line by New Taipei Metro's own count (2,831 a day at
        // Zhongyuan; Taipei Metro's file has 701); a station of both
        // companies keeps the larger count.
        XCTAssertEqual(try points("中原", "mrt"), 3)
        XCTAssertEqual(try points("板橋", "mrt"), 42)
        // The Taoyuan Airport MRT, 2025 (28,773 a day at Taipei Main Station).
        XCTAssertEqual(ridership.riders(of: try BundledRealData.station("台北車站", in: "tymc"), data: railways.stationData), 28_773)
        XCTAssertEqual(try points("長庚醫院站", "tymc"), 10)
        XCTAssertEqual(try points("機場第一航廈站", "tymc"), 12)
        XCTAssertEqual(try points("機場第二航廈站", "tymc"), 11)
        // The Sanying Line has no year of riders yet.
        XCTAssertEqual(try points("三峽", "sanying"), 1)
    }

    func testAStationBuiltByARealOneBringsItsTransfers() throws {
        let (session, taipei) = try makeSession(at: "臺北")
        let metre = WorldCoordinate.unitsPerMetre
        let site = PlanPoint(x: taipei.x + 100 * metre, y: taipei.y)
        let near = try session.performEdit { try $0.buildStation(named: "Near", at: site).id }
        let place = try XCTUnwrap(session.nearestRealStation(to: site))
        let points = GameSession.transferPoints(of: place, data: session.railways?.stationData, ridership: session.railways?.ridership)
        XCTAssertEqual(points, TransferDemand.maximumPoints, "TRA 63 and the high-speed rail 47 pass the most a station takes")
        XCTAssertEqual(session.world.station(id: near)?.transferPoints, points)
        XCTAssertEqual(session.world.transferTrips(of: near), points * TransferDemand.tripsPerPoint)
        XCTAssertTrue(session.commandLog.entries.contains { $0.action == .transfers([near: points]) })

        // The card says who changes there and how many a day.
        let text = try XCTUnwrap(session.transferText(of: near))
        XCTAssertTrue(text.contains("台鐵") && text.contains("高鐵"), text)
        XCTAssertTrue(text.contains((points * TransferDemand.tripsPerPoint).formatted()), text)
        XCTAssertEqual(session.realStationDetails(of: near).first, text)

        // A second station by no real one brings none.
        let (hills, houtong) = try makeSession(at: "猴硐")
        let far = try hills.performEdit { try $0.buildStation(named: "Far", at: PlanPoint(x: houtong.x + 3_000 * metre, y: houtong.y)).id }
        XCTAssertNil(hills.nearestRealStation(to: PlanPoint(x: houtong.x + 3_000 * metre, y: houtong.y)))
        XCTAssertEqual(hills.world.station(id: far)?.transferPoints, 0)
        XCTAssertNil(hills.transferText(of: far))

        // Undo takes the station and its points back together.
        session.undo()
        XCTAssertNil(session.world.station(id: near))
        XCTAssertFalse(session.world.stations.contains { $0.transferPoints > 0 })
    }

    func testNoTransfersWhenTheGameHasThemOffOrOnABlankMap() throws {
        let (off, taipei) = try makeSession(at: "臺北", transfers: false)
        let station = try off.performEdit { try $0.buildStation(named: "Near", at: taipei).id }
        XCTAssertEqual(off.world.station(id: station)?.transferPoints, 0)
        XCTAssertNil(off.transferText(of: station))
        XCTAssertFalse(off.commandLog.entries.contains { $0.action.name == "transfers" })

        var options = NewGameOptions()
        var blank = GameWorld.newGame()
        options.apply(to: &blank)
        XCTAssertFalse(blank.realTransfers, "a blank map has no real railways")
        var real = GameWorld.newGame(anchor: try XCTUnwrap(try BundledRealData.station("臺北", in: "tra_sched").anchor))
        options.apply(to: &real)
        XCTAssertTrue(real.realTransfers)
        options.realTransfers = false
        options.apply(to: &real)
        XCTAssertFalse(real.realTransfers)
        XCTAssertTrue(options.summary(in: .traditionalChinese).contains("沒有從真實鐵路轉乘的旅客"))
    }

    func testTheLogKeepsThePointsSoAReplayNeedsNoRailways() throws {
        let (session, taipei) = try makeSession(at: "臺北")
        let start = session.world
        let station = try session.performEdit { try $0.buildStation(named: "Near", at: taipei).id }
        let entry = try XCTUnwrap(session.commandLog.entries.last)
        guard case .transfers(let points) = entry.action else { return XCTFail("\(entry.action)") }
        XCTAssertEqual(points.keys.sorted(), [station])

        let data = try JSONEncoder().encode(entry)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""points":[[\#(station.rawValue),\#(points[station] ?? 0)]]"#))
        XCTAssertEqual(try JSONDecoder().decode(CommandLog.Entry.self, from: data), entry)

        // A session without the railways sets what the log says.
        var built = start
        try built.buildStation(named: "Near", at: taipei)
        let replay = GameSession(world: built, language: .traditionalChinese)
        replay.applyTransfers(points)
        XCTAssertEqual(replay.world.stations, session.world.stations)
    }
}
