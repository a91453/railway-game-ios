import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 574 (PR-2): the network tool's cable car mode, its card, the
/// cabins' places and the Maokong Gondola laid as it is.
@MainActor
final class CablewayToolTests: XCTestCase {
    private static let cell = Land.cellLength

    private func makeSession(balance: Money = Money(10_000_000_000)) throws -> GameSession {
        var world = try makeWorld(width: 64 * Self.cell, height: 16 * Self.cell, balance: balance)
        world.setEconomyMode(.management)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.network)
        session.setNetworkMode(.cableway)
        return session
    }

    private func middle(row: Int, column: Int) -> PlanPoint {
        PlanPoint(x: Int64(column) * Self.cell + Self.cell / 2, y: Int64(row) * Self.cell + Self.cell / 2)
    }

    /// Two taps ten cells apart: 640 m of rope between two stations,
    /// NT$600,000 a station and NT$1,500 a metre, two minutes end to end;
    /// built through one command, the same as GameCore's own.
    func testTwoTapsBuildACableCar() throws {
        let session = try makeSession()
        XCTAssertTrue(session.allows(NetworkToolMode.cableway))
        session.tapNetwork(at: middle(row: 2, column: 2), reach: 0)
        XCTAssertNil(session.cablewayPreview, "one stop is no cable car yet")
        session.tapNetwork(at: middle(row: 2, column: 12), reach: 0)
        let preview = try XCTUnwrap(session.cablewayPreview)
        XCTAssertNil(preview.problem)
        XCTAssertEqual(preview.metres, 640)
        XCTAssertEqual(preview.stations, 2)
        XCTAssertEqual(preview.price, Money(2 * 60_000_000 + 640 * 150_000))
        XCTAssertEqual(preview.rideMinutes, 2, "128 s")
        XCTAssertEqual(session.networkDraftText(), "2 stations · 640 m · 2 min end to end")
        XCTAssertEqual(session.cablewayMapOverlay?.draft?.points.count, 2)
        XCTAssertEqual(session.cablewayMapOverlay?.draftIsBuildable, true)

        var expected = session.world
        try expected.createCableway(stops: session.cablewayDraft)
        XCTAssertTrue(session.buildCableway())
        XCTAssertEqual(session.world.cableways, expected.cableways)
        XCTAssertEqual(session.world.economy.balance, expected.economy.balance)
        XCTAssertTrue(session.cablewayDraft.isEmpty)
        XCTAssertEqual(session.message?.text, "Cable car 1 now runs, for \(preview.price.moneyText).")
        let overlay = try XCTUnwrap(session.cablewayMapOverlay)
        XCTAssertEqual(overlay.ropes.map(\.points), [[middle(row: 2, column: 2), middle(row: 2, column: 12)]])
        XCTAssertNil(overlay.draft)

        // The command log replays it (decision 193).
        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.9", build: "90", data: [:]).encoded()
        )
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world.cableways, session.world.cableways)

        session.removeCableway(CablewayID(rawValue: 1))
        XCTAssertTrue(session.world.cableways.isEmpty)
        XCTAssertNil(session.cablewayMapOverlay)
    }

    func testTheEditsAreWrittenAndReadBack() throws {
        let edits: [PlayerCommand.Edit] = [
            .createCableway(stops: [CablewayStop(cell: CellPosition(row: 1, column: 2)), CablewayStop(cell: CellPosition(row: 3, column: 4), boards: false)]),
            .createCableway(stops: [CablewayStop(cell: CellPosition(row: 1, column: 2))], legMetres: [827]),
            .removeCableway(CablewayID(rawValue: 3)),
        ]
        for edit in edits {
            XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.Edit.self, from: JSONEncoder().encode(edit)), edit)
        }
    }

    /// A tap on the last stop takes it back; with the angle option the
    /// next stop boards no one (never the first), and a draft ending on
    /// one cannot be built.
    func testAngleStationsAndTakingAStopBack() throws {
        let session = try makeSession()
        session.cablewayPlacesAngle = true
        session.tapNetwork(at: middle(row: 2, column: 2), reach: 0)
        session.tapNetwork(at: middle(row: 2, column: 6), reach: 0)
        XCTAssertEqual(session.cablewayDraft.map(\.boards), [true, false], "the first is always a station")
        XCTAssertEqual(session.cablewayPreview?.problem, "The last stop must be a station, not an angle station.")
        XCTAssertFalse(session.buildCableway())
        session.tapNetwork(at: middle(row: 2, column: 6), reach: 0)
        XCTAssertEqual(session.cablewayDraft.count, 1, "the last stop again takes it back")
        session.cablewayPlacesAngle = false
        session.tapNetwork(at: middle(row: 6, column: 6), reach: 0)
        session.undoCablewayStop()
        XCTAssertEqual(session.cablewayDraft.count, 1)
        session.setNetworkMode(.build)
        XCTAssertTrue(session.cablewayDraft.isEmpty, "another mode forgets the stops")
    }

    /// Without the money, GameCore's refusal is the preview's problem.
    func testAShortfallIsTheProblem() throws {
        let session = try makeSession(balance: Money(100))
        session.tapNetwork(at: middle(row: 2, column: 2), reach: 0)
        session.tapNetwork(at: middle(row: 2, column: 12), reach: 0)
        XCTAssertNotNil(session.cablewayPreview?.problem)
        XCTAssertFalse(session.buildCableway())
        XCTAssertTrue(session.world.cableways.isEmpty)
    }

    /// The card: what it is, what it carries, whether it runs today, and
    /// what it costs before its first day is settled.
    func testTheCardSaysWhatItCarriesAndWhetherItRuns() throws {
        let session = try makeSession()
        session.tapNetwork(at: middle(row: 2, column: 2), reach: 0)
        session.tapNetwork(at: middle(row: 2, column: 12), reach: 0)
        XCTAssertTrue(session.buildCableway())
        let card = try XCTUnwrap(session.cablewayCard(CablewayID(rawValue: 1)))
        XCTAssertEqual(card.title, "Cable car 1")
        XCTAssertEqual(card.rows.first, "2 stations · 640 m · 2 min end to end")
        XCTAssertEqual(card.rows[1], "2,400 people an hour each way · \(Cableway.fare.moneyText) a ride")
        let today = session.world.clock.now.seconds / GameTime.secondsPerDay
        XCTAssertEqual(card.runs, session.world.cablewayIsOpen(CablewayID(rawValue: 1), onDay: today))
        XCTAssertEqual(card.rows.last, "Costs \(Money(640 * 500).moneyText) a day to run")
        XCTAssertNil(session.cablewayCard(CablewayID(rawValue: 2)))
    }

    // MARK: - Cabins

    private func maokongShaped() throws -> Cableway {
        var world = try makeWorld(width: 64 * Self.cell, height: 64 * Self.cell, balance: Money(10_000_000_000))
        return try world.createCableway(
            stops: [
                CablewayStop(cell: CellPosition(row: 1, column: 1)), CablewayStop(cell: CellPosition(row: 1, column: 12), boards: false),
                CablewayStop(cell: CellPosition(row: 5, column: 18)), CablewayStop(cell: CellPosition(row: 8, column: 26), boards: false),
                CablewayStop(cell: CellPosition(row: 25, column: 24)), CablewayStop(cell: CellPosition(row: 42, column: 22))
            ],
            legMetres: RealCableway.maokong.legMetres
        )
    }

    /// Maokong's 4,033 m: spans of 166, 88, 114, 223 and 218 s (rounded
    /// up at 5 m/s), 809 s each way, and 60 s at each of five stops each
    /// way: 2,218 s round, 184 cabins at 12 s.
    func testTheLoopAndTheCabinCount() throws {
        let maokong = try maokongShaped()
        XCTAssertEqual(CablewayCabins.loopSeconds(of: maokong), 2 * 809 + 2 * 5 * 60)
        XCTAssertEqual(CablewayCabins.count(of: maokong), 184)
        let cabins = CablewayCabins.cabins(of: maokong, atSecond: 0, open: true)
        XCTAssertEqual(cabins.count, 184)
        XCTAssertEqual(Set(cabins.map(\.number)).count, 184)
        XCTAssertEqual(cabins.filter(\.crystal).count, 42, "two in nine")
        XCTAssertEqual(cabins[0].place, .span(leg: 0, permille: 0, outbound: true))
        // Cabin 1 is 12 s behind: 12 s before the loop's end, turning at
        // the first stop.
        XCTAssertEqual(cabins[1].place, .station(stop: 0, outbound: true))
        // Cabin 6 is 72 s behind: 154 s into the 166 s back down span 0,
        // 12 s from the first stop.
        XCTAssertEqual(cabins[6].place, .span(leg: 0, permille: 1_000 - 154 * 1_000 / 166, outbound: false))
    }

    /// The same cabin moves along: out on span 0, through the angle
    /// station, on; and comes round again after the loop.
    func testACabinMovesAlongTheLoop() throws {
        let maokong = try maokongShaped()
        func place(_ second: Int64) -> CablewayCabins.Place {
            CablewayCabins.cabins(of: maokong, atSecond: second, open: true)[0].place
        }
        XCTAssertEqual(place(83), .span(leg: 0, permille: 500, outbound: true))
        XCTAssertEqual(place(166), .station(stop: 1, outbound: true))
        XCTAssertEqual(place(226), .span(leg: 1, permille: 0, outbound: true))
        XCTAssertEqual(place(809 + 4 * 60), .station(stop: 5, outbound: false), "turning at the top")
        XCTAssertEqual(place(809 + 5 * 60), .span(leg: 4, permille: 1_000, outbound: false))
        XCTAssertEqual(place(2_218 + 83), place(83))
        let middle = CablewayCabins.planPoint(of: .span(leg: 0, permille: 500, outbound: true), in: maokong)
        let a = maokong.stops[0].cell, b = maokong.stops[1].cell
        XCTAssertEqual(middle.x, (Int64(a.column) + Int64(b.column)) * Self.cell / 2 + Self.cell / 2)
    }

    /// Standing still, every cabin is put away at an end, half at each.
    func testStandingStillTheCabinsAreAtTheEnds() throws {
        let maokong = try maokongShaped()
        let cabins = CablewayCabins.cabins(of: maokong, atSecond: 500, open: false)
        XCTAssertEqual(cabins.filter { $0.place == .station(stop: 0, outbound: true) }.count, 92)
        XCTAssertEqual(cabins.filter { $0.place == .station(stop: 5, outbound: false) }.count, 92)
    }

    // MARK: - Maokong

    /// On a map of Muzha, the mode offers the Maokong Gondola and lays its
    /// six stops with the real spans: 4,033 m, 17 minutes end to end.
    func testTheMaokongGondolaIsOfferedOnAMapOfMuzha() throws {
        var world = try makeWorld(width: 128 * Self.cell, height: 128 * Self.cell, balance: Money(10_000_000_000))
        world.setEconomyMode(.management)
        world.setGeoAnchor(try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.9825, longitudeDegrees: 121.584)))
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTool(.network)
        session.setNetworkMode(.cableway)
        let offer = try XCTUnwrap(session.realCablewayOffer)
        XCTAssertEqual(offer.name, "貓空纜車")
        XCTAssertEqual(offer.legMetres.reduce(0, +), 4_033, "gondola.taipei")
        session.traceRealCableway(offer)
        XCTAssertNil(session.realCablewayOffer, "not while one is drawn")
        XCTAssertEqual(session.cablewayDraft.map(\.boards), [true, false, true, false, true, true])
        let preview = try XCTUnwrap(session.cablewayPreview)
        XCTAssertNil(preview.problem)
        XCTAssertEqual(preview.metres, 4_033)
        XCTAssertEqual(preview.rideMinutes, 17)
        XCTAssertEqual(session.networkDraftText(), "4 站 · 4,033 公尺 · 全程 17 分")
        // The stops lie where the line runs: Maokong some 3 km south of
        // the zoo, and Zhinan Temple to the east of it.
        let stops = session.cablewayDraft
        XCTAssertGreaterThan(stops[5].cell.row - stops[0].cell.row, 40)
        XCTAssertGreaterThan(stops[4].cell.column, stops[0].cell.column)
        XCTAssertTrue(session.buildCableway())
        XCTAssertNil(session.realCablewayOffer, "not once it is built")
    }

    /// Off the Earth, or with Maokong off the map, nothing is offered.
    func testNoOfferOffTheMap() throws {
        let session = try makeSession()
        XCTAssertNil(session.realCablewayOffer)
        var far = try makeWorld(width: 64 * Self.cell, height: 64 * Self.cell)
        far.setGeoAnchor(try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.6, longitudeDegrees: 120.3)))
        XCTAssertNil(RealCableway.maokong.stops(in: far))
    }
}
