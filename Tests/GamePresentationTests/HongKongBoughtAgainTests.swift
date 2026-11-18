import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 528 on Hong Kong's map (`HongKongMapTests`): a line of the
/// three sold together (decision 862) removed and bought again. A class
/// of its own so the CI shards can deal it apart from the other Hong
/// Kong tests.
@MainActor
final class HongKongBoughtAgainTests: XCTestCase {
    /// The Airport Express, the Tung Chung Line and the Disneyland Resort
    /// Line bought together, the Airport Express is removed in its panel:
    /// it is on sale again alone and is bought again, taking up the lane
    /// it left, which no train of the other two can get onto. Then the
    /// Tung Chung Line, the same. Each was refused (「這裡不能建軌道…」): at
    /// Hong Kong, Kowloon and Tsing Yi, which the other lines still call
    /// at, the platforms on the lane left counted as theirs, were kept,
    /// and the line laid again came onto them.
    func testALineOfTheAirportThreeRemovedIsBoughtAgain() throws {
        let ids = ["hkmtr:AEL", "hkmtr:TCL", "hkmtr:DRL"]
        let session = try HongKongMapTests.hongKong()
        let three = try XCTUnwrap(session.realLineBundles.first { $0.lines.contains { $0.id == "hkmtr:AEL" } })
        XCTAssertEqual(Set(three.lines.map(\.id)), Set(ids))
        let first = session.realLineBundleOffer(for: three)
        XCTAssertTrue(session.acquireRealLines(first), first.problemText(in: .traditionalChinese) ?? session.message?.text ?? "")

        for id in ["hkmtr:AEL", "hkmtr:TCL"] {
            let others = ids.filter { $0 != id }
            let theirs = Set(others.flatMap { session.world.acquisition(of: $0)?.track ?? [] })
            XCTAssertFalse(theirs.isEmpty, id)
            func theirPlatforms() -> [String] {
                session.world.network.platforms.filter { theirs.contains($0.edge) }.map { "\($0.station) \($0.edge) \($0.start)" }
            }
            let platforms = theirPlatforms()
            let stations = session.world.stations.count
            let trains = session.world.trains.count

            let removed = try XCTUnwrap(session.world.acquisition(of: id)?.line, id)
            session.selectLine(removed)
            session.removeSelectedLine()
            XCTAssertNil(session.world.line(id: removed), "\(id): \(session.message?.text ?? "")")
            let left = Set(session.world.trackLeft(by: id))
            XCTAssertFalse(left.isEmpty, "\(id): its track stays")
            XCTAssertTrue(left.isDisjoint(with: theirs), "\(id): a lane of its own")
            // The stations it shared are still called at, but by trains
            // that cannot get onto the lane it left.
            let used = RealLineClearing.edgesInUse(in: session.world)
            XCTAssertTrue(left.isDisjoint(with: used), "\(id): \(left.intersection(used).count) of the \(left.count) pieces it left count as in use")
            XCTAssertTrue(theirs.isSubset(of: used.union(theirs.filter { session.world.network.platforms(on: $0).isEmpty })), "\(id): the others' platforms are in use")

            let listed = try XCTUnwrap(session.realLineBundles.first { $0.lines.contains { $0.id == id } }, "\(id) on sale again")
            XCTAssertEqual(listed.lines.map(\.id), [id], "alone: the other two are the company's")
            let offer = session.realLineBundleOffer(for: listed)
            XCTAssertNil(offer.problemText(in: .traditionalChinese), "\(id): \(offer.problemText(in: .traditionalChinese) ?? "")")
            let clearing = try XCTUnwrap(offer.acquisitions?.first?.clearing, "\(id): the lane it left taken up")
            XCTAssertEqual(Set(clearing.edges.map(TrackEdgeID.edge)), left, "\(id): all it left, and only that")
            XCTAssertNil(clearing.shared, id)
            XCTAssertTrue(session.acquireRealLines(offer), "\(id): \(session.message?.text ?? "")")

            XCTAssertEqual(session.world.trackLeft(by: id), [], "\(id): bought again, nothing is left")
            XCTAssertEqual(session.world.stations.count, stations, "\(id): its stations are the ones it left")
            XCTAssertEqual(session.world.trains.count, trains, "\(id): with its trains")
            XCTAssertTrue(theirs.allSatisfy { session.world.network.edge($0) != nil }, "\(id): the other lines' track stays")
            XCTAssertEqual(theirPlatforms(), platforms, "\(id): and their platforms")
            for line in ids {
                let bought = try XCTUnwrap(session.world.acquisition(of: line)?.line, "\(id) \(line)")
                XCTAssertFalse(try XCTUnwrap(session.world.line(id: bought)).assignedTrains.isEmpty, "\(id) \(line)")
            }
        }
    }
}
