import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 585 續 (FERRY-QIJIN): the author, on 115.1: in the ferry mode
/// round Kaohsiung harbour, Shaochuantou and the harbour's north side were
/// marked pale blue, Cijin not at all ("旗津完全沒有淺藍色"). On a map whose
/// land is read in as it is needed (the whole of Taiwan, a demo), a block
/// of 1 km not read yet has no water in the world: Cijin, with no station
/// within 2 km, had no shore, and the sea beside the blocks read had a
/// straight one. A map that comes whole, or a place's first tile, has
/// Cijin's shore (``FerryPierSnapTests``).
@MainActor
final class FerryCijinShoreTests: XCTestCase {
    nonisolated private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The real ferry stations (the Kaohsiung harbour ferry's Cijin and
    /// Gushan stations, as on the map).
    private static let cijinStation = (latitude: 22.6125, longitude: 120.2680)
    private static let gushanStation = (latitude: 22.6197, longitude: 120.2700)

    @MainActor private struct Map {
        let session: GameSession
        let frame: RealWorldFrame
        let water: WaterGrid

        func cell(_ latitude: Double, _ longitude: Double) -> CellPosition {
            let (x, y) = frame.worldPosition(latitude: latitude, longitude: longitude)
            return CellPosition(containing: PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded())))
        }

        func metres(_ a: CellPosition, _ b: CellPosition) -> Double {
            let dx = Double(a.column - b.column), dy = Double(a.row - b.row)
            return (dx * dx + dy * dy).squareRoot() * Double(Land.cellLength) / Double(WorldCoordinate.unitsPerMetre)
        }

