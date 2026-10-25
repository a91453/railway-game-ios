import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 400, 10i-5: the bus tool draws a route from a station along the
/// roads, previews it with GameCore's own commands on a copy of the world,
/// opens it, edits it, and the station panel's cards show and change it;
/// the map draws it along the road cells. A cell is 4,096 units (64 m).
///
/// A managed world of 64 × 16 cells with land demand: station A in cell
/// (8, 5) with 1,000 residents; 200 residents in each of cells (8, 24) to
/// (8, 28), beyond A's 800 m; a road along row 8 from column 5 to 30, and
/// a lone road at (2, 40) to (2, 42) that joins nothing.
@MainActor
final class BusRouteEditorTests: XCTestCase {
    private let cell = Land.cellLength
    private let stop = CellPosition(row: 8, column: 26)

    private func world(balance: Money = 100_000_000) throws -> (GameWorld, StationID) {
        var world = GameWorld(bounds: try WorldBounds(width: 64 * cell, height: 16 * cell), economy: GameEconomy(balance: balance, costs: testCosts))
        let station = try world.buildStation(named: "A", at: CellPosition(row: 8, column: 5).middle)
        world.setEconomyMode(.management)
        try world.setLand([LandCell(row: 8, column: 5, use: .residential, residents: 1_000, jobs: 0)]
            + (24...28).map { LandCell(row: 8, column: $0, use: .residential, residents: 200, jobs: 0) })
        world.setLandDemand(true)
        world.enableRoads()
        try world.setRoads((5...30).map { CellPosition(row: 8, column: $0) } + (40...42).map { CellPosition(row: 2, column: $0) },
                           in: [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1), LandBlock(row: 0, column: 2)])
        return (world, station.id)
    }

    private func session(balance: Money = 100_000_000) throws -> (GameSession, StationID) {
        let (world, station) = try world(balance: balance)
        let session = GameSession(world: world)
        session.selectTool(.bus)
        return (session, station)
    }

    private var reach: Int64 { cell }

    // MARK: - Drawing

    func testTheFirstTapPicksAStationAndTheNextPutStopsOnRoads() throws {
        let (session, a) = try session()
        XCTAssertTrue(session.allowsBusTool)
        session.tapBusTool(at: CellPosition(row: 8, column: 20).middle, reach: reach)
        XCTAssertNil(session.busDraft.station, "no station there")
        XCTAssertEqual(session.message?.text, "Tap the station the bus route feeds first.")
        session.tapBusTool(at: CellPosition(row: 8, column: 5).middle, reach: reach)
        XCTAssertEqual(session.busDraft.station, a)
        XCTAssertNil(session.busPreview, "no stop yet")
        session.tapBusTool(at: CellPosition(row: 9, column: 26).middle, reach: reach)
        XCTAssertEqual(session.busDraft.stops, [], "off the road")
        XCTAssertEqual(session.message?.text, "Bus stops go on roads.")
        session.tapBusTool(at: stop.middle, reach: reach)
        XCTAssertEqual(session.busDraft.stops, [stop])
        let preview = try XCTUnwrap(session.busPreview)
        XCTAssertNil(preview.problem)
        XCTAssertTrue(preview.canOpen)
        // 21 cells along row 8, 64 m each; a stop $10,000, two buses
        // $50,000 each.
        XCTAssertEqual(preview.metres, 1_344)
        XCTAssertEqual(preview.price, Money(11_000_000))
        XCTAssertEqual(preview.headway, 10)
        // 144 departures, there and back 2.688 km each, $20 a kilometre.
        XCTAssertEqual(preview.departures, 144)
        XCTAssertEqual(preview.dailyCost, Money(774_144))
        XCTAssertGreaterThan(preview.riders, 0, "the 200s beyond A's 800 m")
        XCTAssertEqual(preview.lines(for: session.busDraft, in: .english).first, "1.3 km · 1 stop")
        XCTAssertEqual(preview.lines(for: session.busDraft, in: .traditionalChinese).last, "營運成本每天 \(Money(774_144).moneyText)")
        // Tapping the stop again takes it away; the last stop, then the
        // station, come off one at a time.
        session.tapBusTool(at: stop.middle, reach: reach)
        XCTAssertEqual(session.busDraft.stops, [])
        session.tapBusTool(at: stop.middle, reach: reach)
        session.removeLastBusStop()
        XCTAssertEqual(session.busDraft.stops, [])
        XCTAssertEqual(session.busDraft.station, a)
        session.removeLastBusStop()
        XCTAssertNil(session.busDraft.station)
    }

    func testAStationNoRoadReachesIsRefusedWithWhatToDo() throws {
        var (world, _) = try world()
        let off = try world.buildStation(named: "B", at: CellPosition(row: 12, column: 50).middle)
        let session = GameSession(world: world)
        session.selectTool(.bus)
        session.tapBusTool(at: off.location, reach: reach)
        XCTAssertNil(session.busDraft.station)
        XCTAssertEqual(session.message?.text, "No road reaches B yet: build its station road in the station's panel first.")
    }

    func testAStopNoRoadJoinsIsMarkedAndCannotOpen() throws {
        let (session, a) = try session()
        session.tapBusTool(at: CellPosition(row: 8, column: 5).middle, reach: reach)
        session.tapBusTool(at: stop.middle, reach: reach)
        session.tapBusTool(at: CellPosition(row: 2, column: 41).middle, reach: reach)
        let preview = try XCTUnwrap(session.busPreview)
        XCTAssertFalse(preview.canOpen)
        XCTAssertEqual(preview.problem, GameError.busStopsNotConnected(leg: 0).playerMessage(in: .english))
        // GameCore's leg 0 is the farthest stop (the one tapped last) to
        // the next.
        XCTAssertEqual(preview.brokenLeg, [CellPosition(row: 2, column: 41).middle, stop.middle])
        let draft = try XCTUnwrap(session.busMapOverlay?.draft)
        XCTAssertEqual(draft.broken.count, 2)
        XCTAssertFalse(draft.isBuildable)
        XCTAssertEqual(draft.station, session.world.station(id: a)?.location)
        XCTAssertFalse(session.confirmBusRoute(), "nothing to open")
        XCTAssertTrue(session.world.busRoutes.isEmpty)
    }

    func testTooFewBusesAreSaidAndTooLittleCashRefuses() throws {
        let (session, _) = try session(balance: 5_000_000)
        session.tapBusTool(at: CellPosition(row: 8, column: 5).middle, reach: reach)
        session.tapBusTool(at: stop.middle, reach: reach)
        XCTAssertEqual(session.busPreview?.problem,
                       GameError.insufficientFunds(required: Money(11_000_000), available: session.world.economy.balance).playerMessage(in: .english))
        XCTAssertEqual(session.busPreview?.metres, 1_344, "the figures still show")
        // A round trip is 19 minutes: one bus keeps every 19, not 5.
        session.setBusDraftHeadway(5)
        session.setBusDraftBuses(1)
        XCTAssertEqual(session.busPreview?.headway, 19)
        XCTAssertEqual(session.busPreview?.lines(for: session.busDraft, in: .traditionalChinese)[1], "每 19 分一班 · 1 輛車（車不夠每 5 分一班）")
    }

    // MARK: - Opening and changing

    func testConfirmOpensTheRouteThroughTheCommandLog() throws {
        let (session, a) = try session()
        session.tapBusTool(at: CellPosition(row: 8, column: 5).middle, reach: reach)
        let near = CellPosition(row: 8, column: 15)
        session.tapBusTool(at: near.middle, reach: reach)
        session.tapBusTool(at: stop.middle, reach: reach)
        let balance = session.world.economy.balance
        let price = try XCTUnwrap(session.busPreview?.price)
        XCTAssertTrue(session.confirmBusRoute())
        let route = try XCTUnwrap(session.world.busRoutes.first)
        XCTAssertEqual(route.station, a)
        XCTAssertEqual(route.stops, [stop, near], "the farthest first")
        XCTAssertEqual(route.buses, 2)
        XCTAssertEqual(route.service, .every(minutes: 10))
        XCTAssertEqual(session.world.economy.balance, balance - price)
        XCTAssertEqual(session.message?.text, "A bus now runs to A, for \(price.moneyText).")
        guard case .command(.edit(.createBusRoute(a, let stops, .every(minutes: 10), 2)))? = session.commandLog.entries.last?.action else {
            return XCTFail("\(String(describing: session.commandLog.entries.last?.action))")
        }
        XCTAssertEqual(stops.map(\.cell), [stop, near])
        XCTAssertNil(session.busDraft.station, "a new route starts from a station again")
        XCTAssertEqual(session.tool, .bus)
        // It is undone as any edit.
        XCTAssertTrue(session.canUndo)
    }

    func testEditingARouteMovesItsStopsAsOneCommand() throws {
        let (session, a) = try session()
        session.startBusRoute(from: a)
        session.tapBusTool(at: stop.middle, reach: reach)
        XCTAssertTrue(session.confirmBusRoute())
        let id = try XCTUnwrap(session.world.busRoutes.first?.id)
        session.selectTool(.select)
        session.editBusRoute(id)
        XCTAssertEqual(session.tool, .bus)
        XCTAssertEqual(session.busDraft.route, id)
        XCTAssertEqual(session.busDraft.stops, [stop])
        XCTAssertEqual(session.busPreview?.isUnchanged, true)
        XCTAssertEqual(session.busPreview?.canOpen, false, "nothing changed")
        XCTAssertNil(session.busMapOverlay?.routes.first { $0.id == id }, "the draft is drawn in its place")
        // The route keeps its station: taking back stops never drops it.
        session.removeLastBusStop()
        session.removeLastBusStop()
        XCTAssertEqual(session.busDraft.station, a)
        let far = CellPosition(row: 8, column: 28)
        session.tapBusTool(at: stop.middle, reach: reach)
        session.tapBusTool(at: far.middle, reach: reach)
        session.setBusDraftBuses(3)
        let preview = try XCTUnwrap(session.busPreview)
        XCTAssertEqual(preview.price, Money(6_000_000), "one stop and one bus more")
        XCTAssertTrue(session.confirmBusRoute())
        let route = try XCTUnwrap(session.world.busRoute(id: id))
        XCTAssertEqual(route.stops, [far, stop])
        XCTAssertEqual(route.buses, 3)
        XCTAssertEqual(session.world.busRoutes.count, 1)
        guard case .command(.edit(.reviseBusRoute(id, _, _, 3)))? = session.commandLog.entries.last?.action else {
            return XCTFail("\(String(describing: session.commandLog.entries.last?.action))")
        }
    }

    func testTheRouteCardShowsItsDayAndChangesItsBuses() throws {
        let (session, a) = try session()
        session.startBusRoute(from: a)
        session.tapBusTool(at: stop.middle, reach: reach)
        session.confirmBusRoute()
        let id = try XCTUnwrap(session.world.busRoutes.first?.id)
        var card = try XCTUnwrap(session.world.busRouteCards(feeding: a, in: .english).first)
        XCTAssertEqual(card.title, "Feeder bus 1")
        XCTAssertEqual(card.wayText, "1.3 km · 1 stop")
        XCTAssertEqual(card.serviceText, "A bus every 10 min · 2 buses")
        XCTAssertEqual(card.dayText, "No whole day run yet.")
        XCTAssertNil(card.net)
        XCTAssertEqual(session.world.busRouteCards(feeding: a, in: .traditionalChinese).first?.title, "接駁公車 1 號")
        session.setBusHeadway(id, to: 20)
        session.setBusCount(id, to: 1)
        card = try XCTUnwrap(session.world.busRouteCards(feeding: a, in: .english).first)
        XCTAssertEqual(card.serviceText, "A bus every 20 min · 1 bus")
        XCTAssertEqual(card.headway, 20)
        // A day's takings, booked at midnight.
        var world = session.world
        world.setSpeed(.normal)
        try world.advance(ticks: 25 * 60)
        card = try XCTUnwrap(world.busRouteCards(feeding: a, in: .english).first)
        let day = try XCTUnwrap(world.busRoute(id: id)?.days.last)
        XCTAssertEqual(card.net, day.fares - day.cost)
        XCTAssertTrue(card.dayText.hasPrefix("Last day: \(Money(day.riders).displayText) riders · fares "), card.dayText)
        session.removeBusRoute(id)
        XCTAssertTrue(session.world.busRoutes.isEmpty)
        XCTAssertEqual(session.message?.text, "The bus route is closed.")
    }

    // MARK: - The map

    func testTheMapDrawsEachRouteAlongTheRoadsInItsLinesColour() throws {
        var (world, a) = try world()
        try world.createBusRoute(to: a, stops: [stop], service: .every(minutes: 10), buses: 0)
        let session = GameSession(world: world)
        let overlay = try XCTUnwrap(session.busMapOverlay)
        XCTAssertNil(overlay.draft)
        let route = try XCTUnwrap(overlay.routes.first)
        XCTAssertFalse(route.runs, "no bus")
        XCTAssertNil(route.line)
        XCTAssertEqual(route.stops, [stop.middle])
        XCTAssertEqual(route.points.first, stop.middle)
        XCTAssertEqual(route.points.last, session.world.station(id: a)?.location)
        XCTAssertEqual(route.points.count, 23, "22 cells along row 8, then the station itself")
        XCTAssertNil(GameSession(world: try self.world().0).busMapOverlay, "no route, nothing drawn")
    }

    func testThePathFollowsTheRoadsAndIsNilWhereNoneJoins() {
        // An L: along row 0 to column 3, then down column 3 to row 3.
        let roads = Set((0...3).map { CellPosition(row: 0, column: $0) } + (1...3).map { CellPosition(row: $0, column: 3) })
        let path = BusRoadPath.cells(from: CellPosition(row: 0, column: 0), to: CellPosition(row: 3, column: 3), roads: roads)
        XCTAssertEqual(path?.first, CellPosition(row: 0, column: 0))
        XCTAssertEqual(path?.last, CellPosition(row: 3, column: 3))
        // Across the corner: (0, 2) to (1, 3) is one diagonal step.
        XCTAssertEqual(path, [CellPosition(row: 0, column: 0), CellPosition(row: 0, column: 1), CellPosition(row: 0, column: 2),
                              CellPosition(row: 1, column: 3), CellPosition(row: 2, column: 3), CellPosition(row: 3, column: 3)])
        XCTAssertNil(BusRoadPath.cells(from: CellPosition(row: 0, column: 0), to: CellPosition(row: 9, column: 9), roads: roads))
        XCTAssertEqual(BusRoadPath.cells(from: CellPosition(row: 0, column: 0), to: CellPosition(row: 0, column: 0), roads: roads),
                       [CellPosition(row: 0, column: 0)])
    }

    // MARK: - Where the tool is

    func testTheToolIsOnlyWhereThereAreRoadsAndOutOfLessons() throws {
        let plain = GameSession(world: GameWorld(bounds: try WorldBounds(width: 64 * cell, height: 16 * cell), economy: GameEconomy(balance: 0, costs: testCosts)))
        XCTAssertFalse(plain.allowsBusTool, "no roads")
        XCTAssertFalse(plain.allows(ConstructionTool.bus))
        let (session, _) = try session()
        XCTAssertTrue(session.allows(ConstructionTool.bus))
        XCTAssertTrue(ConstructionTool.bus.pausesGame)
        XCTAssertNil(TutorialTarget(tool: .bus))
        XCTAssertEqual(ConstructionTool.bus.title(in: .traditionalChinese), "公車")
        // Leaving the tool lets go of the route drawn.
        session.tapBusTool(at: CellPosition(row: 8, column: 5).middle, reach: reach)
        session.selectTool(.select)
        XCTAssertNil(session.busDraft.station)
    }

    func testTheBusEditsAreWrittenAndReadBack() throws {
        let edits: [PlayerCommand.Edit] = [
            .createBusRoute(StationID(rawValue: 3), stops: [.init(stop)], service: .every(minutes: 15), buses: 2),
            .reviseBusRoute(BusRouteID(rawValue: 1), stops: [.init(stop)], service: .runs([360, 420]), buses: 1),
            .setBusCount(BusRouteID(rawValue: 1), buses: 4),
            .setBusRuns(BusRouteID(rawValue: 1), .every(minutes: 30)),
            .removeBusRoute(BusRouteID(rawValue: 1)),
        ]
        for edit in edits {
            let data = try JSONEncoder().encode(edit)
            XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.Edit.self, from: data), edit)
        }
    }
}
