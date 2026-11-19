import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 862: the real lines for sale that share a station are sold
/// together, in one purchase, laid in the order the game lists them.
@MainActor
final class RealLineBundleTests: XCTestCase {
    // MARK: - Which lines go together

    /// Two lines of one system with a stop of the same name go together,
    /// and a third joins two that share nothing; the same name in another
    /// system joins nothing.
    func testLinesThatShareAStopOfTheirSystemGoTogether() {
        let groups = RealLineBundle.groups(of: [
            ("a", ["one", "two"]), ("a", ["five", "six"]), ("b", ["two", "three"]), ("a", ["two", "four"]), ("a", ["four", "five"]),
            ("b", ["nine"]),
        ])
        XCTAssertEqual(groups, [0, 0, 2, 0, 0, 5], "the first, fourth, fifth and (through the fifth) second of system a; b's two alone")
        XCTAssertEqual(RealLineBundle.groups(of: []), [])
    }

    private func bundles(of session: GameSession) -> [[String]] {
        session.realLineBundles.map { $0.lines.map(\.id) }
    }

    /// Every line on sale is in one bundle, in the order of the list.
    private func checkEveryLineIsSoldOnce(_ session: GameSession, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(bundles(of: session).flatMap { $0 }.sorted(), session.buyableRealLines.map(\.id).sorted(), file: file, line: line)
        // A line with a timetable from where it leaves another (decision
        // 400) is laid after that one.
        guard let railways = session.railways else { return XCTFail("no railways", file: file, line: line) }
        for bundle in session.realLineBundles {
            for (index, later) in bundle.lines.enumerated() {
                for earlier in bundle.lines[..<index] {
                    XCTAssertNil(railways.metroRuns["\(earlier.id) after \(later.id)"], "\(earlier.id) is cut after \(later.id), listed after it", file: file, line: line)
                }
            }
        }
    }

    /// The bundles of each map, worked out from the lines' stops: the
    /// same groups the timetable checkup plays
    /// (`TimetableCheckupAllBoughtTests`), each in the order it is laid.
    func testEveryMapSellsItsLinesThatShareAStationTogether() throws {
        let taiwan = try TimetableCheckupAllBoughtTests.wholeTaiwan(rules: .simple)
        checkEveryLineIsSoldOnce(taiwan)
        XCTAssertEqual(bundles(of: taiwan).filter { $0.count > 1 }, [["tra:LIUJIA", "tra:NEIWAN"], ["ntdlrt:V", "ntdlrt:VB"]])
        XCTAssertEqual(taiwan.realLineBundles.count, 13, "15 lines, two pairs")

        let hongKong = try HongKongMapTests.hongKong()
        checkEveryLineIsSoldOnce(hongKong)
        XCTAssertEqual(bundles(of: hongKong).filter { $0.count > 1 }, [["hkmtr:TCL", "hkmtr:AEL", "hkmtr:DRL"]])

        let rovaniemi = try RovaniemiRailwaysTests.rovaniemi()
        checkEveryLineIsSoldOnce(rovaniemi)
        XCTAssertEqual(bundles(of: rovaniemi), [["vr:KJA", "vr:MUL"]])

        // Fukuoka (not open yet): the Kuko Line, which runs through both
        // stations it shares, first.
        let fukuoka = try FukuokaRailwaysTests.fukuoka()
        checkEveryLineIsSoldOnce(fukuoka)
        XCTAssertEqual(bundles(of: fukuoka), [["fksubway:K", "fksubway:H", "fksubway:N"]])
    }

    func testABundleIsNamedAfterItsFirstLine() throws {
        let session = try HongKongMapTests.hongKong()
        let airport = try XCTUnwrap(session.realLineBundles.first { !$0.isSingle })
        XCTAssertEqual(airport.title(in: .traditionalChinese), "機場快綫等 3 條路線")
        XCTAssertEqual(airport.title(in: .english), "Airport Express and 2 more")
        XCTAssertEqual(airport.togetherText(in: .traditionalChinese), "這幾條線共用車站，一起收購：機場快綫、東涌綫、迪士尼綫。")
        XCTAssertEqual(session.realLineBundle(of: airport.lines[2]), airport, "opened from any of its lines")
        let alone = try XCTUnwrap(session.realLineBundles.first { $0.isSingle })
        XCTAssertEqual(alone.title(in: .traditionalChinese), alone.first.name(in: .traditionalChinese))
        XCTAssertNil(alone.togetherText(in: .traditionalChinese))
        // The list has a row a bundle.
        XCTAssertEqual(session.realLineListings.map(\.bundle.id).sorted(), session.realLineBundles.map(\.id).sorted())
    }

