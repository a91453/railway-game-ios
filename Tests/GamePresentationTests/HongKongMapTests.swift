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

    /// A game on Hong Kong's map with its railways and its people, as the
    /// launcher starts it.
    private func hongKong(demo: Bool = false) throws -> GameSession {
        let ground = try Self.ground()
        var world = GameWorld.newOverseasGame(ground, balance: Money(100_000_000_000))
        if demo { world.setUnlimitedFunds(true) }
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try HongKongRailwaysTests.railways()
        session.population = ground.population
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

    /// With no city open the real-world data holds no ground, and reads
    /// what it did.
    func testNoGroundIsReadWhileNoCityIsOpen() {
        XCTAssertEqual(OverseasMaps.open, [])
        XCTAssertTrue(RealWorldData.load(file: RealWorldDataLoadTests.file).overseas.isEmpty)
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
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        let session = try XCTUnwrap(launcher.session)
        XCTAssertTrue(ground.holds(session.world))
        XCTAssertNotNil(session.world.landBlocks, "its land is read in as it is needed")
        XCTAssertEqual(session.population?.total, ground.population?.total)
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

    /// Each line on sale is bought, one after another on the same map:
    /// none is refused, each has its trains, and the land round its
    /// stations is read in with Hong Kong's people.
    func testEveryLineOnSaleIsBought() throws {
        let session = try hongKong()
        for id in session.buyableRealLines.map(\.id).sorted() {
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, id)
            let offer = session.realLineOffer(for: line)
            XCTAssertNil(offer.problem, "\(id): \(offer.problem ?? "")")
            XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(session.message?.text ?? "")")
            let bought = try XCTUnwrap(session.world.acquisition(of: id), id)
            let ran = try XCTUnwrap(session.world.line(id: try XCTUnwrap(bought.line)), id)
            XCTAssertFalse(ran.assignedTrains.isEmpty, id)
        }
        XCTAssertGreaterThan(session.world.land.cells.reduce(0) { $0 + $1.residents }, 100_000)
        XCTAssertEqual(session.buyableRealLines.map(\.id), [])
    }

    /// The Tung Chung Line bought and run for two days on the map: every
    /// run of the second day was sent out, and people rode.
    func testTheTungChungLineRunsOnTheMap() throws {
        let session = try hongKong()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:TCL" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        var played = session.world
        let bought = try XCTUnwrap(played.acquisition(of: "hkmtr:TCL"))
        for _ in 0..<51 { try played.advance(ticks: 60) }
        let ran = try XCTUnwrap(played.line(id: try XCTUnwrap(bought.line)))
        let today = played.clock.now.seconds / GameTime.secondsPerDay
        let missed = zip(ran.runs, ran.runDays).filter { run, day in
            run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
        }
        XCTAssertEqual(missed.count, 0, "runs not sent out yesterday: \(missed.count) of \(ran.runs.count)")
        XCTAssertGreaterThan(played.accounts.days.last?.fareRevenue ?? .zero, .zero, "people rode")
    }

    /// The demo mode's real lines, laid over the whole map at once: all
    /// twelve of the MTR, every one with trains standing on its track
    /// (#2099's two faults: a station with a platform on one track only,
    /// and a terminus the returning train cannot call at).
    func testTheDemoLaysEveryLineWithTrains() async throws {
        let session = try hongKong(demo: true)
        let view = WorldRegion(bounds: session.world.bounds)
        let outcome = await session.layDemoRealLines(in: view, routes: .max, anyWidth: true) { $0.system.id == "hkmtr" }
        XCTAssertEqual(outcome?.lines, 12, session.message?.text ?? "")
        XCTAssertEqual(session.world.lines.count, 12)
        for line in session.world.lines {
            XCTAssertFalse(line.assignedTrains.isEmpty, "\(line.name) has no train")
            for id in line.assignedTrains {
                XCTAssertNotNil(try XCTUnwrap(session.world.train(id: id)).position, "\(line.name)")
            }
        }
    }
}
