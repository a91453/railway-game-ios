import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 315: buying a real branch line on a real-world map, its track,
/// stations, trains and TRA's own timetable in one command.
@MainActor
final class RealLineAcquisitionTests: XCTestCase {
    /// A real-world game round the middle of `line`'s stations, with the
    /// bundled railways and `balance`.
    static func game(round network: String, balance: Money = Money(100_000_000_000), side: Int64 = 1 << 20, heights: Bool = false, transfers: Bool = false, rules: NewGameRules = .realistic) throws -> GameSession {
        let railways = try BundledRealData.railways()
        let runs = try XCTUnwrap(railways.branchRuns[network] ?? railways.metroRuns[network], network)
        let prefix = String(network.prefix { $0 != ":" })
        let system = railways.branchRuns[network] != nil ? "tra_sched" : prefix == "trtc" ? "mrt" : prefix
        let stations = try runs.stops.map { try BundledRealData.station($0, in: system) }
        let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
        let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        var world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: side, height: side), balance: balance, rules: rules)
        if heights { try world.mapGround() }
        if transfers { world.setRealTransfers(true) }
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = railways
        if heights { session.heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat")) }
        return session
    }

    private func line(_ network: String, in session: GameSession) throws -> RealBranchLine {
        try XCTUnwrap(session.buyableRealLines.first { $0.network == network }, "\(network) on sale")
    }

    /// Decision 528: the Pingxi Line bought, removed and bought again,
    /// over the track it left: the same riders and trains paid for, the
    /// stations it left not built again.
    func testThePingxiLineIsBoughtAgainAfterItIsRemoved() throws {
        let session = try Self.game(round: "PINGXI")
        let first = session.realLineOffer(for: try line("PINGXI", in: session))
        XCTAssertTrue(session.acquireRealLine(first), session.message?.text ?? "")
        session.selectLine(try XCTUnwrap(session.world.acquisition(of: "tra:PINGXI")?.line))
        session.removeSelectedLine()
        XCTAssertNil(session.world.acquisition(of: "tra:PINGXI"))
        let again = session.realLineOffer(for: try line("PINGXI", in: session))
        XCTAssertNotNil(again.acquisition?.clearing, again.problem ?? "")
        XCTAssertEqual(again.price?.riders, first.price?.riders)
        XCTAssertEqual(again.price?.trains, first.price?.trains)
        XCTAssertLessThan(try XCTUnwrap(again.price?.building), try XCTUnwrap(first.price?.building))
        XCTAssertTrue(session.acquireRealLine(again), session.message?.text ?? "")
        XCTAssertEqual(session.world.lines.count, 1)
        XCTAssertEqual(session.world.stations.count, 7)
    }

    func testThePingxiLineIsBoughtAsOneCommandAndRunsItsRealTrains() throws {
        let session = try Self.game(round: "PINGXI")
        let pingxi = try line("PINGXI", in: session)
        XCTAssertEqual(pingxi.stops, ["三貂嶺", "大華", "十分", "望古", "嶺腳", "平溪", "菁桐"])
        XCTAssertEqual(session.buyableRealLine(through: "十分"), pingxi)
        XCTAssertNil(session.buyableRealLine(through: "三貂嶺"), "the junction is the main line's")

        let offer = session.realLineOffer(for: pingxi)
        XCTAssertNil(offer.problem)
        let price = try XCTUnwrap(offer.price)
        let acquisition = try XCTUnwrap(offer.acquisition)
        print("Pingxi: building \(price.building.moneyText), trains \(price.trains.moneyText), riders \(price.riders.moneyText) (\(acquisition.dailyRiders) a day), total \(price.total.moneyText)")
        XCTAssertGreaterThan(price.building, .zero)
        XCTAssertGreaterThan(price.trains, .zero)
        XCTAssertEqual(price.riders, LineAcquisition.value(ofDailyRiders: acquisition.dailyRiders))
        XCTAssertGreaterThan(acquisition.dailyRiders, 0)
        XCTAssertEqual(acquisition.trains.count, 3)

        let before = session.world
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        XCTAssertEqual(heard.last, .lineAcquired)
        XCTAssertEqual(session.world.economy.balance, before.economy.balance - price.total)
        let bought = try XCTUnwrap(session.world.acquisition(of: "tra:PINGXI"))
        let line = try XCTUnwrap(session.world.line(id: try XCTUnwrap(bought.line)))
        XCTAssertEqual(line.stops.count, 7)
        XCTAssertEqual(line.trains.count, 3)
        XCTAssertFalse(session.buyableRealLines.contains(pingxi), "bought once")
        let card = try XCTUnwrap(session.lastLineAcquired)
        XCTAssertEqual(card.ends.from, "三貂嶺")
        XCTAssertEqual(card.ends.to, "菁桐")
        XCTAssertEqual(card.trains, 3)
        print(card.sizeText(in: .traditionalChinese), card.timetableText(in: .traditionalChinese))

        // One command, logged as itself; it codes and decodes to itself.
        guard case .command(let command)? = session.commandLog.entries.last?.action, case .acquireRealLine = command else {
            return XCTFail("logged as a purchase")
        }
        let data = try JSONEncoder().encode(command)
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: data), command)

        // Two days of the real timetable: each day every run goes.
        var world = session.world
        try world.advance(ticks: 2 * 24 * 60)
        let runDays = try XCTUnwrap(world.line(id: try XCTUnwrap(bought.line))?.runDays)
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        let missed = zip(line.runs, runDays).filter { run, day in
            run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
        }
        XCTAssertEqual(missed.count, 0, "runs not sent out yesterday: \(missed.count) of \(line.runs.count)")

        // Undo takes all of it back.
        session.undo()
        XCTAssertEqual(session.world, before)
    }

    /// Decision 327: removing a line bought sells its trains as removing
    /// any line does, wherever its timetable has them, and then its
    /// platforms and track come down. With the old command its trains
    /// stayed, standing in the way.
    func testRemovingALineBoughtSellsItsTrains() throws {
        let bought = try Self.game(round: "PINGXI")
        XCTAssertTrue(bought.acquireRealLine(bought.realLineOffer(for: try line("PINGXI", in: bought))), bought.message?.text ?? "")
        let id = try XCTUnwrap(bought.world.acquisition(of: "tra:PINGXI")?.line)
        var world = bought.world
        // The next day, to when one of its trains is out on a run.
        try world.advance(ticks: (24 + 6) * 60)
        let trains = try XCTUnwrap(world.line(id: id)?.assignedTrains)
        XCTAssertFalse(trains.isEmpty)
        for _ in 0..<(12 * 60) where !trains.contains(where: { world.train(id: $0)?.execution != nil }) {
            try world.advance(ticks: 1)
        }
        XCTAssertTrue(trains.contains { world.train(id: $0)?.execution != nil }, "some out on a run")
        let proceeds = trains.reduce(Money.zero) { $0 + world.trainSaleQuote($1) }

        func demolish(_ world: inout GameWorld) -> [GameError] {
            var refusals: [GameError] = []
            for platform in world.network.platforms {
                do throws(GameError) { try world.removeTrackPlatform(platform.station, on: platform.edge, from: platform.start) } catch { refusals.append(error) }
            }
            for edge in world.network.edges {
                do throws(GameError) { try world.removeTrackEdge(edge.id) } catch { refusals.append(error) }
            }
            return refusals
        }
        var old = world
        try old.removeLine(id)
        try old.advance(ticks: 24 * 60)
        XCTAssertFalse(demolish(&old).isEmpty, "the old command leaves its trains in the way")

        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectLine(id)
        XCTAssertEqual(session.selectedLineRemovalSale?.trains, trains.count)
        XCTAssertEqual(session.selectedLineRemovalSale?.proceeds, proceeds)
        session.removeSelectedLine()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(trains.allSatisfy { session.world.train(id: $0) == nil })
        XCTAssertEqual(session.world.economy.balance, world.economy.balance + proceeds)
        XCTAssertNil(session.world.acquisition(of: "tra:PINGXI"), "decision 528: on sale again")
        var after = session.world
        XCTAssertEqual(demolish(&after), [])
        XCTAssertTrue(after.network.edges.isEmpty)
    }

    /// Each line on sale, over the app's heights: bought, and two days of
    /// its real timetable run, every run sent out, under the app's simple
    /// rules (decision 258), where trains that met at a station of more
    /// than one track once waited there for good.
    func testEveryLineOnSaleIsBoughtOverTheRealGroundAndRunsItsDay() throws {
        for network in ["PINGXI", "SHENAO", "JIJI", "NEIWAN", "LIUJIA", "SHALUN"] {
            let session = try Self.game(round: network, side: 1 << 21, heights: true, rules: .simple)
            let line = try line(network, in: session)
            let offer = session.realLineOffer(for: line)
            XCTAssertNil(offer.problem, network)
            guard let price = offer.price, let acquisition = offer.acquisition else { continue }
            print("\(network): building \(price.building.moneyText), trains \(price.trains.moneyText) (\(acquisition.trains.count)), riders \(price.riders.moneyText) (\(acquisition.dailyRiders) a day), total \(price.total.moneyText)")
            XCTAssertTrue(session.acquireRealLine(offer), "\(network): \(session.message?.text ?? "")")
            var world = session.world
            let bought = try XCTUnwrap(world.acquisition(of: line.id))
            try world.advance(ticks: 2 * 24 * 60)
            let runs = try XCTUnwrap(world.line(id: try XCTUnwrap(bought.line)))
            let today = world.clock.now.seconds / GameTime.secondsPerDay
            let missed = zip(runs.runs, runs.runDays).filter { run, day in
                run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
            }
            XCTAssertEqual(missed.count, 0, "\(network): runs not sent out yesterday: \(missed.count) of \(runs.runs.count)")
        }
    }

    /// BUGHUNT_BUILD P3-3: a depot of the player's nearer the junction
    /// than any station is not taken as the line's junction station (the
    /// purchase was refused, a depot being no line's stop).
    func testADepotByTheJunctionIsNotTheJunctionStation() throws {
        let scratch = try Self.game(round: "NEIWAN", side: 1 << 21)
        let neiwan = try line("NEIWAN", in: scratch)
        XCTAssertTrue(scratch.acquireRealLine(scratch.realLineOffer(for: neiwan)), scratch.message?.text ?? "")
        let junction = try XCTUnwrap(scratch.world.stations.first { $0.name == neiwan.stops[0] }, neiwan.stops[0]).location

        var world = try Self.game(round: "NEIWAN", side: 1 << 21).world
        let depot = try world.buildStation(named: "機廠", at: PlanPoint(x: junction.x + 100 * WorldCoordinate.unitsPerMetre, y: junction.y))
        try world.setStationDepot(depot.id, to: true)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = scratch.railways
        let offer = session.realLineOffer(for: try line("NEIWAN", in: session))
        XCTAssertNil(offer.problem)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        let bought = try XCTUnwrap(session.world.line(id: try XCTUnwrap(session.world.acquisition(of: neiwan.id)?.line)))
        XCTAssertFalse(bought.stops.contains(depot.id))
        XCTAssertEqual(session.world.station(id: depot.id)?.isDepot, true)
    }

    /// Decision 462: the Liujia and Neiwan Lines part at Zhuzhong, the
    /// Liujia Line's platforms up on its viaduct and the Neiwan Line's on
    /// the ground. Either is bought after the other, in either order: one
    /// station of both, its riders changing between them, each line with
    /// platforms of its own, the Liujia Line's at least the clearance of
    /// crossing track over the Neiwan Line's, and both run their day.
    /// Before, the second was refused, its track crossing the first's
    /// level at Zhuzhong.
    func testTheLiujiaAndNeiwanLinesAreBothBoughtThroughZhuzhong() throws {
        for order in [["LIUJIA", "NEIWAN"], ["NEIWAN", "LIUJIA"]] {
            let session = try Self.game(round: "NEIWAN", side: 1 << 21, heights: true, rules: .simple)
            var platformsOf: [String: [TrackPlatform]] = [:]
            for network in order {
                let line = try line(network, in: session)
                let offer = session.realLineOffer(for: line)
                XCTAssertNil(offer.problem, "\(order): \(network)")
                XCTAssertTrue(session.acquireRealLine(offer), "\(order): \(network): \(session.message?.text ?? "")")
                // Each line runs from its terminal to Zhuzhong, its junction.
                let bought = try XCTUnwrap(session.world.acquisition(of: line.id), "\(order): \(network)")
                let zhuzhong = try XCTUnwrap(session.world.line(id: try XCTUnwrap(bought.line))?.stops.last)
                let before = platformsOf.values.joined()
                platformsOf[network] = session.world.trackPlatforms(of: zhuzhong).filter { !before.contains($0) }
                XCTAssertEqual(platformsOf[network]?.count, 2, "\(order): \(network)'s own two platforms at Zhuzhong")
            }
            var world = session.world
            let lines = try order.map { network in
                try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: "tra:\(network)")?.line)))
            }
            XCTAssertEqual(lines[0].stops.last, lines[1].stops.last, "\(order): one Zhuzhong of both lines")
            func heights(_ network: String) -> [Int64] {
                (platformsOf[network] ?? []).compactMap { platform in
                    world.network.edge(platform.edge).flatMap { edge in [edge.from, edge.to].compactMap { world.network.node($0)?.position.z }.min() }
                }
            }
            let liujia = try XCTUnwrap(heights("LIUJIA").min()), neiwan = try XCTUnwrap(heights("NEIWAN").max())
            XCTAssertGreaterThanOrEqual(liujia - neiwan, TrackStructure.clearance, "\(order): the Liujia Line's platforms over the Neiwan Line's")

            try world.advance(ticks: 2 * 24 * 60)
            let today = world.clock.now.seconds / GameTime.secondsPerDay
            for (network, line) in zip(order, lines) {
                let runs = try XCTUnwrap(world.line(id: line.id))
                let missed = zip(runs.runs, runs.runDays).filter { run, day in
                    run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
                }
                XCTAssertEqual(missed.count, 0, "\(order): \(network): runs not sent out yesterday: \(missed.count) of \(runs.runs.count)")
            }
        }
    }

    /// Decision 462: a save from before, its Liujia Line bought with its
    /// Zhuzhong platforms on the ground, buys the Neiwan Line too: laid
    /// over the Liujia Line's there, at the station both share, and both
    /// run their day.
    func testASaveOfBeforeWithTheLiujiaLineBuysTheNeiwanLine() throws {
        let session = try Self.game(round: "NEIWAN", side: 1 << 21, heights: true, rules: .simple)
        let before = session.realLineOffer(for: try line("LIUJIA", in: session), raising: .none).offer
        XCTAssertTrue(session.acquireRealLine(before), session.message?.text ?? "")
        let liujia = try XCTUnwrap(session.world.line(id: try XCTUnwrap(session.world.acquisition(of: "tra:LIUJIA")?.line)))
        let zhuzhong = try XCTUnwrap(liujia.stops.last)
        let groundPlatforms = session.world.trackPlatforms(of: zhuzhong)

        let neiwan = try line("NEIWAN", in: session)
        XCTAssertTrue(session.realLineOffer(for: neiwan, raising: .viaducts).crossesTrack, "the Neiwan Line on the ground meets the Liujia Line's")
        let offer = session.realLineOffer(for: neiwan)
        XCTAssertNil(offer.problem)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        var world = session.world
        let bought = try XCTUnwrap(world.line(id: try XCTUnwrap(world.acquisition(of: "tra:NEIWAN")?.line)))
        XCTAssertEqual(bought.stops.last, zhuzhong, "one Zhuzhong of both lines")
        func lowest(_ platforms: [TrackPlatform]) -> [Int64] {
            platforms.compactMap { platform in
                world.network.edge(platform.edge).flatMap { edge in [edge.from, edge.to].compactMap { world.network.node($0)?.position.z }.min() }
            }
        }
        let raised = world.trackPlatforms(of: zhuzhong).filter { !groundPlatforms.contains($0) }
        XCTAssertEqual(raised.count, 2)
        let over = try XCTUnwrap(lowest(raised).min()) - XCTUnwrap(lowest(groundPlatforms).max())
        XCTAssertGreaterThanOrEqual(over, TrackStructure.clearance)

        try world.advance(ticks: 2 * 24 * 60)
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        for id in [liujia.id, bought.id] {
            let runs = try XCTUnwrap(world.line(id: id))
            let missed = zip(runs.runs, runs.runDays).filter { run, day in
                run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
            }
            XCTAssertEqual(missed.count, 0, "\(runs.name): runs not sent out yesterday: \(missed.count) of \(runs.runs.count)")
        }
    }

    /// Decision 400 (10j-2, 10j-3): Danhai's Blue Coast Line, the Xinbeitou
    /// and Xiaobitan Branch Lines are on sale beside
    /// the branch lines, each bought as one command, its two tracks laid
    /// along the real line, and a day of its real timetable run, every run
    /// sent out, under simple and realistic rules (decision 258); the
    /// Sanying Line too, in classes of its own (`SanyingLineSimpleDayTests`,
    /// `SanyingLineRealisticDayTests`), its two days the longest; the Green
    /// Mountain Line with its depot too (`DanhaiDepotTests`, decision 489).
    /// Not on sale: the other metro lines, whose ends stand more trains at
    /// once than the game lays tracks
    /// (`extract_metro_runs.py`); Kaohsiung's Circular Light Rail, which
    /// runs round its loop. The Ankeng LRT is on sale too
    /// (`AnkengLineTests`, decision 535 continued), and the Wenhu Line
    /// (`WenhuLineTests`, decision 543).
    func testTheLightRailsAndMetrosAreBoughtAndRunTheirRealDay() throws {
        let lines: [(id: String, type: TrainType, tier: LineAcquisition.Tier)] = [
            ("ntdlrt:VB", .c, .lightRail), ("trtc:R_XBT", .a, .metro), ("trtc:G_XBT", .a, .metro),
        ]
        for (id, type, tier) in lines {
            for rules in [NewGameRules.simple, .realistic] {
                try Self.buyAndRunRealDay(id, type: type, tier: tier, rules: rules)
            }
        }
    }

    /// `id` bought on a game round it under `rules`, as one command, and
    /// run to three in the morning of the third day: none of the lines not
    /// on sale is offered, and every run of the second day was sent out.
    static func buyAndRunRealDay(_ id: String, type: TrainType, tier: LineAcquisition.Tier, rules: NewGameRules) throws {
        let absent = [
            "krtc:C", "trtc:R", "trtc:G", "trtc:O_XINZHUANG", "trtc:O_LUZHOU", "trtc:BL", "trtc:Y",
            "tymc:A", "krtc:KR", "krtc:KO", "tmrt:TG",
        ]
        let session = try game(round: id, side: 1 << 21, heights: true, rules: rules)
        for absent in absent {
            XCTAssertFalse(session.buyableRealLines.contains { $0.id == absent }, absent)
        }
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, "\(id) on sale")
        XCTAssertEqual(line.tier, tier, id)
        let runs = try XCTUnwrap(session.railways?.metroRuns[id])
        XCTAssertEqual(line.stops, runs.stops, id)
        let offer = session.realLineOffer(for: line)
        XCTAssertNil(offer.problem, "\(id): \(offer.problem ?? "")")
        let acquisition = try XCTUnwrap(offer.acquisition, id)
        // Bought with its depot (decision 479), the depot sends its trains
        // out and takes them in, not the timetable's positioning runs;
        // one past an end (decision 489, the Ankeng LRT's) keeps those
        // taking the other end's trains back there for the night.
        let pastAnEnd = RealLineDepotSite.sites(of: id).contains { $0.beyond != nil }
        let sold = runs.runs.filter { acquisition.depot == nil || pastAnEnd || !($0.positioning || $0.train == "回送") }
        XCTAssertEqual(acquisition.runs.count, sold.count, id)
        XCTAssertEqual(acquisition.trains.count, runs.overnight.values.reduce(0, +), id)
        XCTAssertEqual(acquisition.trainType, type, id)
        XCTAssertEqual(acquisition.tier, tier, id)
        XCTAssertNotNil(acquisition.color, "\(id): its official colour")
        XCTAssertEqual(offer.price?.riders, LineAcquisition.value(ofDailyRiders: acquisition.dailyRiders, tier: tier), id)
        XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(session.message?.text ?? "")")
        var world = session.world
        let bought = try XCTUnwrap(world.acquisition(of: id))
        XCTAssertEqual(bought.value, offer.price?.riders, id)
        // To three in the morning: a light rail's and a metro's last
        // runs of a day leave after midnight.
        let started = Date()
        for hour in 0..<51 {
            try world.advance(ticks: 60)
            if ProcessInfo.processInfo.environment["ACQUIRE_TRACE"] != nil {
                FileHandle.standardError.write(Data("\(id) \(rules) hour \(hour) \(String(format: "%.1f", Date().timeIntervalSince(started))) s\n".utf8))
            }
        }
        let ran = try XCTUnwrap(world.line(id: try XCTUnwrap(bought.line)))
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        let missed = zip(ran.runs, ran.runDays).filter { run, day in
            run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
        }
        XCTAssertEqual(missed.count, 0, "\(id) (\(rules)): runs not sent out yesterday: \(missed.count) of \(ran.runs.count)")
        FileHandle.standardError.write(Data(
            "\(id) (\(rules)): \(acquisition.trains.count) trains, \(ran.runs.count) runs, 51 hours played in \(String(format: "%.1f", Date().timeIntervalSince(started))) s\n".utf8
        ))
    }

    /// A normal game on a place of Taiwan, bought tile by tile (decision
    /// 167), started at `latitude`, `longitude`, with the app's data, as
    /// the launcher begins it; with money enough, `unlimited`.
    private func tiledGame(at latitude: Double, _ longitude: Double, data: RealWorldData, unlimited: Bool = false) throws -> GameSession {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
        var world = GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
            population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
        ))
        XCTAssertNotNil(world.mapExpansion, "bought tile by tile")
        if unlimited { world.setUnlimitedFunds(true) }
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        session.coverage = data.coverage
        session.railways = data.railways
        return session
    }

    /// Decision 401: on a map bought tile by tile, a line reaching past the
    /// land owned buys the tiles under it too (decision 315 §1's price),
    /// whatever the riders' milestone. The Jiji and Neiwan Lines cross
    /// three tiles; a game starts with one, so neither could be bought, nor
    /// the Pingxi Line from its junction: "this land is not yours yet".
    func testALineReachingPastTheLandOwnedBuysTheTilesUnderIt() throws {
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        for network in ["PINGXI", "SHENAO", "JIJI", "NEIWAN", "LIUJIA", "SHALUN"] {
            let junction = try BundledRealData.station(try XCTUnwrap(data.railways?.branchRuns[network]?.stops.first), in: "tra_sched").coordinate
            let session = try tiledGame(at: junction.latitude, junction.longitude, data: data)
            let line = try line(network, in: session)
            let offer = session.realLineOffer(for: line)
            XCTAssertNil(offer.problem, "\(network): \(offer.problem ?? "")")
            guard let acquisition = offer.acquisition, let price = offer.price else { continue }
            let owned = try XCTUnwrap(session.world.mapExpansion?.owned)
            let under = Set((acquisition.pieces.flatMap(\.ground) + acquisition.stops.map(\.at)).map { MapExpansion.tile(at: $0) })
            let tiles = acquisition.tiles ?? []
            XCTAssertTrue(Set(tiles).isDisjoint(with: owned), network)
            XCTAssertTrue(under.subtracting(owned).isSubset(of: tiles), network)
            XCTAssertEqual(price.land > .zero, !tiles.isEmpty, network)
            if ["JIJI", "NEIWAN", "PINGXI"].contains(network) { XCTAssertFalse(tiles.isEmpty, "\(network) reaches past the first tile") }
            print("\(network): \(tiles.count) tiles for \(price.land.moneyText), total \(price.total.moneyText)")
            XCTAssertEqual(offer.priceRows(in: .traditionalChinese).dropLast().map(\.amount).reduce(.zero, +), price.total, network)
            // Bought with money enough (the prices above are a standard
            // game's: unlimited funds price nothing); one line of three
            // tiles is enough, and keeps the test short.
            guard network == "JIJI" else { continue }
            let rich = try tiledGame(at: junction.latitude, junction.longitude, data: data, unlimited: true)
            XCTAssertTrue(rich.acquireRealLine(offer), "\(network): \(rich.message?.text ?? "")")
            XCTAssertTrue(under.allSatisfy { rich.world.ownsMapTile($0) }, network)
            XCTAssertTrue(tiles.allSatisfy { tile in rich.world.landBlocks?.contains(tile.landBlocks(in: rich.world.bounds)[0]) ?? false }, "\(network): the tiles' land read in")
            // One command: one Undo takes the land back with the line.
            rich.undo()
            XCTAssertNil(rich.world.acquisition(of: line.id), network)
            XCTAssertEqual(rich.world.mapExpansion?.owned, owned, network)
        }
        // Started in Taipei, the Jiji Line's land does not touch the
        // company's: the card says what to do.
        let taipei = try tiledGame(at: 25.047882, 121.517219, data: data)
        let offer = taipei.realLineOffer(for: try line("JIJI", in: taipei))
        XCTAssertNil(offer.acquisition)
        XCTAssertEqual(offer.problem, "這條線經過的地和你的地不相連。先用「擴建地圖」買到這條線旁邊，再收購。")
    }

    /// A line bought runs the company's trains: the map draws no real ones
    /// on it, and still those of the lines not bought.
    func testTheMapDrawsNoRealTrainsOnALineBought() throws {
        let operations = try XCTUnwrap(try BundledRealData.railways().operations)
        let all = RealTrainTraffic(operations: operations) { _ in true }
        let rest = RealTrainTraffic(operations: operations, bought: ["tra:PINGXI"]) { _ in true }
        XCTAssertTrue(all.lines.contains { $0.system == "tra" && $0.line.id == "PINGXI" })
        XCTAssertFalse(rest.lines.contains { $0.system == "tra" && $0.line.id == "PINGXI" })
        XCTAssertEqual(rest.lines.count, all.lines.count - 1)
    }

    /// A line bought is laid over the real ground with the real bridges,
    /// viaducts and tunnels (decision 279), as the company's own traced
    /// line is: sampled every 64 m along its main track, by the thresholds
    /// of ``RealWorldDemoGroundTests/testTheTrackFollowsTheRealStructures()``.
    func testALineBoughtFollowsTheRealStructures() throws {
        var tunnel = (inside: 0, all: 0), carried = (up: 0, all: 0), ground = (off: 0, all: 0)
        for network in ["PINGXI", "SHENAO", "JIJI", "NEIWAN", "LIUJIA", "SHALUN"] {
            let session = try Self.game(round: network, side: 1 << 21, heights: true)
            let offer = session.realLineOffer(for: try line(network, in: session))
            let acquisition = try XCTUnwrap(offer.acquisition, "\(network): \(offer.problem ?? "")")
            XCTAssertTrue(session.acquireRealLine(offer), "\(network): \(session.message?.text ?? "")")
            let world = session.world
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            let structures = try XCTUnwrap(session.railways?.structures)
            let path = WorldPath(acquisition.pieces[0].nodes.map { WorldVector(x: Double($0.x), y: Double($0.y)) })
            let real = structures.stretches(along: path, frame: frame, system: "tra_sched")
            // A station stands level on the ground (decision 132), its
            // loops' stretch with it: Neiwan's junction, Zhuzhong, is on
            // the real bridge over the Touqian River.
            let stations = acquisition.platforms.filter { $0.at.piece == 0 }.map { platform in
                let centre = platform.at.distance + Double(platform.length) / 2
                return (centre - RealWorldDemo.loopReach - Double(platform.length) / 2)...(centre + RealWorldDemo.loopReach + Double(platform.length) / 2)
            }
            var built: [(point: WorldVector, kind: TrackSectionKind)] = []
            for edge in world.network.edges {
                let geometry = try XCTUnwrap(world.trackGeometry(of: edge.id))
                for span in edge.sectionSpans where span.end > span.start {
                    for point in geometry.points(from: span.start, to: span.end) {
                        built.append((WorldVector(x: Double(point.x), y: Double(point.y)), span.kind))
                    }
                }
            }
            let metre = Double(WorldCoordinate.unitsPerMetre)
            for distance in stride(from: 0, through: path.length, by: 64 * metre) {
                let point = path.point(at: distance)
                guard !stations.contains(where: { $0.contains(distance) }),
                      let kind = built.min(by: { ($0.point - point).length < ($1.point - point).length })?.kind else { continue }
                if let stretch = real.first(where: {
                    $0.range.upperBound - $0.range.lowerBound >= TrackRise.shortestCarried
                        && ($0.range.lowerBound + TrackRise.carriedInset...$0.range.upperBound - TrackRise.carriedInset).contains(distance)
                }) {
                    if stretch.kind == .tunnel {
                        tunnel.all += 1
                        tunnel.inside += kind == .tunnel ? 1 : 0
                    } else {
                        carried.all += 1
                        carried.up += [.viaduct, .bridge].contains(kind) ? 1 : 0

                    }
                } else if !real.contains(where: { ($0.range.lowerBound - 200 * metre...$0.range.upperBound + 200 * metre).contains(distance) }) {
                    ground.all += 1
                    ground.off += [.viaduct, .tunnel].contains(kind) ? 1 : 0
                }
            }
        }
        print("tunnels \(tunnel), bridges and viaducts \(carried), ground \(ground)")
        XCTAssertGreaterThan(tunnel.all, 20)
        XCTAssertGreaterThanOrEqual(Double(tunnel.inside), 0.85 * Double(tunnel.all), "\(tunnel)")
        // Measured: 117 of 125. Neiwan's low 499 m bridge between Zhudong and
        // Hengshan was 4 of them on the ground while its bound and its
        // approach's were let go together; the approach's now goes first
        // (``TrackRise/Bound/isOnGround``). The ones left are the Liujia and
        // Shalun Lines' viaducts within 300 m of Liujia, Chang Jung
        // Christian University and Shalun, stations the real line raises
        // but the game stands on the ground (decision 132): the track
        // climbs to the viaduct beyond them.
        XCTAssertGreaterThan(carried.all, 8)
        XCTAssertGreaterThanOrEqual(Double(carried.up), 0.85 * Double(carried.all), "\(carried)")
        XCTAssertGreaterThan(ground.all, 300)
        XCTAssertLessThanOrEqual(Double(ground.off), 0.04 * Double(ground.all), "\(ground)")
    }

    /// Past the junction, the station card calls Taiwan Railway's riders
    /// the line's regulars; at the junction they still change from it.
    func testTheStationCardCallsTheRidersAlongALineBoughtItsRegulars() throws {
        let session = try Self.game(round: "PINGXI", transfers: true)
        let offer = session.realLineOffer(for: try line("PINGXI", in: session))
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        let stops = try XCTUnwrap(session.world.line(id: try XCTUnwrap(session.world.acquisition(of: "tra:PINGXI")).line!)?.stops)
        let shifen = try XCTUnwrap(stops.first { session.world.station(id: $0)?.name == "十分" })
        let text = try XCTUnwrap(session.transferText(of: shifen))
        XCTAssertTrue(text.hasPrefix("沿線的常客：每天約 "), text)
        // The line runs from its terminal: the junction is its last stop.
        let junction = try XCTUnwrap(session.transferText(of: try XCTUnwrap(stops.last)))
        XCTAssertTrue(junction.hasPrefix("從台鐵轉乘"), junction)
    }

    /// A station of the player's beside a real one past the junction
    /// offers the line; the card lists the price, and closes once bought for
    /// the card that says so.
    func testAStationBesideTheLineOffersIt() async throws {
        let session = try Self.game(round: "PINGXI")
        let pingxi = try line("PINGXI", in: session)
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let shifen = try BundledRealData.station("十分", in: "tra_sched").coordinate
        let at = frame.worldPosition(latitude: shifen.latitude, longitude: shifen.longitude)
        let metre = WorldCoordinate.unitsPerMetre
        let near = try session.performEdit { try $0.buildStation(named: "Near", at: PlanPoint(x: Int64(at.x) + 100 * metre, y: Int64(at.y))).id }
        XCTAssertEqual(session.buyableRealLine(at: near), pingxi)

        session.offerRealLine(pingxi)
        await session.realLineOfferPrepared()
        let offer = try XCTUnwrap(session.shownRealLineOffer)
        let rows = offer.priceRows(in: .traditionalChinese)
        XCTAssertEqual(rows.map(\.label), ["軌道、車站與月台", "3 列車", "沿線的常客", "合計"])
        XCTAssertEqual(rows.dropLast().map(\.amount).reduce(.zero, +), rows.last?.amount)
        XCTAssertEqual(offer.summaryText(in: .traditionalChinese), "三貂嶺—菁桐：7 站、3 列車與真實班次")
        XCTAssertNil(offer.problem, offer.problem ?? "")
        let today = RealLineAcquired.startsToday(at: session.world.clock.now)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        XCTAssertNil(session.shownRealLineOffer)
        XCTAssertEqual(session.lastLineAcquired?.startsToday, today)
        XCTAssertEqual(session.lastLineAcquired?.handoverText(in: .traditionalChinese), today ? "今天首班車起由你經營" : "明天首班車起由你經營")
    }

    /// BUGHUNT_BUILD P3-2: a line bought before four in the morning runs
    /// that day's runs (``LineAcquisition/firstServiceDay(at:)``), so the
    /// card and the message say today's first train, not tomorrow's.
    func testALineBoughtBeforeFourRunsFromTodaysFirstTrain() {
        let day = GameTime.secondsPerDay, hour = GameTime.secondsPerHour
        XCTAssertTrue(RealLineAcquired.startsToday(at: GameTime(seconds: 3 * hour)))
        XCTAssertTrue(RealLineAcquired.startsToday(at: GameTime(seconds: 2 * day + 4 * hour - 1)))
        XCTAssertFalse(RealLineAcquired.startsToday(at: GameTime(seconds: 2 * day + 4 * hour)))
        XCTAssertFalse(RealLineAcquired.startsToday(at: GameTime(seconds: 23 * hour)))
        XCTAssertEqual(RealLineAcquired.handoverText(today: true, in: .traditionalChinese), "今天首班車起由你經營")
        XCTAssertEqual(RealLineAcquired.handoverText(today: false, in: .traditionalChinese), "明天首班車起由你經營")
    }
}

/// Decision 400 (10j-3): the Sanying Line bought and its two real days run
/// under simple rules (decision 258), every run sent out: its trains
/// standing overnight at stations between once stood across the night's
/// last runs and held the line still from the second day. A class of its
/// own, each rule apart, as two days of its twelve trains take minutes
/// (`swift-shards.sh` deals them to two shards).
@MainActor
final class SanyingLineSimpleDayTests: XCTestCase {
    func testTheSanyingLineRunsTwoRealDays() throws {
        try RealLineAcquisitionTests.buyAndRunRealDay("sanying:LB", type: .b, tier: .metro, rules: .simple)
    }
}

/// Decision 400 (10j-3): the same under realistic rules.
@MainActor
final class SanyingLineRealisticDayTests: XCTestCase {
    func testTheSanyingLineRunsTwoRealDays() throws {
        try RealLineAcquisitionTests.buyAndRunRealDay("sanying:LB", type: .b, tier: .metro, rules: .realistic)
    }
}
