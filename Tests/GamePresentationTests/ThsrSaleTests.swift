import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// THSR-SALE (decision 993): the Taiwan High Speed Rail on sale in a
/// Taiwan game bought tile by tile, Nangang to Zuoying, as the Kyushu
/// Shinkansen is on Japan's map (decision 975).
@MainActor
final class ThsrSaleTests: XCTestCase {
    static let id = "thsr_sched:THSR"
    static let stops = ["南港", "台北", "板橋", "桃園", "新竹", "苗栗", "台中", "彰化", "雲林", "嘉義", "台南", "左營"]

    /// A new Taiwan game round `latitude`, `longitude`, as the launcher opens it.
    static func game(at latitude: Double, _ longitude: Double) throws -> GameSession {
        let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
        let world = GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
            population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
        ))
        XCTAssertNotNil(world.mapExpansion, "bought tile by tile")
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        session.coverage = data.coverage
        session.railways = data.railways
        return session
    }

    func testTheRunsAreTheRealDay() throws {
        let railways = try BundledRealData.railways()
        let runs = try XCTUnwrap(railways.metroRuns[Self.id])
        XCTAssertEqual(runs.stops, Self.stops)
        XCTAssertEqual(runs.runs.filter { !$0.positioning }.count, 169)
        XCTAssertEqual(runs.overnight, ["南港": 10, "左營": 30])
        XCTAssertEqual(RealLineDepotSite.sites(of: Self.id).map(\.chinese), ["南港留置線", "左營機廠"])
        XCTAssertEqual(TrackGauge.ofRealLine(Self.id), .shinkansen)
    }

    /// `THSR_SALE_REPORT=1`: from Taipei, the offer's price item by item,
    /// the tiles it buys, then the line bought and its first day played.
    func testReport() throws {
        guard ProcessInfo.processInfo.environment["THSR_SALE_REPORT"] != nil else { throw XCTSkip("THSR_SALE_REPORT=1") }
        let session = try Self.game(at: 25.047882, 121.517219)
        let listing = try XCTUnwrap(session.realLineListings.first { $0.bundle.lines.map(\.id) == [Self.id] }, "sold by itself")
        print("THSR listing: \(listing.metres) m, buyable \(listing.isBuyable), owned \(session.world.mapExpansion?.owned.count ?? 0), balance \(session.world.economy.balance.moneyText)")
        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id })
        let started = Date()
        let offer = session.realLineOffer(for: real)
        print("THSR offer in \(Date().timeIntervalSince(started)) s: problem \(offer.problem ?? "none")")
        let price = try XCTUnwrap(offer.price)
        let acquisition = try XCTUnwrap(offer.acquisition)
        print("THSR price: land \(price.land.moneyText), building \(price.building.moneyText), trains \(price.trains.moneyText), riders \(price.riders.moneyText), total \(price.total.moneyText); tiles \(acquisition.tiles?.count ?? 0), trains \(acquisition.trains.count), depots \(([acquisition.depot] + (acquisition.moreDepots ?? [])).compactMap { $0?.name })")
        session.perform { (world: inout GameWorld) throws(GameError) -> String in
            world.setUnlimitedFunds(true)
            return ""
        }
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: real)), session.message?.text ?? "")
        var world = session.world
        world.setUnlimitedFunds(false)
        let budget = TimetableCheckup.Budget(notSent: 0, late: 0, lateOutOfDepot: 0, peakGapMinutes: 0)
        try? TimetableCheckupWorlds.check("thsr realistic", world, day: 0, budget: budget)
    }

    /// `THSR_WHERE=1`: where GameCore refuses the line, laid piece by
    /// piece on a copy of the world (as `KS_WHERE` found the Kyushu
    /// Shinkansen's, decision 975).
    func testWhere() throws {
        guard ProcessInfo.processInfo.environment["THSR_WHERE"] != nil else { throw XCTSkip("THSR_WHERE=1") }
        let session = try Self.game(at: 25.047882, 121.517219)
        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id })
        let laying = session.realLineLaying
        let m = Double(WorldCoordinate.unitsPerMetre)
        func show(_ c: WorldCoordinate, in world: GameWorld) -> String {
            let ground = Double(world.groundHeight(at: c.plan) ?? 0)
            let geo = RealWorldFrame(world: world).map { $0.coordinate(worldX: Double(c.x), worldY: Double(c.y)) }
            return String(format: "(%.0f, %.0f, z %.1f, over %.1f)", Double(c.x) / m, Double(c.y) / m, Double(c.z) / m, (Double(c.z) - ground) / m)
                + (geo.map { String(format: " %.6f,%.6f", $0.latitude, $0.longitude) } ?? "")
        }
        let depot = ProcessInfo.processInfo.environment["THSR_DEPOT"] != "0"
        let start = Date()
        let tried = laying.offer(for: real, raising: .viaducts, depot: depot, clearingTrack: false, besideThrough: false)
        print("THSR try depot \(depot): problem \(tried.offer.problem ?? "none") crosses \(tried.crossesTrack) in \(Date().timeIntervalSince(start)) s")
        guard let acquisition = tried.laid else { return }
        print("THSR pieces \(acquisition.pieces.count), tiles \(acquisition.tiles?.count ?? 0)")
        for (number, piece) in acquisition.pieces.enumerated() {
            let first = piece.nodes.first.map { show($0, in: session.world) } ?? "-"
            let last = piece.nodes.last.map { show($0, in: session.world) } ?? "-"
            print("THSR piece \(number): together \(piece.together) nodes \(piece.nodes.count) start \(piece.start.map { "\($0.piece).\($0.node)" } ?? "-") end \(piece.end.map { "\($0.piece).\($0.node)" } ?? "-") structure \(piece.structure) \(first) -> \(last)")
        }
        for platform in acquisition.platforms {
            print("THSR platform of \(acquisition.stops[platform.stop].name) piece \(platform.at.piece) at \(Int(platform.at.distance / m)) m")
        }
        var world = session.world.pricingCopy()
        world.setUnlimitedFunds(true)
        for tile in acquisition.tiles ?? [] { try world.buyMapTile(tile, passingMilestone: true) }
        GameSession.readLand(roundStationsOf: &world, population: session.population, places: session.places, water: session.water, coverage: session.coverage)
        var nodes: [[TrackNodeID]] = []
        laying: for (number, piece) in acquisition.pieces.enumerated() {
            try world.readGround(under: piece.ground, from: session.heights)
            var ids: [TrackNodeID] = []
            for (index, position) in piece.nodes.enumerated() {
                if index == 0, let start = piece.start {
                    ids.append(nodes[start.piece][start.node])
                } else if index == piece.nodes.count - 1, let end = piece.end {
                    ids.append(nodes[end.piece][end.node])
                } else {
                    do {
                        ids.append(try world.buildTrackNode(at: position))
                    } catch {
                        print("THSR   piece \(number) node \(index) \(show(position, in: world)) error \(error)")
                        break laying
                    }
                }
            }
            for (index, curve) in piece.curves.enumerated() {
                do {
                    _ = try world.buildTrackEdge(from: ids[index], to: ids[index + 1], curve: curve, structure: piece.structure(ofEdge: index),
                                                 gauge: TrackGauge.ofRealLine(acquisition.realLine))
                } catch {
                    print("THSR   piece \(number) of \(acquisition.pieces.count) edge \(index) of \(piece.curves.count) together \(piece.together) structure \(piece.structure(ofEdge: index)) error \(error)")
                    print("THSR     from \(show(piece.nodes[index], in: world)) to \(show(piece.nodes[index + 1], in: world))")
                    let other: TrackEdgeID? = switch error {
                    case .trackConflict(let edge), .trackTooClose(let edge): edge
                    default: nil
                    }
                    if let other, let edge = world.network.edge(other), let a = world.network.node(edge.from), let b = world.network.node(edge.to) {
                        print("THSR     other edge \(other) structure \(edge.structure) from \(show(a.position, in: world)) to \(show(b.position, in: world)) new \(!session.world.network.edges.contains { $0.id == other })")
                        if let p = nodes.firstIndex(where: { $0.contains(edge.from) || $0.contains(edge.to) }) {
                            print("THSR     other edge is in piece \(p) together \(acquisition.pieces[p].together)")
                        }
                    }
                    break laying
                }
            }
            nodes.append(ids)
        }
        print("THSR laid \(nodes.count) of \(acquisition.pieces.count) pieces")
    }

    /// `THSR_SALE_PROFIT=<days>`: from Taipei, the line bought (funds
    /// unlimited, then the price taken back off), each day of `days` its
    /// riders, fares, costs and the company's day, to price it from what
    /// it earns (decision 993). Release build: a day is some seconds.
    func testProfit() throws {
        guard let value = ProcessInfo.processInfo.environment["THSR_SALE_PROFIT"], let days = Int(value) else { throw XCTSkip("THSR_SALE_PROFIT=<days>") }
        let session = try Self.game(at: 25.047882, 121.517219)
        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id })
        let offer = session.realLineOffer(for: real)
        let price = try XCTUnwrap(offer.price, offer.problem ?? "")
        print("THSR price: land \(price.land.moneyText), building \(price.building.moneyText), trains \(price.trains.moneyText), riders \(price.riders.moneyText), total \(price.total.moneyText), tiles \(offer.acquisition?.tiles?.count ?? 0)")
        session.perform { (world: inout GameWorld) throws(GameError) -> String in
            world.setUnlimitedFunds(true)
            return ""
        }
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        var world = session.world
        world.setUnlimitedFunds(false)
        let line = try XCTUnwrap(world.acquisition(of: Self.id)?.line)
        print("| day | boardings | fares | operating | maintenance | energy | staff | line profit | company fares | company costs | tax | balance |")
        var total: Int64 = 0, counted = 0
        for _ in 0..<days {
            try world.advance(ticks: 24 * 60)
            guard let tally = world.lineAccounts?.lines.first(where: { $0.line == line })?.days.last?.tally, let day = world.accounts.days.last else { continue }
            let profit = tally.fareRevenue - tally.operatingCost - tally.maintenanceCost - tally.energyCost - tally.staffCost
            if day.day >= 7 { total += profit.amount; counted += 1 }
            print("| \(day.day) | \(tally.boardings) | \(tally.fareRevenue.moneyText) | \(tally.operatingCost.moneyText) | \(tally.maintenanceCost.moneyText) | \(tally.energyCost.moneyText) | \(tally.staffCost.moneyText) | \(profit.moneyText) | \(day.fareRevenue.moneyText) | \(day.totalCost.moneyText) | \(day.taxCost.moneyText) | \(world.economy.balance.moneyText) |")
        }
        if counted > 0 {
            let average = total / Int64(counted)
            print("THSR average line profit a day from day 7: \(Money(average).moneyText); a year \(Money(average * 365).moneyText); price \(price.total.moneyText) is \(String(format: "%.1f", Double(price.total.amount) / Double(max(1, average * 365)))) years of it")
        }
    }
}
