import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 607 (ROADIX-2): the interchange screenshot's streets
/// (`ScreenshotScene.interchange`, 24.1489, 120.6233, the camera of
/// `testInterchange`) keep their trees, bus stops and buses' lanes when the
/// decks' link roads are raised. Built as the app builds it, with its files.
final class Map3DInterchangeStreetTests: XCTestCase {
    func testTheInterchangesStreetsKeepTheirTreesBusStopsAndBuses() throws {
        let world = ScreenshotScene.interchange.make(in: .traditionalChinese)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let focus = frame.worldPosition(latitude: 24.1489, longitude: 120.6233)
        let baseMap = Map3DFrameCostReportTests.baseMap
        let tiles = try BaseMapTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan.pmtiles"), options: .alwaysMapped))
        let footprints = try FootprintTiles(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_buildings.pmtiles"), options: .alwaysMapped))
        let temples = try RealTemples(data: Data(contentsOf: baseMap.appendingPathComponent("taiwan_temples.json")))
        let noBuild = try RealNoBuildLand(data: Data(contentsOf: Map3DTrenchTests.root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_no_build.json")))
        let scene = Map3DScene(world: world, skyline: CitySkyline(world: world), focus: (focus.x, focus.y), baseMap: tiles,
                               cityTiles: CityTileArea.areas(in: baseMap.appendingPathComponent("city")), footprints: footprints,
                               heights: HighSpeedDemoTests.heights, lineBands: Map3DLineBands(world: world, palette: .standard),
                               railways: try HighSpeedDemoTests.railways(), temples: temples, noBuild: noBuild)
        let metre = Map3DScene.Builder.metre
        let cx = Float((focus.x - scene.originX) / metre), cz = Float((focus.y - scene.originY) / metre)
        let pack = Map3DModelPack.standard
        let tree = try XCTUnwrap(pack.index(of: Map3DProp.tree.modelName)), busStop = try XCTUnwrap(pack.index(of: Map3DProp.busStop.modelName))
        let camera = try XCTUnwrap(Map3DScreenshotView("320,200,40")?.camera(at: (24.1489, 120.6233), in: scene, of: world, viewport: (874, 402)))
        // The chunks the screenshot draws in full, and their props.
        let shown = scene.chunks.filter { camera.wantsDetail(minimum: $0.minimum, maximum: $0.maximum) }.flatMap(\.props)
        // The street across the bottom of the picture, between the camera
        // (north of the place, looking south-south-west) and the place.
        let front = shown.filter { $0.transform[14] - cz > -260 && $0.transform[14] - cz < -40 && abs($0.transform[12] - cx) < 450 }
        let near = shown.filter { hypot($0.transform[12] - cx, $0.transform[14] - cz) < 600 }
        var busLanes: Float = 0
        for lane in scene.streetLife.lanes where lane.buses {
            for (a, b) in zip(lane.path.points, lane.path.points.dropFirst()) where hypot((a.x + b.x) / 2 - cx, (a.z + b.z) / 2 - cz) < 1_500 {
                busLanes += hypot(b.x - a.x, b.z - a.z)
            }
        }
        let count = { (props: [Map3DInstance], model: Int) in props.filter { $0.model == model }.count }
        print(String(format: "ROADIX2 front trees %d, bus stops %d; within 600 m trees %d, bus stops %d; bus lanes %.0f m",
                      count(front, tree), count(front, busStop), count(near, tree), count(near, busStop), busLanes))
        // main 4e244db0 and this branch alike: front 31 trees and 2 bus
        // stops, within 600 m 300 trees and 8 bus stops, 25,738 m of
        // buses' lanes within 1.5 km.
        XCTAssertGreaterThanOrEqual(count(front, tree), 31, "the trees along the street across the picture")
        XCTAssertGreaterThanOrEqual(count(front, busStop), 2, "its bus stops")
        XCTAssertGreaterThanOrEqual(count(near, tree), 300)
        XCTAssertGreaterThanOrEqual(count(near, busStop), 8)
        XCTAssertGreaterThanOrEqual(busLanes, 25_700, "the buses' lanes")
    }
}
