@testable import GameCore
import XCTest

/// What the build card reads of an edge over the ground (ARCHITECTURE
/// decision 124, the design's third step): its long section and its price
/// part by part, which add up to what building it charged. Read only: the
/// rules and prices are `TrackSectionTests`'; the worlds here are the same,
/// and every number is worked out by hand (the track price is 100 a pricing
/// length, `testCosts`).
final class TrackLongSectionTests: XCTestCase {
    /// 64 × 64 cells, 4 × 4 blocks of land.
    private static let bounds = try! WorldBounds(width: 262_144, height: 262_144)
    /// The row the test track runs along, in the first row of cells.
    private static let row: Int64 = 2_048

    private func world() -> GameWorld {
        GameWorld(bounds: Self.bounds, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
    }

    /// A world with ground whose block (0, 0) has corner column c at
    /// `columns[c]` metres (the last repeated past the list), every row
    /// alike.
    private func world(columns: [Int]) throws -> GameWorld {
        var world = world()
        let side = GroundBlock.side
        let heights = (0..<side).flatMap { _ in (0..<side).map { Int16(columns[min($0, columns.count - 1)]) } }
        try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights)!])
        return world
    }

    /// Builds a straight edge along the test row and returns its ID and
    /// what it cost.
    private func build(
        _ world: inout GameWorld, from: Int64, to: Int64, z: Int64, structure: TrackStructure
    ) throws -> (id: TrackEdgeID, cost: Money) {
        let before = world.economy.balance
        let a = try world.buildTrackNode(at: WorldCoordinate(x: from, y: Self.row, z: z))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: to, y: Self.row, z: z))
        let id = try world.buildTrackEdge(from: a, to: b, structure: structure)
        return (id, Money(before.amount - world.economy.balance.amount))
    }

    /// Stage S4's world without ground: the track price for every length,
    /// a viaduct's two more apart, no earthwork or piers; the ground at 0 m.
    func testAWorldWithoutGroundSplitsStageS4sPrice() throws {
        var world = world()
        let (id, cost) = try build(&world, from: 1_024, to: 5_120, z: 2_048, structure: .elevated)
        let section = try XCTUnwrap(world.longSection(of: id))
        XCTAssertEqual(section.cost, TrackCostParts(track: Money(400), earthwork: .zero, viaductsAndBridges: Money(800), tunnels: .zero))
        XCTAssertEqual(section.cost.total, cost)
        XCTAssertEqual(section.samples.map(\.distance), [0, 512, 1_536, 2_560, 3_584, 4_096])
        XCTAssertEqual(Set(section.samples.map(\.ground)), [0])
        XCTAssertEqual(Set(section.samples.map(\.rail)), [2_048])
        XCTAssertEqual(Set(section.samples.map(\.kind)), [.viaduct])
        XCTAssertNil(world.longSection(of: .edge(99)))
    }

    /// `TrackSectionTests`' valley 20 m deep: the samples at the ends and
    /// each length's middle, and the price in parts.
    func testAValleysLongSectionAndPriceInParts() throws {
        var world = try world(columns: [20, 20, 0, 0, 20])
        let (id, cost) = try build(&world, from: 1_024, to: 17_408, z: 1_280, structure: .automatic)
        let section = try XCTUnwrap(world.longSection(of: id))
        XCTAssertEqual(section.length, 16_384)
        XCTAssertEqual(section.samples.count, 18)
        XCTAssertEqual(section.samples.map(\.height), [0, 0, 0, 0, 160, 480, 800, 1_120, 1_280, 1_280, 1_280, 1_280, 1_120, 800, 480, 160, 0, 0])
        XCTAssertEqual(section.samples[5], TrackGroundSample(distance: 4_608, rail: 1_280, ground: 800, kind: .embankment, isWater: false))
        XCTAssertEqual(section.samples.first?.kind, .surface)
        XCTAssertEqual(section.samples.last?.kind, .viaduct)
        XCTAssertEqual(section.spans.map(\.kind), [.surface, .embankment, .viaduct])
        // 16 lengths at 100; earthwork 185; 11 viaduct lengths at 2 · 100
        // more, and piers 250.
        XCTAssertEqual(section.cost, TrackCostParts(track: Money(1_600), earthwork: Money(185), viaductsAndBridges: Money(2_450), tunnels: .zero))
        XCTAssertEqual(section.cost.total, cost)
    }

    /// The hill: a tunnel's four prices more for its 16 lengths; the parts
    /// and pulling down the house over the open track add up to the cost.
    func testATunnelsPartsAndTheDemolitionAddUpToTheCost() throws {
        var world = try world(columns: [0, 0, 20, 20, 20, 20, 0])
        _ = try world.placeBuilding(.house, at: PlanPoint(x: 12_800, y: Self.row))
        let beside = try world.placeBuilding(.house, at: PlanPoint(x: 29_696, y: Self.row))
        let demolition = world.clearingCost(of: [beside])
        let (id, cost) = try build(&world, from: 1_024, to: 33_792, z: 0, structure: .automatic)
        let section = try XCTUnwrap(world.longSection(of: id))
        XCTAssertEqual(section.cost.track, Money(3_200))
        XCTAssertEqual(section.cost.tunnels, Money(6_400))
        XCTAssertEqual(section.cost.viaductsAndBridges, .zero)
        XCTAssertGreaterThan(section.cost.earthwork, .zero)
        XCTAssertEqual(section.cost.total + demolition, cost)
        XCTAssertTrue(section.samples.contains { $0.kind == .tunnel && $0.height < -TrackSectionRules.deepestCutting })
    }

    /// The lake: the lengths over it are marked wet and carried by a
    /// bridge, which costs three prices more a length.
    func testABridgesLengthsAreOverWater() throws {
        var world = try world(columns: [0])
        try world.setWater([CellPosition(row: 0, column: 2)])
        let (id, cost) = try build(&world, from: 1_024, to: 17_408, z: 512, structure: .automatic)
        let section = try XCTUnwrap(world.longSection(of: id))
        XCTAssertEqual(section.samples.indices.filter { section.samples[$0].isWater }, [8, 9, 10, 11])
        XCTAssertEqual(section.samples.filter(\.isWater).map(\.kind), [.bridge, .bridge, .bridge, .bridge])
        XCTAssertEqual(section.cost, TrackCostParts(track: Money(1_600), earthwork: Money(2_394), viaductsAndBridges: Money(1_200), tunnels: .zero))
        XCTAssertEqual(section.cost.total, cost)
    }
}
