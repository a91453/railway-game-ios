import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 351, its sequel: in the demo mode one tap lays the real lines
/// whose stations are in view, on a real-world map at Taipei Main Station
/// with the bundled lines.
@MainActor
final class DemoRealLinesTests: XCTestCase {
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A demo game at Taipei Main Station with unlimited funds, and the
    /// view `half` metres each way round it.
    private func taipei(demo: Bool = true, half: Double = 1_500) throws -> (session: GameSession, view: WorldRegion) {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor))
        world.setUnlimitedFunds(true)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        session.news.isDemo = demo
        let centre = try BundledRealData.point(tra.coordinate, in: world)
        let x = Double(centre.x), y = Double(centre.y), reach = half * metre
        return (session, WorldRegion(minX: x - reach, minY: y - reach, maxX: x + reach, maxY: y + reach))
    }

    /// The pieces of a line drawn in several are one line, its stations
    /// in order along it.
    func testALineInPiecesIsOneLineWithItsStationsInOrder() throws {
        let railways = try BundledRealData.railways()
        let (session, _) = try taipei()
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let bounds = session.world.bounds
        let everywhere = WorldRegion(bounds: bounds)
        let planned = DemoRealLines.plan(
            railways: railways, frame: frame, bounds: bounds, view: everywhere, carLength: session.world.platformCarLength
        )
        let bannan = planned.routes.filter { $0.lineKey == "mrt|BL" }
        XCTAssertEqual(bannan.count, 1, "11 pieces, one line")
        let names = try XCTUnwrap(bannan.first).stops.map(\.chinese)
        XCTAssertTrue(names.contains("台北車站"), "\(names)")
        let order = ["西門", "台北車站", "善導寺", "忠孝新生"].compactMap { names.firstIndex(of: $0) }
        XCTAssertEqual(order.count, 4, "\(names)")
        XCTAssertTrue(order == order.sorted() || order == order.sorted().reversed(), "\(names)")
        for route in planned.routes {
            for (a, b) in zip(route.stops, route.stops.dropFirst()) {
                XCTAssertLessThan(a.platform.upperBound + DemoRealLines.platformGap, b.platform.lowerBound + 1, "\(route.lineKey) \(a.chinese) \(b.chinese)")
            }
        }
    }

    /// One tap: real lines with their stations in view, a line calling at
    /// them in the real line's colour, trains running it; one Undo takes
    /// it all back.
    func testOneTapLaysTheRealLinesInViewWithTrainsRunning() async throws {
        let (session, view) = try taipei()
        session.setSpeed(.normal)
        let before = session.world
        let laid = await session.layDemoRealLines(in: view)
        XCTAssertEqual(session.world.clock.speed, .normal, "running again as before")
        let outcome = try XCTUnwrap(laid)
        XCTAssertNil(session.demoRealLinesProgress, "done")
        XCTAssertGreaterThanOrEqual(outcome.lines, 3, session.message?.text ?? "")
        XCTAssertEqual(session.world.lines.count, outcome.lines)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.world.lines.allSatisfy { $0.stops.count >= 2 && $0.color != nil })
        XCTAssertTrue(session.world.lines.contains { $0.name.hasPrefix("板南線") }, "\(session.world.lines.map(\.name))")
        // Trains on every line, on the track.
        for line in session.world.lines {
            XCTAssertFalse(line.assignedTrains.isEmpty, line.name)
        }
        // Every station is in view.
        for station in session.world.stations {
            let point = station.location
            XCTAssertTrue(Double(point.x) >= view.minX - 200 * metre && Double(point.x) <= view.maxX + 200 * metre, station.name)
            XCTAssertTrue(Double(point.y) >= view.minY - 200 * metre && Double(point.y) <= view.maxY + 200 * metre, station.name)
        }
        XCTAssertTrue(session.news.isDemo, "it counts nothing")
        // The trains run: by 08:00 they have left where they stood.
        var running = session.world
        let standing = running.trains.map(\.position)
        running.setSpeed(.normal)
        try running.advance(ticks: 8 * 60)
        XCTAssertNotEqual(running.trains.map(\.position), standing)
        XCTAssertGreaterThan(session.world.trains.count, session.world.lines.count, "more than one train a line")

        session.undo()
        XCTAssertEqual(session.world.network, before.network, "one Undo")
        XCTAssertEqual(session.world.lines, before.lines)
        XCTAssertEqual(session.world.trains, before.trains)
    }

    /// Outside a demo game, too wide a view or nothing in view: nothing is
    /// laid.
    func testNothingIsLaidOutsideADemoOrInTooWideAView() async throws {
        let (normal, view) = try taipei(demo: false)
        XCTAssertFalse(normal.canLayDemoRealLines)
        let laid = await normal.layDemoRealLines(in: view)
        XCTAssertNil(laid)
        XCTAssertTrue(normal.world.network.edges.isEmpty)

        let (wide, wideView) = try taipei(half: 25_000)
        let before = wide.world
        let widely = await wide.layDemoRealLines(in: wideView)
        XCTAssertNil(widely)
        XCTAssertEqual(wide.message?.kind, .failure)
        XCTAssertEqual(wide.world, before)

        let (empty, _) = try taipei()
        let nowhere = WorldRegion(minX: 0, minY: 0, maxX: 100, maxY: 100)
        let none = await empty.layDemoRealLines(in: nowhere)
        XCTAssertNil(none)
        XCTAssertTrue(empty.world.network.edges.isEmpty)
    }
}
