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

    func testAPlacesPointsAddUpItsSystems() throws {
        let (session, taipei) = try makeSession(at: "臺北")
        let place = try XCTUnwrap(session.nearestRealStation(to: taipei))
        let data = session.railways?.stationData
        let systems = Set(place.systems.map(\.id))
        XCTAssertTrue(systems.isSuperset(of: ["tra_sched", "thsr_sched", "mrt"]), "\(systems)")
        // 臺北 is a special-class TRA station: 6, the high-speed rail 6, the
        // metro 2, and 2 for each other metro there.
        XCTAssertEqual(data?.stationClass(forStation: "臺北"), .special)
        let expected = min(6 + 6 + Int64(systems.subtracting(["tra_sched", "thsr_sched"]).count) * 2, TransferDemand.maximumPoints)
        XCTAssertEqual(GameSession.transferPoints(of: place, data: data), expected)

        // A TRA station alone gives its grade's points.
        let (other, houtong) = try makeSession(at: "猴硐")
        let small = try XCTUnwrap(other.nearestRealStation(to: houtong))
        XCTAssertEqual(small.systems.map(\.id), ["tra_sched"])
        let grade = other.railways?.stationData?.stationClass(forStation: "猴硐")
        let points: Int64 = switch grade {
        case .special: 6
        case .first: 4
        case .second: 2
        default: 1
        }
        XCTAssertEqual(GameSession.transferPoints(of: small, data: other.railways?.stationData), points)
    }

    func testAStationBuiltByARealOneBringsItsTransfers() throws {
        let (session, taipei) = try makeSession(at: "臺北")
        let metre = WorldCoordinate.unitsPerMetre
        let site = PlanPoint(x: taipei.x + 100 * metre, y: taipei.y)
        let near = try session.performEdit { try $0.buildStation(named: "Near", at: site).id }
        let place = try XCTUnwrap(session.nearestRealStation(to: site))
        let points = GameSession.transferPoints(of: place, data: session.railways?.stationData)
        XCTAssertGreaterThanOrEqual(points, 12, "TRA and the high-speed rail at least")
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
