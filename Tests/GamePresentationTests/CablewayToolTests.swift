import Foundation
import GameCore
@testable import GamePresentation
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
            .createCableway(stops: [CablewayStop(cell: CellPosition(row: 1, column: 2))], legMetres: [827], meetsNear: PlanPoint(x: 5, y: 7)),
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

    /// Decision 586: with the Wenhu Line bought, the Maokong Gondola laid
    /// as it is meets MRT Taipei Zoo, where riders change, not Muzha, the
    /// nearer; both are beyond the 400 m a cable car finds a station in.
    func testTheMaokongGondolaMeetsTaipeiZoo() throws {
        let session = try RealLineAcquisitionTests.game(round: "trtc:BR", side: 1 << 21)
        let wenhu = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:BR" }, "on sale")
        let offer = session.realLineOffer(for: wenhu)
        XCTAssertTrue(session.acquireRealLine(offer), offer.problem ?? session.message?.text ?? "")
        let stops = try XCTUnwrap(RealCableway.maokong.stops(in: session.world))
        var plain = session.world
        let nearest = try plain.createCableway(stops: stops, legMetres: RealCableway.maokong.legMetres)
        XCTAssertNil(plain.cableway(id: nearest.id)?.transfer, "no station within 400 m")
        session.selectTool(.network)
        session.setNetworkMode(.cableway)
        session.traceRealCableway(try XCTUnwrap(session.realCablewayOffer))
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        let transfer = try XCTUnwrap(session.world.cableways.last?.transfer)
        XCTAssertEqual(session.world.station(id: transfer.station)?.name, "動物園")
        XCTAssertEqual(transfer.stop, 0, "at the gondola's Taipei Zoo stop")
    }

    // MARK: - Decision 870: every real cable car

    /// A game on the Earth round `latitude`, `longitude`, `cells` land
    /// cells a side, in the cable car mode.
    private func realSession(latitude: Double, longitude: Double, cells: Int64 = 128) throws -> GameSession {
        var world = try makeWorld(width: cells * Self.cell, height: cells * Self.cell, balance: Money(10_000_000_000))
        world.setEconomyMode(.management)
        world.setGeoAnchor(try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTool(.network)
        session.setNetworkMode(.cableway)
        return session
    }

    /// On a map of Sun Moon Lake the mode offers the ropeway and lays its
    /// two stations with the real span, 1,860 m; once built it is the
    /// real one, with its stops' names and Sun Moon Lake's cabins.
    func testTheSunMoonLakeRopewayIsOffered() throws {
        let session = try realSession(latitude: 23.8562, longitude: 120.9429)
        XCTAssertEqual(session.realCablewayOffers.map(\.name), ["日月潭纜車"])
        session.traceRealCableway(try XCTUnwrap(session.realCablewayOffer))
        XCTAssertEqual(session.realCablewayOffers, [], "not while one is drawn")
        let preview = try XCTUnwrap(session.cablewayPreview)
        XCTAssertNil(preview.problem)
        XCTAssertEqual(preview.stations, 2)
        XCTAssertEqual(preview.metres, 1_860)
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        XCTAssertEqual(session.realCablewayOffers, [], "not once it is built")
        let built = try XCTUnwrap(session.world.cableways.last)
        XCTAssertEqual(RealCableway.matching(built, in: session.world), .sunMoonLake)
        XCTAssertEqual(Map3DCableways.look(of: built, in: session.world), .sunMoonLake)
    }

    /// On a map of Wulai the mode offers the Wulai cable car: two stations
    /// 381 m apart, on different land cells, the upper one to the south-east.
    func testTheWulaiCableCarIsOffered() throws {
        let session = try realSession(latitude: 24.8475, longitude: 121.5522, cells: 64)
        XCTAssertEqual(session.realCablewayOffers.map(\.name), ["烏來空中纜車"])
        session.traceRealCableway(.wulai)
        let stops = session.cablewayDraft
        XCTAssertEqual(stops.map(\.boards), [true, true])
        XCTAssertGreaterThan(stops[1].cell.row, stops[0].cell.row, "south")
        XCTAssertGreaterThan(stops[1].cell.column, stops[0].cell.column, "east")
        let preview = try XCTUnwrap(session.cablewayPreview)
        XCTAssertNil(preview.problem)
        XCTAssertEqual(preview.metres, 381)
        XCTAssertEqual(session.networkDraftText(), "2 站 · 381 公尺 · 全程 1 分")
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        XCTAssertEqual(RealCableway.matching(try XCTUnwrap(session.world.cableways.last), in: session.world), .wulai)
        // Decision 930: drawn as an aerial tramway, two cabins half the
        // loop apart: one on its way up as the other comes down, one at
        // each end while it stands still; a cabin of another number is
        // none of its.
        let built = try XCTUnwrap(session.world.cableways.last)
        XCTAssertEqual(Map3DCableways.look(of: built, in: session.world), .wulai)
        XCTAssertTrue(Map3DCableways.CabinLook.wulai.isPair)
        XCTAssertFalse(Map3DCableways.CabinLook.maokong.isPair)
        let pair = CablewayCabins.numbers(of: built, pair: true)
        XCTAssertEqual(pair, [0, 11])
        XCTAssertEqual(CablewayCabins.numbers(of: built, pair: false), Array(0..<22))
        XCTAssertEqual(session.world.cabinNumbers(of: built), pair)
        // REVIEW-L33: Wulai's green cabin 0 is no crystal cabin (no glass
        // floor), though cabin 0 of a gondola is.
        XCTAssertTrue(CablewayCabins.isCrystal(0, pair: false))
        XCTAssertFalse(pair.contains { CablewayCabins.isCrystal($0, pair: true) })
        guard case .span(_, let up, let outbound) = CablewayCabins.glide(of: pair[0], on: built, atSecond: 40),
              case .span(_, let down, let back) = CablewayCabins.glide(of: pair[1], on: built, atSecond: 40) else { return XCTFail("both out on the span") }
        XCTAssertTrue(outbound)
        XCTAssertFalse(back)
        XCTAssertEqual(up + (1 - down), 1, accuracy: 0.15, "they pass at about the middle")
        let standing = CablewayCabins.cabins(of: built, atSecond: 0, open: false).filter { pair.contains($0.number) }.map(\.place)
        XCTAssertEqual(Set(standing), [.station(stop: 0, outbound: true), .station(stop: 1, outbound: false)])
        XCTAssertEqual(session.realCablewayOffers, [])
    }

    /// A map with Maokong and Wulai both on it offers both, the one nearer
    /// the middle of the map first, and building one leaves the other.
    func testAMapWithTwoRealCableCarsOffersBothNearestFirst() throws {
        // Wulai is some 16 km south of Maokong: a map 512 cells (32.8 km)
        // a side holds both, its middle nearer Wulai's.
        let session = try realSession(latitude: 24.90, longitude: 121.57, cells: 512)
        XCTAssertEqual(session.realCablewayOffers.map(\.name), ["烏來空中纜車", "貓空纜車"])
        XCTAssertEqual(session.realCablewayOffer, .wulai)
        session.traceRealCableway(.maokong)
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        XCTAssertEqual(session.realCablewayOffers.map(\.name), ["烏來空中纜車"])
        session.traceRealCableway(.wulai)
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        XCTAssertEqual(session.realCablewayOffers, [])
        XCTAssertEqual(session.world.cableways.count, 2)
    }

    // MARK: - Decision 872: Ngong Ping

    /// On a map of north Lantau the mode offers the Ngong Ping cable car:
    /// Tung Chung, two angle stations where the rope turns, Ngong Ping,
    /// 5,767 m, no span over what a cable car may span; Ngong Ping lies
    /// to the south-west of Tung Chung.
    func testTheNgongPingCableCarIsOffered() throws {
        let session = try realSession(latitude: 22.2735, longitude: 113.92, cells: 128)
        XCTAssertEqual(session.realCablewayOffers.map(\.name), ["昂坪纜車"])
        session.traceRealCableway(.ngongPing)
        let stops = session.cablewayDraft
        XCTAssertEqual(stops.map(\.boards), [true, false, false, true])
        XCTAssertGreaterThan(stops[3].cell.row - stops[0].cell.row, 50, "some 3.8 km south")
        XCTAssertGreaterThan(stops[0].cell.column - stops[3].cell.column, 50, "some 3.8 km west")
        XCTAssertGreaterThan(stops[0].cell.column, stops[1].cell.column, "first west, to Airport Island")
        let preview = try XCTUnwrap(session.cablewayPreview)
        XCTAssertNil(preview.problem)
        XCTAssertEqual(preview.stations, 2)
        XCTAssertEqual(preview.metres, 5_767)
        XCTAssertEqual(RealCableway.ngongPing.legMetres, [619, 3_575, 1_573])
        // No station of the company's is there to meet: the place given
        // (MTR Tung Chung) is within reach of the first stop all the same.
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        let built = try XCTUnwrap(session.world.cableways.last)
        XCTAssertEqual(RealCableway.matching(built, in: session.world), .ngongPing)
        // Decision 897: its own cabins, not Maokong's.
        XCTAssertEqual(Map3DCableways.look(of: built, in: session.world), .ngongPing)
        XCTAssertEqual(session.realCablewayOffers, [])
    }

    /// With the Tung Chung Line bought, the cable car laid as it is meets
    /// MTR Tung Chung at its Tung Chung stop.
    func testTheNgongPingCableCarMeetsTungChung() throws {
        let session = try RealLineAcquisitionTests.game(round: "hkmtr:TCL", side: 1 << 22)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:TCL" }, "on sale")
        let offer = session.realLineOffer(for: line)
        XCTAssertTrue(session.acquireRealLine(offer), offer.problem ?? session.message?.text ?? "")
        session.selectTool(.network)
        session.setNetworkMode(.cableway)
        XCTAssertTrue(session.realCablewayOffers.contains(.ngongPing))
        session.traceRealCableway(.ngongPing)
        XCTAssertNil(session.cablewayPreview?.problem)
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        let transfer = try XCTUnwrap(session.world.cableways.last?.transfer)
        XCTAssertEqual(session.world.station(id: transfer.station)?.name, "東涌")
        XCTAssertEqual(transfer.stop, 0, "at the cable car's Tung Chung stop")
    }

    // MARK: - Decision 880: the sights' visitors ride

    /// ``realSession(latitude:longitude:cells:)`` with Taiwan's sights on
    /// the map, as a new game has them.
    private func sightsSession(latitude: Double, longitude: Double, cells: Int64 = 128) throws -> GameSession {
        var world = try makeWorld(width: cells * Self.cell, height: cells * Self.cell, balance: Money(10_000_000_000))
        world.setEconomyMode(.management)
        world.setGeoAnchor(try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
        world.setTourism(RealWorldFrame(world: world).map { AttractionCatalog.attractions(in: $0, bounds: world.bounds) })
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTool(.network)
        session.setNetworkMode(.cableway)
        return session
    }

    /// Plays `world` past the second midnight, so days 0 (a Monday) and 1
    /// are settled.
    private func playTwoDays(_ world: inout GameWorld) throws {
        world.setSpeed(.normal)
        while world.clock.now.seconds < 2 * GameTime.secondsPerDay + 60 { try world.advance(ticks: 60) }
    }

    /// The rides `cableway`'s sightseers take on `day`, by hand: of each
    /// sight's visitors `permille` thousandths, there and back.
    private func rides(_ sights: [Attraction], permille: Int64, in world: GameWorld, onDay day: Int64) -> Int64 {
        sights.reduce(0) { $0 + 2 * (world.visitorsExpected(for: $1, onDay: day) * permille / 1_000) }
    }

    /// The Sun Moon Lake Ropeway meets no railway and no one lives by it:
    /// the visitors of the lake (1.8 km from its lakeside station) and of
    /// the Formosan Aboriginal Culture Village at its other end ride it,
    /// a tenth of each, and the takings of a Tuesday pay its running many
    /// times over.
    func testTheSunMoonLakeRopewayCarriesTheLakesVisitors() throws {
        let session = try sightsSession(latitude: 23.8562, longitude: 120.9429)
        session.traceRealCableway(.sunMoonLake)
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        var world = session.world
        let built = try XCTUnwrap(world.cableways.last)
        XCTAssertNil(built.transfer)
        let sights = world.sights(ofCableway: built.id)
        XCTAssertEqual(sights.map(\.name), ["日月潭", "九族文化村"])
        XCTAssertEqual(built.sightseerPermille, 100)
        let tuesday = world.cablewaySightseerRides(built.id, onDay: 1)
        XCTAssertEqual(tuesday, rides(sights, permille: 100, in: world, onDay: 1))
        XCTAssertGreaterThan(tuesday, 500)
        XCTAssertEqual(session.cablewayCard(built.id)?.rows.contains("日月潭、九族文化村的遊客會來搭"), true)
        try playTwoDays(&world)
        let days = try XCTUnwrap(world.cableway(id: built.id)).days
        XCTAssertEqual(days.map(\.riders), [0, tuesday], "Monday it stands still")
        XCTAssertGreaterThan(days[1].fares, Money(days[1].cost.amount * 5))
    }

    /// The Wulai cable car, 381 m: Wulai's hot spring street is 1.7 km
    /// down the valley, and a quarter of the tenth (381 of 1,500 m) of its
    /// visitors come up for the ride, enough to pay its running.
    func testTheWulaiCableCarCarriesWulaisVisitors() throws {
        let session = try sightsSession(latitude: 24.8560, longitude: 121.5522, cells: 64)
        session.traceRealCableway(.wulai)
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        var world = session.world
        let built = try XCTUnwrap(world.cableways.last)
        let sights = world.sights(ofCableway: built.id)
        XCTAssertEqual(sights.map(\.name), ["烏來溫泉"])
        XCTAssertEqual(built.sightseerPermille, 25)
        let tuesday = world.cablewaySightseerRides(built.id, onDay: 1)
        XCTAssertEqual(tuesday, rides(sights, permille: 25, in: world, onDay: 1))
        try playTwoDays(&world)
        let days = try XCTUnwrap(world.cableway(id: built.id)).days
        XCTAssertEqual(days.map(\.riders), [0, tuesday])
        XCTAssertGreaterThan(days[1].fares, days[1].cost)
    }

    /// Hong Kong had no sights: a game saved before decision 880 gets the
    /// Tian Tan Buddha when it is opened, and the Ngong Ping cable car,
    /// with no line bought, carries a tenth of its visitors.
    func testAnOlderHongKongSaveGetsTheBuddhaAndTheCableCarItsVisitors() throws {
        let session = try realSession(latitude: 22.2735, longitude: 113.92, cells: 128)
        // Decision 894: and the other sights of Hong Kong on this map.
        XCTAssertEqual(session.world.tourism?.attractions.first?.name, "天壇大佛")
        XCTAssertEqual(session.world.tourism?.attractions.first?.kind, .landmark)
        session.traceRealCableway(.ngongPing)
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        var world = session.world
        let built = try XCTUnwrap(world.cableways.last)
        XCTAssertNil(built.transfer, "no line bought")
        let sights = world.sights(ofCableway: built.id)
        XCTAssertEqual(sights.map(\.name), ["天壇大佛"])
        let tuesday = world.cablewaySightseerRides(built.id, onDay: 1)
        XCTAssertEqual(tuesday, rides(sights, permille: 100, in: world, onDay: 1))
        XCTAssertEqual(session.cablewayCard(built.id)?.rows.contains("天壇大佛的遊客會來搭"), true)
        try playTwoDays(&world)
        let days = try XCTUnwrap(world.cableway(id: built.id)).days
        XCTAssertEqual(days.map(\.riders), [0, tuesday])
        XCTAssertGreaterThan(days[1].fares, days[1].cost)
        // Opened again, it keeps the sights it has.
        XCTAssertEqual(AttractionCatalog.withSights(world), world)
    }

    /// Only a free game on a map that had no sights gets them: a map of
    /// Taiwan without tourism (a demo that turned it off) stays without,
    /// and a new game in Hong Kong starts with the Buddha.
    func testOnlyAMapThatHadNoSightsGetsThem() throws {
        let taiwan = try realSession(latitude: 23.8562, longitude: 120.9429)
        XCTAssertNil(taiwan.world.tourism)
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 22.2735, longitudeDegrees: 113.92))
        let fresh = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 128 * Self.cell, height: 128 * Self.cell), land: [])
        XCTAssertEqual(fresh.tourism?.attractions.first?.englishName, "Tian Tan Buddha")
        XCTAssertLessThan(AttractionCatalog.hongKongSpots[0].stars, GameWorld.alertedSightStars)
    }

    /// A cable car with no station, no sight and no one living by it says
    /// so on its card.
    func testTheCardSaysWhenNoOneHasAReasonToRide() throws {
        let session = try realSession(latitude: 23.8562, longitude: 120.9429)
        session.traceRealCableway(.sunMoonLake)
        XCTAssertTrue(session.buildCableway(), session.message?.text ?? "")
        let id = try XCTUnwrap(session.world.cableways.last?.id)
        XCTAssertEqual(session.cablewayCard(id)?.rows.contains("附近沒有車站，也沒有景點：搭的人會很少"), true)
    }

    /// Each real cable car's spans are one fewer than its stops, within
    /// what a cable car may span, and no two share a first stop's place.
    func testEveryRealCableCarCanBeLaid() {
        for real in RealCableway.all {
            XCTAssertEqual(real.legMetres.count, real.stops.count - 1, real.name)
            XCTAssertTrue(real.legMetres.allSatisfy { (1...Cableway.maximumLegMetres).contains($0) }, real.name)
            XCTAssertTrue(real.stops.first?.boards == true && real.stops.last?.boards == true, real.name)
        }
        XCTAssertEqual(Set(RealCableway.all.map(\.name)).count, RealCableway.all.count)
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
