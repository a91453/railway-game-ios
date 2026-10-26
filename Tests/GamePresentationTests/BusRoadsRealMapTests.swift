import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 424 on the app's own base map: a bus route drawn round Taipei
/// Station puts its stops on bus roads, follows them, and gives GameCore the
/// metres of the way drawn.
@MainActor
final class BusRoadsRealMapTests: XCTestCase {
    private static let taipei = (latitude: 25.0478, longitude: 121.5170)

    /// Taipei, the land round a station a cell north of Taipei Station read
    /// with its roads, and that station.
    private func game() throws -> (GameSession, StationID, PlanPoint) {
        var world = GameWorld.newWholeTaiwanGame()
        let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
        let position = frame.worldPosition(latitude: Self.taipei.latitude, longitude: Self.taipei.longitude)
        let taipei = PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()) - Land.cellLength)
        let station = try world.buildStation(named: "Taipei", at: taipei)
        let session = GameSession(world: world)
        try CommandLogReplay.realWorld.install(
            RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true), in: session
        )
        session.readLand(within: WholeTaiwan.landReach, of: taipei)
        session.selectTool(.bus)
        return (session, station.id, taipei)
    }

    /// Whether `point` is within a corner's cut of a bus road.
    private func isOnARoad(_ point: PlanPoint, _ roads: BusRoads) -> Bool {
        roads.place(near: point, within: BusWay.cornerRadius) != nil
    }

    func testStopsLieOnBusRoadsAndTheWayAndGameCoresMetresAreTheRoads() throws {
        let (session, station, taipei) = try game()
        let roads = try XCTUnwrap(session.busRoads, "a real map with its base map has bus roads")
        let cells = try XCTUnwrap(session.world.roads).cells
        let reach = Land.cellLength
        session.tapBusTool(at: taipei, reach: reach)
        XCTAssertEqual(session.busDraft.station, station)

        // A stop a tap away from a bus road 600 to 900 m off: on the road.
        var stop: PlanPoint?
        for dy in stride(from: -600, through: -900, by: -17) {
            for dx in stride(from: 300, through: 700, by: 13) {
                let tap = PlanPoint(x: taipei.x + Int64(dx) * 64, y: taipei.y + Int64(dy) * 64)
                if roads.place(near: tap, within: 20, accepting: { cells.contains(CellPosition(containing: $0)) }) != nil {
                    stop = tap
                    break
                }
            }
            if stop != nil { break }
        }
        let tap = try XCTUnwrap(stop)
        session.tapBusTool(at: tap, reach: reach)
        XCTAssertEqual(session.busDraft.stops.count, 1, session.message?.text ?? "")
        let pin = try XCTUnwrap(session.busDraft.stopPoints.first)
        XCTAssertNotNil(roads.place(near: pin, within: 1), "the stop is on a bus road")
        XCTAssertTrue(cells.contains(session.busDraft.stops[0]))

        let preview = try XCTUnwrap(session.busPreview)
        XCTAssertNil(preview.problem, preview.problem ?? "")
        let legs = try XCTUnwrap(session.busDraft.legMetres)
        XCTAssertEqual(legs.count, 1)
        XCTAssertEqual(preview.metres, legs[0], "GameCore takes the metres of the way drawn")
        // Along the roads, not the cells: the stretch is at least the
        // straight line to the station and no more than three times it.
        let there = try XCTUnwrap(session.world.station(id: station)).location
        let straight = hypot(Double(pin.x - there.x), Double(pin.y - there.y)) / 64
        XCTAssertGreaterThanOrEqual(Double(legs[0]), straight - 1)
        XCTAssertLessThan(Double(legs[0]), straight * 3)

        // The way drawn lies on the roads: each point within a corner's
        // cut of one, bar the short way from the road to the station.
        XCTAssertGreaterThan(session.busDraftPath.count, 2)
        XCTAssertEqual(session.busDraftPath.first, there)
        for point in session.busDraftPath.dropFirst() where hypot(Double(point.x - there.x), Double(point.y - there.y)) / 64 > 40 {
            XCTAssertTrue(isOnARoad(point, roads), "\(point) is off the roads")
        }

        // The route opens with those legs.
        XCTAssertTrue(session.confirmBusRoute())
        let route = try XCTUnwrap(session.world.busRoutes.first)
        XCTAssertEqual(route.legMetres, legs)

        // It is drawn on the roads from the saved route's cells too.
        let overlay = try XCTUnwrap(session.busMapOverlay)
        XCTAssertEqual(overlay.routes.count, 1)
        XCTAssertGreaterThan(overlay.routes[0].points.count, 2)
        XCTAssertEqual(overlay.routes[0].stops.count, 1)
        XCTAssertNotNil(roads.place(near: overlay.routes[0].stops[0], within: 1))

        // Edited for its headway alone, the route keeps the legs it had.
        session.editBusRoute(route.id)
        XCTAssertEqual(session.busDraft.stopPoints.count, 1)
        XCTAssertNotNil(roads.place(near: session.busDraft.stopPoints[0], within: 1), "the saved stop is put on a bus road")
        session.setBusDraftHeadway(20)
        XCTAssertTrue(session.confirmBusRoute())
        XCTAssertEqual(session.world.busRoutes.first?.legMetres, legs)
        XCTAssertEqual(session.world.busRoutes.first?.service, .every(minutes: 20))
    }

    func testATapNearAStopTakesItAway() throws {
        let (session, _, taipei) = try game()
        let roads = try XCTUnwrap(session.busRoads)
        let cells = try XCTUnwrap(session.world.roads).cells
        session.tapBusTool(at: taipei, reach: Land.cellLength)
        var tap: PlanPoint?
        search: for dy in stride(from: -500, through: -800, by: -11) {
            for dx in stride(from: 100, through: 500, by: 11) {
                let point = PlanPoint(x: taipei.x + Int64(dx) * 64, y: taipei.y + Int64(dy) * 64)
                if roads.place(near: point, within: 5, accepting: { cells.contains(CellPosition(containing: $0)) }) != nil {
                    tap = point
                    break search
                }
            }
        }
        let point = try XCTUnwrap(tap)
        session.tapBusTool(at: point, reach: Land.cellLength)
        XCTAssertEqual(session.busDraft.stops.count, 1)
        // Ten metres along, still within 25 m of the stop: it comes off.
        session.tapBusTool(at: PlanPoint(x: point.x + 10 * 64, y: point.y), reach: Land.cellLength)
        XCTAssertEqual(session.busDraft.stops, [])
        XCTAssertEqual(session.busDraft.stopPoints, [])
    }

    func testATapInTheMiddleOfABlockIsRefusedThoughItsCellHasAnAlley() throws {
        let (session, _, taipei) = try game()
        let roads = try XCTUnwrap(session.busRoads)
        let cells = try XCTUnwrap(session.world.roads).cells
        session.tapBusTool(at: taipei, reach: Land.cellLength)
        XCTAssertNotNil(session.busDraft.station)
        // A point of a road cell that no bus road is within 25 m of.
        var block: PlanPoint?
        search: for dy in stride(from: -500, through: -900, by: -7) {
            for dx in stride(from: -400, through: 400, by: 7) {
                let tap = PlanPoint(x: taipei.x + Int64(dx) * 64, y: taipei.y + Int64(dy) * 64)
                if cells.contains(CellPosition(containing: tap)), roads.place(near: tap, within: BusRoadNetwork.snapReach + 2) == nil {
                    block = tap
                    break search
                }
            }
        }
        let tap = try XCTUnwrap(block, "round Taipei Station some road cell has no bus road within 25 m")
        session.tapBusTool(at: tap, reach: Land.cellLength)
        XCTAssertEqual(session.busDraft.stops, [])
        XCTAssertEqual(session.message?.text, "Bus stops go on roads.")
    }
}
