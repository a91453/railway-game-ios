import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 586: what the Maokong Gondola (``RealCableway/maokong``) carries
/// and earns, run only when asked (`CABLE_TOURISM_REPORT=<days>`, a few
/// minutes in a release build). The Wenhu Line is bought on a real-world
/// map twice the usual a side, so the gondola meets Taipei Zoo station; the
/// gondola is built as the cable car mode lays it and the game is played
/// at the top speed (ten minutes a tick) for the days asked. Each day's
/// riders, fares, running and balance are printed, with the Maokong sight's
/// tourists, as a Markdown table. It asserts nothing: the numbers are in
/// the decision.
@MainActor
final class CablewayTourismReportTests: XCTestCase {
    func testTheMaokongGondolasDays() throws {
        guard let wanted = ProcessInfo.processInfo.environment["CABLE_TOURISM_REPORT"], let days = Int(wanted), days > 0 else {
            throw XCTSkip("Set CABLE_TOURISM_REPORT=<days> to measure the Maokong Gondola (decision 586).")
        }
        let session = try RealLineAcquisitionTests.game(round: "trtc:BR", side: 1 << 21)
        let wenhu = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:BR" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: wenhu)), session.message?.text ?? "")
        let stops = try XCTUnwrap(RealCableway.maokong.stops(in: session.world))
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.createCableway(stops: stops, legMetres: RealCableway.maokong.legMetres)
            world.setSpeed(.fast)
            return ""
        })
        let start = session.world.dayIndex(of: session.world.clock.now)
        var world = session.world
        let ticks = days * 144 + 1
        try world.advance(ticks: ticks)
        let cableway = try XCTUnwrap(world.cableways.first)
        let met = cableway.transfer.flatMap { world.station(id: $0.station)?.name } ?? "-"
        let sight = world.tourism?.attractions.first { $0.englishName == "Maokong" }
        print("""

        ### Maokong Gondola (decision 586), from day \(start), \(days) days
        meets: \(met); feeder trips \(cableway.feederTrips), local trips \(cableway.localTrips); \
        Maokong sight: \(sight.map { "\($0.stars) stars, this year \($0.thisYear)" } ?? "none")

        | day | weekday | open | riders | fares | running | balance |
        | --: | --: | --- | --: | --: | --: | --: |
        """)
        var riders: Int64 = 0, fares = Money.zero, cost = Money.zero
        for day in cableway.days {
            riders += day.riders
            fares = fares + day.fares
            cost = cost + day.cost
            print("| \(day.day) | \(StationDemand.weekday(ofDay: day.day)) | \(day.closed ? "no" : "yes") | \(day.riders) "
                + "| \(day.fares.amount / 100) | \(day.cost.amount / 100) | \((day.fares - day.cost).amount / 100) |")
        }
        print("| all | | | \(riders) | \(fares.amount / 100) | \(cost.amount / 100) | \((fares - cost).amount / 100) |\n")
    }
}
