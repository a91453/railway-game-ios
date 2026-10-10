import GameCore
import GamePresentation
import XCTest

/// What the player sees of track over the ground (ARCHITECTURE decision
/// 124, the design's third step): the build card's long section and cost
/// in parts, worked out on the preview's copy of the world, and the height
/// and steep slope layer. The worlds are GameCore's `TrackSectionTests`'
/// (the track price 100 a pricing length), so the numbers are the ones
/// worked out by hand there.
@MainActor
final class TerrainPresentationTests: XCTestCase {
    private static let costs = ConstructionCosts(track: 100, station: 1_000, train: 5_000)
    /// The row the test track runs along, in the first row of cells.
    private static let row: Int64 = 2_048

    /// 64 × 64 cells; with `columns`, ground in block (0, 0) whose corner
    /// column c stands `columns[c]` metres (the last repeated), every row
    /// alike.
    private func world(columns: [Int]? = nil) throws -> GameWorld {
        var world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144), economy: GameEconomy(balance: 100_000_000, costs: Self.costs),
            clock: GameClock(speed: .paused)
        )
        if let columns {
            let side = GroundBlock.side
            let heights = (0..<side).flatMap { _ in (0..<side).map { Int16(columns[min($0, columns.count - 1)]) } }
            try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights)!])
        }
        return world
    }

    /// A session whose network tool has picked new points at x = `from`
    /// and `to` on the test row, on the ground.
    private func preview(_ world: GameWorld, from: Int64, to: Int64) -> GameSession {
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: from, y: Self.row), reach: 16)
        session.tapNetwork(at: PlanPoint(x: to, y: Self.row), reach: 16)
        return session
    }

    // MARK: - The build card

    /// The valley 20 m deep: the automatic track on the ground at both ends
    /// is a surface, an embankment and a viaduct; its parts add up to the
    /// cost, and the chart spans the ground's 20 m with a tenth spare.
    func testAValleysCostInPartsAndLongSection() throws {
        let session = preview(try world(columns: [20, 20, 0, 0, 20]), from: 1_024, to: 17_408)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem)
        XCTAssertEqual(preview.cost, Money(4_235))
        let parts = try XCTUnwrap(preview.costParts)
        XCTAssertEqual(parts.track, TrackCostParts(track: Money(1_600), earthwork: Money(185), viaductsAndBridges: Money(2_450), tunnels: .zero))
        XCTAssertEqual(parts.demolition, .zero)
        XCTAssertEqual(parts.total, preview.cost)
        XCTAssertEqual(parts.lines(in: .english).map(\.name), ["Track", "Earthwork", "Viaducts and bridges", "Total"])
        XCTAssertEqual(parts.lines(in: .traditionalChinese).map(\.cost), [Money(1_600), Money(185), Money(2_450), Money(4_235)])
        XCTAssertEqual(parts.lines(in: .traditionalChinese).map(\.name), ["軌道", "土方", "高架與橋", "合計"])

        let section = try XCTUnwrap(preview.longSection)
        let chart = LongSectionChart(section)
        XCTAssertEqual(chart.kinds, [.surface, .embankment, .viaduct])
        XCTAssertEqual(chart.bands.map(\.kind), [.surface, .embankment, .viaduct])
        // From 0 to 1,280 units (20 m), 128 spare either way.
        XCTAssertEqual([chart.bottom, chart.top], [-128, 1_408])
        XCTAssertEqual(chart.rail.first, LongSectionChart.Point(x: 0, y: 1_408.0 / 1_536))
        XCTAssertEqual(chart.ground[8], LongSectionChart.Point(x: 7_680.0 / 16_384, y: 128.0 / 1_536), "the valley's floor")
        XCTAssertEqual(chart.rail.last?.x, 1)
        for point in chart.rail + chart.ground + chart.bands.flatMap(\.outline) {
            XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y), "\(point)")
        }
        // The embankment's outline: the rail from 3,072 to 5,120, then the
        // ground back.
        let embankment = chart.bands[1].outline
        XCTAssertEqual(embankment.first?.x, 3_072.0 / 16_384)
        XCTAssertEqual(embankment.count, 2 * 4)
        XCTAssertTrue(chart.water.isEmpty)
    }

    /// The hill: a tunnel, and pulling down the house beside it is a part
    /// of its own.
    func testATunnelAndTheDemolitionAreLinesOfTheirOwn() throws {
        var world = try world(columns: [0, 0, 20, 20, 20, 20, 0])
        // A managed company pays to pull its buildings down.
        world.setEconomyMode(.management)
        let house = try world.placeBuilding(.house, at: PlanPoint(x: 29_696, y: Self.row))
        let session = preview(world, from: 1_024, to: 33_792)
        let preview = try XCTUnwrap(session.networkPreview)
        let parts = try XCTUnwrap(preview.costParts)
        XCTAssertEqual(parts.track.tunnels, Money(6_400))
        XCTAssertEqual(parts.demolition, world.clearingCost(of: [house]))
        XCTAssertGreaterThan(parts.demolition, .zero)
        XCTAssertEqual(parts.total, preview.cost)
        XCTAssertEqual(parts.lines(in: .traditionalChinese).map(\.name), ["軌道", "土方", "隧道", "拆遷", "合計"])
        XCTAssertEqual(LongSectionChart(try XCTUnwrap(preview.longSection)).kinds, [.surface, .cutting, .tunnel])
    }

    /// The lake: the bridge's lengths are water on the chart; a stretch
    /// GameCore refuses has no parts or section.
    func testABridgeCrossesWaterOnTheChart() throws {
        var world = try world(columns: [0])
        try world.setWater([CellPosition(row: 0, column: 2)])
        let session = preview(world, from: 1_024, to: 17_408)
        // On the ground the track would run over the lake.
        let refused = try XCTUnwrap(session.networkPreview)
        XCTAssertNotNil(refused.problem)
        XCTAssertNil(refused.costParts)
        XCTAssertNil(refused.longSection)
        // 8 m up, a bridge over it.
        session.networkHeight = 512
        let bridge = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(bridge.problem)
        let chart = LongSectionChart(try XCTUnwrap(bridge.longSection))
        XCTAssertEqual(chart.kinds, [.embankment, .bridge])
        XCTAssertEqual(chart.water, [7_168.0 / 16_384 ... 11_264.0 / 16_384])
        XCTAssertEqual(bridge.costParts?.total, bridge.cost)
    }

    /// A level stretch on a world without ground still spans 16 m, the
    /// track in the middle.
    func testAFlatChartSpansSixteenMetres() throws {
        let session = preview(try world(), from: 1_024, to: 5_120)
        let chart = LongSectionChart(try XCTUnwrap(session.networkPreview?.longSection))
        XCTAssertEqual([chart.bottom, chart.top], [-512, 512])
        XCTAssertEqual(Set(chart.rail.map(\.y)), [0.5])
        XCTAssertEqual(session.networkPreview?.costParts?.lines(in: .english).map(\.name), ["Track", "Total"])
    }

    // MARK: - The height and steep slope layer

    func testABlankMapIsFlat() throws {
        let map = TerrainMap(world: try world(), heights: nil)
        XCTAssertTrue(map.isFlat)
        XCTAssertNil(map.height(atX: 2_048, y: 2_048))
        let tiles = map.tiles(in: WorldRegion(minX: 0, minY: 0, maxX: 262_144, maxY: 262_144), blockSize: 4)
        XCTAssertTrue(tiles.shaded.isEmpty && tiles.steep.isEmpty)
    }

    /// Without the heights file the layer reads the ground the world has:
    /// the valley's corners, water left out, a steep cell hatched.
    func testTheLayerReadsTheWorldsGround() throws {
        var world = try world(columns: [20, 20, 0, 0, 20])
        try world.setWater([CellPosition(row: 0, column: 3)])
        try world.setSteep([CellPosition(row: 0, column: 1)])
        let map = TerrainMap(world: world, heights: nil)
        XCTAssertFalse(map.isFlat)
        XCTAssertEqual(map.step, 1)
        XCTAssertEqual(map.height(atX: 0, y: 0), 20)
        XCTAssertEqual(map.height(atX: 6_144, y: 0), 10, "halfway down the valley's side")
        XCTAssertNil(map.height(atX: 70_000, y: 0), "a block not read")
        let tiles = map.tiles(in: WorldRegion(minX: 0, minY: 0, maxX: 20_000, maxY: 1_000))
        XCTAssertEqual(tiles.shaded.map(\.minX), [0, 4_096, 8_192, 16_384], "column 3 is water")
        XCTAssertEqual(tiles.shaded.map(\.value), [20, 10, 0, 20])
        XCTAssertEqual(tiles.steep.map(\.minX), [4_096])
        // The side falling to the east faces away from the light; the flat
        // floor keeps its tint.
        XCTAssertEqual(tiles.shaded[2].color, TerrainMap.tint(metres: 0))
        XCTAssertNotEqual(tiles.shaded[1].color, TerrainMap.tint(metres: 10))
        XCTAssertEqual(map.cellLines(atX: 4_500, y: 100, in: .traditionalChinese), ["海拔 18 公尺", "陡坡（超過 30%）：城市不在這裡開發"])
        XCTAssertEqual(map.cellLines(atX: 13_000, y: 100, in: .english), ["Water"])
    }

    func testShadingFollowsTheLightFromTheNorthWest() {
        let base = TerrainMap.tint(metres: 500)
        XCTAssertEqual(TerrainMap.shade(base, eastward: 0, southward: 0), base)
        // Rising to the south-east, it faces the light; to the north-west,
        // away from it.
        let facing = TerrainMap.shade(base, eastward: 0.5, southward: 0.5)
        let away = TerrainMap.shade(base, eastward: -0.5, southward: -0.5)
        XCTAssertGreaterThan(Int(facing.red) + Int(facing.green) + Int(facing.blue), Int(base.red) + Int(base.green) + Int(base.blue))
        XCTAssertLessThan(Int(away.red) + Int(away.green) + Int(away.blue), Int(base.red) + Int(base.green) + Int(base.blue))
        XCTAssertEqual(TerrainMap.tint(metres: -5), TerrainMap.tints[0].color)
        XCTAssertEqual(TerrainMap.tint(metres: 9_000), TerrainMap.tints.last?.color)
    }

    /// Alishan from the app's heights file: the station's 2,216 m, and the
    /// whole of Taiwan at every few corners.
    func testTheBundledHeightsShowAlishan() throws {
        let grid = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 23.5103, longitudeDegrees: 120.8050))
        let world = GameWorld.newGame(anchor: anchor)
        let map = TerrainMap(world: world, heights: grid)
        let middle = Double(GameWorld.newGameBounds.width / 2)
        XCTAssertEqual(try XCTUnwrap(map.height(atX: middle, y: middle)), 2_216, accuracy: 40)
        // 1 km a side, in blocks of 128 m.
        let region = WorldRegion(minX: middle - 32_768, minY: middle - 32_768, maxX: middle + 32_767, maxY: middle + 32_767)
        XCTAssertEqual(map.tiles(in: region, blockSize: 2).shaded.count, 8 * 8)
    }

    /// A map wider than the layer's corners keeps every few: the last
    /// cells, past the last whole step, are drawn too.
    func testTheLastCellsOfALargeMapHaveTheirHeight() throws {
        let grid = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.0818, longitudeDegrees: 120.5385))
        // 1,031 cells across: a step of 2 leaves one cell past the last.
        let bounds = try WorldBounds(width: 1_031 * Land.cellLength, height: 2 * Land.cellLength)
        let map = TerrainMap(world: GameWorld.newGame(anchor: anchor, bounds: bounds), heights: grid)
        XCTAssertEqual(map.step, 2)
        XCTAssertNotNil(map.height(atX: 1_030.5 * Double(Land.cellLength), y: Double(Land.cellLength) / 2), "the last cell")
        XCTAssertNotNil(map.height(atX: Double(bounds.width - 1), y: Double(bounds.height - 1)), "the south-east corner")
    }

    // MARK: - Slopes on the map

    /// The valley's embankment: two lengths, 2.5 m and 7.5 m high (160 and
    /// 480 units), so slopes 3.75 m and 11.25 m wide (240 and 720) beside a
    /// bed 10 m wide; the track runs east along y = 2,048.
    func testAnEmbankmentsSlopesWidenWithItsHeight() throws {
        var world = try world(columns: [20, 20, 0, 0, 20])
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: Self.row, z: 1_280))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 17_408, y: Self.row, z: 1_280))
        let id = try world.buildTrackEdge(from: a, to: b, structure: .automatic)
        let slopes = TrackSlope.slopes(of: try XCTUnwrap(world.longSection(of: id)), geometry: try XCTUnwrap(world.trackGeometry(of: id)))
        XCTAssertEqual(slopes.map(\.kind), [.embankment, .embankment])
        XCTAssertEqual(slopes[0].bands, [
            [TrackSlope.Point(x: 4_096, y: 2_368), TrackSlope.Point(x: 5_120, y: 2_368), TrackSlope.Point(x: 5_120, y: 2_608), TrackSlope.Point(x: 4_096, y: 2_608)],
            [TrackSlope.Point(x: 4_096, y: 1_728), TrackSlope.Point(x: 5_120, y: 1_728), TrackSlope.Point(x: 5_120, y: 1_488), TrackSlope.Point(x: 4_096, y: 1_488)],
        ])
        XCTAssertEqual(slopes[1].bands[0].last, TrackSlope.Point(x: 5_120, y: 2_048 + 320 + 720))
        XCTAssertEqual(slopes[1].hachures.count, 8)
        // A short hachure hangs from the top of the bank, by the bed.
        XCTAssertEqual(slopes[1].hachures[1], TrackSlope.Hachure(from: TrackSlope.Point(x: 5_504, y: 2_368), to: TrackSlope.Point(x: 5_504, y: 2_728)))
        // In a cutting it hangs from the top of the cut, the band's outer edge.
        var hill = try self.world(columns: [0, 0, 20, 20, 20, 20, 0])
        let c = try hill.buildTrackNode(at: WorldCoordinate(x: 1_024, y: Self.row, z: 0))
        let d = try hill.buildTrackNode(at: WorldCoordinate(x: 33_792, y: Self.row, z: 0))
        let cut = try hill.buildTrackEdge(from: c, to: d, structure: .automatic)
        let cutting = try XCTUnwrap(TrackSlope.slopes(of: try XCTUnwrap(hill.longSection(of: cut)), geometry: try XCTUnwrap(hill.trackGeometry(of: cut))).first)
        XCTAssertEqual(cutting.kind, .cutting)
        let outer = try XCTUnwrap(cutting.bands[0].last)
        XCTAssertEqual(cutting.hachures[1].to.y, outer.y)
    }
    /// Each slope covers its own pricing length, the edge's last and
    /// shorter one included: from where it starts, 16 m from the edge's
    /// start at a time, not 8 m either side of its middle.
    func testTheLastShortLengthsSlopeCoversOnlyThatLength() throws {
        var world = try world(columns: [20, 20, 14, 14])
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: Self.row, z: 1_280))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 7_000, y: Self.row, z: 1_280))
        let id = try world.buildTrackEdge(from: a, to: b, structure: .automatic)
        let section = try XCTUnwrap(world.longSection(of: id))
        XCTAssertEqual(section.samples.dropFirst().dropLast().last?.kind, .embankment, "the short last length is a bank")
        let slopes = TrackSlope.slopes(of: section, geometry: try XCTUnwrap(world.trackGeometry(of: id)))
        let last = try XCTUnwrap(slopes.last)
        XCTAssertEqual(last.bands[0].first?.x, 1_024 + 5 * 1_024, "the last length starts 80 m along")
        XCTAssertEqual(last.bands[0][1].x, 7_000)
        for slope in slopes {
            XCTAssertEqual((Int(slope.bands[0][0].x) - 1_024) % 1_024, 0, "\(slope.bands[0])")
        }
    }
}