        func shore(within cells: Int, of centre: CellPosition) -> [CellPosition] {
            guard let overlay = session.ferryMapOverlay else { return [] }
            return overlay.shore.flatMap { run in run.columns.map { CellPosition(row: run.row, column: $0) } }
                .filter { abs($0.row - centre.row) <= cells && abs($0.column - centre.column) <= cells }
        }
    }

    /// The whole of Taiwan with the land read in round a point on the
    /// harbour's north side, 2.5 km north of Cijin's ferry station: the
    /// blocks of Shaochuantou and the harbour are read, Cijin's not, as on
    /// the author's map.
    private func map() throws -> Map {
        let folder = Self.root.appendingPathComponent("RailwayGameApp/Resources/RealWorld")
        let water = try WaterGrid(data: Data(contentsOf: folder.appendingPathComponent("taiwan_water.json")))
        let population = try PopulationGrid(data: Data(contentsOf: folder.appendingPathComponent("taiwan_population.json")))
        var world = GameWorld.newWholeTaiwanGame()
        world.setEconomyMode(.management)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let (x, y) = frame.worldPosition(latitude: 22.635, longitude: 120.280)
        GameSession.readLand(within: WholeTaiwan.landReach, of: [PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded()))],
                             in: &world, population: population, places: nil, water: water)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = population
        session.water = water
        session.selectTool(.bus)
        session.setBusMode(.ferries)
        return Map(session: session, frame: frame, water: water)
    }

    /// The author's map: Cijin's shore is marked, as Shaochuantou's is,
    /// and the sea beside the land read is not.
    func testCijinsShoreIsMarkedBeforeItsLandIsRead() throws {
        let map = try map()
        let world = map.session.world
        let cijin = map.cell(Self.cijinStation.latitude, Self.cijinStation.longitude)
        XCTAssertFalse(try XCTUnwrap(world.landBlocks).contains(LandBlock(cellRow: cijin.row, column: cijin.column)), "Cijin is not read in")
        XCTAssertFalse(map.shore(within: 6, of: map.cell(22.6175, 120.2650)).isEmpty, "Shaochuantou is marked")
        let near = map.shore(within: RealFerry.snapCells, of: cijin)
        print("FERRY-QIJIN shore cells within \(RealFerry.snapCells) of Cijin's ferry station: \(near.count)")
        XCTAssertFalse(near.isEmpty, "旗津完全沒有淺藍色")

        // Every cell marked is land, by the world where it is read and by
        // the app's water where it is not: no straight shore on the sea.
        let all = try XCTUnwrap(map.session.ferryMapOverlay).shore
        let read = Set(try XCTUnwrap(world.landBlocks))
        let wet = Set(map.water.cells(frame: map.frame, bounds: world.bounds, in: Set((-6...6).flatMap { dr in (-6...6).map { dc in
            LandBlock(row: cijin.row / Land.blockCells + dr, column: cijin.column / Land.blockCells + dc)
        } }).subtracting(read)))
        for run in all {
            for column in run.columns {
                let cell = CellPosition(row: run.row, column: column)
                if read.contains(LandBlock(cellRow: cell.row, column: cell.column)) {
                    XCTAssertFalse(world.terrain.isWater(row: cell.row, column: cell.column))
                } else {
                    XCTAssertFalse(wet.contains(cell), "\(cell) is the sea")
                }
            }
        }
    }

    /// A tap at Cijin's ferry station puts a pier on Cijin's shore without
    /// changing the world; the real Gushan–Cijin ferry lays its piers by
    /// the real stations, and its land is read in as it opens.
    func testTheRealGushanCijinFerryOpens() throws {
        let map = try map()
        let session = map.session
        let cijin = map.cell(Self.cijinStation.latitude, Self.cijinStation.longitude)
        let gushan = map.cell(Self.gushanStation.latitude, Self.gushanStation.longitude)

        let before = session.world
        session.tapBusTool(at: cijin.middle, reach: 0)
        let tapped = try XCTUnwrap(session.ferryDraft.first, String(describing: session.message?.text))
        XCTAssertEqual(session.world, before, "a tap reads nothing in")
        XCTAssertLessThanOrEqual(map.metres(tapped, cijin), 300)
        session.undoFerryPier()

        XCTAssertEqual(session.realFerryOffer, .gushanCijin)
        session.traceRealFerry(.gushanCijin)
        let piers = session.ferryDraft
        XCTAssertEqual(piers.count, 2)
        for (pier, station) in zip(piers, [gushan, cijin]) {
            print("FERRY-QIJIN pier \(pier) is \(Int(map.metres(pier, station))) m from the real station")
            XCTAssertLessThanOrEqual(map.metres(pier, station), 300)
        }
        XCTAssertEqual(session.world, before, "laying it reads nothing in")
        // Gushan's on the north bank, Cijin's on the south.
        XCTAssertLessThan(piers[0].row, piers[1].row)
        XCTAssertNil(session.ferryPreview?.problem)
        XCTAssertTrue(session.buildFerryRoute(), String(describing: session.message?.text))
        XCTAssertEqual(session.world.ferryRoutes.last?.piers, piers)
        XCTAssertTrue(try XCTUnwrap(session.world.landBlocks).contains(LandBlock(cellRow: cijin.row, column: cijin.column)), "read in")
        for pier in piers { XCTAssertTrue(session.world.isPierCell(row: pier.row, column: pier.column)) }
    }

    /// The screenshot scene of the pull request is the author's map:
    /// Cijin not read in, its shore marked.
    func testTheScreenshotSceneMarksCijinsShore() throws {
        let folder = Self.root.appendingPathComponent("RailwayGameApp/Resources/RealWorld")
        let water = try WaterGrid(data: Data(contentsOf: folder.appendingPathComponent("taiwan_water.json")))
        let world = ScreenshotScene.cijinShore.make(in: .traditionalChinese, water: water)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = try PopulationGrid(data: Data(contentsOf: folder.appendingPathComponent("taiwan_population.json")))
        session.water = water
        session.selectTool(.bus)
        session.setBusMode(.ferries)
        let map = Map(session: session, frame: frame, water: water)
        let cijin = map.cell(Self.cijinStation.latitude, Self.cijinStation.longitude)
        XCTAssertFalse(try XCTUnwrap(world.landBlocks).contains(LandBlock(cellRow: cijin.row, column: cijin.column)))
        XCTAssertFalse(world.terrain.water.isEmpty, "the harbour's north side is read with its water")
        XCTAssertFalse(map.shore(within: RealFerry.snapCells, of: cijin).isEmpty)
    }

    /// The whole island's shore is worked out only in the ferry mode:
    /// building elsewhere, which reads land in, does not pay for it.
    func testTheShoreIsWorkedOutOnlyInTheFerryMode() throws {
        let map = try map()
        let session = map.session
        session.setBusMode(.routes)
        _ = session.ferryMapOverlay
        session.readLand(within: WholeTaiwan.landReach, of: map.cell(22.6125, 120.2680).middle)
        _ = session.ferryMapOverlay
        XCTAssertNil(session.ferryShoreMemo, "no shore outside the ferry mode")
        session.setBusMode(.ferries)
        XCTAssertFalse(try XCTUnwrap(session.ferryMapOverlay).shore.isEmpty)
        XCTAssertNotNil(session.ferryShoreMemo)
    }
}