    // MARK: - Bought together

    /// Buys the lines `ids` one at a time, in that order, as before
    /// decision 862; what each cost.
    private func buyOneByOne(_ ids: [String], in session: GameSession, file: StaticString = #filePath, line: UInt = #line) throws -> [RealLineOffer] {
        try ids.map { id in
            let listed = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, "\(id) on sale", file: file, line: line)
            let offer = session.realLineOffer(for: listed)
            XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(offer.problem ?? session.message?.text ?? "")", file: file, line: line)
            return offer
        }
    }

    /// A bundle bought is the world its lines bought one after another in
    /// its order leave, for the same price: the one purchase lays nothing
    /// its own way.
    private func checkABundleIsItsLinesOneAfterAnother(
        _ name: String, _ open: () throws -> GameSession, holding id: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let together = try open(), oneByOne = try open()
        let bundle = try XCTUnwrap(together.realLineBundles.first { $0.lines.contains { $0.id == id } }, name, file: file, line: line)
        XCTAssertGreaterThan(bundle.lines.count, 1, name, file: file, line: line)
        let before = together.world.economy.balance
        let offer = together.realLineBundleOffer(for: bundle)
        XCTAssertNil(offer.problem, "\(name): \(offer.problemText(in: .traditionalChinese) ?? "")", file: file, line: line)
        XCTAssertEqual(offer.offers.map(\.line.id), bundle.lines.map(\.id), name, file: file, line: line)
        XCTAssertTrue(together.acquireRealLines(offer), "\(name): \(together.message?.text ?? "")", file: file, line: line)
        XCTAssertNil(together.shownRealLineOffer, file: file, line: line)

        let single = try buyOneByOne(bundle.lines.map(\.id), in: oneByOne, file: file, line: line)
        XCTAssertEqual(offer.acquisitions, single.compactMap(\.acquisition), "\(name): each line laid as bought after those before it", file: file, line: line)
        XCTAssertEqual(offer.price?.total, single.compactMap(\.price?.total).reduce(.zero, +), name, file: file, line: line)
        XCTAssertEqual(before - together.world.economy.balance, try XCTUnwrap(offer.price?.total), "\(name): charged what the card said", file: file, line: line)
        XCTAssertTrue(together.world == oneByOne.world, "\(name): the same world as the lines bought one after another", file: file, line: line)

        // One entry in the log, and one step back.
        XCTAssertEqual(together.commandLog.entries.filter { if case .command(.acquireRealLines) = $0.action { true } else { false } }.count, 1, file: file, line: line)
        let card = try XCTUnwrap(together.lastLineAcquired, file: file, line: line)
        XCTAssertEqual(card.with.count, bundle.lines.count - 1, file: file, line: line)
        XCTAssertEqual(card.sizeTexts(in: .traditionalChinese).count, bundle.lines.count, file: file, line: line)
        XCTAssertEqual(card.endsText(in: .traditionalChinese), "\(bundle.lines.count) 條路線", file: file, line: line)
        together.undo()
        for sold in bundle.lines {
            XCTAssertNil(together.world.acquisition(of: sold.id), "\(name): Undo takes back \(sold.id)", file: file, line: line)
        }
    }

    func testRovaniemisTwoLinesAreBoughtAsOneAfterTheOther() throws {
        try checkABundleIsItsLinesOneAfterAnother("rovaniemi", { try RovaniemiRailwaysTests.rovaniemi() }, holding: "vr:KJA")
    }

    func testDanhaisTwoLinesAreBoughtAsOneAfterTheOther() throws {
        try checkABundleIsItsLinesOneAfterAnother(
            "danhai", { try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true, rules: .simple) }, holding: "ntdlrt:VB"
        )
    }

    func testLiujiaAndNeiwanAreBoughtAsOneAfterTheOther() throws {
        try checkABundleIsItsLinesOneAfterAnother(
            "zhuzhong", { try RealLineAcquisitionTests.game(round: "NEIWAN", side: 1 << 21, heights: true, rules: .simple) }, holding: "tra:LIUJIA"
        )
    }

    func testHongKongsThreeLinesToTheAirportAreBoughtAsOneAfterAnother() throws {
        try checkABundleIsItsLinesOneAfterAnother("hong kong", { try HongKongMapTests.hongKong() }, holding: "hkmtr:TCL")
    }

    /// The Blue Coast Line bought with the Green Mountain Line is laid
    /// from where they part (decision 489), as bought after it.
    func testALineSharingItsFirstStationsIsSoldFromWhereTheyPart() throws {
        let session = try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true, rules: .simple)
        let bundle = try XCTUnwrap(session.realLineBundles.first { !$0.isSingle })
        XCTAssertEqual(bundle.lines.map(\.id), ["ntdlrt:V", "ntdlrt:VB"])
        XCTAssertEqual(bundle.lines.map(\.stops.count), [11, 12], "each listed whole")
        let offer = session.realLineBundleOffer(for: bundle)
        XCTAssertEqual(offer.offers.map(\.line.after), [nil, "ntdlrt:V"])
        XCTAssertEqual(offer.offers.last?.line.stops, ["濱海沙崙", "台北海洋大學", "沙崙", "淡水漁人碼頭"])
        let rows = offer.lineRows(in: .traditionalChinese)
        XCTAssertEqual(rows.map(\.name), ["淡海輕軌綠山線", "淡海輕軌藍海線"])
        XCTAssertEqual(rows.compactMap(\.price).reduce(.zero, +), offer.price?.total)
        let prices = offer.priceRows(in: .traditionalChinese)
        XCTAssertEqual(prices.map(\.label).suffix(2), ["沿線的常客", "合計"])
        XCTAssertEqual(prices.dropLast().map(\.amount).reduce(.zero, +), prices.last?.amount)
        XCTAssertEqual(prices.last?.amount, offer.price?.total)
        // Beside Buy, the price of both; one line's card has none.
        XCTAssertEqual(offer.totalText(in: .traditionalChinese), "2 條路線合計 \(try XCTUnwrap(offer.price?.total).moneyText)")
        XCTAssertEqual(offer.totalText(in: .english), "2 lines, \(try XCTUnwrap(offer.price?.total).moneyText) in all")
        let alone = RealLineBundleOffer(bundle: RealLineBundle([bundle.first]), offers: [offer.offers[0]])
        XCTAssertNotNil(alone.price)
        XCTAssertNil(alone.totalText(in: .traditionalChinese))
    }

    // MARK: - A game that already has one of them

    /// A game that bought one line of a group before decision 862 keeps
    /// it as it is, and is sold the rest of the group together.
    func testAGameWithOneLineOfAGroupIsSoldTheRestTogether() throws {
        let session = try HongKongMapTests.hongKong()
        _ = try buyOneByOne(["hkmtr:TCL"], in: session)
        let kept = session.world
        XCTAssertEqual(bundles(of: session).filter { $0.count > 1 }, [["hkmtr:AEL", "hkmtr:DRL"]], "both meet the line bought")
        checkEveryLineIsSoldOnce(session)
        let rest = try XCTUnwrap(session.realLineBundles.first { !$0.isSingle })
        let offer = session.realLineBundleOffer(for: rest)
        XCTAssertTrue(session.acquireRealLines(offer), offer.problemText(in: .traditionalChinese) ?? session.message?.text ?? "")
        for id in ["hkmtr:AEL", "hkmtr:TCL", "hkmtr:DRL"] {
            let line = try XCTUnwrap(session.world.acquisition(of: id)?.line.flatMap { session.world.line(id: $0) }, id)
            XCTAssertFalse(line.assignedTrains.isEmpty, id)
        }
        XCTAssertTrue(session.realLineBundles.allSatisfy(\.isSingle))
        // What it had is where it was.
        let tungChung = try XCTUnwrap(kept.acquisition(of: "hkmtr:TCL")?.line)
        XCTAssertEqual(session.world.line(id: tungChung)?.stops, kept.line(id: tungChung)?.stops)
        for platform in try XCTUnwrap(kept.line(id: tungChung)).stops.flatMap({ kept.network.platforms(of: $0) }) {
            XCTAssertTrue(session.world.network.platforms(of: platform.station).contains(platform))
        }

        // One of two bought: the other is sold alone, as before.
        let danhai = try RealLineAcquisitionTests.game(round: "ntdlrt:V", side: 1 << 21, heights: true, rules: .simple)
        _ = try buyOneByOne(["ntdlrt:VB"], in: danhai)
        XCTAssertEqual(bundles(of: danhai).filter { $0.contains("ntdlrt:V") }, [["ntdlrt:V"]])
    }

    // MARK: - All or none

    /// A bundle one of whose lines cannot be built buys none of them: the
    /// command is refused whole.
    func testABundleOneLineOfWhichIsRefusedBuysNone() throws {
        let session = try RovaniemiRailwaysTests.rovaniemi()
        let bundle = try XCTUnwrap(session.realLineBundles.first)
        let offer = session.realLineBundleOffer(for: bundle)
        let acquisitions = try XCTUnwrap(offer.acquisitions)
        let before = session.world
        // The first line twice: built once, refused the second time.
        XCTAssertThrowsError(try session.performCommand(.acquireRealLines([acquisitions[0], acquisitions[0]])))
        XCTAssertTrue(session.world == before, "nothing bought")
        XCTAssertEqual(session.commandLog.entries.last?.refused, true)

        // And an offer a line of which could not be laid out buys nothing.
        let refused = RealLineBundleOffer(bundle: bundle, offers: [
            offer.offers[0], RealLineOffer(line: bundle.lines[1], acquisition: nil, price: nil, problem: "不行"),
        ])
        XCTAssertNil(refused.acquisitions)
        XCTAssertNil(refused.price)
        XCTAssertEqual(refused.priceRows(in: .traditionalChinese).count, 0)
        XCTAssertNil(refused.totalText(in: .traditionalChinese))
        XCTAssertEqual(refused.problemText(in: .traditionalChinese), "羅瓦涅米—穆羅拉：不行")
        XCTAssertFalse(session.acquireRealLines(refused))
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertTrue(session.world == before)
    }

    /// The log reads the command back (decision 193).
    func testTheCommandIsReadBackFromTheLog() throws {
        let session = try RovaniemiRailwaysTests.rovaniemi()
        let acquisitions = try XCTUnwrap(session.realLineBundleOffer(for: try XCTUnwrap(session.realLineBundles.first)).acquisitions)
        let command = PlayerCommand.acquireRealLines(acquisitions)
        XCTAssertEqual(command.name, "acquireRealLines")
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command)), command)
    }

    // MARK: - The land that reaches any of them

    /// On a map bought tile by tile, a bundle is bought from the land
    /// that reaches any of its lines: that one is laid first, and its
    /// land reaches the others. From Neiwan, the far end of the Neiwan
    /// Line, the Liujia Line (listed first) is out of reach on its own.
    func testTheLandThatReachesOneLineBuysTheBundle() async throws {
        let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        let neiwan = try BundledRealData.station("內灣", in: "tra_sched").coordinate
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: neiwan.latitude, longitudeDegrees: neiwan.longitude))
        var world = GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
            population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
        ))
        world.setUnlimitedFunds(true)
        XCTAssertNotNil(world.mapExpansion, "bought tile by tile")
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        session.coverage = data.coverage
        session.railways = data.railways

        let bundle = try XCTUnwrap(session.realLineBundles.first { $0.lines.contains { $0.id == "tra:NEIWAN" } })
        XCTAssertEqual(bundle.lines.map(\.id), ["tra:LIUJIA", "tra:NEIWAN"])
        let liujia = session.realLineOffer(for: bundle.first)
        try XCTSkipIf(liujia.problem != GameSession.landProblem(in: .traditionalChinese), "the first tile reaches the Liujia Line too")

        session.refreshRealLineAvailability()
        await session.realLineAvailabilityChecked()
        XCTAssertTrue(session.realLineOutOfReach.contains("tra:LIUJIA"))
        let listing = try XCTUnwrap(session.realLineListings.first { $0.bundle == bundle })
        XCTAssertTrue(listing.isBuyable, "its other line is within reach")

        let offer = session.realLineBundleOffer(for: bundle)
        XCTAssertNil(offer.problem, offer.problemText(in: .traditionalChinese) ?? "")
        XCTAssertEqual(offer.offers.map(\.line.id), ["tra:NEIWAN", "tra:LIUJIA"], "the line the land reaches first")
        XCTAssertTrue(session.acquireRealLines(offer), session.message?.text ?? "")
        XCTAssertNotNil(session.world.acquisition(of: "tra:LIUJIA"))
        XCTAssertNotNil(session.world.acquisition(of: "tra:NEIWAN"))
    }
}
