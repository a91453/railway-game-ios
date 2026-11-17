import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 712: Hong Kong's map is as large as its map pack says, not the
/// 16 km square of other places outside Taiwan; its land is the pack's
/// people, read in round the stations; every line of the MTR lies on it.
@MainActor
final class HongKongMapTests: XCTestCase {
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    nonisolated static func ground() throws -> OverseasGround {
        try OverseasGround(city: .hongKong, pack: try XCTUnwrap(HongKongRailwaysTests.pack(.hongKong)))
    }

    private func hongKong(demo: Bool = false) throws -> GameSession {
        try Self.hongKong(demo: demo)
    }

    /// A game on Hong Kong's map with its railways and its people, as the
    /// launcher starts it (also for `HongKongSharedTrackBuyOrderTests`,
    /// `HongKongTungChungDayTests` and `HongKongEveryLineTests`, split off
    /// so the CI shards can deal them apart).
    static func hongKong(demo: Bool = false) throws -> GameSession {
        let ground = try Self.ground()
        var world = GameWorld.newOverseasGame(ground, balance: Money(100_000_000_000))
        if demo { world.setUnlimitedFunds(true) }
        // Decision 726: on the city's ground, with its sea, as the launcher
        // starts it.
        XCTAssertNotNil(ground.heights)
        try world.mapGround()
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try HongKongRailwaysTests.railways()
        session.population = ground.population
        session.water = ground.water
        session.heights = ground.heights
        session.news.isDemo = demo
        return session
    }

    // MARK: - The extent

