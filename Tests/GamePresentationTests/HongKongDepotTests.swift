import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 829: Hong Kong's South Island Line and Tung Chung Line are
/// bought with their real depots, as Taiwan's lines are. Before, neither
/// had one: the trains the timetable leaves without service stood at
/// platforms, and each night some waited on one another until the rule
/// for a line without a depot (decision 816) moved them.
@MainActor
final class HongKongDepotTests: XCTestCase {
    private func offer(_ id: String, in session: GameSession) throws -> RealLineOffer {
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:\(id)" }, "\(id) is on sale")
        return session.realLineOffer(for: line)
    }

    private func bought(_ id: String, in world: GameWorld) throws -> ServiceLine {
        let line = try XCTUnwrap(world.acquisition(of: "hkmtr:\(id)")?.line, "\(id) is bought")
        return try XCTUnwrap(world.line(id: line))
    }

    /// How far, in metres, the bought depot's station stands from a real
    /// place.
    private func metres(from depot: Station, to place: (latitude: Double, longitude: Double), in world: GameWorld) throws -> Double {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let there = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
        let dx = Double(depot.point.x) - there.x, dy = Double(depot.point.y) - there.y
        return (dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre)
    }

    /// Wong Chuk Hang Depot, south-west of the viaduct east of Wong Chuk
    /// Hang station: a siding for each of the line's ten trains.
    func testTheSouthIslandLineIsBoughtWithWongChukHangDepot() throws {
        let session = try HongKongMapTests.hongKong()
        let offer = try offer("SIL", in: session)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        let depot = try XCTUnwrap(acquisition.depot, "bought with its depot")
        XCTAssertEqual(depot.name, "黃竹坑車廠")
        XCTAssertEqual(depot.platforms.count, RealLineDepotSite.wongChukHang.sidings)
        XCTAssertEqual(depot.platforms.count, acquisition.trains.count)
        XCTAssertNil(acquisition.moreDepots)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let line = try bought("SIL", in: world)
        XCTAssertEqual(line.depots.count, 1)
        let station = try XCTUnwrap(line.depots.first.flatMap { world.station(id: $0) })
        XCTAssertEqual(station.name, "黃竹坑車廠")
        // The real depot building's middle (OpenStreetMap way 454129803).
        XCTAssertLessThan(try metres(from: station, to: (22.246557, 114.168178), in: world), 500)
    }

    /// Siu Ho Wan Depot, between Sunny Bay and Tung Chung, north of the
    /// line: on the first track's side, where no depot was laid before.
    /// The trains the timetable leaves overnight between the ends start
    /// in it, and the line runs no positioning runs of the timetable's.
    func testTheTungChungLineIsBoughtWithSiuHoWanDepot() throws {
        let session = try HongKongMapTests.hongKong()
        let offer = try offer("TCL", in: session)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        let depot = try XCTUnwrap(acquisition.depot, "bought with its depot")
        XCTAssertEqual(depot.name, "小蠔灣車廠")
        XCTAssertEqual(depot.platforms.count, RealLineDepotSite.siuHoWan.sidings)
        XCTAssertEqual(depot.platforms.count, acquisition.trains.count)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let line = try bought("TCL", in: world)
        XCTAssertEqual(line.depots.count, 1)
        let station = try XCTUnwrap(line.depots.first.flatMap { world.station(id: $0) })
        XCTAssertEqual(station.name, "小蠔灣車廠")
        // The middle of the real covered stabling tracks (ways 453753728
        // to 453753731).
        XCTAssertLessThan(try metres(from: station, to: (22.307868, 113.982615), in: world), 500)

        let runs = try XCTUnwrap(session.railways?.metroRuns["hkmtr:TCL"])
        let between = runs.overnight.filter { $0.key != runs.stops.first && $0.key != runs.stops.last }.values.reduce(0, +)
        XCTAssertGreaterThan(between, 0)
        XCTAssertEqual(world.trains.count { world.stationsStoppedAt(by: $0.id).contains(station.id) }, between)
        let positioning = runs.runs.count { $0.positioning || $0.train == "回送" }
        XCTAssertGreaterThan(positioning, 0)
        XCTAssertEqual(line.runs.count, runs.runs.count - positioning)
    }

    /// The Tung Chung Line's depot is laid whichever of the three lines
    /// beside one another to the airport is bought first.
    func testTheDepotIsLaidBesideTheAirportExpress() throws {
        let session = try HongKongMapTests.hongKong()
        for id in ["AEL", "DRL", "TCL"] {
            let offer = try offer(id, in: session)
            XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(offer.problem ?? session.message?.text ?? "")")
        }
        let world = session.world
        let line = try bought("TCL", in: world)
        XCTAssertEqual(line.depots.compactMap { world.station(id: $0)?.name }, ["小蠔灣車廠"])
        // The other two have none of their own (decision 829).
        for id in ["AEL", "DRL"] {
            let other = try bought(id, in: world)
            XCTAssertEqual(other.depots, [])
        }
    }

