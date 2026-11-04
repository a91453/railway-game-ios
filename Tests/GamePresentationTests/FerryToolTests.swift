import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 585 (PR-2): the transit tool's ferry mode, its card and the
/// real ferries laid as they are.
@MainActor
final class FerryToolTests: XCTestCase {
    private static let cell = Land.cellLength

    /// 64 × 16 cells with water across rows 4 and 5 and no roads: piers
    /// stand on rows 3 and 6.
    private func makeSession(balance: Money = Money(10_000_000_000)) throws -> GameSession {
        var world = try makeWorld(width: 64 * Self.cell, height: 16 * Self.cell, balance: balance)
        world.setEconomyMode(.management)
        try world.setWater((4...5).flatMap { row in (0..<64).map { CellPosition(row: row, column: $0) } })
        let session = GameSession(world: world, language: .english)
        session.selectTool(.bus)
        session.setBusMode(.ferries)
        return session
    }

    private func middle(row: Int, column: Int) -> PlanPoint {
        PlanPoint(x: Int64(column) * Self.cell + Self.cell / 2, y: Int64(row) * Self.cell + Self.cell / 2)
    }

    private func replayed(_ session: GameSession) throws -> GameWorld {
        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.9", build: "90", data: [:]).encoded()
        )
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        return replay.session.world
    }

    /// Two piers 20 cells apart on the same shore, with no roads: 1,280 m,
    /// NT$300,000 a pier and NT$1,000,000 a boat, 6 minutes across, a boat
    /// every 15 minutes, 48 sailings of 99 each way on a weekday; opened
    /// through one command, the same as GameCore's own.
    func testTwoTapsOpenAFerryWithoutRoads() throws {
        let session = try makeSession()
        XCTAssertNil(session.world.roads)
        XCTAssertFalse(session.allowsBusTool)
        XCTAssertTrue(session.allowsFerryMode)
        session.tapBusTool(at: middle(row: 6, column: 6), reach: 0)
        XCTAssertEqual(session.ferryDraft, [CellPosition(row: 6, column: 6)])
        XCTAssertNil(session.ferryPreview, "one pier is no route yet")
        session.tapBusTool(at: middle(row: 6, column: 26), reach: 0)
        let preview = try XCTUnwrap(session.ferryPreview)
        XCTAssertNil(preview.problem)
        XCTAssertEqual(preview.piers, 2)
        XCTAssertEqual(preview.metres, 1_280)
        XCTAssertEqual(preview.price, Money(2 * 30_000_000 + 2 * 100_000_000))
        XCTAssertEqual(preview.rideMinutes, 6)
        XCTAssertEqual(preview.headway, 15)
        XCTAssertEqual(preview.dailyCapacity, 48 * 2 * 99)
        XCTAssertNil(preview.station)
        XCTAssertEqual(session.ferryDraftText(), "2 piers · 1,280 m · 6 min across")
        XCTAssertEqual(session.ferryMapOverlay?.draft?.piers.count, 2)
        XCTAssertEqual(session.ferryMapOverlay?.draftIsBuildable, true)

        var expected = session.world
        try expected.createFerryRoute(piers: session.ferryDraft, service: .every(minutes: 15), boats: 2)
        XCTAssertTrue(session.buildFerryRoute())
        XCTAssertEqual(session.world.ferryRoutes, expected.ferryRoutes)
        XCTAssertEqual(session.world.economy.balance, expected.economy.balance)
        XCTAssertTrue(session.ferryDraft.isEmpty)
        XCTAssertEqual(session.message?.text, "Ferry 1 now sails, for \(preview.price.moneyText).")
        let overlay = try XCTUnwrap(session.ferryMapOverlay)
        XCTAssertEqual(overlay.routes.map(\.piers), [[middle(row: 6, column: 6), middle(row: 6, column: 26)]])
        XCTAssertNil(overlay.draft)
        XCTAssertEqual(try replayed(session).ferryRoutes, session.world.ferryRoutes, "the command log replays it")

        let id = FerryRouteID(rawValue: 1)
        session.setFerryBoats(id, to: 3)
        XCTAssertEqual(session.world.ferryRoute(id: id)?.boats, 3)
        XCTAssertEqual(session.world.economy.balance, expected.economy.balance - Money(100_000_000))
        session.setFerryMinutesApart(id, to: 30)
        XCTAssertEqual(session.world.ferryRoute(id: id)?.headway, 30)
        XCTAssertEqual(try replayed(session).ferryRoutes, session.world.ferryRoutes)
        session.removeFerryRoute(id)
        XCTAssertTrue(session.world.ferryRoutes.isEmpty)
        XCTAssertNil(session.ferryMapOverlay)
    }

    func testTheEditsAreWrittenAndReadBack() throws {
        let piers = [PlayerCommand.Edit.BusStop(CellPosition(row: 6, column: 6)), .init(CellPosition(row: 3, column: 26))]
        let edits: [PlayerCommand.Edit] = [
            .createFerryRoute(piers: piers, service: .every(minutes: 15), boats: 2),
            .createFerryRoute(piers: piers, legMetres: [1_260], service: .runs([420, 480]), boats: 1),
            .setFerryBoats(FerryRouteID(rawValue: 2), boats: 4),
            .setFerryRuns(FerryRouteID(rawValue: 2), .every(minutes: 20)),
            .removeFerryRoute(FerryRouteID(rawValue: 3)),
        ]
        for edit in edits {
            XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.Edit.self, from: JSONEncoder().encode(edit)), edit)
        }
    }

    /// A tap away from the shore or on the water puts no pier; a tap on the
    /// last pier takes it back.
    func testPiersStandOnlyOnTheShore() throws {
        let session = try makeSession()
        session.tapBusTool(at: middle(row: 10, column: 6), reach: 0)
        XCTAssertTrue(session.ferryDraft.isEmpty)
        XCTAssertEqual(session.message?.kind, .failure)
        session.tapBusTool(at: middle(row: 4, column: 6), reach: 0)
        XCTAssertTrue(session.ferryDraft.isEmpty, "not on the water")
        session.tapBusTool(at: middle(row: 3, column: 6), reach: 0)
        session.tapBusTool(at: middle(row: 6, column: 6), reach: 0)
        XCTAssertEqual(session.ferryDraft.count, 2)
        session.tapBusTool(at: middle(row: 6, column: 6), reach: 0)
        XCTAssertEqual(session.ferryDraft, [CellPosition(row: 3, column: 6)])
        session.undoFerryPier()
        XCTAssertTrue(session.ferryDraft.isEmpty)
        session.setBusMode(.routes)
        XCTAssertEqual(session.busMode, .routes)
    }

    /// Short of money, the preview says so and nothing is built.
    func testAShortfallIsTheProblem() throws {
        let session = try makeSession(balance: Money(100_000_000))
        session.tapBusTool(at: middle(row: 6, column: 6), reach: 0)
        session.tapBusTool(at: middle(row: 6, column: 26), reach: 0)
        XCTAssertNotNil(session.ferryPreview?.problem)
        XCTAssertFalse(session.buildFerryRoute())
        XCTAssertTrue(session.world.ferryRoutes.isEmpty)
    }

    /// The card: the crossing, the boats, whether it sails today, and the
    /// day's cost until a day has passed.
    func testTheCardSaysWhatItCarriesAndWhetherItSails() throws {
        let session = try makeSession()
        session.setFerryDraftBoats(1)
        session.setFerryDraftMinutesApart(20)
        session.tapBusTool(at: middle(row: 6, column: 6), reach: 0)
        session.tapBusTool(at: middle(row: 6, column: 26), reach: 0)
        XCTAssertTrue(session.buildFerryRoute())
        let card = try XCTUnwrap(session.ferryCard(FerryRouteID(rawValue: 1)))
        XCTAssertEqual(card.title, "Ferry 1")
        XCTAssertEqual(card.boats, 1)
        XCTAssertEqual(card.minutesApart, 20)
        XCTAssertTrue(card.sails)
        XCTAssertEqual(card.rows.first, "2 piers · 1,280 m · 6 min across")
        XCTAssertTrue(card.rows[1].hasPrefix("A boat every 20 min · 1 boat"))
        XCTAssertTrue(card.rows.contains { $0.hasPrefix("Sails today, 7:00–") })
        XCTAssertTrue(card.rows.last?.hasPrefix("Costs ") ?? false)
        XCTAssertNil(session.ferryCard(FerryRouteID(rawValue: 9)))
    }

    func testTheModesAndTheToolsName() {
        XCTAssertEqual(BusToolMode.allCases, [.routes, .roads, .ferries])
        XCTAssertEqual(BusToolMode.allCases.map { $0.title(in: .traditionalChinese) }, ["公車", "道路", "渡輪"])
        XCTAssertEqual(ConstructionTool.bus.title(in: .traditionalChinese), "接駁")
        XCTAssertEqual(ConstructionTool.bus.title(in: .english), "Transit")
    }

    // MARK: - The real ferries

    /// On a map of the Tamsui River's mouth with water between the two
    /// piers, the mode offers Tamsui–Bali and lays it with its real
    /// crossing: 1,260 m, 6 minutes.
    func testTamsuiBaliIsOfferedOnAMapOfTheRiverMouth() throws {
        var world = try makeWorld(width: 128 * Self.cell, height: 128 * Self.cell, balance: Money(10_000_000_000))
        world.setEconomyMode(.management)
        world.setGeoAnchor(try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.164, longitudeDegrees: 121.4376)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let cells = RealFerry.tamsuiBali.piers.map { pier in
            let (x, y) = frame.worldPosition(latitude: pier.latitude, longitude: pier.longitude)
            return CellPosition(containing: PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded())))
        }
        XCTAssertGreaterThan(cells[1].row, cells[0].row, "Bali lies south of Tamsui")
        // The river: every row strictly between the two piers is water.
        try world.setWater(((cells[0].row + 1)..<cells[1].row).flatMap { row in (0..<128).map { CellPosition(row: row, column: $0) } })
        XCTAssertNil(RealFerry.gushanCijin.piers(in: world), "Kaohsiung is off this map")
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTool(.bus)
        session.setBusMode(.ferries)
        let offer = try XCTUnwrap(session.realFerryOffer)
        XCTAssertEqual(offer.name, "淡水—八里")
        session.traceRealFerry(offer)
        XCTAssertNil(session.realFerryOffer, "not while one is drawn")
        XCTAssertEqual(session.ferryDraft, cells, "the piers' own cells are on the shore")
        let preview = try XCTUnwrap(session.ferryPreview)
        XCTAssertNil(preview.problem)
        XCTAssertEqual(preview.metres, 1_260)
        XCTAssertEqual(preview.rideMinutes, 6)
        XCTAssertEqual(session.ferryDraftText(), "2 個碼頭 · 1,260 公尺 · 船程 6 分")
        XCTAssertTrue(session.buildFerryRoute())
        XCTAssertNil(session.realFerryOffer, "not once it is open")
    }

    /// Off the Earth, or with no shore near a pier, nothing is offered.
    func testNoOfferOffTheMapOrAwayFromTheWater() throws {
        let session = try makeSession()
        XCTAssertNil(session.realFerryOffer)
        var dry = try makeWorld(width: 128 * Self.cell, height: 128 * Self.cell)
        dry.setGeoAnchor(try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.6165, longitudeDegrees: 120.268)))
        XCTAssertNil(RealFerry.gushanCijin.piers(in: dry), "no water, no pier")
    }
}
