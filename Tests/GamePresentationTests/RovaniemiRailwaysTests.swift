import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 789: Rovaniemi's map pack, VR's Kemijärvi line and the main
/// line's end to Muurola with Fintraffic's real timetables, read only when
/// its map is open, which it is not yet.
@MainActor
final class RovaniemiRailwaysTests: XCTestCase {
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// The bundled files read with Rovaniemi open.
    nonisolated static let open: RealRailways.Loaded = RealRailways.load(overseas: [.rovaniemi], pack: HongKongRailwaysTests.pack) { name, ext in
        try BundledRealData.file(name, ext)
    }

    static func railways() throws -> RealRailways {
        try XCTUnwrap(open.railways)
    }

    nonisolated static func ground() throws -> OverseasGround {
        try OverseasGround(city: .rovaniemi, pack: try XCTUnwrap(HongKongRailwaysTests.pack(.rovaniemi)))
    }

    /// A game on Rovaniemi's map with its railways and its people, as the
    /// launcher would start it.
    static func rovaniemi() throws -> GameSession {
        let ground = try Self.ground()
        var world = GameWorld.newOverseasGame(ground, balance: Money(100_000_000_000))
        try world.mapGround()
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try railways()
        session.population = ground.population
        session.water = ground.water
        session.heights = ground.heights
        return session
    }

    // MARK: - The switch

    /// Rovaniemi is not open: the game reads, offers and credits nothing
    /// of it, and Hong Kong is as it was.
    func testRovaniemiIsNotOpenYet() throws {
        XCTAssertFalse(OverseasMaps.open.contains(.rovaniemi))
        let railways = try HongKongRailwaysTests.railways()
        XCTAssertFalse(railways.lines.contains { $0.system.id == "vr" })
        XCTAssertFalse(railways.metroRuns.keys.contains { $0.hasPrefix("vr:") })
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertFalse(DataSourceCredits.sections(in: language).contains { $0.id == "rovaniemiRailways" })
            XCTAssertTrue(DataSourceCredits.sections(in: language, overseas: [.rovaniemi]).contains { $0.id == "rovaniemiRailways" })
        }
    }

    // MARK: - The railways

    /// The two lines out of Rovaniemi, with their stations in order, all
    /// read without an issue.
    func testTheLinesAndTheirStations() throws {
        XCTAssertEqual(Self.open.issues, [])
        let railways = try Self.railways()
        let lines = railways.lines.filter { $0.system.id == "vr" }
        XCTAssertEqual(Set(lines.map(\.lineKey)), ["vr|KJA", "vr|MUL"])
        let stations = railways.stations.filter { $0.system.id == "vr" }
        XCTAssertEqual(Set(stations.map(\.chinese)), ["羅瓦涅米", "米西", "凱米耶爾維", "穆羅拉"])
        XCTAssertEqual(railways.metroRuns["vr:KJA"]?.stops, ["羅瓦涅米", "米西", "凱米耶爾維"])
        XCTAssertEqual(railways.metroRuns["vr:MUL"]?.stops, ["羅瓦涅米", "穆羅拉"])
    }

    /// The Kemijärvi line runs the real trains: the night train from
    /// Helsinki in every morning (PYO 265, Rovaniemi 07:35, Kemijärvi
    /// 08:50) and back every evening (PYO 274), and more on the busy days
    /// of the week before Christmas; the trains that run through Misi
    /// pass it.
    func testTheKemijarviLineRunsTheRealTrains() throws {
        let runs = try XCTUnwrap(try Self.railways().metroRuns["vr:KJA"])
        let night = try XCTUnwrap(runs.runs.first { $0.train == "PYO 265" })
        XCTAssertEqual(night.calls.first?.departure, 7 * 3600 + 35 * 60)
        XCTAssertEqual(night.calls.last?.arrival, 8 * 3600 + 50 * 60)
        XCTAssertEqual(night.days, [0, 1, 2, 3, 4, 5, 6])
        XCTAssertNotNil(runs.runs.first { $0.train == "PYO 274" })
        XCTAssertTrue(runs.runs.contains { $0.passes == ["米西"] })
        XCTAssertGreaterThanOrEqual(runs.runs.filter { !$0.positioning }.count, 10)
    }

    // MARK: - The map

    /// The map reaches from Muurola to Kemijärvi, with its people, and
    /// every station lies well inside it.
    func testEveryStationLiesOnTheMap() throws {
        let ground = try Self.ground()
        let extent = try XCTUnwrap(HongKongRailwaysTests.pack(.rovaniemi)).extent()
        XCTAssertEqual(extent, MapPack.Extent(north: 66.80, south: 66.30, west: 25.20, east: 27.60))
        XCTAssertNotNil(ground.heights)
        XCTAssertNotNil(ground.water)
        XCTAssertNotNil(ground.baseMap)
        let people = try XCTUnwrap(ground.population)
        XCTAssertGreaterThan(people.total, 50_000)
        let session = try Self.rovaniemi()
        let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
        let region = WorldRegion(bounds: session.world.bounds)
        for station in try Self.railways().stations where station.system.id == "vr" {
            let point = frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)
            let margin = min(point.x - region.minX, region.maxX - point.x, point.y - region.minY, region.maxY - point.y) / metre
            XCTAssertGreaterThan(margin, 1_000, station.chinese)
        }
    }

    /// Both lines are on sale on the map, each is bought with its trains
    /// and runs a whole day. The Kemijärvi line's spare train stands at
    /// Kemijärvi from Saturday night to Thursday on the line's own
    /// platform, and the night train from Helsinki, due in at 08:50, is
    /// held a minute before the game sends it to a loop: a minute, never
    /// more (docs/handoff/ROVANIEMI-MAP-1.md, left for the next pull
    /// request).
    func testBothLinesAreBoughtAndRunADay() throws {
        XCTAssertEqual(try Self.rovaniemi().buyableRealLines.map(\.id).sorted(), ["vr:KJA", "vr:MUL"])
        for (id, trains) in [("vr:KJA", 3), ("vr:MUL", 4)] {
            let session = try Self.rovaniemi()
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id })
            XCTAssertTrue(line.keepsRight)
            let offer = session.realLineOffer(for: line)
            XCTAssertNil(offer.problem, id)
            XCTAssertTrue(session.acquireRealLine(offer), "\(id): \(session.message?.text ?? "")")
            let bought = try XCTUnwrap(session.world.acquisition(of: id))
            let ran = try XCTUnwrap(session.world.line(id: try XCTUnwrap(bought.line)))
            XCTAssertEqual(ran.assignedTrains.count, trains, id)
            var played = session.world
            var stuck = 0, longest = 0
            for _ in 0..<(24 * 60) {
                try played.advance(ticks: 1)
                stuck = played.deadlockedTrains().isEmpty ? 0 : stuck + 1
                longest = max(longest, stuck)
            }
            XCTAssertLessThanOrEqual(longest, 1, id)
            let after = try XCTUnwrap(played.line(id: ran.id))
            XCTAssertGreaterThan(zip(after.runs, after.runDays).filter { $0.1 != nil }.count, 0, id)
        }
    }
}
