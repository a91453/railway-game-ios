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
    private func game(round network: String, balance: Money = Money(100_000_000_000), side: Int64 = 1 << 20, heights: Bool = false, transfers: Bool = false, rules: NewGameRules = .realistic) throws -> GameSession {
        let railways = try BundledRealData.railways()
        let runs = try XCTUnwrap(railways.branchRuns[network])
        let stations = try runs.stops.map { try BundledRealData.station($0, in: "tra_sched") }
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

    func testThePingxiLineIsBoughtAsOneCommandAndRunsItsRealTrains() throws {
        let session = try game(round: "PINGXI")
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
        let line = try XCTUnwrap(session.world.line(id: bought.line))
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
        let runDays = try XCTUnwrap(world.line(id: bought.line)?.runDays)
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
        let bought = try game(round: "PINGXI")
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
        XCTAssertNotNil(session.world.acquisition(of: "tra:PINGXI"), "the real line is still the company's")
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
            let session = try game(round: network, side: 1 << 21, heights: true, rules: .simple)
            let line = try line(network, in: session)
            let offer = session.realLineOffer(for: line)
            XCTAssertNil(offer.problem, network)
            guard let price = offer.price, let acquisition = offer.acquisition else { continue }
            print("\(network): building \(price.building.moneyText), trains \(price.trains.moneyText) (\(acquisition.trains.count)), riders \(price.riders.moneyText) (\(acquisition.dailyRiders) a day), total \(price.total.moneyText)")
            XCTAssertTrue(session.acquireRealLine(offer), "\(network): \(session.message?.text ?? "")")
            var world = session.world
            let bought = try XCTUnwrap(world.acquisition(of: line.id))
            try world.advance(ticks: 2 * 24 * 60)
            let runs = try XCTUnwrap(world.line(id: bought.line))
            let today = world.clock.now.seconds / GameTime.secondsPerDay
            let missed = zip(runs.runs, runs.runDays).filter { run, day in
                run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
            }
            XCTAssertEqual(missed.count, 0, "\(network): runs not sent out yesterday: \(missed.count) of \(runs.runs.count)")
        }
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
            // game's: unlimited funds price nothing).
            let rich = try tiledGame(at: junction.latitude, junction.longitude, data: data, unlimited: true)
            XCTAssertTrue(rich.acquireRealLine(offer), "\(network): \(rich.message?.text ?? "")")
            XCTAssertTrue(under.allSatisfy { rich.world.ownsMapTile($0) }, network)
            XCTAssertTrue(tiles.allSatisfy { tile in rich.world.landBlocks?.contains(tile.landBlocks(in: rich.world.bounds)[0]) ?? false }, "\(network): the tiles' land read in")
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
            let session = try game(round: network, side: 1 << 21, heights: true)
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
        let session = try game(round: "PINGXI", transfers: true)
        let offer = session.realLineOffer(for: try line("PINGXI", in: session))
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        let stops = try XCTUnwrap(session.world.line(id: try XCTUnwrap(session.world.acquisition(of: "tra:PINGXI")).line)?.stops)
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
    func testAStationBesideTheLineOffersIt() throws {
        let session = try game(round: "PINGXI")
        let pingxi = try line("PINGXI", in: session)
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let shifen = try BundledRealData.station("十分", in: "tra_sched").coordinate
        let at = frame.worldPosition(latitude: shifen.latitude, longitude: shifen.longitude)
        let metre = WorldCoordinate.unitsPerMetre
        let near = try session.performEdit { try $0.buildStation(named: "Near", at: PlanPoint(x: Int64(at.x) + 100 * metre, y: Int64(at.y))).id }
        XCTAssertEqual(session.buyableRealLine(at: near), pingxi)

        session.offerRealLine(pingxi)
        let offer = try XCTUnwrap(session.shownRealLineOffer)
        let rows = offer.priceRows(in: .traditionalChinese)
        XCTAssertEqual(rows.map(\.label), ["軌道、車站與月台", "3 列車", "沿線的常客", "合計"])
        XCTAssertEqual(rows.dropLast().map(\.amount).reduce(.zero, +), rows.last?.amount)
        XCTAssertEqual(offer.summaryText(in: .traditionalChinese), "三貂嶺—菁桐：7 站、3 列車與真實班次")
        XCTAssertNil(offer.problem, offer.problem ?? "")
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        XCTAssertNil(session.shownRealLineOffer)
        XCTAssertNotNil(session.lastLineAcquired)
    }
}
