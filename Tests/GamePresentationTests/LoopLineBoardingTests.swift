@testable import GameCore
@testable import GamePresentation
import XCTest

/// 82.1 #2 (decision 364): a ring made the way a player makes one, from a
/// line whose trains stand at its two ends, carries the passengers who
/// come for it every way round.
@MainActor
final class LoopLineBoardingTests: XCTestCase {
    private static let middle = Int64(524_288)
    private static let metre = WorldCoordinate.unitsPerMetre
    private static let spacing = 800 * metre

    /// A loop of single track on the simple rules' map: three straight
    /// edges 800 m long along the top going east, a curve down the east
    /// end, three along the bottom going west and a curve up the west end;
    /// a station beside the middle of each straight edge, clockwise A to F,
    /// and the edges at A and D made double with the select tool's "Make
    /// double track" (this piece only), so trains going each way can pass.
    private func loopSession() throws -> (GameSession, [StationID]) {
        var world = GameWorld.newGame(rules: .simple)
        world.setTourism(nil)
        world.economy = GameEconomy(balance: Money(10_000_000_000), costs: world.economy.costs)
        let u = Self.spacing
        let c = u * 1_338 / 1_024
        let x0 = Self.middle - u, y0 = Self.middle - u
        func plan(_ x: Int64, _ y: Int64) -> PlanPoint { PlanPoint(x: x0 + x, y: y0 + y) }
        let spots: [(Int64, Int64)] = [(0, 0), (u, 0), (2 * u, 0), (3 * u, 0), (4 * u, u), (3 * u, 2 * u), (2 * u, 2 * u), (u, 2 * u), (0, 2 * u), (-u, u)]
        var nodes: [TrackNodeID] = []
        for (x, y) in spots { nodes.append(try world.buildTrackNode(at: WorldCoordinate(x: x0 + x, y: y0 + y))) }
        let curves: [TrackCurve] = [
            .straight, .straight, .straight,
            .cubic(plan(3 * u + c, 0), plan(4 * u, u - c)),
            .cubic(plan(4 * u, u + c), plan(3 * u + c, 2 * u)),
            .straight, .straight, .straight,
            .cubic(plan(-c, 2 * u), plan(-u, u + c)),
            .cubic(plan(-u, u - c), plan(-c, 0)),
        ]
        var edges: [TrackEdgeID] = []
        for (index, curve) in curves.enumerated() {
            edges.append(try world.buildTrackEdge(from: nodes[index], to: nodes[(index + 1) % nodes.count], curve: curve))
        }
        let platform = 4 * world.platformCarLength
        let top = -64 * Self.metre, bottom = 2 * u + 64 * Self.metre
        let places: [(edge: Int, x: Int64, y: Int64)] = [(0, u / 2, top), (1, 3 * u / 2, top), (2, 5 * u / 2, top), (5, 5 * u / 2, bottom), (6, 3 * u / 2, bottom), (7, u / 2, bottom)]
        var stations: [StationID] = []
        for (index, place) in places.enumerated() {
            let id = try world.buildStation(named: ["A", "B", "C", "D", "E", "F"][index], at: plan(place.x, place.y)).id
            try world.addTrackPlatform(id, on: edges[place.edge], from: u / 2 - platform / 2, to: u / 2 + platform / 2)
            stations.append(id)
        }
        let session = GameSession(world: world, language: .english)
        for tap in [plan(u / 4, 0), plan(2 * u + 3 * u / 4, 2 * u)] {
            session.selectTool(.select)
            session.tapMap(at: tap, reach: 16)
            session.trackUpgradeWholeRun = false
            session.beginTrackUpgrade(.doubleTrack)
            session.buildTrackUpgrade()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        session.selectTool(.select)
        return (session, stations)
    }

    /// The player draws A to F, confirms the card with `trains` trains a
    /// time of day and makes the line a ring; a day later, the ledger of
    /// each station and the passengers at A still waiting the outer way
    /// for D or E.
    private func ringDay(trains: Int) throws -> (world: GameWorld, stations: [StationID], outerWayFromA: Int64) {
        let (session, stations) = try loopSession()
        session.startPickingLineStops(announces: false)
        for station in stations {
            session.selectStation(station)
            session.addSelectedStationToLineDraft()
        }
        session.confirmLineDraft()
        session.updateLineConfirmation { $0.setting(.peak, to: trains).setting(.offPeak, to: trains).setting(.low, to: trains) }
        session.confirmLine()
        let line = try XCTUnwrap(session.world.lines.last)
        XCTAssertEqual(line.trains.count, trains)
        session.selectLine(line.id)
        session.setSelectedLineRing(true)
        var world = session.world
        XCTAssertEqual(world.line(id: line.id)?.isRing, true)
        world.setSpeed(.normal)
        try world.advance(ticks: Int(GameTime.minutesPerDay))
        let outerWayFromA = world.waitingPassengers(at: stations[0])
            .filter { $0.direction == .inbound && ($0.destination == stations[3] || $0.destination == stations[4]) }
            .reduce(0) { $0 + $1.count }
        return (world, stations, outerWayFromA)
    }

    private func assertEveryoneRides(_ world: GameWorld, _ stations: [StationID], file: StaticString = #filePath, line: UInt = #line) {
        let a = world.passengerLedger(of: stations[0])
        XCTAssertGreaterThan(a.released, 3_000, file: file, line: line)
        XCTAssertGreaterThan(a.arrived, a.released * 99 / 100, "\(a)", file: file, line: line)
        for station in stations {
            let ledger = world.passengerLedger(of: station)
            XCTAssertEqual(ledger.overflowed + ledger.abandoned, 0, "\(world.station(id: station)?.name ?? "") \(ledger)", file: file, line: line)
        }
    }

    /// Two trains, one standing at each end: the inner one laps from A,
    /// the outer one stands at F. Over a day nearly everyone who came to A
    /// rides, the outer way past F too, and nobody is turned away or left
    /// behind. Before decision 364 the outer train lapped from F back to
    /// F, so at A it went only to F: those for E and D waited (about 1,900
    /// at the end of the first day, and A's queue full by the third).
    func testARingMadeFromALineCarriesItsPassengersBothWaysRound() throws {
        let (world, stations, outerWayFromA) = try ringDay(trains: 2)
        assertEveryoneRides(world, stations)
        XCTAssertLessThan(outerWayFromA, 100, "A to D and E the outer way")
    }

    /// The card's first offer, one train: it runs the inner way, so
    /// nobody is planned the outer way to wait for a train that never
    /// comes (decision 364). Before, about 1,000 at A were waiting for D
    /// and E the outer way at the end of the first day.
    func testARingWithOneTrainPlansNobodyTheOuterWay() throws {
        let (world, stations, outerWayFromA) = try ringDay(trains: 1)
        assertEveryoneRides(world, stations)
        XCTAssertEqual(outerWayFromA, 0)
    }
}
