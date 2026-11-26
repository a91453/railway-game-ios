import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 1006 (the owner, 2026-11-26: 「overture後面還有一層隨機生成應該也要照當地64m人口格來看吧 如果那個地方沒人住還有房子隨機生成也很怪」
/// 「所以記得整個地圖都需套用」): the game's own houses on a 64 m cell are as
/// many as its people and jobs need, by the city's own floor table, on
/// every map: a cell where a few live has a house or two, not a street of
/// them, and its ground is the land round it.
final class Map3DHousesByPeopleTests: XCTestCase {
    // MARK: - The share

    func testAD1LotsShareIsTheFloorItsPeopleNeed() {
        // A D1 home's table (56 residents, 12 jobs) fills it, and so does
        // a D1 shop's (16 and 72) and an office's (8 and 84).
        for use in [LandUse.residential, .commercial, .office] {
            let table = Building.tableCapacity(of: use, .d1)
            XCTAssertEqual(CitySkyline.fill(residents: table.residents, jobs: table.jobs, density: 1), 1, accuracy: 1e-9, "\(use)")
        }
        XCTAssertEqual(CitySkyline.fill(residents: 0, jobs: 0, density: 1), 0)
        // Three people need 144 of the cell's 3,072 m².
        XCTAssertEqual(CitySkyline.fill(residents: 3, jobs: 0, density: 1), 144.0 / 3_072, accuracy: 1e-12)
        // Living and working both count.
        XCTAssertEqual(CitySkyline.fill(residents: 10, jobs: 15, density: 1), (480.0 + 480) / 3_072, accuracy: 1e-12)
        XCTAssertEqual(CitySkyline.fill(residents: 500, jobs: 0, density: 1), 1)
        // A denser lot is full.
        for density in 2...4 {
            XCTAssertEqual(CitySkyline.fill(residents: 1, jobs: 0, density: density), 1)
        }
        XCTAssertEqual(CitySkyline.Lot(row: 0, column: 0, use: .residential, density: 1, fill: 3).fill, 1)
        XCTAssertEqual(CitySkyline.Lot(row: 0, column: 0, use: .residential, density: 1, fill: -1).fill, 0)
    }

    /// The owner, 2026-11-26: 「但也要顧慮目前照官方的只有日本 日本先做 其他還在使用world pop」.
    /// Only a map whose people and jobs are a census's (Japan's, Taiwan's
    /// since decision 1002, Finland's since decision 1007 and Hong Kong's
    /// since decision 1008) lays the houses by them; the blank map's keep
    /// every lot full.
    func testOnlyACensusMapsHousesFollowItsPeople() throws {
        func look(_ latitude: Double, _ longitude: Double) throws -> Map3DRegionLook.Buildings {
            Map3DRegionLook(anchor: try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()),
                                                            longitude: Int64((longitude * 10_000_000).rounded())))).buildings
        }
        XCTAssertTrue(CitySkyline.housesByPeople(try look(33.5906, 130.3989)), "Fukuoka")
        XCTAssertTrue(CitySkyline.housesByPeople(try look(32.8032, 130.7079)), "Kumamoto")
        XCTAssertTrue(CitySkyline.housesByPeople(try look(25.0478, 121.5170)), "Taipei (decision 1002)")
        XCTAssertTrue(CitySkyline.housesByPeople(try look(22.2819, 114.1582)), "Hong Kong (decision 1008)")
        XCTAssertTrue(CitySkyline.housesByPeople(try look(66.4977, 25.7155)), "Rovaniemi (decision 1007)")
        // The blank map's towns: every lot full, as before.
        let world = GameWorld.newGame()
        let skyline = CitySkyline(world: world)
        XCTAssertFalse(skyline.isEmpty)
        XCTAssertTrue(skyline.lots.allSatisfy { $0.fill == 1 })
    }

    func testAThinLotsGroundIsTheLandsRound() {
        XCTAssertEqual(Map3DPalette.GroundKind(CitySkyline.Lot(row: 0, column: 0, use: .residential, density: 1, fill: 1)), .yard)
        XCTAssertEqual(Map3DPalette.GroundKind(CitySkyline.Lot(row: 0, column: 0, use: .residential, density: 1, fill: CitySkyline.thinFill)), .yard)
        XCTAssertNil(Map3DPalette.GroundKind(CitySkyline.Lot(row: 0, column: 0, use: .residential, density: 1, fill: 0.1)))
        XCTAssertNil(Map3DPalette.GroundKind(CitySkyline.Lot(row: 0, column: 0, use: .commercial, density: 1, fill: 0.1)))
    }

    /// The owner, 2026-11-26: 「但就依現有已存在官方建物+overtrue資料 最後才是隨機補 依比例密集度來看 不要隨便亂補」.
    /// Between real buildings, the game's houses take only the floor the
    /// real ones leave its people: two storeys over a tenth of the cell
    /// (819 m²) is about a quarter of a full D1 lot's 3,072 m².
    func testBetweenRealBuildingsOnlyThePeopleLeftGetHouses() {
        typealias B = Map3DScene.Builder
        XCTAssertEqual(B.fillLeft(1, realShare: 0), 1)
        XCTAssertEqual(B.fillLeft(0.4, realShare: 0), 0.4)
        XCTAssertEqual(B.fillLeft(1, realShare: 0.1), 1 - 819.2 / 3_072, accuracy: 1e-9)
        XCTAssertEqual(B.fillLeft(0.2, realShare: 0.1), 0)
        XCTAssertEqual(B.fillLeft(1, realShare: 0.24), 1 - 0.24 * 8 / 3, accuracy: 1e-9)
    }

    // MARK: - The houses along the roads (real-world maps)

    private func builder() -> (builder: Map3DScene.Builder, cell: Map3DScene.ChunkKey) {
        let world = GameWorld.newGame()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        let cell = Map3DScene.ChunkKey(column: Int(world.bounds.width / 2 / Land.cellLength),
                                       row: Int(world.bounds.height / 2 / Land.cellLength))
        let west = Float(builder.gridLine(cell.column, origin: 0)), north = Float(builder.gridLine(cell.row, origin: 0))
        // A lane slanting across the cell and a street along its south edge.
        for (points, half, kind) in [([Map3DPoint(-40, 0, -6), Map3DPoint(110, 0, 50)], Float(2.5), Map3DBaseMap.RoadKind.minor),
                                     ([Map3DPoint(-40, 0, 66), Map3DPoint(110, 0, 66)], Float(6.5), .secondary)] {
            builder.state.baseMap.roadLines.append((points.map { $0 + Map3DPoint(west, 0, north) }, half))
            builder.state.baseMap.roadKinds.append((kind, false))
        }
        builder.state.roadside.streetFrontage = true
        builder.prepareFrontage()
        return (builder, cell)
    }

    /// A lot laid with fewer people keeps some of the full lot's houses,
    /// where they stood, about as many as its share; with no one, none.
    func testTheHousesAlongTheRoadsAreAsManyAsThePeople() {
        func middles(_ fill: Double) -> [Map3DPoint] {
            var (builder, cell) = builder()
            return builder.layFrontage(cell, density: 1, shops: false, blocked: [], fill: fill).houses.map(\.house.middle)
        }
        let full = middles(1)
        XCTAssertGreaterThan(full.count, 8)
        XCTAssertTrue(middles(0).isEmpty)
        var previous = full
        for fill in [0.75, 0.5, 0.25, 0.05] {
            let some = middles(fill)
            // Each house stands where the lot of the next share up had
            // one (a lot that grows adds houses), but where another road's
            // house the bigger lot kept stood in its way.
            let moved = some.filter { house in !previous.contains { ($0 - house).length < 1e-4 } }
            XCTAssertLessThanOrEqual(moved.count, max(1, some.count / 5), "\(fill)")
            XCTAssertLessThanOrEqual(some.count, previous.count, "\(fill)")
            previous = some
        }
        let half = middles(0.5).count
        XCTAssertGreaterThanOrEqual(half, full.count / 5, "about half of \(full.count)")
        XCTAssertLessThanOrEqual(half, full.count * 4 / 5, "about half of \(full.count)")
    }

    /// The owner, 2026-11-26: 「但記得建物還是需要沿著路平均分散」. Of a side's
    /// houses at a share of 1/2ⁿ, every 2ⁿ in a row hold exactly one, so
    /// none bunch up and no stretch is left bare, whatever the side.
    func testTheHousesKeptAreSpreadEvenlyAlongTheRoad() {
        for (n, fill) in [(1, 0.5), (2, 0.25), (3, 0.125)] {
            let window = 1 << n
            for side: Int32 in [0, 50_000, 100, 300] {
                let kept = (0..<200).map { Map3DScene.Builder.keepsHouse((17, -4), side: side, index: Int32($0), fill: fill) }
                for first in 0...(kept.count - window) {
                    XCTAssertEqual(kept[first..<first + window].filter { $0 }.count, 1, "\(fill) \(side) from \(first)")
                }
            }
        }
        XCTAssertTrue((0..<50).allSatisfy { Map3DScene.Builder.keepsHouse((1, 2), side: 0, index: Int32($0), fill: 1) })
        XCTAssertFalse((0..<50).contains { Map3DScene.Builder.keepsHouse((1, 2), side: 0, index: Int32($0), fill: 0) })
    }

    // MARK: - The rows of houses (blank maps)

    private func drawn(fill: Double) -> Int {
        let world = GameWorld.newGame()
        var near = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        near.addRowHouses(base: .zero, side: 64, density: 1, shops: false, seed: (11, 3), fill: fill)
        return [near.meshes, near.nearMeshes, near.farMeshes].flatMap { $0.values }.map(\.vertices.count).reduce(0, +)
    }

    func testTheRowsOfHousesAreAsManyAsThePeople() {
        let full = drawn(fill: 1), half = drawn(fill: 0.5), few = drawn(fill: 0.1)
        XCTAssertGreaterThan(full, half)
        XCTAssertGreaterThan(half, few)
        XCTAssertEqual(drawn(fill: 0), 0)
    }
}
