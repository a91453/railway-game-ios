import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 586: the Maokong Gondola (``RealCableway/maokong``) on a map
/// with the Wenhu Line bought (`trtc:BR`, as the real-line tests buy it),
/// laid as it is, so it meets MRT Taipei Zoo; run only when asked
/// (`CABLE_TOURISM_REPORT=<days>`, seconds in a debug build; the real
/// people read in round the stations, as decision 552's report). It prints the
/// station it meets, the trips it brings to that station and carries
/// between its stops (decision 574's derived figures), and for each day
/// from day 0 whether it runs, whether the Maokong sight
/// (`AttractionCatalog`'s `t009`) is reached by it, the sight's tourists
/// (``GameWorld/touristsExpected(for:onDay:)``, the rail stations' own
/// rule), their rides up and down and those rides' fares, worked out
/// without playing; `CABLE_TOURISM_PLAY=<days>` then plays those days and
/// prints the riders the gondola booked. It asserts nothing: the numbers
/// are in the decision.
@MainActor
final class CablewayTourismReportTests: XCTestCase {
    func testTheMaokongSightsTourists() throws {
        guard let wanted = ProcessInfo.processInfo.environment["CABLE_TOURISM_REPORT"], let days = Int64(wanted), days > 0 else {
            throw XCTSkip("Set CABLE_TOURISM_REPORT=<days> to measure the Maokong Gondola's tourists (decision 586).")
        }
        // As the line-buying report (decision 552) opens a map round the
        // Wenhu Line: the real people, read in round the stations.
        let railways = try BundledRealData.railways()
        let runs = try XCTUnwrap(railways.metroRuns["trtc:BR"])
        let stations = try runs.stops.map { try BundledRealData.station($0, in: "mrt") }
        let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
        let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        var opened = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 21, height: 1 << 21), balance: Money(200_000_000_000), land: [])
        opened.setLandOnDemand()
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let session = GameSession(world: opened, language: .traditionalChinese)
        session.railways = railways
        session.population = data.population
        session.places = data.places
        session.water = data.water
        let wenhu = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:BR" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: wenhu)), session.message?.text ?? "")
        session.selectTool(.network)
        session.setNetworkMode(.cableway)
        session.traceRealCableway(try XCTUnwrap(session.realCablewayOffer))
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        var world = session.world
        let cableway = try XCTUnwrap(world.cableways.last)
        let built = try XCTUnwrap(world.cableway(id: cableway.id))
        let meets = built.transfer.flatMap { world.station(id: $0.station)?.name } ?? "-"
        let stationTrips = built.transfer.flatMap { world.stationDemand(of: $0.station)?.dailyTrips } ?? 0
        let sight = try XCTUnwrap(world.tourism?.attractions.first { $0.englishName == "Maokong" })
        print("""

        ### Maokong Gondola meeting the Wenhu Line (decision 586), days 0 to \(days - 1)
        meets: \(meets) (\(stationTrips) trips a day); feeder trips \(built.feederTrips), local trips \(built.localTrips); running NT$\(built.dailyCost.amount / 100) a day
        sight: \(sight.stars) hundredths of a star, \(sight.kind); its station \(world.attractionStation(of: sight.id).flatMap { world.station(id: $0)?.name } ?? "-")

        | day | weekday | holiday | runs | reached | tourists | rides | fares |
        | --: | --: | --- | --- | --- | --: | --: | --: |
        """)
        var rides: Int64 = 0, open: Int64 = 0
        for day in 0..<days {
            let runs = world.cablewayIsOpen(cableway.id, onDay: day)
            let reached = world.feederAccess(to: sight.point, onDay: day) != nil
            let tourists = reached ? world.touristsExpected(for: sight, onDay: day) : 0
            rides += 2 * tourists
            if runs { open += 1 }
            print("| \(day) | \(StationDemand.weekday(ofDay: day)) | \(world.holiday(onDay: day) != nil ? "yes" : "") | \(runs ? "yes" : "no") "
                + "| \(reached ? "yes" : "no") | \(tourists) | \(2 * tourists) | \(2 * tourists * Cableway.fare.amount / 100) |")
        }
        print("| all | | | \(open) days | | | \(rides) | \(rides * Cableway.fare.amount / 100) |\n")
        // `CABLE_TOURISM_PLAY=<days>`: those days played at the top speed
        // (ten minutes a tick, as HEALTH-110's fast runs), and each day's
        // riders as the gondola books them, tourists and all.
        guard let play = ProcessInfo.processInfo.environment["CABLE_TOURISM_PLAY"].flatMap({ Int64($0) }), play > 0 else { return }
        world.setSpeed(.fast)
        let started = Date()
        while world.clock.now.seconds < play * GameTime.secondsPerDay + 60 {
            try world.advance(ticks: 1)
        }
        let played = try XCTUnwrap(world.cableway(id: cableway.id))
        print("| day | riders | closed |\n| --: | --: | --- |")
        for day in played.days {
            print("| \(day.day) | \(day.riders) | \(day.closed ? "yes" : "") |")
        }
        print("played \(play) days in \(Int(Date().timeIntervalSince(started))) s\n")
    }
}
