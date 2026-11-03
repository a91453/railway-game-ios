import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 556: the Taoyuan Airport MRT on sale, bought with its two real
/// depots beside the line, Luzhu between Shanbi and Kengkou and Qingpu
/// between Hengshan and Linghang, the trains its timetable leaves overnight
/// at stations between its ends standing in them, and a crossover either
/// side of each station between its ends that a run starts or ends at
/// (its expresses turn at Airport Terminal 2, its shuttles at Terminal 1
/// and Huanbei).
@MainActor
final class TaoyuanAirportLineTests: XCTestCase {
    static let id = "tymc:A"

    func testTheLineIsBoughtWithItsTwoRealDepots() throws {
        let session = try RealLineAcquisitionTests.game(round: Self.id, side: 1 << 22, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id }, "on sale")
        XCTAssertEqual(line.cars, 4)
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        let depots = [acquisition.depot].compactMap(\.self) + (acquisition.moreDepots ?? [])
        XCTAssertEqual(depots.map(\.name), ["蘆竹機廠", "青埔機廠"])
        XCTAssertEqual(depots.map(\.platforms.count), [RealLineDepotSite.luzhu.sidings, RealLineDepotSite.qingpu.sidings])
        let runs = try XCTUnwrap(session.railways?.metroRuns[Self.id])
        XCTAssertEqual(acquisition.trains.count, runs.overnight.values.reduce(0, +))
        XCTAssertEqual(acquisition.trainType, .b)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let bought = try XCTUnwrap(world.lines.first)
        let stations = world.stations.filter(\.isDepot)
        XCTAssertEqual(Set(stations.map(\.name)), ["蘆竹機廠", "青埔機廠"])
        XCTAssertEqual(Set(bought.depots), Set(stations.map(\.id)))
        // Overnight: those the real timetable leaves between the ends
        // stand in the depots, those at the ends at their platforms.
        let between = runs.overnight.filter { $0.key != runs.stops.first && $0.key != runs.stops.last }.values.reduce(0, +)
        let inDepots = world.trains.count { train in stations.contains { world.stationsStoppedAt(by: train.id).contains($0.id) } }
        XCTAssertEqual(inDepots, between)
    }
}
