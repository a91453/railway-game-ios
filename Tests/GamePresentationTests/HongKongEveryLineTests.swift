import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Every line of Hong Kong's MTR bought, or laid by the demo, on its map
/// (`HongKongMapTests`); a class of its own so the CI shards can deal it
/// apart from the other Hong Kong tests.
@MainActor
final class HongKongEveryLineTests: XCTestCase {
    private func hongKong(demo: Bool = false) throws -> GameSession {
        try HongKongMapTests.hongKong(demo: demo)
    }

    /// Each line on sale is bought, one after another on the same map:
    /// each has its trains, and the land round its stations is read in
    /// with Hong Kong's people. None is refused (decision 753: the Tung
    /// Chung Line, drawn along the Airport Express's track, was).
    func testEveryLineOnSaleIsBought() throws {
        let session = try hongKong()
        for id in session.buyableRealLines.map(\.id).sorted() {
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, id)
            let offer = session.realLineOffer(for: line)
            XCTAssertNil(offer.problem, "\(id): \(offer.problem ?? "")")
            XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(session.message?.text ?? "")")
            let bought = try XCTUnwrap(session.world.acquisition(of: id), id)
            let ran = try XCTUnwrap(session.world.line(id: try XCTUnwrap(bought.line)), id)
            XCTAssertFalse(ran.assignedTrains.isEmpty, id)
        }
        XCTAssertGreaterThan(session.world.land.cells.reduce(0) { $0 + $1.residents }, 100_000)
        XCTAssertEqual(session.buyableRealLines.map(\.id), [])
    }

    /// The demo mode's real lines, laid over the whole map at once: all
    /// twelve of the MTR, every one with trains standing on its track
    /// (#2099's two faults: a station with a platform on one track only,
    /// and a terminus the returning train cannot call at).
    func testTheDemoLaysEveryLineWithTrains() async throws {
        let session = try hongKong(demo: true)
        let view = WorldRegion(bounds: session.world.bounds)
        let outcome = await session.layDemoRealLines(in: view, routes: .max, anyWidth: true) { $0.system.id == "hkmtr" }
        XCTAssertEqual(outcome?.lines, 12, session.message?.text ?? "")
        XCTAssertEqual(session.world.lines.count, 12)
        // Each line's drawing ends at its end stations and is run on
        // past them (``DemoRealLines/runningOn(_:by:)``): the end stations
        // have their platforms, and a line of two stations is laid.
        let laid = Dictionary(session.world.lines.map { line in (line.name, line.stops.compactMap { session.world.station(id: $0)?.name }) }) { first, _ in first }
        XCTAssertEqual(laid["迪士尼綫 迪士尼–欣澳"], ["迪士尼", "欣澳"])
        XCTAssertEqual(laid["將軍澳綫 將軍澳–康城"], ["將軍澳", "康城"])
        XCTAssertEqual(laid["東涌綫 香港–東涌"]?.count, 8)
        XCTAssertEqual(laid["東鐵綫 金鐘–羅湖"]?.count, 14)
        XCTAssertLessThanOrEqual(outcome?.missed ?? .max, 1, "the Tsuen Wan Line's start from Central")
        for line in session.world.lines {
            XCTAssertFalse(line.assignedTrains.isEmpty, "\(line.name) has no train")
            for id in line.assignedTrains {
                XCTAssertNotNil(try XCTUnwrap(session.world.train(id: id)).position, "\(line.name)")
            }
        }
    }
}