    /// The pack says how far the map reaches: WorldPop's box of Hong
    /// Kong, some 62 km by 45 km, with everyone of its grid.
    func testThePackSaysHowFarTheMapReaches() throws {
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.hongKong))
        let extent = try pack.extent()
        XCTAssertEqual(extent, MapPack.Extent(north: 22.5584, south: 22.15, west: 113.8333, east: 114.4417))
        let ground = try Self.ground()
        let half = RealWorldFrame.halfExtent(of: ground.bounds)
        XCTAssertEqual(half.east * 2 / 1_000, 62.5, accuracy: 0.5)
        XCTAssertEqual(half.south * 2 / 1_000, 45.5, accuracy: 0.5)
        XCTAssertEqual(ground.anchor.longitudeDegrees, 114.1375, accuracy: 0.0001)
        XCTAssertEqual(ground.anchor.latitudeDegrees, 22.354, accuracy: 0.001)
        // WorldPop's Hong Kong, 2025: 7.4 million people.
        XCTAssertEqual(try XCTUnwrap(ground.population).total, 7_396_724)
    }

    /// A box that is not one, or wider than a world, has no ground.
    func testABoxThatFitsNoWorldHasNoGround() {
        XCTAssertNil(MapPack.Extent(north: 22, south: 23, west: 113, east: 114).anchor)
        XCTAssertNil(MapPack.Extent(north: 23, south: 22, west: 114, east: 113).bounds)
        XCTAssertNil(MapPack.Extent(north: 60, south: 10, west: 100, east: 130).bounds)
        XCTAssertNotNil(MapPack.Extent(north: 23, south: 22, west: 113, east: 114).bounds)
    }

    /// A pack without an extent is no ground, and says so.
    func testAPackWithoutAnExtentIsListed() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HongKongMapTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"{"id":"hongkong"}"#.utf8).write(to: folder.appendingPathComponent("pack.json"))
        XCTAssertThrowsError(try OverseasGround(city: .hongKong, pack: MapPack(root: folder)))
        let data = RealWorldData.load(overseas: [.hongKong], pack: { _ in MapPack(root: folder) }, file: RealWorldDataLoadTests.file)
        XCTAssertTrue(data.overseas.isEmpty)
        XCTAssertTrue(data.issues.contains { $0.file == "MapPacks/hongkong/pack.json" })
        XCTAssertNotNil(data.population, "Taiwan's as it was")
    }

    // MARK: - The switch

    /// Hong Kong is open (decision 712's third pull request), and
    /// Rovaniemi (decision 818), so the app's real-world data holds their
    /// ground; with no city asked for it holds none, and reads what it did.
    func testTheGroundIsReadOnlyOfAnOpenCity() {
        XCTAssertEqual(OverseasMaps.open, [.hongKong, .rovaniemi])
        XCTAssertEqual(RealWorldData.load(overseas: OverseasMaps.open, pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file).overseas.map(\.city), [OverseasMap.hongKong, .rovaniemi])
        XCTAssertTrue(RealWorldData.load(overseas: [], file: RealWorldDataLoadTests.file).overseas.isEmpty)
    }

    /// The launcher starts a game on the city's map once its ground is
    /// read, with the city's people; not before, and Taiwan's games keep
    /// Taiwan's people.
    func testTheLauncherStartsAGameOnTheCitysMap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HongKongMapTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        XCTAssertFalse(launcher.startOverseasMap(.hongKong))
        XCTAssertNil(launcher.session)
        await launcher.loadRealWorldData {
            RealWorldData.load(overseas: [.hongKong], pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        }.value
        let ground = try XCTUnwrap(launcher.overseasGrounds.first)
        // Decision 712, continued: a first map, so open (`AirRoutesTests`).
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        let session = try XCTUnwrap(launcher.session)
        XCTAssertTrue(ground.holds(session.world))
        XCTAssertNotNil(session.world.landBlocks, "its land is read in as it is needed")
        XCTAssertEqual(session.population?.total, ground.population?.total)
        // Decision 726: and its own ground and water, Taiwan's elsewhere.
        let taiMoShan = (latitude: 22.41056, longitude: 114.12444)
        XCTAssertGreaterThan(try XCTUnwrap(session.heights).height(latitude: taiMoShan.latitude, longitude: taiMoShan.longitude), 900)
        XCTAssertEqual(try XCTUnwrap(session.water).isWater(latitude: 22.2880, longitude: 114.1720), true, "Victoria Harbour")
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let peak = frame.worldPosition(latitude: taiMoShan.latitude, longitude: taiMoShan.longitude)
        XCTAssertFalse(
            session.world.missingGroundBlocks(under: [PlanPoint(x: Int64(peak.x.rounded()), y: Int64(peak.y.rounded()))]).isEmpty,
            "the map has ground, read as track comes to it"
        )
        let taiwan = GameWorld.newWholeTaiwanGame()
        XCTAssertEqual(launcher.water(for: taiwan)?.isWater(latitude: 22.2880, longitude: 114.1720), launcher.water?.isWater(latitude: 22.2880, longitude: 114.1720))
        XCTAssertEqual(
            launcher.heights(for: taiwan)?.height(latitude: 23.47, longitude: 120.957), launcher.heights?.height(latitude: 23.47, longitude: 120.957),
            "Yushan, from Taiwan's file"
        )
        XCTAssertEqual(launcher.population(for: GameWorld.newWholeTaiwanGame())?.total, launcher.population?.total)
        XCTAssertNotEqual(launcher.population?.total, ground.population?.total)
    }

    // MARK: - The lines

    /// Every station of every line lies on the map, a kilometre and more
    /// from its edge.
    func testEveryLineLiesOnTheMap() throws {
        let session = try hongKong()
        let railways = try XCTUnwrap(session.railways)
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let region = WorldRegion(bounds: session.world.bounds)
        let stations = railways.stations.filter { $0.system.id == "hkmtr" }
        XCTAssertEqual(stations.count, 97)
        for station in stations {
            let point = frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)
            let margin = min(point.x - region.minX, region.maxX - point.x, point.y - region.minY, region.maxY - point.y) / metre
            XCTAssertGreaterThan(margin, 1_000, station.chinese)
        }
    }

    /// Every line whose day of runs was worked out is on sale on the map
    /// (on a 16 km map the Airport Express, the Tung Chung Line and the
    /// East Rail branch were not: they did not fit), and none is listed
    /// as only partly on it.
    func testEveryLineWithRunsIsOnSale() throws {
        let session = try hongKong()
        let railways = try XCTUnwrap(session.railways)
        let withRuns = RealBranchLine.overseasLines.map { "hkmtr:\($0.network)" }.filter { railways.metroRuns[$0] != nil }
        XCTAssertEqual(session.buyableRealLines.map(\.id).sorted(), withRuns.sorted())
        XCTAssertEqual(Set(withRuns), ["hkmtr:AEL", "hkmtr:TCL", "hkmtr:SIL", "hkmtr:DRL", "hkmtr:EAL_LMC", "hkmtr:TKL_LHP"])
        XCTAssertNil(session.realLinesForSaleNote)
    }

    /// The South Island Line is bought on its own, with every train of
    /// its day: its end at Admiralty stands where the line's own point of
    /// the station is, not at the East Rail Line's 33 m away, where its
    /// way turned inside the station and the tracks its trains wait on lay
    /// too close for a train on each
    /// (``RealBranchLine/standsOnItsOwnPoints``).
    func testTheSouthIslandLineIsBoughtAlone() throws {
        let session = try hongKong()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:SIL" })
        XCTAssertTrue(line.standsOnItsOwnPoints)
        let offer = session.realLineOffer(for: line)
        XCTAssertNil(offer.problem)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        let bought = try XCTUnwrap(session.world.acquisition(of: "hkmtr:SIL"))
        let ran = try XCTUnwrap(session.world.line(id: try XCTUnwrap(bought.line)))
        XCTAssertEqual(ran.assignedTrains.count, 10)
        for id in ran.assignedTrains {
            XCTAssertNotNil(try XCTUnwrap(session.world.train(id: id)).position)
        }
        // No line of Taiwan's is laid so.
        XCTAssertFalse(RealBranchLine.urbanLines.contains { rail in
            RealBranchLine(network: rail.network, english: rail.english, chinese: rail.chinese, stops: [], system: rail.system).standsOnItsOwnPoints
        })
    }

    /// Decision 748: at the South Island Line's stations whose real
    /// platform is one island (MTR's station plans), the two tracks either
    /// side of it stand the island's 11 m apart, so the 3D map draws the
    /// island between them; at Ocean Park, two side platforms, 5 m as
    /// before. At the two ends the first loop on the right is the island's
    /// other track; the other loops stand 16 m and more the other way, so
    /// no track nearer either island track is paired with it instead.
    func testTheSouthIslandLinesIslandsStandWideApart() throws {
        let session = try hongKong()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:SIL" })
        XCTAssertEqual(line.islandStations, ["金鐘", "利東", "黃竹坑", "海怡半島"])
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let snapshot = session.world.railwaySnapshot()
        /// How far apart the station's platform tracks stand: from the
        /// middle of each to the nearest point of each other's track.
        func spacings(_ name: String) throws -> [(i: Int, j: Int, apart: Double)] {
            let station = try XCTUnwrap(session.world.stations.first { $0.name == name && !$0.isDepot }, name)
            let lines = snapshot.platforms.filter { $0.platform.station == station.id && $0.points.count > 1 }
                .map { $0.points.map { WorldVector($0.plan) } }
            func away(_ point: WorldVector, _ line: [WorldVector]) -> Double {
                zip(line, line.dropFirst()).map { a, b in
                    let along = b - a, length = along.length
                    let t = length > 0 ? min(1, max(0, (point - a).dot(along) / (length * length))) : 0
                    return (point - (a + along * t)).length
                }.min() ?? .infinity
            }
            return lines.indices.flatMap { i in
                lines.indices.filter { $0 > i }.map { (i, $0, away(lines[i][lines[i].count / 2], lines[$0]) / metre) }
            }
        }
        for name in ["金鐘", "利東", "黃竹坑", "海怡半島"] {
            let pairs = try spacings(name)
            // The island's two tracks, wide enough apart for it (on a
            // curve the purchase's tracks stray a metre or two from their
            // offsets), and no other track nearer either of them to be
            // paired with it instead.
            let island = try XCTUnwrap(pairs.first { $0.apart > 10.4 && $0.apart < 15 }, "\(name): \(pairs)")
            let nearer = pairs.filter { pair in
                pair.apart < island.apart && [pair.i, pair.j].contains { [island.i, island.j].contains($0) }
            }
            XCTAssertTrue(nearer.isEmpty, "\(name): \(pairs)")
        }
        let ocean = try spacings("海洋公園")
        XCTAssertEqual(ocean.count, 1)
        XCTAssertEqual(try XCTUnwrap(ocean.first).apart, 5, accuracy: 0.6)
    }

    /// Decision 712, later: the Airport Express's station at the airport
    /// is the airport's station, so its passengers ride the line.
    func testTheAirportExpressServesTheAirport() throws {
        let session = try hongKong()
        XCTAssertNil(session.world.airportDays().first?.station)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:AEL" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let day = try XCTUnwrap(session.world.airportDays().first)
        XCTAssertEqual(day.airport.name, "香港國際機場")
        let station = try XCTUnwrap(session.world.station(id: try XCTUnwrap(day.station)))
        XCTAssertEqual(station.name, "機場")
        XCTAssertGreaterThan(day.ridersAtMost, 0)
    }

    /// Decision 712 (continued): for the screenshots by day, the Airport
    /// Express bought and run on to the morning, a train is found standing
    /// at Kowloon Station (the stop nearest the place asked for) and
    /// followed, the game paused in daylight.
    func testATrainIsFollowedAtKowloonForTheScreenshot() async throws {
        let session = try hongKong()
        XCTAssertTrue(session.buyForScreenshot("hkmtr:AEL"), session.message?.text ?? "")
        await session.runForScreenshot(until: 7 * 3_600 + 40 * 60)
        let found = await session.followAtStopForScreenshot(on: "hkmtr:AEL", near: (22.3049, 114.1615))
        XCTAssertTrue(found)
        let train = try XCTUnwrap(session.followedTrainID)
        let at = try XCTUnwrap(session.world.train(id: train)?.position.flatMap { session.world.location(of: $0) }?.position.plan)
        let kowloon = try XCTUnwrap(session.world.stations.first { $0.name == "九龍" })
        XCTAssertLessThanOrEqual(max(abs(at.x - kowloon.location.x), abs(at.y - kowloon.location.y)), 120 * WorldCoordinate.unitsPerMetre)
        let clock = session.world.clock.now.seconds % GameTime.secondsPerDay
        XCTAssertTrue((7 * 3_600 + 40 * 60..<10 * 3_600).contains(clock), "\(clock)")
        XCTAssertEqual(session.world.clock.speed, .paused)
    }

    /// No train of a line's day stands overnight between its ends in the
    /// way of the morning's first trains: the train that leaves such a
    /// station to begin the day is gone three minutes before the first
    /// train through reaches it (the Tung Chung Line's four left at 7:40
    /// to 8:00, an hour and more after the first trains queued behind
    /// them, and 22 runs of the day found no train in time).
    func testNoTrainStandsInTheWayOfTheFirstTrains() throws {
        let railways = try HongKongRailwaysTests.railways()
        var checked = 0
        for (id, line) in railways.metroRuns where id.hasPrefix("hkmtr:") {
            for run in line.runs where run.positioning {
                guard let first = run.calls.first, let last = run.calls.last, first.station != line.stops.first, first.station != line.stops.last else { continue }
                let through = line.runs.filter { !$0.positioning }.compactMap { other -> Int64? in
                    let names = other.calls.map(\.station)
                    guard let at = names.firstIndex(of: first.station), at > 0, let end = names.firstIndex(of: last.station), at < end else { return nil }
                    return other.calls[at].arrival
                }
                guard let soonest = through.min() else { continue }
                XCTAssertLessThanOrEqual(first.departure, soonest - 180, "\(id) from \(first.station)")
                checked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 4, "the Tung Chung Line's four")
    }

    /// The two shuttles of two trains, the Disneyland Resort Line and the
    /// LOHAS Park line, each bought alone and run through the morning: no
    /// train deadlocks. With one track at each end, the two trains leaving
    /// the ends at once each waited for the other's platform (Chien,
    /// 2026-11-14: 「迪士尼綫會死結」, at 6:16 and 6:21 of the first day);
    /// each end has a second track (`tools/real-timetables/extract_metro_runs.py`).
    /// The East Rail Line's branch to Lok Ma Chau stood two trains at each
    /// end of two tracks, and its first two trains stopped the same way at
    /// Sheung Shui (Chien, 2026-11-14); each of its ends has a third track.
    func testTheShuttlesDoNotDeadlock() throws {
        for (id, tracks) in [("hkmtr:DRL", 2), ("hkmtr:TKL_LHP", 2), ("hkmtr:EAL_LMC", 3)] {
            let session = try hongKong()
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id })
            XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), "\(id): \(session.message?.text ?? "")")
            let bought = try XCTUnwrap(session.world.acquisition(of: id))
            let ran = try XCTUnwrap(session.world.line(id: try XCTUnwrap(bought.line)))
            for end in [ran.stops.first, ran.stops.last] {
                XCTAssertEqual(session.world.network.platforms(of: try XCTUnwrap(end)).count, tracks, id)
            }
            var played = session.world
            for _ in 0..<(9 * 60) {
                try played.advance(ticks: 1)
                XCTAssertEqual(played.deadlockedTrains(), [], "\(id) at \(played.clock.now.seconds % GameTime.secondsPerDay)")
                if !played.deadlockedTrains().isEmpty { break }
            }
            let after = try XCTUnwrap(played.line(id: ran.id))
            let departures = zip(after.runs, after.runDays).filter { $0.1 != nil }.count
            XCTAssertGreaterThan(departures, 10, id)
        }
    }
}
