import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 438 (the screens): the bus tool opens city routes with a first
/// tap on a road, edits them, lists them, and draws them; its roads mode
/// draws a road with a drag, lays it, and takes up the player's own. A cell
/// is 4,096 units (64 m).
///
/// The world of ``BusRouteEditorTests``: 64 × 16 cells, station A in cell
/// (8, 5) with 1,000 residents; 200 residents in each of cells (8, 24) to
/// (8, 28); a road along row 8 from column 5 to 30, and a lone road at
/// (2, 40) to (2, 42).
@MainActor
final class CityBusToolTests: XCTestCase {
    private let cell = Land.cellLength

    private func session(balance: Money = 100_000_000, unlimitedFunds: Bool = false) throws -> GameSession {
        var world = GameWorld(bounds: try WorldBounds(width: 64 * cell, height: 16 * cell), economy: GameEconomy(balance: balance, costs: testCosts))
        try world.buildStation(named: "A", at: CellPosition(row: 8, column: 5).middle)
        world.setEconomyMode(.management)
        try world.setLand([LandCell(row: 8, column: 5, use: .residential, residents: 1_000, jobs: 0)]
            + (24...28).map { LandCell(row: 8, column: $0, use: .residential, residents: 200, jobs: 0) })
        world.setLandDemand(true)
        world.enableRoads()
        world.setUnlimitedFunds(unlimitedFunds)
        try world.setRoads((5...30).map { CellPosition(row: 8, column: $0) } + (40...42).map { CellPosition(row: 2, column: $0) },
                           in: [LandBlock(row: 0, column: 0), LandBlock(row: 0, column: 1), LandBlock(row: 0, column: 2)])
        let session = GameSession(world: world)
        session.selectTool(.bus)
        return session
    }

    private var reach: Int64 { cell }

    private func at(_ row: Int, _ column: Int) -> PlanPoint {
        CellPosition(row: row, column: column).middle
    }

