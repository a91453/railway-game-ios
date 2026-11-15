import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 753's three lines on one track bought in every order, on
/// Hong Kong's map (`HongKongMapTests`); a class of its own so the CI
/// shards can deal it apart from the other Hong Kong tests.
@MainActor
final class HongKongSharedTrackBuyOrderTests: XCTestCase {
    private func hongKong(demo: Bool = false) throws -> GameSession {
        try HongKongMapTests.hongKong(demo: demo)
    }

    /// Decision 753 (2026-11-14: 「新版不能同時蓋迪士尼線跟機場快線」「記得
    /// 東涌也是他們重複線路」): the Airport Express, the Tung Chung Line and
    /// the Disneyland Resort Line, drawn along one track round Sunny Bay
    /// and from Hong Kong to the airport island, are each bought after the
    /// other two, in every order, and every one of them has its trains.
    /// The Tung Chung Line was refused after the Airport Express and the
    /// other way round (decision 712), and both after the Disneyland
    /// Resort Line, laid on their track at Sunny Bay.
    func testTheThreeLinesOnOneTrackAreBoughtInEveryOrder() throws {
        let ids = ["hkmtr:AEL", "hkmtr:TCL", "hkmtr:DRL"]
        let orders = ids.flatMap { a in ids.filter { $0 != a }.flatMap { b in ids.filter { $0 != a && $0 != b }.map { [a, b, $0] } } }
        XCTAssertEqual(orders.count, 6)
        for order in orders {
            let session = try hongKong()
            for id in order {
                let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, "\(order) \(id)")
                let offer = session.realLineOffer(for: line)
                XCTAssertNil(offer.problem, "\(order) \(id): \(offer.problem ?? "")")
                guard session.acquireRealLine(offer), let bought = session.world.acquisition(of: id) else {
                    XCTFail("\(order) \(id): \(session.message?.text ?? "")")
                    break
                }
                let ran = try XCTUnwrap(session.world.line(id: try XCTUnwrap(bought.line)), "\(order) \(id)")
                XCTAssertFalse(ran.assignedTrains.isEmpty, "\(order) \(id)")
            }
        }
        XCTAssertNil(RealBranchLine.overseasLanes["hkmtr:TCL"])
        XCTAssertTrue(RealBranchLine.overseasLanes.keys.allSatisfy { $0.hasPrefix("hkmtr:") })
    }
}
