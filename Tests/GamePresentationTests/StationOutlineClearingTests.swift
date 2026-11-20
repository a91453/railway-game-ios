import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// MRT-SHELL-CLEAR-OUTLINE (MRT-STATION-AUDIT 1 and 2): the track, the
/// platforms and a station's own building (the Tamsui line's shells, the
/// kit's houses, the depots' sheds) leave out the real buildings they
/// overlap, not every one on the 64 m cells they touch. Shilin bought
/// left out 100 real buildings round its shell and viaduct before.
@MainActor
final class StationOutlineClearingTests: XCTestCase {
    func testTheOutlineAndItsMargin() {
        let square = [Map3DPoint(0, 0, 0), Map3DPoint(10, 0, 0), Map3DPoint(10, 0, 10), Map3DPoint(0, 0, 10)]
        let outline = StationOutline(square, margin: 2)
        XCTAssertEqual(outline.minX, -2, accuracy: 1e-4)
        XCTAssertEqual(outline.maxZ, 12, accuracy: 1e-4)
        func box(_ x: Float, _ z: Float, _ side: Float) -> [Map3DPoint] {
            [Map3DPoint(x, 0, z), Map3DPoint(x + side, 0, z), Map3DPoint(x + side, 0, z + side), Map3DPoint(x, 0, z + side)]
        }
        XCTAssertTrue(outline.overlaps(box(3, 3, 2)), "inside it")
        XCTAssertTrue(outline.overlaps(box(-20, -20, 60)), "round it")
        XCTAssertTrue(outline.overlaps(box(11, 4, 5)), "within the margin")
        XCTAssertTrue(outline.overlaps([Map3DPoint(-5, 0, 5), Map3DPoint(15, 0, 5), Map3DPoint(15, 0, 6), Map3DPoint(-5, 0, 6)]), "across it")
        XCTAssertFalse(outline.overlaps(box(13, 0, 5)), "beyond the margin")
        XCTAssertFalse(outline.overlaps(box(30, 30, 5)), "far off")
    }

    func testShilinsShellLeavesTheBuildingsRoundIt() throws {
        let real = try BundledRealData.station("士林", in: "mrt")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(real.anchor))
        try world.mapGround()
        world.setUnlimitedFunds(true)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        session.heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        let pin = try XCTUnwrap(session.nearestRealStation(to: try BundledRealData.point(real.coordinate, in: session.world)))
        XCTAssertTrue(session.buyRealStation(session.realStationOffer(for: pin, system: "mrt")), session.message?.text ?? "")
        let bought = session.world
        let station = try XCTUnwrap(bought.stations.first { $0.name == "士林" })
        let frame = try XCTUnwrap(RealWorldFrame(world: bought))
        let scene = Map3DScene.frame(world: bought, focus: (x: Double(station.location.x), y: Double(station.location.y)))
        var builder = Map3DScene.Builder(originX: scene.originX, originY: scene.originY, region: scene.region, world: bought,
                                         heights: session.heights)
        let snapshot = bought.railwaySnapshot()
        let cleared = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        let stationCells = builder.addStations(snapshot, frame: frame, shops: false)
        let stations = cleared.union(stationCells)
        XCTAssertEqual(builder.stationOutlines.count, 1, "its shell")
        XCTAssertFalse(builder.outlineOnlyCells.isEmpty)
        let realClear = stationCells.subtracting(builder.outlineOnlyCells)
        builder.indexTrackOutline()
        // The real buildings on the cells the track and the shell take.
        let tiles = try FootprintTiles(data: Data(contentsOf: HongKongBuildingsTests.taiwan, options: .alwaysMapped))
        let footprints = Map3DFootprints(tiles: tiles, frame: frame, region: builder.region)
        let cell = Double(Land.cellLength)
        func key(_ point: (x: Double, y: Double)) -> Map3DScene.ChunkKey {
            Map3DScene.ChunkKey(column: Int((point.x / cell).rounded(.down)), row: Int((point.y / cell).rounded(.down)))
        }
        var kept = 0, under = 0
        for building in footprints.buildings {
            guard let outline = building.rings.first, outline.count >= 3 else { continue }
            let keys = outline.map { key(($0.x, $0.y)) }
            guard keys.contains(where: stations.contains), !keys.contains(where: realClear.contains) else { continue }
            if builder.underRailway(outline.map { builder.point(x: $0.x, y: $0.y, height: 0) }) { under += 1 } else { kept += 1 }
        }
        // 100 were left out before; 86 come back (measured 2026-11-20).
        XCTAssertGreaterThanOrEqual(kept, 60, "kept round the shell and beside the viaduct")
        XCTAssertLessThanOrEqual(under, 20, "left out under it and the track")
    }
}
