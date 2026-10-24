import Foundation
@testable import GameCore
import XCTest

/// Buying the map (ARCHITECTURE decision 160): a world split into tiles of
/// a new game's size, of which the company owns some, builds only on them,
/// and buys the others one at a time next to one it owns, once its best
/// day has carried enough riders.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class MapExpansionTests: XCTestCase {
    /// A tile's side, 16.384 km.
    private let length = MapExpansion.tileLength
    private let middle = MapTile(row: 2, column: 2)

    /// A blank world of 5 × 5 tiles (81.92 km a side) owning the middle
    /// tile, with `balance` in cents, managed unless `free`, each tile
    /// beyond the first needing `step` riders of the best day.
    private func world(
        balance: Money = 10_000_000_000, free: Bool = false, seed: UInt32? = 7, step: Int64 = MapExpansion.standardRidersStep
    ) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 5 * length, height: 5 * length), economy: GameEconomy(balance: balance, costs: testCosts),
            clock: GameClock(speed: .paused)
        )
        if !free { world.setEconomyMode(.management) }
        try world.enableMapExpansion(owning: middle, townSeed: seed, ridersStep: step)
        return world
    }

    /// The point `x`, `y` tiles from the world's north-west corner: 2.5,
    /// 2.5 is the middle of the middle tile.
    private func at(_ x: Double, _ y: Double) -> PlanPoint {
        PlanPoint(x: Int64(x * Double(length)), y: Int64(y * Double(length)))
    }

    // MARK: - Tiles

    func testTheWorldIsSplitIntoTilesOfANewGamesSize() throws {
        XCTAssertEqual(length, 1_048_576)
        XCTAssertEqual(MapExpansion.rows(in: WorldBounds.standard), 1)
        let world = try world()
        XCTAssertEqual(world.mapTileRows, 5)
        XCTAssertEqual(world.mapTileColumns, 5)
        XCTAssertEqual(MapExpansion.tile(at: PlanPoint(x: 2 * length - 1, y: 2 * length)), MapTile(row: 2, column: 1))
        XCTAssertEqual(MapExpansion.tile(at: PlanPoint(x: 2 * length, y: 3 * length - 1)), middle)
        // A world whose side is not whole tiles: its last tile is cut.
        let odd = GameWorld(bounds: try WorldBounds(width: length + 10, height: length), economy: GameEconomy(balance: 0))
        XCTAssertEqual(odd.mapTileColumns, 2)
        XCTAssertEqual(odd.mapArea(of: MapTile(row: 0, column: 1)), MapTileArea(minX: length, minY: 0, maxX: length + 10, maxY: length))
        XCTAssertFalse(odd.isOnMap(MapTile(row: 1, column: 0)))
        XCTAssertFalse(odd.isOnMap(MapTile(row: 0, column: -1)))
        // A world that does not buy its map owns all of it.
        XCTAssertTrue(odd.ownsGround(at: PlanPoint(x: length + 5, y: 0)))
        XCTAssertTrue(odd.ownsMapTile(MapTile(row: 0, column: 1)))
        XCTAssertEqual(odd.mapTilesForSale(), [])
    }

    func testTheMiddleTileStartsOwnedAndItsNeighboursAreForSale() throws {
        let world = try world()
        XCTAssertEqual(world.mapExpansion?.owned, [middle])
        XCTAssertTrue(world.ownsGround(at: at(2.5, 2.5)))
        XCTAssertFalse(world.ownsGround(at: at(1.5, 2.5)))
        XCTAssertEqual(world.mapTilesForSale(), [
            MapTile(row: 1, column: 2), MapTile(row: 2, column: 1), MapTile(row: 2, column: 3), MapTile(row: 3, column: 2),
        ])
    }

    func testEnablingNeedsATileHoldingEverythingBuilt() throws {
        var world = GameWorld(bounds: try WorldBounds(width: 5 * length, height: 5 * length), economy: GameEconomy(balance: 100_000, costs: testCosts))
        XCTAssertThrowsGameError(try world.enableMapExpansion(owning: MapTile(row: 5, column: 0), townSeed: nil), .invalidMapTile)
        try world.buildStation(named: "West", at: at(0.5, 2.5))
        let before = world
        XCTAssertThrowsGameError(try world.enableMapExpansion(owning: middle, townSeed: nil), .invalidMapTile)
        XCTAssertEqual(world, before)
        try world.enableMapExpansion(owning: MapTile(row: 2, column: 0), townSeed: nil)
        XCTAssertEqual(world.mapExpansion, MapExpansion(owned: [MapTile(row: 2, column: 0)], townSeed: nil))
    }

    /// Turning it on again would start over from one tile while the land
    /// bought stays in the books: it is turned on once.
    func testItIsTurnedOnOnce() throws {
        var world = try world()
        world.mapExpansion?.bestDayRiders = 100_000
        try world.buyMapTile(MapTile(row: 2, column: 3))
        XCTAssertEqual(world.accounts.assets.filter { $0.kind == .mapTile }.count, 1)
        let before = world
        XCTAssertThrowsGameError(try world.enableMapExpansion(owning: middle, townSeed: 7), .mapExpansionEnabled)
        XCTAssertThrowsGameError(try world.enableMapExpansion(owning: MapTile(row: 2, column: 3), townSeed: nil), .mapExpansionEnabled)
        XCTAssertEqual(world, before)
    }

    // MARK: - Building only on the company's own ground

    func testStationsAndTrackStandOnlyOnTilesOwned() throws {
        var world = try world()
        let west = at(1.9, 2.5)
        let before = world
        XCTAssertThrowsGameError(try world.buildStation(named: "West", at: west), .mapTileNotOwned(MapTile(row: 2, column: 1)))
        XCTAssertThrowsGameError(try world.buildTrackNode(at: WorldCoordinate(x: west.x, y: west.y, z: 0)), .mapTileNotOwned(MapTile(row: 2, column: 1)))
        XCTAssertEqual(world, before)
        try world.buildStation(named: "Middle", at: at(2.5, 2.5))
        XCTAssertEqual(world.stations.count, 1)
    }

    /// A straight edge between two tiles owned that cuts across the corner
    /// of one not owned is refused, naming it.
    func testAnEdgeMayNotCrossATileNotOwned() throws {
        var world = try world()
        world.mapExpansion?.owned = [middle, MapTile(row: 2, column: 3), MapTile(row: 3, column: 3)]
        let a = try world.buildTrackNode(at: WorldCoordinate(x: at(2.1, 2.9).x, y: at(2.1, 2.9).y, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: at(3.1, 3.9).x, y: at(3.1, 3.9).y, z: 0))
        // From (2.1, 2.9) to (3.1, 3.9) the line crosses y = 3 at x = 2.2,
        // in tile (3, 2).
        let before = world
        XCTAssertThrowsGameError(try world.buildTrackEdge(from: a, to: b), .mapTileNotOwned(MapTile(row: 3, column: 2)))
        XCTAssertEqual(world, before)
        // Along the tiles owned it is built.
        let c = try world.buildTrackNode(at: WorldCoordinate(x: at(3.1, 2.9).x, y: at(3.1, 2.9).y, z: 0))
        try world.buildTrackEdge(from: a, to: c)
        try world.buildTrackEdge(from: c, to: b)
        XCTAssertEqual(world.network.edges.count, 2)
    }

    /// A curve that keeps to the tile owned may be pulled by control points
    /// beyond it (a Bézier curve goes only three quarters of the way to
    /// them): it is built, and the save, which checks the track as it is
    /// built, loads.
    func testACurveWhoseControlPointsLieBeyondTheTileOwnedLoads() throws {
        var world = try world()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: at(2.4, 2.9).x, y: at(2.4, 2.9).y, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: at(2.6, 2.9).x, y: at(2.6, 2.9).y, z: 0))
        // The curve reaches y = 2.99 tiles, short of the tile below.
        try world.buildTrackEdge(from: a, to: b, curve: .cubic(at(2.4, 3.02), at(2.6, 3.02)))
        XCTAssertFalse(world.ownsMapTile(MapTile(row: 3, column: 2)))
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
        // One that does reach it is refused.
        XCTAssertThrowsGameError(try world.buildTrackEdge(from: a, to: b, curve: .cubic(at(2.4, 3.2), at(2.6, 3.2))),
                                 .mapTileNotOwned(MapTile(row: 3, column: 2)))
    }

    /// Splitting an edge samples each part afresh, so a part of a curve
    /// that keeps one unit inside the tile owned can reach a unit beyond
    /// it: the split is refused rather than leaving a save that will not
    /// load.
    func testASplitStaysOnTheTilesOwned() throws {
        var world = try world()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_621_440, y: 3_144_653, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 2_624_657, y: 3_144_179, z: 0))
        let edge = try world.buildTrackEdge(
            from: a, to: b, curve: .cubic(PlanPoint(x: 2_622_843, y: 3_146_819), PlanPoint(x: 2_619_950, y: 3_145_208))
        )
        XCTAssertEqual(world.network.geometry(of: edge)?.points.map(\.plan.y).max(), 3 * length - 1)
        let before = world
        XCTAssertThrowsGameError(try world.splitTrackEdge(edge, at: 1_102), .mapTileNotOwned(MapTile(row: 3, column: 2)))
        XCTAssertEqual(world, before)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
    }

    func testTheLineTestIsExact() {
        let a = PlanPoint(x: 0, y: 0), b = PlanPoint(x: 10, y: 10)
        XCTAssertTrue(GameWorld.segment(a, b, touchesMinX: 5, minY: 5, maxX: 20, maxY: 20))
        // Passing the rectangle's corner on the far side.
        XCTAssertFalse(GameWorld.segment(a, b, touchesMinX: 6, minY: 0, maxX: 20, maxY: 4))
        // Touching it at a corner counts.
        XCTAssertTrue(GameWorld.segment(a, b, touchesMinX: 10, minY: 10, maxX: 12, maxY: 12))
        // Short of it.
        XCTAssertFalse(GameWorld.segment(a, b, touchesMinX: 11, minY: 11, maxX: 12, maxY: 12))
    }

    func testBuildingsAndZonesStayOnTilesOwned() throws {
        var world = try world()
        // An office block 32 m a side centred 8 m inside the middle tile's
        // west edge reaches 8 m over it.
        let edge = 2 * length
        let before = world
        XCTAssertThrowsGameError(
            try world.placeBuilding(.office, at: PlanPoint(x: edge + 8 * 64, y: at(2.5, 2.5).y)), .mapTileNotOwned(MapTile(row: 2, column: 1))
        )
        // Cells 511 and 512 lie either side of that edge (256 cells a tile).
        XCTAssertThrowsGameError(try world.setZone(.residential, rows: 600...601, columns: 511...512), .mapTileNotOwned(MapTile(row: 2, column: 1)))
        XCTAssertEqual(world, before)
        try world.placeBuilding(.office, at: PlanPoint(x: edge + 16 * 64, y: at(2.5, 2.5).y))
        XCTAssertEqual(try world.setZone(.residential, rows: 600...601, columns: 512...513), 4)
    }

    // MARK: - Buying a tile

    func testBuyingIsCheckedInOrder() throws {
        var plain = GameWorld(bounds: try WorldBounds(width: 5 * length, height: 5 * length), economy: GameEconomy(balance: 0))
        XCTAssertThrowsGameError(try plain.buyMapTile(middle), .mapExpansionNotEnabled)
        var world = try world(balance: 400_000_000)
        let before = world
        XCTAssertThrowsGameError(try world.buyMapTile(MapTile(row: -1, column: 2)), .invalidMapTile)
        XCTAssertThrowsGameError(try world.buyMapTile(middle), .mapTileOwned)
        XCTAssertThrowsGameError(try world.buyMapTile(MapTile(row: 1, column: 1)), .mapTileNotAdjacent)
        XCTAssertThrowsGameError(try world.buyMapTile(MapTile(row: 2, column: 1)), .mapExpansionLocked(ridersNeeded: 100_000))
        world.mapExpansion?.bestDayRiders = 100_000
        let unlocked = world
        XCTAssertThrowsGameError(
            try world.buyMapTile(MapTile(row: 2, column: 1)), .insufficientFunds(required: 500_000_000, available: 400_000_000)
        )
        XCTAssertEqual(world, unlocked)
        XCTAssertNotEqual(world, before)
    }

    /// One tile more for every 100,000 riders of the best day; the price
    /// rises by $5 million for each tile owned.
    func testTheMilestonesAndPrices() throws {
        var world = try world(seed: nil)
        world.mapExpansion?.bestDayRiders = 199_999
        XCTAssertEqual(world.mapExpansion?.allowance, 2)
        XCTAssertEqual(world.mapExpansion?.nextPrice, 500_000_000)
        try world.buyMapTile(MapTile(row: 2, column: 1))
        XCTAssertEqual(world.economy.balance, 9_500_000_000)
        XCTAssertEqual(world.mapExpansion?.nextPrice, 1_000_000_000)
        XCTAssertThrowsGameError(try world.buyMapTile(MapTile(row: 2, column: 0)), .mapExpansionLocked(ridersNeeded: 200_000))
        world.mapExpansion?.bestDayRiders = 200_000
        try world.buyMapTile(MapTile(row: 2, column: 0))
        XCTAssertEqual(world.economy.balance, 8_500_000_000)
        XCTAssertEqual(world.mapExpansion?.owned, [MapTile(row: 2, column: 0), MapTile(row: 2, column: 1), middle])
        XCTAssertEqual(MapExpansion.ridersNeeded(toOwn: 25), 2_400_000)
    }

    /// Decision 401: a tile under a real line bought with it passes the
    /// milestone, at the same price; the other checks stand.
    func testATileBoughtWithARealLinePassesTheMilestone() throws {
        var world = try world(seed: nil)
        XCTAssertThrowsGameError(try world.buyMapTile(MapTile(row: 2, column: 1)), .mapExpansionLocked(ridersNeeded: 100_000))
        XCTAssertThrowsGameError(try world.buyMapTile(MapTile(row: 1, column: 1), passingMilestone: true), .mapTileNotAdjacent)
        try world.buyMapTile(MapTile(row: 2, column: 1), passingMilestone: true)
        try world.buyMapTile(MapTile(row: 2, column: 0), passingMilestone: true)
        XCTAssertEqual(world.economy.balance, 8_500_000_000)
        XCTAssertEqual(world.mapExpansion?.owned, [MapTile(row: 2, column: 0), MapTile(row: 2, column: 1), middle])
    }

    /// A managed company books a tile as land, never written down.
    func testATileIsLandOnTheBooks() throws {
        var world = try world(seed: nil)
        world.mapExpansion?.bestDayRiders = 100_000
        try world.buyMapTile(MapTile(row: 1, column: 2))
        let record = try XCTUnwrap(world.accounts.assets.last)
        XCTAssertEqual(record.kind, .mapTile)
        XCTAssertEqual(record.owner, 7, "row 1 × 5 columns + column 2")
        XCTAssertEqual(record.cost, 500_000_000)
        XCTAssertEqual(world.balanceSheet().land, AssetClassBalance(cost: 500_000_000, depreciation: .zero))
        XCTAssertEqual(world.balanceSheet().equity, 10_000_000_000)
        XCTAssertEqual(AssetClass.land.lifeDays, 0)
        var day = record
        XCTAssertEqual(day.depreciateOneDay(), .zero)
        XCTAssertEqual(day.days, 0)
    }

    /// Free play needs no milestone, pays and keeps no record.
    func testFreePlayBuysWithoutAMilestone() throws {
        var world = try world(free: true, seed: nil)
        try world.buyMapTile(MapTile(row: 2, column: 3))
        XCTAssertEqual(world.economy.balance, 9_500_000_000)
        XCTAssertEqual(world.accounts.assets, [])
        XCTAssertEqual(world.mapTileQuote(MapTile(row: 2, column: 4))?.ridersNeeded, 0)
    }

    /// A tile bought on a blank map grows the towns a new game's map would
    /// with the tile's own seed, laid in the tile.
    func testABoughtTileGrowsItsTowns() throws {
        var world = try world(seed: 7)
        world.mapExpansion?.bestDayRiders = 100_000
        let tile = MapTile(row: 2, column: 3)
        try world.buyMapTile(tile)
        let seed = MapExpansion.townSeed(of: tile, from: 7)
        let expected = Land.towns(seed: seed, in: .standard).cells.map {
            LandCell(row: $0.row + 512, column: $0.column + 768, use: $0.use, residents: $0.residents, jobs: $0.jobs)
        }
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(world.land.cells, expected)
        XCTAssertNotEqual(seed, MapExpansion.townSeed(of: MapTile(row: 2, column: 1), from: 7))
    }

    /// A new game's towns on the middle tile of 5 × 5 are the ones a new
    /// game of one tile has, moved to it.
    func testTheMiddleTilesTownsAreANewGamesTowns() throws {
        let one = Land.towns(seed: 42, in: .standard).cells
        let five = Land.towns(seed: 42, in: try WorldBounds(width: 5 * length, height: 5 * length)).cells
        XCTAssertEqual(five, one.map { LandCell(row: $0.row + 512, column: $0.column + 512, use: $0.use, residents: $0.residents, jobs: $0.jobs) })
    }

    // MARK: - The riders each tile needs (decision 167)

    /// A real place's first tile may hold too few people to carry 100,000
    /// riders a day, so a map has its own step: the allowance, the riders
    /// each tile needs, the refusal and the quote all follow it.
    func testAMapsOwnStepSetsTheMilestones() throws {
        var world = try world(seed: nil, step: 25_000)
        XCTAssertEqual(world.mapExpansion?.ridersStep, 25_000)
        XCTAssertEqual(world.mapExpansion?.allowance, 1)
        XCTAssertThrowsGameError(try world.buyMapTile(MapTile(row: 2, column: 1)), .mapExpansionLocked(ridersNeeded: 25_000))
        // 74,999 riders: one tile and two more.
        world.mapExpansion?.bestDayRiders = 74_999
        XCTAssertEqual(world.mapExpansion?.allowance, 3)
        try world.buyMapTile(MapTile(row: 2, column: 1))
        try world.buyMapTile(MapTile(row: 2, column: 0))
        // $50 a rider of the step for each tile owned: $1.25 million, then $2.5 million.
        XCTAssertEqual(world.economy.balance, 10_000_000_000 - 125_000_000 - 250_000_000)
        XCTAssertEqual(world.mapExpansion?.nextPrice, 375_000_000)
        XCTAssertThrowsGameError(try world.buyMapTile(MapTile(row: 1, column: 2)), .mapExpansionLocked(ridersNeeded: 75_000))
        let quote = try XCTUnwrap(world.mapTileQuote(MapTile(row: 1, column: 2)))
        XCTAssertEqual(quote.ridersNeeded, 75_000)
        XCTAssertFalse(quote.isUnlocked)
        world.mapExpansion?.bestDayRiders = 75_000
        XCTAssertTrue(try XCTUnwrap(world.mapTileQuote(MapTile(row: 1, column: 2))).isUnlocked)
        XCTAssertEqual(world.mapExpansion?.ridersNeeded(toOwn: 4), 75_000)
        XCTAssertEqual(world.mapExpansion?.ridersNeeded(toOwn: 1), 0)
        XCTAssertEqual(MapExpansion.ridersNeeded(toOwn: 4, step: 25_000), 75_000)
        XCTAssertEqual(MapExpansion.ridersNeeded(toOwn: 4), 300_000, "a map that says nothing asks the standard 100,000 a tile")
    }

    /// The price of a tile is $50 for each rider of the step, for each tile
    /// owned: the standard step's $5 million, a country town's less, and no
    /// overflow at the most.
    func testThePriceFollowsTheStep() throws {
        XCTAssertEqual(MapExpansion(owned: [middle], townSeed: nil).nextPrice, 500_000_000)
        XCTAssertEqual(MapExpansion(owned: [middle], townSeed: nil, ridersStep: 21_000).nextPrice, 105_000_000, "$1.05 million")
        let two = [middle, MapTile(row: 2, column: 3)]
        XCTAssertEqual(MapExpansion(owned: two, townSeed: nil, ridersStep: 21_000).nextPrice, 210_000_000)
        XCTAssertEqual(MapExpansion(owned: [middle], townSeed: nil, ridersStep: 1).nextPrice, 5_000, "$50")
        // A world of the most tiles, all owned but one, at the most.
        let all = (0..<1_023).map { MapTile(row: $0 / 32, column: $0 % 32) }
        let dearest = MapExpansion(owned: all, townSeed: nil, ridersStep: MapExpansion.maximumRidersStep).nextPrice
        XCTAssertEqual(dearest.amount, 1_023 * 4_294_967_296 * 5_000)
        XCTAssertGreaterThan(dearest.amount, 0)
    }

    /// The step is the map's, from 1 to 2^32; the refusal comes after
    /// "turned on already" and before the tile, and changes nothing.
    func testAStepOutOfRangeIsRefused() throws {
        var world = GameWorld(bounds: try WorldBounds(width: 5 * length, height: 5 * length), economy: GameEconomy(balance: 100_000, costs: testCosts))
        let before = world
        for step: Int64 in [0, -1, MapExpansion.maximumRidersStep + 1, .min, .max] {
            XCTAssertThrowsGameError(try world.enableMapExpansion(owning: middle, townSeed: nil, ridersStep: step), .invalidRidersStep)
        }
        XCTAssertEqual(world, before)
        XCTAssertThrowsGameError(
            try world.enableMapExpansion(owning: MapTile(row: 9, column: 9), townSeed: nil, ridersStep: 0), .invalidRidersStep
        )
        try world.enableMapExpansion(owning: middle, townSeed: nil, ridersStep: MapExpansion.maximumRidersStep)
        XCTAssertEqual(world.mapExpansion?.ridersStep, 4_294_967_296)
        XCTAssertEqual(world.mapExpansion?.ridersNeeded(toOwn: 25), 24 * 4_294_967_296)
        XCTAssertThrowsGameError(try world.enableMapExpansion(owning: middle, townSeed: nil, ridersStep: 0), .mapExpansionEnabled)
        // A map made directly keeps to the range too.
        XCTAssertEqual(MapExpansion(owned: [middle], townSeed: nil, ridersStep: 0).ridersStep, 1)
        XCTAssertEqual(MapExpansion(owned: [middle], townSeed: nil, ridersStep: .max).ridersStep, MapExpansion.maximumRidersStep)
        XCTAssertEqual(MapExpansion(owned: [middle], townSeed: nil).ridersStep, 100_000)
    }

    /// A step other than the standard is saved, and a bad one is refused.
    func testTheStepIsSavedOnlyWhenItIsNotTheStandard() throws {
        let standard = String(decoding: try JSONEncoder().encode(try world()), as: UTF8.self)
        XCTAssertFalse(standard.contains("ridersStep"), "as before decision 167")
        let own = try world(step: 12_500)
        let data = try JSONEncoder().encode(own)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""ridersStep":12500"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), own)
        for bad in ["0", "-3", "4294967297", #""many""#, "1.5"] {
            let broken = text.replacingOccurrences(of: #""ridersStep":12500"#, with: #""ridersStep":\#(bad)"#)
            XCTAssertNotEqual(broken, text)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(broken.utf8)), bad)
        }
    }

    // MARK: - The best day

    func testTheBestDayIsKeptAtMidnight() throws {
        var world = try world()
        world.accounts.days = [DayAccount(day: 0), DayAccount(day: 1)]
        world.accounts.days[0].fareTrips = 101_000
        world.accounts.days[1].fareTrips = 12_000
        world.recordBestDay(endingWith: 0)
        world.recordBestDay(endingWith: 1)
        XCTAssertEqual(world.mapExpansion?.bestDayRiders, 101_000)
        XCTAssertEqual(world.mapExpansion?.allowance, 2)
    }

    // MARK: - The outside connections

    /// The stations by the edge of the land owned are the outside
    /// connections; a tile bought beyond one makes it ordinary.
    func testTheOutsideConnectionsFollowTheLandOwned() throws {
        var world = try world(seed: nil)
        world.setOutsideConnections(true)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 2 * length + 30_000, y: at(2.5, 2.5).y))
        let middleStation = try world.buildStation(named: "Middle", at: at(2.5, 2.5))
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 3 * length - 64_000, y: at(2.5, 2.5).y))
        XCTAssertTrue(world.isOutsideConnection(west.id))
        XCTAssertFalse(world.isOutsideConnection(middleStation.id))
        XCTAssertTrue(world.isOutsideConnection(east.id))
        world.mapExpansion?.bestDayRiders = 100_000
        let quote = try XCTUnwrap(world.mapTileQuote(MapTile(row: 2, column: 1)))
        XCTAssertEqual(quote.outsideConnectionsLost, [west.id])
        XCTAssertTrue(quote.isUnlocked)
        XCTAssertNil(world.mapTileQuote(MapTile(row: 0, column: 0)))
        try world.buyMapTile(MapTile(row: 2, column: 1))
        XCTAssertFalse(world.isOutsideConnection(west.id))
        XCTAssertTrue(world.isOutsideConnection(east.id))
    }

    /// Without the map bought, the edge is the world's, as before.
    func testWithoutBuyingTheEdgeIsTheWorlds() throws {
        var world = GameWorld(bounds: .standard, economy: GameEconomy(balance: 100_000, costs: testCosts))
        world.setOutsideConnections(true)
        XCTAssertTrue(world.isOutsideConnectionSite(PlanPoint(x: 63_999, y: 500_000)))
        XCTAssertFalse(world.isOutsideConnectionSite(PlanPoint(x: 64_000, y: 500_000)))
        XCTAssertTrue(world.isOutsideConnectionSite(PlanPoint(x: 500_000, y: length - 64_000)))
        XCTAssertFalse(world.isOutsideConnectionSite(PlanPoint(x: 500_000, y: length - 64_001)))
    }

    // MARK: - Saves

    func testTheMapRoundTripsAndBadSavesAreRefused() throws {
        var world = try world()
        world.mapExpansion?.bestDayRiders = 100_000
        try world.buyMapTile(MapTile(row: 1, column: 2))
        try world.buildStation(named: "North", at: at(2.5, 1.5))
        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""owned":[[1,2],[2,2]]"#))
        func refused(_ replacement: String) {
            let bad = text.replacingOccurrences(of: #""owned":[[1,2],[2,2]]"#, with: replacement)
            XCTAssertNotEqual(bad, text)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(bad.utf8)), replacement)
        }
        refused(#""owned":[[2,2],[1,2]]"#)
        refused(#""owned":[[1,2],[1,2],[2,2]]"#)
        refused(#""owned":[[0,2],[2,2]]"#)
        refused(#""owned":[[2,2]]"#)
        refused(#""owned":[]"#)
        refused(#""owned":[[2,2],[9,2]]"#)
    }

    /// Version 42 (decision 167): a map that asks 25,000 riders a tile, its
    /// second tile bought. It saves byte for byte and is the world this
    /// build makes.
    func testVersionFortyTwoKeepsItsStep() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v42-map-expansion-step.json")
        var made = try world(balance: 2_000_000_000, seed: nil, step: 25_000)
        try made.buildStation(named: "Middle", at: at(2.5, 2.5))
        made.mapExpansion?.bestDayRiders = 26_000
        try made.buyMapTile(MapTile(row: 2, column: 3))
        try made.buildStation(named: "East", at: at(3.5, 2.5))
        made.setSpeed(.normal)
        try made.advance(ticks: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["MAP_EXPANSION_STEP_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 42)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.mapExpansion?.ridersStep, 25_000)
        XCTAssertEqual(world.mapExpansion?.owned, [middle, MapTile(row: 2, column: 3)])
        XCTAssertEqual(world.mapExpansion?.allowance, 2)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 42,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    func testVersionFortyKeepsItsMap() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v40-map-expansion.json")
        var made = try world(balance: 2_000_000_000, seed: 7)
        made.setOutsideConnections(true)
        try made.buildStation(named: "Middle", at: at(2.5, 2.5))
        made.mapExpansion?.bestDayRiders = 101_000
        try made.buyMapTile(MapTile(row: 2, column: 3))
        try made.buildStation(named: "East", at: at(3.5, 2.5))
        made.setSpeed(.normal)
        try made.advance(ticks: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["MAP_EXPANSION_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 40)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.mapExpansion?.owned, [middle, MapTile(row: 2, column: 3)])
        XCTAssertEqual(world.mapExpansion?.bestDayRiders, 101_000)
        XCTAssertEqual(world.balanceSheet().land.cost, 500_000_000)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 40,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