    private func replayed(_ session: GameSession) throws -> GameWorld {
        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.9", build: "90", data: [:]).encoded()
        )
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        return replay.session.world
    }

    // MARK: - City routes

    func testAFirstTapOnARoadStartsACityRouteThatOpensWithTwoStops() throws {
        let session = try session()
        session.tapBusTool(at: at(8, 24), reach: reach)
        XCTAssertTrue(session.busDraft.city)
        XCTAssertNil(session.busDraft.station)
        XCTAssertEqual(session.busDraft.stops, [CellPosition(row: 8, column: 24)])
        XCTAssertNil(session.busPreview, "a city route needs two stops")
        XCTAssertNotNil(session.busMapOverlay?.draft, "its first stop is drawn")
        XCTAssertNil(session.busMapOverlay?.draft?.station)
        session.tapBusTool(at: at(8, 28), reach: reach)
        // Its stops as tapped, first to last: GameCore's order too.
        XCTAssertEqual(session.busDraft.coreStops, [CellPosition(row: 8, column: 24), CellPosition(row: 8, column: 28)])
        let preview = try XCTUnwrap(session.busPreview)
        XCTAssertTrue(preview.canOpen)
        XCTAssertEqual(preview.metres, 256, "four cells along row 8")
        XCTAssertNil(preview.transfer, "no stop near a station")
        // Two stops $10,000 each, two buses $50,000 each.
        XCTAssertEqual(preview.price, Money(12_000_000))
        XCTAssertTrue(session.confirmBusRoute())
        let route = try XCTUnwrap(session.world.busRoutes.last)
        XCTAssertNil(route.station)
        XCTAssertEqual(route.stops, [CellPosition(row: 8, column: 24), CellPosition(row: 8, column: 28)])
        XCTAssertEqual(session.message?.text, "City bus \(route.id.rawValue) now runs, for \(Money(12_000_000).moneyText).")
        guard case .command(.edit(.createCityBusRoute(let stops, nil, .every(minutes: 10), 2)))? = session.commandLog.entries.last?.action else {
            return XCTFail("the city route is logged as a city route")
        }
        XCTAssertEqual(stops.map(\.cell), route.stops)
        XCTAssertFalse(session.busDraft.isBegun)
        XCTAssertEqual(try replayed(session), session.world)
    }

    func testTheFirstStopTakenBackLetsGoOfTheCityRoute() throws {
        let session = try session()
        session.tapBusTool(at: at(8, 24), reach: reach)
        session.removeLastBusStop()
        XCTAssertFalse(session.busDraft.isBegun)
        // Then a station can be picked as before.
        session.tapBusTool(at: at(8, 5), reach: reach)
        XCTAssertNotNil(session.busDraft.station)
        XCTAssertFalse(session.busDraft.city)
    }

    func testACityRouteNearAStationSaysWhereRidersChange() throws {
        let session = try session()
        // Column 10 is 320 m from A, within a stop's 400 m.
        session.tapBusTool(at: at(8, 10), reach: reach)
        session.tapBusTool(at: at(8, 26), reach: reach)
        let preview = try XCTUnwrap(session.busPreview)
        XCTAssertEqual(preview.transfer, "A")
        let lines = preview.lines(for: session.busDraft, in: .english)
        XCTAssertTrue(lines.contains("Riders can change to the trains at A."), "\(lines)")
        XCTAssertTrue(preview.lines(for: session.busDraft, in: .traditionalChinese).contains("在A站可以轉乘。"))
        XCTAssertTrue(session.confirmBusRoute())
        let card = try XCTUnwrap(session.world.cityBusRouteCards(in: .english).first)
        XCTAssertTrue(card.title.hasPrefix("City bus "))
        XCTAssertTrue(card.wayText.hasSuffix("trains at A"), card.wayText)
        XCTAssertTrue(try XCTUnwrap(session.world.cityBusRouteCards(in: .traditionalChinese).first).title.hasPrefix("市區公車 "))
        let station = try XCTUnwrap(session.world.stations.first?.id)
        XCTAssertTrue(session.world.busRouteCards(feeding: station, in: .english).isEmpty, "a city route is not one of A's")
    }

    func testACityRouteIsEditedFirstToLastAndDrawnInNavy() throws {
        let session = try session()
        session.tapBusTool(at: at(8, 24), reach: reach)
        session.tapBusTool(at: at(8, 28), reach: reach)
        XCTAssertTrue(session.confirmBusRoute())
        let id = try XCTUnwrap(session.world.busRoutes.last?.id)
        session.selectTool(.select)
        let overlay = try XCTUnwrap(session.busMapOverlay)
        let drawn = try XCTUnwrap(overlay.routes.first)
        XCTAssertNil(drawn.line, "no line's colour: the ink's navy")
        XCTAssertEqual(drawn.points.first, at(8, 24))
        XCTAssertEqual(drawn.points.last, at(8, 28))
        XCTAssertEqual(drawn.stops, [at(8, 24), at(8, 28)])
        session.editBusRoute(id)
        XCTAssertEqual(session.tool, .bus)
        XCTAssertEqual(session.busMode, .routes)
        XCTAssertTrue(session.busDraft.city)
        XCTAssertEqual(session.busDraft.route, id)
        XCTAssertEqual(session.busDraft.stops, [CellPosition(row: 8, column: 24), CellPosition(row: 8, column: 28)])
        XCTAssertEqual(session.busPreview?.isUnchanged, true)
        session.tapBusTool(at: at(8, 30), reach: reach)
        XCTAssertTrue(session.confirmBusRoute())
        XCTAssertEqual(session.world.busRoute(id: id)?.stops.last, CellPosition(row: 8, column: 30))
        XCTAssertEqual(session.message?.text, "City bus \(id.rawValue) is changed, for \(Money(1_000_000).moneyText).")
        XCTAssertEqual(try replayed(session), session.world)
    }

    func testTheEditsAreWrittenAndReadBack() throws {
        let cells = [PlayerCommand.Edit.BusStop(CellPosition(row: 8, column: 24)), .init(CellPosition(row: 8, column: 28))]
        let edits: [PlayerCommand.Edit] = [
            .createCityBusRoute(stops: cells, service: .every(minutes: 15), buses: 2),
            .createCityBusRoute(stops: cells, legMetres: [256], service: .runs([360, 420]), buses: 1),
            .buildRoad(along: cells),
            .removeRoads(cells),
        ]
        for edit in edits {
            XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.Edit.self, from: JSONEncoder().encode(edit)), edit)
        }
    }

    // MARK: - Roads

    func testADraftGoesThroughEveryCellAndAStepBackTakesTheLastBack() {
        var draft = RoadDraft()
        draft.extend(to: CellPosition(row: 2, column: 2))
        draft.extend(to: CellPosition(row: 4, column: 6))
        // Corner to corner, then straight on.
        XCTAssertEqual(draft.cells, [
            CellPosition(row: 2, column: 2), CellPosition(row: 3, column: 3), CellPosition(row: 4, column: 4),
            CellPosition(row: 4, column: 5), CellPosition(row: 4, column: 6),
        ])
        draft.extend(to: CellPosition(row: 4, column: 5))
        XCTAssertEqual(draft.cells.last, CellPosition(row: 4, column: 5))
        XCTAssertEqual(draft.cells.count, 4)
        var long = RoadDraft()
        long.extend(to: CellPosition(row: 0, column: 0))
        long.extend(to: CellPosition(row: 0, column: 400))
        XCTAssertEqual(long.cells.count, RoadGrid.longestBuiltRoad)
    }

    func testADragDrawsARoadTheActionButtonLays() throws {
        let session = try session()
        session.setBusMode(.roads)
        XCTAssertEqual(session.busMode, .roads)
        session.dragRoad(from: at(12, 10), to: at(12, 12))
        session.endRoadDrag(from: at(12, 10), to: at(12, 14))
        let cells = (10...14).map { CellPosition(row: 12, column: $0) }
        XCTAssertEqual(session.roadDraft.cells, cells)
        let preview = try XCTUnwrap(session.roadPreview)
        XCTAssertTrue(preview.canBuild)
        // Five cells, 64 m each, $50 a metre.
        XCTAssertEqual(preview.metres, 320)
        XCTAssertEqual(preview.price, Money(1_600_000))
        XCTAssertEqual(preview.line(in: .english), "320 m of new road")
        XCTAssertEqual(preview.line(in: .traditionalChinese), "新鋪 320 公尺")
        let overlay = try XCTUnwrap(session.roadMapOverlay)
        // Decision 476: one line through the cells' middles, as it will be
        // laid, not a block a cell.
        XCTAssertEqual(overlay.draft, [cells.map(\.middle)])
        XCTAssertTrue(overlay.isBuildable)
        let before = session.world.economy.balance
        XCTAssertTrue(session.confirmRoad())
        XCTAssertEqual(session.world.economy.balance, before - Money(1_600_000))
        XCTAssertEqual(session.world.roads?.built, Set(cells))
        XCTAssertEqual(session.message?.text, "The road is built, for \(Money(1_600_000).moneyText).")
        XCTAssertTrue(session.roadDraft.isEmpty)
        XCTAssertEqual(session.roadMapOverlay?.own, [cells.map(\.middle)], "marked while the roads mode is open")
        XCTAssertEqual(try replayed(session), session.world)
        // Out of the mode, the 2D streets of a map with no base map draw them.
        session.setBusMode(.routes)
        XCTAssertNil(session.roadMapOverlay)
    }

    /// Decision 476: with unlimited funds the cash does not go down, and
    /// the message says what the button said the road cost, not $0.
    func testWithUnlimitedFundsTheRoadSaysItsPrice() throws {
        let session = try session(unlimitedFunds: true)
        session.setBusMode(.roads)
        session.endRoadDrag(from: at(12, 10), to: at(12, 14))
        XCTAssertEqual(session.roadPreview?.price, Money(1_600_000))
        XCTAssertTrue(session.confirmRoad())
        XCTAssertEqual(
            session.message?.text,
            "The road is built. It cost \(Money(1_600_000).moneyText); with unlimited funds nothing is paid."
        )
    }

    /// Before the public beta (BH1, 2026-10-30): a road drawn over one
    /// just laid joins it for nothing; an undo of the one laid left the
    /// button's price as it was, and the action button then paid the whole
    /// road ($224 for $128 shown) while the message said $128.
    func testAfterAnUndoTheRoadDrawnIsPricedAgain() throws {
        let session = try session()
        session.setBusMode(.roads)
        session.endRoadDrag(from: at(12, 10), to: at(12, 14))
        XCTAssertTrue(session.confirmRoad())
        session.endRoadDrag(from: at(12, 12), to: at(12, 18))
        XCTAssertEqual(session.roadPreview?.price, Money(1_280_000), "four new cells; three joined")
        session.undo()
        XCTAssertEqual(session.roadPreview?.price, Money(2_240_000), "seven new cells once the first road is gone")
        let before = session.world.economy.balance
        XCTAssertTrue(session.confirmRoad())
        XCTAssertEqual(session.world.economy.balance, before - Money(2_240_000))
        XCTAssertEqual(session.message?.text, "The road is built, for \(Money(2_240_000).moneyText).")
    }

    /// The same, when the world changed some other way since the price was
    /// shown: the button shows the new price and lays nothing until it is
    /// pressed again.
    func testARoadWhosePriceChangedIsShownBeforeItIsPaid() throws {
        let session = try session()
        session.setBusMode(.roads)
        session.endRoadDrag(from: at(12, 12), to: at(12, 18))
        XCTAssertEqual(session.roadPreview?.price, Money(2_240_000))
        try session.performEdit { (world: inout GameWorld) throws(GameError) in
            try world.buildRoad(along: (10...14).map { CellPosition(row: 12, column: $0) })
        }
        let before = session.world
        XCTAssertFalse(session.confirmRoad())
        XCTAssertEqual(session.world, before, "nothing paid at a price not shown")
        XCTAssertEqual(session.roadPreview?.price, Money(1_280_000))
        XCTAssertEqual(session.message?.text, "The road now costs \(Money(1_280_000).moneyText). Tap again to lay it.")
        XCTAssertTrue(session.confirmRoad())
        XCTAssertEqual(session.world.economy.balance, before.economy.balance - Money(1_280_000))
    }

    func testADragFromTheRoadsLastCellCarriesItOn() throws {
        let session = try session()
        session.setBusMode(.roads)
        session.endRoadDrag(from: at(12, 10), to: at(12, 12))
        session.endRoadDrag(from: at(12, 12), to: at(12, 14))
        XCTAssertEqual(session.roadDraft.cells, (10...14).map { CellPosition(row: 12, column: $0) })
        session.endRoadDrag(from: at(13, 20), to: at(13, 21))
        XCTAssertEqual(session.roadDraft.cells, [CellPosition(row: 13, column: 20), CellPosition(row: 13, column: 21)], "a new road")
        session.cancelRoadDrag()
        XCTAssertTrue(session.roadDraft.isEmpty)
    }

    func testARoadAlongTheCitysRoadLaysNothing() throws {
        let session = try session()
        session.setBusMode(.roads)
        session.endRoadDrag(from: at(8, 10), to: at(8, 12))
        let preview = try XCTUnwrap(session.roadPreview)
        XCTAssertFalse(preview.canBuild)
        XCTAssertEqual(preview.line(in: .english), "There's a road here already.")
        XCTAssertEqual(session.roadMapOverlay?.draft.isEmpty, false, "drawn faint over the city's road")
        XCTAssertFalse(session.confirmRoad())
    }

    /// Decision 476's sequel: a road drawn over the city's says how much of
    /// it joins the road already there, which costs nothing.
    func testARoadFromTheCitysRoadSaysWhatItJoinsForFree() throws {
        let session = try session()
        session.setBusMode(.roads)
        session.endRoadDrag(from: at(8, 10), to: at(10, 10))
        let preview = try XCTUnwrap(session.roadPreview)
        XCTAssertTrue(preview.canBuild)
        XCTAssertEqual(preview.joined, 64)
        XCTAssertEqual(preview.line(in: .english), "\(preview.metres) m of new road; joins 64 m of road already there, free")
        XCTAssertEqual(preview.line(in: .traditionalChinese), "新鋪 \(preview.metres) 公尺，接上現有的路 64 公尺，這段不用錢")
    }

    func testARoadTheCompanyCannotPayForIsRefused() throws {
        let session = try session(balance: 1_000_000)
        session.setBusMode(.roads)
        session.endRoadDrag(from: at(12, 10), to: at(12, 14))
        let preview = try XCTUnwrap(session.roadPreview)
        XCTAssertFalse(preview.canBuild)
        XCTAssertNotNil(preview.problem)
    }

    func testATapPicksThePlayersStretchToTakeUpButNotTheCitys() throws {
        let session = try session()
        session.setBusMode(.roads)
        // The stretch from the city's road at (8, 12) up to row 11.
        session.endRoadDrag(from: at(8, 12), to: at(11, 12))
        XCTAssertTrue(session.confirmRoad())
        let own = (9...11).map { CellPosition(row: $0, column: 12) }
        XCTAssertEqual(session.world.roads?.built, Set(own))
        session.tapBusTool(at: at(8, 20), reach: reach)
        XCTAssertNil(session.roadRemoval)
        XCTAssertEqual(session.message?.text, "This is the city's road; it can't be taken up.")
        session.tapBusTool(at: at(12, 30), reach: reach)
        XCTAssertEqual(session.message?.text, "Drag across the map to lay a road. Tap one of your roads to take it up.")
        session.tapBusTool(at: at(10, 12), reach: reach)
        let removal = try XCTUnwrap(session.roadRemoval)
        XCTAssertEqual(Set(removal.cells), Set(own), "the whole stretch, not the city's road it joins")
        XCTAssertTrue(removal.canRemove)
        XCTAssertEqual(session.roadMapOverlay?.removal, [own.map(\.middle)])
        // A tap on it again lets go.
        session.tapBusTool(at: at(9, 12), reach: reach)
        XCTAssertNil(session.roadRemoval)
        session.tapBusTool(at: at(9, 12), reach: reach)
        let before = session.world.economy.balance
        XCTAssertTrue(session.confirmRoad())
        XCTAssertEqual(session.world.roads?.built, [])
        XCTAssertEqual(session.world.economy.balance, before, "nothing paid back")
        XCTAssertEqual(session.message?.text, "The road is taken up.")
        XCTAssertEqual(try replayed(session), session.world)
    }

    func testARoadABusRunsOnCannotBeTakenUpAndNamesTheRoute() throws {
        let session = try session()
        session.setBusMode(.roads)
        session.endRoadDrag(from: at(12, 10), to: at(12, 14))
        XCTAssertTrue(session.confirmRoad())
        session.setBusMode(.routes)
        XCTAssertNil(session.roadMapOverlay)
        session.tapBusTool(at: at(12, 10), reach: reach)
        session.tapBusTool(at: at(12, 14), reach: reach)
        XCTAssertTrue(session.confirmBusRoute())
        let id = try XCTUnwrap(session.world.busRoutes.last?.id)
        session.setBusMode(.roads)
        session.tapBusTool(at: at(12, 12), reach: reach)
        let removal = try XCTUnwrap(session.roadRemoval)
        XCTAssertFalse(removal.canRemove)
        XCTAssertEqual(removal.problem, "City bus \(id.rawValue) runs on this road. Change the route first.")
        XCTAssertFalse(session.confirmRoad())
        XCTAssertEqual(session.world.roads?.built.count, 5)
    }

    func testLeavingTheToolOrModeLetsGoOfTheRoadDrawn() throws {
        let session = try session()
        session.setBusMode(.roads)
        session.endRoadDrag(from: at(12, 10), to: at(12, 14))
        session.setBusMode(.routes)
        XCTAssertTrue(session.roadDraft.isEmpty)
        XCTAssertNil(session.roadPreview)
        session.setBusMode(.roads)
        session.endRoadDrag(from: at(12, 10), to: at(12, 14))
        session.selectTool(.select)
        XCTAssertTrue(session.roadDraft.isEmpty)
        XCTAssertNil(session.roadMapOverlay)
    }
}