    /// The South Island Line's first night under the realistic rules:
    /// by three in the morning every train stands in the depot or at an
    /// end of the line, none between, and the next morning's first runs
    /// leave. Half a minute.
    func testTheNightsTrainsStandInTheDepot() throws {
        var world = try DepotReturnReportTests.hongKongBought(["SIL"], rules: .realistic)
        let line = try XCTUnwrap(world.lines.first { $0.hasRuns })
        let depot = try XCTUnwrap(line.depots.first, "bought with its depot")
        world.setSpeed(.fast)
        while world.clock.now.seconds < GameTime.secondsPerDay + 3 * 3_600 {
            try world.advance(ticks: 1)
        }
        let ends: Set<StationID> = [line.stops[0], line.stops[line.stops.count - 1]]
        var inDepot = 0
        for train in world.trains {
            let at = world.stationsStoppedAt(by: train.id)
            XCTAssertTrue(at.contains(depot) || !ends.isDisjoint(with: at), "\(train.name) stands at \(at.compactMap { world.station(id: $0)?.name })")
            inDepot += at.contains(depot) ? 1 : 0
        }
        XCTAssertGreaterThan(inDepot, 0)
        // The second morning's first hour of runs all leave.
        while world.clock.now.seconds < GameTime.secondsPerDay + 7 * 3_600 {
            try world.advance(ticks: 1)
        }
        let now = world.clock.now
        let bought = try XCTUnwrap(world.line(id: line.id))
        let missed = RunsNotSent.on(1, of: bought, at: now).filter { bought.runs[$0].start(onDay: 1) % GameTime.secondsPerDay < 7 * 3_600 - 600 }
        XCTAssertEqual(missed, [])
    }
    /// Decision 836: the Tung Chung Line's first afternoon under a new
    /// game's rules (simple, traffic control on). At 14:25 an empty run to
    /// Siu Ho Wan, following a service waiting at Sunny Bay for the Tung
    /// Chung platform, claimed the crossover into the depot ten minutes
    /// ahead of itself; the train on that platform waited for it to leave,
    /// and six trains stood deadlocked, on and off, for 17 minutes. Until
    /// 15:00 none is deadlocked. About a minute.
    func testTheTungChungLineAfternoonHasNoDeadlock() throws {
        var world = try DepotReturnReportTests.hongKongBought(["TCL"], rules: .simple)
        XCTAssertTrue(world.isTrafficControlEnabled, "a new game's rules keep traffic control on")
        world.setSpeed(.normal)
        var worst: (count: Int, at: Int64) = (0, 0)
        while world.clock.now.seconds < 15 * 3_600 {
            try world.advance(ticks: 1)
            let stuck = world.deadlockedTrains().count
            if stuck > worst.count { worst = (stuck, world.clock.now.seconds) }
        }
        XCTAssertEqual(worst.count, 0, "\(worst.count) trains deadlocked at \(worst.at / 3_600):\(worst.at % 3_600 / 60)")
    }

    /// Decision 849: under a new game's rules (traffic control, no block
    /// sections) the South Island Line sends every run of the second
    /// day's morning peak out of Admiralty. A train leaving Ocean Park took
    /// Admiralty's crossovers for the whole four minutes to get there, and
    /// the trains due out waited behind it: 13 runs from 08:27 to 09:36
    /// were not sent before a train came in took its route only near the
    /// home signal.
    func testTheSouthIslandLineMorningPeakSendsEveryRun() throws {
        var world = try DepotReturnReportTests.hongKongBought(["SIL"], rules: .simple)
        XCTAssertTrue(world.isTrafficControlEnabled, "a new game's rules keep traffic control on")
        XCTAssertFalse(world.blockSections, "a new game's simple rules have no block sections")
        world.setSpeed(.normal)
        let end = GameTime.secondsPerDay + 10 * 3_600
        while world.clock.now.seconds < end {
            try world.advance(ticks: 1)
        }
        let line = try bought("SIL", in: world)
        let missed = RunsNotSent.on(1, of: line, at: world.clock.now).map { line.runs[$0].start(onDay: 1) % GameTime.secondsPerDay }
        XCTAssertEqual(missed.map { "\($0 / 3_600):\($0 % 3_600 / 60)" }, [], "runs of the second morning not sent")
        XCTAssertEqual(world.deadlockedTrains(), [])
    }
}
