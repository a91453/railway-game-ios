import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 370 (step 2): Taipei 101 and Taipei Main Station in the model
/// look, where they stand; decision 431's Kaohsiung Main Station and
/// decision 457's central Taipei.
final class Map3DTaipeiLandmarksTests: XCTestCase {
    /// Taipei Main Station: the middle of the map, so of the scene; 101 is
    /// 4.8 km off, outside a new game's scene.
    private let anchor = GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!

    private func builder(_ world: GameWorld) -> Map3DScene.Builder {
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        return Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
    }

    private func triangles(_ meshes: [Map3DScene.ChunkKey: Map3DMesh]) -> Int {
        meshes.values.reduce(0) { $0 + $1.indices.count / 3 }
    }

    private static let wall = Map3DColor.rgb(0xF5F1E9)
    private static let canopyGrass = Map3DColor.rgb(0xCFE0C8)
    private static let flatRoof = Map3DColor.rgb(0xE6E4E0)

    /// OSM specifications (ODbL):
    /// - Taipei 101: relation 11551064, spire way 615183623 (height = 508 m).
    /// - Taipei Main Station: way 23641610 (height = 30 m).
    /// - Kaohsiung Main Station: relation 14940189, outer canopy way 1298938821
    ///   (664.78 m east-west × 333.87 m north-south; canopy crest 23 m),
    ///   and historic Old Kaohsiung Station way 257770396 (25.30 m × 30.36 m,
    ///   building:levels = 3, Imperial Crown tower top 16.86 m).
    private static let kaohsiungCanopyLength: Float = 664.78
    private static let kaohsiungCanopyWidth: Float = 333.87
    private static let kaohsiungCanopyHeight: Float = 23.0
    /// Decision 457 (later): the joint-development towers, 10 and 11
    /// floors by the news, 3.5 m a floor.
    private static let kaohsiungOfficesHeight: Float = 35
    private static let kaohsiungHotelHeight: Float = 38.5
    private static let kaohsiungOldStationWidth: Float = 25.30
    private static let kaohsiungOldStationDepth: Float = 30.36
    /// Decision 548: Kaohsiung 85 Sky Tower (OSM way 34170948 podium
    /// 143.00 m × 68.21 m, height = 50 m; twin wings ways 344740871 &
    /// 344740872 height = 190 m; central tower way 344740874 min_height = 145 m,
    /// height = 330 m; pyramidal crown way 345038766 height = 347.5 m; spire
    /// way 345038767 height = 378 m).
    private static let kaohsiung85Length: Float = 143.00
    private static let kaohsiung85Width: Float = 68.21
    private static let kaohsiung85Height: Float = 378.0
    private static let kaohsiung85CrownHeight: Float = 347.5
    /// Decision 550: Taipei Shin Kong Life Tower (OSM way 204711206 outer
    /// footprint 84.90 m × 40.26 m, building:levels = 51, height = 244.15 m;
    /// stepped podium ways 644774205..644774218 height = 46.56 m & 63.20 m,
    /// way 644774201 height = 78.56 m, north 18F turret way 644774185
    /// height = 86.24 m; main tower shaft way 644774181 height = 211.04 m
    /// with 44F/46F/48F setbacks ways 644774184..644774200 at 187.36 m,
    /// 195.68 m & 203.36 m; crown collar way 644774173 height = 214.88 m &
    /// stepped crown penthouse way 644774171 height = 237.67 m).
    private static let shinKongLength: Float = 84.90
    private static let shinKongWidth: Float = 40.26
    private static let shinKongHeight: Float = 244.15
    private static let shinKongPodiumHeight: Float = 78.56
    private static let shinKongNorthTurretHeight: Float = 86.24
    private static let shinKongShaftHeight: Float = 211.04
    private static let shinKongCrownHeight: Float = 237.67
    /// Decision 581: Changhua Roundhouse (OSM way 220285047 outer footprint
    /// 85.03 m × 49.79 m, railway = roundhouse, building = garages,
    /// building:levels = 1; turntable way 220285048; 12 radial stall tracks
    /// ways 307329549..307329565 & 966441326; front portal cornice 7.06 m,
    /// raised clerestory monitor roof 8.85 m, 12 smokejack caps 10.28 m).
    private static let changhuaRoundhouseLength: Float = 85.03
    private static let changhuaRoundhouseWidth: Float = 49.79
    private static let changhuaRoundhouseHeight: Float = 10.28
    private static let changhuaRoundhouseMonitorHeight: Float = 8.85
    private static let changhuaRoundhouseCorniceHeight: Float = 7.06
    /// Decision 592: Kaohsiung Great Harbor Bridge (OSM relation 15430334,
    /// bridge outline way 1137765107: 126.44 m × 15.38 m with 110 m swing
    /// span way 840552016; elevated observation deck 6.95 m, asymmetric
    /// shell arch canopy 11.20 m, inclined central mast spire 36.0 m),
    /// Gushan Ferry Terminal (OSM node 3921289758, waiting gallery way
    /// 205060865, floating pier way 388956314 & main entrance building way
    /// 588103933: combined 35.02 m × 56.60 m; wave-arched gallery roof
    /// 6.20 m, 2-storey louver facade roof 10.50 m, navigation mast 12.0 m),
    /// and Cijin Ferry Terminal (OSM node 3921289548, red-brick terminal
    /// building way 255744758 & piers ways 388956315, 388956316: combined
    /// 72.83 m × 34.26 m; main tile roof 10.20 m, flanking 3-storey turrets
    /// 14.80 m, central octagonal clock tower roof 21.50 m & finial 23.0 m).
    private static let greatHarborBridgeLength: Float = 126.44
    private static let greatHarborBridgeWidth: Float = 15.38
    private static let greatHarborBridgeHeight: Float = 36.0
    private static let greatHarborBridgeShellHeight: Float = 11.20
    private static let greatHarborBridgeObservationHeight: Float = 6.95
    private static let gushanFerryWidth: Float = 35.02
    private static let gushanFerryLength: Float = 56.60
    private static let gushanFerryHeight: Float = 12.0
    private static let gushanFerryRoofHeight: Float = 10.50
    private static let gushanFerryWaveHeight: Float = 6.20
    private static let cijinFerryLength: Float = 72.83
    private static let cijinFerryWidth: Float = 34.26
    private static let cijinFerryBuildingWidth: Float = 19.52
    private static let cijinFerryHeight: Float = 23.0
    private static let cijinFerryTowerRoofHeight: Float = 21.50
    private static let cijinFerryTurretHeight: Float = 14.80

    /// The landmarks as OSM has their plans and heights: 101 508 m to its
    /// spire, Taipei Main Station's roof 30 m, Kaohsiung Main Station's
    /// canopy 23 m (way 1298938821) with the Imperial Crown old station
    /// (way 257770396), Kaohsiung 85 Sky Tower 378 m to its spire (way
    /// 345038767), Taipei Shin Kong Life Tower 244.15 m to its spire (way
    /// 204711206), Changhua Roundhouse 10.28 m to its 12 smokejack caps
    /// (way 220285047), and Decision 592's Kaohsiung Harbor landmarks;
    /// each within the ground it clears, lit by finite unit outward
    /// normals, drawn with the line patterns; from afar, fewer triangles.
    func testTheModels() {
        let layers: Set<Float> = [Map3DVertex.plain, Map3DVertex.curtainGlass, Map3DVertex.roofTiles, Map3DVertex.floorLines,
                                  Map3DVertex.towerGlass, Map3DVertex.floodlit, Map3DVertex.glowing]
        for landmark in Map3DTaipeiLandmark.allCases {
            let full = landmark.model(full: true), far = landmark.model(full: false)
            XCTAssertLessThan(far.indices.count, full.indices.count * 2 / 3, "\(landmark)")
            XCTAssertGreaterThanOrEqual(landmark.clearing.x, landmark.body.x, "\(landmark)")
            XCTAssertGreaterThanOrEqual(landmark.clearing.y, landmark.body.y, "\(landmark)")
            let expectedTop: Float = switch landmark {
            case .taipei101: 508
            case .taipeiMainStation: 30
            case .kaohsiungMainStation: Self.kaohsiungHotelHeight
            case .kaohsiung85SkyTower: Self.kaohsiung85Height
            case .shinKongLifeTower: Self.shinKongHeight
            case .changhuaRoundhouse: Self.changhuaRoundhouseHeight
            case .greatHarborBridge: Self.greatHarborBridgeHeight
            case .gushanFerryTerminal: Self.gushanFerryHeight
            case .cijinFerryTerminal: Self.cijinFerryHeight
            case .chiangKaiShekMemorialHall: 70
            case .libertySquareGate, .sunYatSenMemorialHall: 30
            case .nationalTheater, .nationalConcertHall: 37
            case .presidentialOffice: 60
            case .ximenRedHouse: 17.5
            case .grandHotel: 87
            case .northGate: 15.2
            case .eastGate: 16.5
            case .southGate: 19
            case .smallSouthGate: 14.5
            }
            for model in [full, far] {
                let top = model.vertices.map(\.z).max() ?? 0
                XCTAssertEqual(top, expectedTop, accuracy: 0.01, "\(landmark)")
                XCTAssertEqual(model.vertices.map(\.z).min(), 0)
                for vertex in model.vertices {
                    XCTAssertTrue(vertex.x.isFinite && vertex.y.isFinite && vertex.z.isFinite)
                    XCTAssertTrue(vertex.nx.isFinite && vertex.ny.isFinite && vertex.nz.isFinite)
                    XCTAssertTrue(vertex.u.isFinite && vertex.v.isFinite)
                    XCTAssertLessThanOrEqual(abs(vertex.x), landmark.clearing.x)
                    XCTAssertLessThanOrEqual(abs(vertex.y), landmark.clearing.y)
                    XCTAssertEqual(Map3DPoint(vertex.nx, vertex.ny, vertex.nz).length, 1, accuracy: 0.001)
                    XCTAssertTrue(layers.contains(vertex.layer), "\(vertex.layer)")
                }
                XCTAssertTrue(model.indices.allSatisfy { Int($0) < model.vertices.count })
            }
            let used = Set(full.vertices.map(\.layer))
            let expectedLayers: Set<Float> = switch landmark {
            case .taipei101, .kaohsiung85SkyTower, .shinKongLifeTower:
                [Map3DVertex.curtainGlass, Map3DVertex.towerGlass, Map3DVertex.floodlit, Map3DVertex.glowing]
            case .taipeiMainStation: [Map3DVertex.curtainGlass, Map3DVertex.roofTiles]
            case .kaohsiungMainStation: [Map3DVertex.curtainGlass, Map3DVertex.roofTiles, Map3DVertex.floorLines]
            case .changhuaRoundhouse:
                [Map3DVertex.curtainGlass, Map3DVertex.roofTiles, Map3DVertex.floorLines, Map3DVertex.floodlit]
            case .greatHarborBridge:
                [Map3DVertex.curtainGlass, Map3DVertex.floodlit, Map3DVertex.glowing]
            case .gushanFerryTerminal, .cijinFerryTerminal:
                [Map3DVertex.curtainGlass, Map3DVertex.roofTiles, Map3DVertex.floorLines, Map3DVertex.floodlit, Map3DVertex.glowing]
            case .chiangKaiShekMemorialHall, .libertySquareGate, .northGate, .eastGate, .southGate, .smallSouthGate:
                [Map3DVertex.plain, Map3DVertex.roofTiles]
            case .nationalTheater, .nationalConcertHall, .sunYatSenMemorialHall, .grandHotel:
                [Map3DVertex.roofTiles, Map3DVertex.floorLines]
            case .presidentialOffice: [Map3DVertex.floorLines, Map3DVertex.floodlit]
            case .ximenRedHouse: [Map3DVertex.floorLines, Map3DVertex.roofTiles]
            }
            XCTAssertTrue(used.isSuperset(of: expectedLayers), "\(landmark)")
        }
        // Pin Taipei 101 and Taipei Main Station triangle counts so adding
        // new landmarks never alters them; check Kaohsiung's, Shin Kong's and Changhua's budgets.
        XCTAssertEqual(Map3DTaipeiLandmark.taipei101.model(full: true).indices.count / 3, 5_804)
        XCTAssertEqual(Map3DTaipeiLandmark.taipei101.model(full: false).indices.count / 3, 2_580)
        XCTAssertEqual(Map3DTaipeiLandmark.taipeiMainStation.model(full: true).indices.count / 3, 4_194)
        XCTAssertEqual(Map3DTaipeiLandmark.taipeiMainStation.model(full: false).indices.count / 3, 902)
        for landmark in [Map3DTaipeiLandmark.kaohsiungMainStation, .kaohsiung85SkyTower, .shinKongLifeTower,
                         .changhuaRoundhouse, .greatHarborBridge, .gushanFerryTerminal, .cijinFerryTerminal] {
            let full = landmark.model(full: true), far = landmark.model(full: false)
            XCTAssertLessThanOrEqual(full.indices.count / 3, 6_000, "\(landmark)")
            XCTAssertLessThanOrEqual(far.indices.count / 3, 2_500, "\(landmark)")
            XCTAssertLessThan(far.indices.count, full.indices.count, "\(landmark)")
        }
    }

    /// Decision 457: the Chinese roof is a part of its own: any plan, any
    /// number of eaves, only the caller's colours, its top where asked.
    func testTheChineseRoofPart() {
        let colours = ChineseRoofColours(tile: 1, ridge: 2, underside: 3, gable: nil, wall: 4)
        for kind in [LandmarkMesh.RoofKind.hipped, .hipGable] {
            for tiers in 1...3 {
                for full in [true, false] {
                    var mesh = LandmarkMesh(full: full)
                    mesh.chineseRoof(9, 6, eaves: 4, over: 1.5, rise: 3.5, sweep: 0.8, kind: kind, tiers: tiers, tierRise: 2,
                                     tierInset: 1.2, colours: colours)
                    let zs = mesh.vertices.map(\.z)
                    XCTAssertEqual(zs.max() ?? 0, 4 + Float(tiers - 1) * 2 + 3.5, accuracy: 0.001, "\(kind) \(tiers)")
                    XCTAssertGreaterThanOrEqual(zs.min() ?? 0, 4 - 0.5 - 0.001)
                    XCTAssertTrue(mesh.vertices.allSatisfy { abs($0.x) <= 9 + 1.5 + 0.4 && abs($0.y) <= 6 + 1.5 + 0.4 })
                    XCTAssertTrue(Set(mesh.vertices.map(\.color)).isSubset(of: [1, 2, 3, 4]))
                    XCTAssertEqual(mesh.vertices.contains { $0.color == 4 }, tiers > 1)
                    for v in mesh.vertices {
                        XCTAssertEqual(Map3DPoint(v.nx, v.ny, v.nz).length, 1, accuracy: 0.001)
                    }
                }
            }
        }
        // Decision 457 (later): the flat-topped roof (盝頂) leaves its
        // middle open, with a ridge round it at the full height.
        for full in [true, false] {
            var mesh = LandmarkMesh(full: full)
            mesh.chineseRoof(9, 6, eaves: 4, over: 1.5, rise: 3.5, sweep: 0.8, kind: .flat(x: 5, y: 3), colours: colours)
            XCTAssertEqual(mesh.vertices.map(\.z).max() ?? 0, 7.5, accuracy: 0.001)
            XCTAssertFalse(mesh.vertices.contains { abs($0.x) < 4.9 && abs($0.y) < 2.9 })
            XCTAssertTrue(mesh.vertices.allSatisfy { abs($0.x) <= 9 + 1.5 + 0.4 && abs($0.y) <= 6 + 1.5 + 0.4 })
        }
    }

    /// Decision 457: each part chosen on its own, the colours paled
    /// together; every hall keeps its parts' order of light to dark.
    func testThePaleColoursKeepTheirOrder() {
        func lightness(_ name: String) -> Float {
            let c = Map3DTaipeiLandmark.palette[name]!
            return (0.2126 * Float(c & 0xFF) + 0.7152 * Float((c >> 8) & 0xFF) + 0.0722 * Float((c >> 16) & 0xFF)) / 255
        }
        for order in [["goldTile", "hallRed", "hallColumn", "bracket"], ["goldTile", "hallGlass", "column", "bracket"],
                      ["hallWhite", "blueTile", "doorway"], ["podium", "hallRed"],
                      // Decision 457 (later): the station's trim, walls and
                      // tiles; 101's frame, upper and lower glass.
                      ["trim", "wall", "stationRoof"], ["frame", "glassTop", "glass"]] {
            for (lighter, darker) in zip(order, order.dropFirst()) {
                XCTAssertGreaterThan(lightness(lighter), lightness(darker), "\(lighter) over \(darker)")
            }
        }
        XCTAssertGreaterThan(lightness("bracket"), 0.5)
        var thick = LandmarkMesh(full: true)
        thick.chineseRoof(9, 6, eaves: 4, over: 1.5, rise: 3.5, sweep: 0.8, tiers: 2, tierRise: 2, tierInset: 1.2, lip: 1.2,
                          colours: ChineseRoofColours(tile: 1, ridge: 2, underside: 3, gable: nil, wall: 4))
        XCTAssertEqual(thick.vertices.map(\.z).min() ?? 0, 4 - 1.2, accuracy: 0.001)
    }

    /// Decision 457: central Taipei's landmarks stand on OpenStreetMap's
    /// plans (the minimum box of each way, ODbL), within 2 m at the
    /// ground; each within the landmark budget.
    func testCentralTaipeiOnOSMsPlans() {
        let plans: [Map3DTaipeiLandmark: (x: Float, y: Float)] = [
            .chiangKaiShekMemorialHall: (124.4, 147.4), // way 1052759757
            .libertySquareGate: (74.7, 17.0), // way 1052759782
            .nationalTheater: (107.9, 103.3), // way 1052759776
            .nationalConcertHall: (102.9, 103.3), // way 1052759775
            .presidentialOffice: (131.9, 92.9), // relation 206817, way 39239021
            .ximenRedHouse: (91.7, 47.8), // way 222080307
            .sunYatSenMemorialHall: (108.7, 112.5), // way 189788192
            .grandHotel: (109.8, 74.2), // way 25202548
            .northGate: (15.1, 11.4), // way 238316480
            .eastGate: (17.7, 13.5), // way 209580573
            .southGate: (33.8, 19.6), // way 245993047
            .smallSouthGate: (13.5, 12.5), // way 246651384
        ]
        for (landmark, plan) in plans {
            for model in [landmark.model(full: true), landmark.model(full: false)] {
                let ground = model.vertices.filter { $0.z < 0.01 }
                let xs = ground.map(\.x), ys = ground.map(\.y)
                XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), plan.x, accuracy: 2, "\(landmark)")
                XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), plan.y, accuracy: 2, "\(landmark)")
                XCTAssertEqual(((xs.max() ?? 0) + (xs.min() ?? 0)) / 2, 0, accuracy: 2, "\(landmark)")
                XCTAssertEqual(((ys.max() ?? 0) + (ys.min() ?? 0)) / 2, 0, accuracy: 2, "\(landmark)")
            }
            XCTAssertLessThanOrEqual(landmark.model(full: true).indices.count / 3, 6_000, "\(landmark)")
            XCTAssertLessThanOrEqual(landmark.model(full: false).indices.count / 3, 2_500, "\(landmark)")
        }
        XCTAssertEqual(Set(plans.keys).count, Map3DTaipeiLandmark.allCases.count - 9)
        // Each stands within 2 m of its way's minimum box's middle.
        let middles: [Map3DTaipeiLandmark: (Double, Double)] = [
            .chiangKaiShekMemorialHall: (25.03468, 121.52172), .libertySquareGate: (25.03665, 121.51772),
            .nationalTheater: (25.03532, 121.51822), .nationalConcertHall: (25.03700, 121.51922),
            .presidentialOffice: (25.03999, 121.51198), .ximenRedHouse: (25.04208, 121.50651),
            .sunYatSenMemorialHall: (25.04000, 121.56029), .grandHotel: (25.07856, 121.52626),
            .northGate: (25.04773, 121.51122), .eastGate: (25.03902, 121.51768),
            .southGate: (25.03513, 121.51502), .smallSouthGate: (25.03691, 121.50809),
        ]
        XCTAssertEqual(Set(middles.keys), Set(plans.keys))
        for (landmark, (latitude, longitude)) in middles {
            XCTAssertEqual(landmark.latitude, latitude, accuracy: 2 / 110_774, "\(landmark)")
            XCTAssertEqual(landmark.longitude, longitude, accuracy: 2 / 100_870, "\(landmark)")
        }
        // None in Taipei Main Station's wall colour, which the tests below
        // count the station by.
        for landmark in plans.keys {
            XCTAssertFalse(landmark.model(full: true).vertices.contains { $0.color == Self.wall }, "\(landmark)")
        }
    }

    /// Decision 431: Kaohsiung Main Station's canopy (OSM relation 14940189,
    /// way 1298938821) and Imperial Crown old station (OSM way 257770396)
    /// match OpenStreetMap's dimensions within 2 m, with outward normals,
    /// and stand clear of surface track while allowing underground track.
    func testKaohsiungMainStation() throws {
        let station = Map3DTaipeiLandmark.kaohsiungMainStation
        for model in [station.model(full: true), station.model(full: false)] {
            let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
            let length = (xs.max() ?? 0) - (xs.min() ?? 0)
            let width = (ys.max() ?? 0) - (ys.min() ?? 0)
            let height = (zs.max() ?? 0) - (zs.min() ?? 0)
            XCTAssertEqual(length, Self.kaohsiungCanopyLength, accuracy: 2.0)
            XCTAssertEqual(width, Self.kaohsiungCanopyWidth, accuracy: 2.0)
            XCTAssertEqual(height, Self.kaohsiungHotelHeight, accuracy: 0.01)
            XCTAssertEqual(model.vertices.filter { $0.color == Self.canopyGrass }.map(\.z).max() ?? 0, Self.kaohsiungCanopyHeight, accuracy: 2.0)
            // The towers on OSM's plans (ways 1298938833, 1298938834:
            // 58.7 m × 104.2 m and 54.2 m × 57.5 m), the offices west of
            // the hotel.
            for (plan, top, size) in [(LandmarkMesh.kaohsiungOffices, Self.kaohsiungOfficesHeight, (x: Float(58.7), y: Float(104.2))),
                                      (LandmarkMesh.kaohsiungHotel, Self.kaohsiungHotelHeight, (x: 54.2, y: 57.5))] {
                let xs = plan.map(\.x), ys = plan.map(\.y)
                XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), size.x, accuracy: 0.5)
                XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), size.y, accuracy: 0.5)
                let roof = model.vertices.filter { abs($0.z - top) < 0.01 && $0.color == Self.flatRoof }
                XCTAssertTrue(roof.contains { $0.x >= (xs.min() ?? 0) && $0.x <= (xs.max() ?? 0) })
            }
            // Old station (OSM way 257770396) on the south plaza.
            let oldStation = model.vertices.filter { $0.y < -109 && abs($0.x) < 20 }
            let oldXs = oldStation.map(\.x), oldYs = oldStation.map(\.y)
            XCTAssertEqual((oldXs.max() ?? 0) - (oldXs.min() ?? 0), Self.kaohsiungOldStationWidth, accuracy: 2.0)
            XCTAssertEqual((oldYs.max() ?? 0) - (oldYs.min() ?? 0), Self.kaohsiungOldStationDepth, accuracy: 2.0)
            // Canopy grass faces upward; canopy soffit faces downward.
            let grass = model.vertices.filter { $0.color == Self.canopyGrass }
            XCTAssertFalse(grass.isEmpty)
            XCTAssertTrue(grass.allSatisfy { $0.nz > 0 })
        }
        let kaohsiungAnchor = GeoAnchor(latitudeDegrees: station.latitude, longitudeDegrees: station.longitude)!
        let world = GameWorld.newGame(anchor: kaohsiungAnchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let built = builder.addTaipeiLandmarks(frame: frame)
        XCTAssertEqual(Set(built.keys), [station])
        XCTAssertEqual(triangles(builder.nearMeshes), station.model(full: true).indices.count / 3)
        XCTAssertEqual(triangles(builder.farMeshes), station.model(full: false).indices.count / 3)
        XCTAssertTrue(builder.keptColours.contains(Self.canopyGrass))
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        let line = stride(from: Float(-300), through: 300, by: 2).map { middle + Map3DPoint($0, 0, 20) }
        var blocked = self.builder(world)
        blocked.trackLines = [(line, .surface)]
        XCTAssertTrue(blocked.addTaipeiLandmarks(frame: frame).isEmpty)
        var tunnel = self.builder(world)
        tunnel.trackLines = [(line, .tunnel)]
        XCTAssertEqual(Set(tunnel.addTaipeiLandmarks(frame: frame).keys), [station])
    }

    /// Decision 548: Kaohsiung 85 Sky Tower's podium (OSM way 34170948),
    /// twin wings flanking the central portal opening (ways 344740871 &
    /// 344740872), bridging central tower (way 344740874), pyramidal crown
    /// (way 345038766) and spire (way 345038767) match OpenStreetMap's
    /// dimensions within 2 m, keep the portal opening clear, and stand
    /// clear of surface track while allowing underground track.
    func testKaohsiung85SkyTower() throws {
        let tower = Map3DTaipeiLandmark.kaohsiung85SkyTower
        let greenRidge = Map3DColor.rgb(0x98C4AE)
        let soffit = Map3DColor.rgb(0xE9E4DB)
        for model in [tower.model(full: true), tower.model(full: false)] {
            let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
            XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), Self.kaohsiung85Length, accuracy: 2.0)
            XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), Self.kaohsiung85Width, accuracy: 2.0)
            XCTAssertEqual((zs.max() ?? 0) - (zs.min() ?? 0), Self.kaohsiung85Height, accuracy: 0.01)
            let ground = model.vertices.filter { $0.z < 0.01 }
            let gxs = ground.map(\.x), gys = ground.map(\.y)
            XCTAssertEqual((gxs.max() ?? 0) - (gxs.min() ?? 0), Self.kaohsiung85Length, accuracy: 2.0)
            XCTAssertEqual((gys.max() ?? 0) - (gys.min() ?? 0), Self.kaohsiung85Width, accuracy: 2.0)
            XCTAssertEqual(((gxs.max() ?? 0) + (gxs.min() ?? 0)) / 2, 0, accuracy: 2.0)
            XCTAssertEqual(((gys.max() ?? 0) + (gys.min() ?? 0)) / 2, 0, accuracy: 2.0)
            // Twin wings (ways 344740871 & 344740872) flank a hollow central
            // portal opening between z = 54 m and z = 146 m.
            XCTAssertFalse(model.vertices.contains { abs($0.x) < 15 && abs($0.y) < 24 && $0.z > 54 && $0.z < 146 })
            XCTAssertTrue(model.vertices.contains { $0.x < -30 && $0.z > 100 && $0.z < 185 })
            XCTAssertTrue(model.vertices.contains { $0.x > 30 && $0.z > 100 && $0.z < 185 })
            // Central tower bridges over the portal (way 344740874) with a
            // downward-facing soffit and rises to the pyramidal crown (way 345038766).
            let portalSoffit = model.vertices.filter { $0.color == soffit && abs($0.z - 148) < 0.1 }
            XCTAssertFalse(portalSoffit.isEmpty)
            XCTAssertTrue(portalSoffit.allSatisfy { $0.nz < -0.9 })
            let crown = model.vertices.filter { $0.color == greenRidge && $0.z > 334 }
            XCTAssertEqual(crown.map(\.z).max() ?? 0, Self.kaohsiung85CrownHeight, accuracy: 2.0)
            XCTAssertFalse(model.vertices.contains { $0.color == Self.wall })
        }
        let towerAnchor = GeoAnchor(latitudeDegrees: tower.latitude, longitudeDegrees: tower.longitude)!
        let world = GameWorld.newGame(anchor: towerAnchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let built = builder.addTaipeiLandmarks(frame: frame)
        XCTAssertEqual(Set(built.keys), [tower])
        XCTAssertEqual(triangles(builder.nearMeshes), tower.model(full: true).indices.count / 3)
        XCTAssertEqual(triangles(builder.farMeshes), tower.model(full: false).indices.count / 3)
        XCTAssertTrue(builder.keptColours.contains(greenRidge))
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        let line = stride(from: Float(-120), through: 120, by: 2).map { middle + Map3DPoint($0, 0, 10) }
        var blocked = self.builder(world)
        blocked.trackLines = [(line, .surface)]
        XCTAssertTrue(blocked.addTaipeiLandmarks(frame: frame).isEmpty)
        var tunnel = self.builder(world)
        tunnel.trackLines = [(line, .tunnel)]
        XCTAssertEqual(Set(tunnel.addTaipeiLandmarks(frame: frame).keys), [tower])
    }

    /// Decision 550: Taipei Shin Kong Life Tower's outer footprint and
    /// height (OSM way 204711206: 84.90 m × 40.26 m × 244.15 m), stepped
    /// department store podium (ways 644774205..644774218 & 644774201),
    /// north 18-level turret (way 644774185), main shaft with upper
    /// setbacks (ways 644774181..644774200), and stepped crown (ways
    /// 644774173 & 644774171) match OpenStreetMap's dimensions within 2 m,
    /// and stand clear of surface track while allowing underground track.
    func testShinKongLifeTower() throws {
        let tower = Map3DTaipeiLandmark.shinKongLifeTower
        let brick = Map3DColor.rgb(0xDDA996)
        let podiumRoof = Map3DColor.rgb(0xEDEEF0)
        for model in [tower.model(full: true), tower.model(full: false)] {
            let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
            XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), Self.shinKongLength, accuracy: 2.0)
            XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), Self.shinKongWidth, accuracy: 2.0)
            XCTAssertEqual((zs.max() ?? 0) - (zs.min() ?? 0), Self.shinKongHeight, accuracy: 0.01)
            let ground = model.vertices.filter { $0.z < 0.01 }
            let gxs = ground.map(\.x), gys = ground.map(\.y)
            XCTAssertEqual((gxs.max() ?? 0) - (gxs.min() ?? 0), Self.shinKongLength, accuracy: 2.0)
            XCTAssertEqual((gys.max() ?? 0) - (gys.min() ?? 0), Self.shinKongWidth, accuracy: 2.0)
            XCTAssertEqual(((gxs.max() ?? 0) + (gxs.min() ?? 0)) / 2, 0, accuracy: 2.0)
            XCTAssertEqual(((gys.max() ?? 0) + (gys.min() ?? 0)) / 2, 0, accuracy: 2.0)
            // Stepped podium roof (way 644774201: 78.56 m), north 18-level
            // turret (way 644774185: 86.24 m), and main shaft top (way 644774181: 211.04 m).
            let decks = model.vertices.filter { $0.color == podiumRoof }.map(\.z)
            XCTAssertTrue(decks.contains { abs($0 - Self.shinKongPodiumHeight) < 0.1 })
            XCTAssertTrue(decks.contains { abs($0 - Self.shinKongNorthTurretHeight) < 0.1 })
            XCTAssertTrue(decks.contains { abs($0 - Self.shinKongShaftHeight) < 0.1 })
            // Stepped ziggurat crown penthouse (way 644774171: 237.67 m).
            let crown = model.vertices.filter { $0.color == brick && $0.z > 220 }
            XCTAssertEqual(crown.map(\.z).max() ?? 0, Self.shinKongCrownHeight, accuracy: 2.0)
            XCTAssertFalse(model.vertices.contains { $0.color == Self.wall })
        }
        let towerAnchor = GeoAnchor(latitudeDegrees: tower.latitude, longitudeDegrees: tower.longitude)!
        let world = GameWorld.newGame(anchor: towerAnchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let built = builder.addTaipeiLandmarks(frame: frame)
        let taken = try XCTUnwrap(built[tower])
        XCTAssertGreaterThanOrEqual(taken.count, 4)
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        XCTAssertTrue(taken.contains(builder.chunk(of: middle)))
        XCTAssertTrue(builder.keptColours.contains(brick))
        let line = stride(from: Float(-120), through: 120, by: 2).map { middle + Map3DPoint($0, 0, 10) }
        var blocked = self.builder(world)
        blocked.trackLines = [(line, .surface)]
        XCTAssertNil(blocked.addTaipeiLandmarks(frame: frame)[tower])
        var tunnel = self.builder(world)
        tunnel.trackLines = [(line, .tunnel)]
        XCTAssertNotNil(tunnel.addTaipeiLandmarks(frame: frame)[tower])
    }

    /// Decision 581: Changhua Roundhouse's fan-shaped footprint (OSM way
    /// 220285047: 85.03 m × 49.79 m), 12 radiating stalls, front portal
    /// cornice (7.06 m), raised clerestory monitor roof (8.85 m), and 12
    /// roof smokejack caps (10.28 m) match OpenStreetMap's dimensions
    /// within 2 m, keep the south turntable courtyard open above ground,
    /// and stand clear of surface track while allowing underground track.
    func testChanghuaRoundhouse() throws {
        let roundhouse = Map3DTaipeiLandmark.changhuaRoundhouse
        let trim = Map3DColor.rgb(0xFBF9F4)
        let crownRoof = Map3DColor.rgb(0xC6CFD6)
        let doorway = Map3DColor.rgb(0x5E676D)
        for model in [roundhouse.model(full: true), roundhouse.model(full: false)] {
            let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
            XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), Self.changhuaRoundhouseLength, accuracy: 2.0)
            XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), Self.changhuaRoundhouseWidth, accuracy: 2.0)
            XCTAssertEqual((zs.max() ?? 0) - (zs.min() ?? 0), Self.changhuaRoundhouseHeight, accuracy: 0.01)
            let ground = model.vertices.filter { $0.z < 0.01 }
            let gxs = ground.map(\.x), gys = ground.map(\.y)
            XCTAssertEqual((gxs.max() ?? 0) - (gxs.min() ?? 0), Self.changhuaRoundhouseLength, accuracy: 2.0)
            XCTAssertEqual((gys.max() ?? 0) - (gys.min() ?? 0), Self.changhuaRoundhouseWidth, accuracy: 2.0)
            XCTAssertEqual(((gxs.max() ?? 0) + (gxs.min() ?? 0)) / 2, 0, accuracy: 2.0)
            XCTAssertEqual(((gys.max() ?? 0) + (gys.min() ?? 0)) / 2, 0, accuracy: 2.0)
            // Front portal cornice (7.06 m), raised clerestory monitor roof
            // (8.85 m), and 12 roof smokejack caps (10.28 m).
            let cornices = model.vertices.filter { $0.color == trim }.map(\.z)
            XCTAssertTrue(cornices.contains { abs($0 - Self.changhuaRoundhouseCorniceHeight) < 0.1 })
            let monitors = model.vertices.filter { $0.color == crownRoof }.map(\.z)
            XCTAssertTrue(monitors.contains { abs($0 - Self.changhuaRoundhouseMonitorHeight) < 0.1 })
            let caps = model.vertices.filter { $0.color == doorway && $0.z > 9.5 }
            XCTAssertEqual(caps.map(\.z).max() ?? 0, Self.changhuaRoundhouseHeight, accuracy: 0.05)
            // The concave south courtyard around Decision 441's turntable
            // (3.47, -19.53) stays open above the ground tracks (z > 0.5 m).
            XCTAssertFalse(model.vertices.contains {
                (($0.x - 3.47) * ($0.x - 3.47) + ($0.y + 19.53) * ($0.y + 19.53)).squareRoot() < 13.5 && $0.z > 0.5
            })
            XCTAssertFalse(model.vertices.contains { $0.color == Self.wall })
        }
        let roundhouseAnchor = GeoAnchor(latitudeDegrees: roundhouse.latitude, longitudeDegrees: roundhouse.longitude)!
        let world = GameWorld.newGame(anchor: roundhouseAnchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let built = builder.addTaipeiLandmarks(frame: frame)
        XCTAssertEqual(Set(built.keys), [roundhouse])
        XCTAssertEqual(triangles(builder.nearMeshes), roundhouse.model(full: true).indices.count / 3)
        XCTAssertEqual(triangles(builder.farMeshes), roundhouse.model(full: false).indices.count / 3)
        XCTAssertTrue(builder.keptColours.contains(crownRoof))
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        let line = stride(from: Float(-120), through: 120, by: 2).map { middle + Map3DPoint($0, 0, 10) }
        var blocked = self.builder(world)
        blocked.trackLines = [(line, .surface)]
        XCTAssertTrue(blocked.addTaipeiLandmarks(frame: frame).isEmpty)
        var tunnel = self.builder(world)
        tunnel.trackLines = [(line, .tunnel)]
        XCTAssertEqual(Set(tunnel.addTaipeiLandmarks(frame: frame).keys), [roundhouse])
    }

    /// Decision 592: Kaohsiung Great Harbor Bridge (OSM relation 15430334,
    /// bridge outline way 1137765107 & swing span way 840552016: 126.44 m ×
    /// 15.38 m × 36.0 m), Gushan Ferry Terminal (OSM node 3921289758, ways
    /// 205060865, 388956314 & 588103933: 35.02 m × 56.60 m × 12.0 m), and
    /// Cijin Ferry Terminal (OSM node 3921289548, ways 255744758, 388956315
    /// & 388956316: 72.83 m × 34.26 m × 23.0 m) match OpenStreetMap's
    /// dimensions within 2 m, and stand clear of surface track while
    /// allowing underground track.
    func testKaohsiungHarborLandmarks() throws {
        let bridge = Map3DTaipeiLandmark.greatHarborBridge
        let gushan = Map3DTaipeiLandmark.gushanFerryTerminal
        let cijin = Map3DTaipeiLandmark.cijinFerryTerminal
        let vermilion = Map3DColor.rgb(0xDC968A)
        let hallWhite = Map3DColor.rgb(0xF8F7F3)
        let brick = Map3DColor.rgb(0xDDA996)

        for model in [bridge.model(full: true), bridge.model(full: false)] {
            let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
            XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), Self.greatHarborBridgeLength, accuracy: 2.0)
            XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), Self.greatHarborBridgeWidth, accuracy: 2.0)
            XCTAssertEqual((zs.max() ?? 0) - (zs.min() ?? 0), Self.greatHarborBridgeHeight, accuracy: 0.01)
            let ground = model.vertices.filter { $0.z < 0.01 }
            let gxs = ground.map(\.x), gys = ground.map(\.y)
            XCTAssertEqual((gxs.max() ?? 0) - (gxs.min() ?? 0), Self.greatHarborBridgeLength, accuracy: 2.0)
            XCTAssertEqual((gys.max() ?? 0) - (gys.min() ?? 0), Self.greatHarborBridgeWidth, accuracy: 2.0)
            XCTAssertEqual(((gxs.max() ?? 0) + (gxs.min() ?? 0)) / 2, 0, accuracy: 2.0)
            XCTAssertEqual(((gys.max() ?? 0) + (gys.min() ?? 0)) / 2, 0, accuracy: 2.0)
            // Elevated whale-back observation deck (6.95 m) & shell arch canopy (11.20 m).
            XCTAssertTrue(model.vertices.contains { $0.color == brick && abs($0.z - Self.greatHarborBridgeObservationHeight) < 0.1 })
            let shell = model.vertices.filter { $0.color == hallWhite && $0.z > 9.0 && $0.z < 12.0 }
            XCTAssertEqual(shell.map(\.z).max() ?? 0, Self.greatHarborBridgeShellHeight, accuracy: 0.2)
            XCTAssertFalse(model.vertices.contains { $0.color == Self.wall })
        }

        for model in [gushan.model(full: true), gushan.model(full: false)] {
            let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
            XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), Self.gushanFerryWidth, accuracy: 2.0)
            XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), Self.gushanFerryLength, accuracy: 2.0)
            XCTAssertEqual((zs.max() ?? 0) - (zs.min() ?? 0), Self.gushanFerryHeight, accuracy: 0.01)
            let ground = model.vertices.filter { $0.z < 0.01 }
            let gxs = ground.map(\.x), gys = ground.map(\.y)
            XCTAssertEqual((gxs.max() ?? 0) - (gxs.min() ?? 0), Self.gushanFerryWidth, accuracy: 2.0)
            XCTAssertEqual((gys.max() ?? 0) - (gys.min() ?? 0), Self.gushanFerryLength, accuracy: 2.0)
            XCTAssertEqual(((gxs.max() ?? 0) + (gxs.min() ?? 0)) / 2, 0, accuracy: 2.0)
            XCTAssertEqual(((gys.max() ?? 0) + (gys.min() ?? 0)) / 2, 0, accuracy: 2.0)
            // Wave-arched waiting gallery roof (way 205060865: 6.20 m) & 2-storey terminal parapet (way 588103933: 10.50 m).
            let galleryWave = model.vertices.filter { $0.y > 0 && $0.z > 5.5 }
            XCTAssertEqual(galleryWave.map(\.z).max() ?? 0, Self.gushanFerryWaveHeight, accuracy: 0.1)
            XCTAssertTrue(model.vertices.contains { $0.color == Self.flatRoof && abs($0.z - Self.gushanFerryRoofHeight) < 0.1 })
            XCTAssertFalse(model.vertices.contains { $0.color == Self.wall })
        }

        for model in [cijin.model(full: true), cijin.model(full: false)] {
            let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
            XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), Self.cijinFerryLength, accuracy: 2.0)
            XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), Self.cijinFerryWidth, accuracy: 2.0)
            XCTAssertEqual((zs.max() ?? 0) - (zs.min() ?? 0), Self.cijinFerryHeight, accuracy: 0.01)
            let ground = model.vertices.filter { $0.z < 0.01 }
            let gxs = ground.map(\.x), gys = ground.map(\.y)
            XCTAssertEqual((gxs.max() ?? 0) - (gxs.min() ?? 0), Self.cijinFerryLength, accuracy: 2.0)
            XCTAssertEqual((gys.max() ?? 0) - (gys.min() ?? 0), Self.cijinFerryWidth, accuracy: 2.0)
            XCTAssertEqual(((gxs.max() ?? 0) + (gxs.min() ?? 0)) / 2, 0, accuracy: 2.0)
            XCTAssertEqual(((gys.max() ?? 0) + (gys.min() ?? 0)) / 2, 0, accuracy: 2.0)
            // Main red-brick building (way 255744758: 72.83 m × 19.52 m), flanking turrets (14.80 m) & octagonal tower roof (21.50 m).
            let buildingGround = ground.filter { $0.y < 3.0 }
            XCTAssertEqual((buildingGround.map(\.y).max() ?? 0) - (buildingGround.map(\.y).min() ?? 0), Self.cijinFerryBuildingWidth, accuracy: 2.0)
            XCTAssertTrue(model.vertices.contains { $0.color == vermilion && abs($0.z - Self.cijinFerryTurretHeight) < 0.1 })
            XCTAssertTrue(model.vertices.contains { $0.color == vermilion && abs($0.z - Self.cijinFerryTowerRoofHeight) < 0.1 })
            XCTAssertFalse(model.vertices.contains { $0.color == Self.wall })
        }

        let harborAnchor = GeoAnchor(latitudeDegrees: bridge.latitude, longitudeDegrees: bridge.longitude)!
        let world = GameWorld.newGame(anchor: harborAnchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let built = builder.addTaipeiLandmarks(frame: frame)
        let harborSet: Set<Map3DTaipeiLandmark> = [bridge, gushan, cijin]
        XCTAssertEqual(Set(built.keys), harborSet)
        XCTAssertEqual(triangles(builder.nearMeshes), harborSet.reduce(0) { $0 + $1.model(full: true).indices.count / 3 })
        XCTAssertEqual(triangles(builder.farMeshes), harborSet.reduce(0) { $0 + $1.model(full: false).indices.count / 3 })
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        let line = stride(from: Float(-120), through: 120, by: 2).map { middle + Map3DPoint($0, 0, 5) }
        var blocked = self.builder(world)
        blocked.trackLines = [(line, .surface)]
        XCTAssertEqual(Set(blocked.addTaipeiLandmarks(frame: frame).keys), [gushan, cijin])
        var tunnel = self.builder(world)
        tunnel.trackLines = [(line, .tunnel)]
        XCTAssertEqual(Set(tunnel.addTaipeiLandmarks(frame: frame).keys), harborSet)
    }

    /// Stood where it is, the station is in full close by and simpler from
    /// afar, in its own colours, and clears the ground under it.
    func testWhereItStands() throws {
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let built = builder.addTaipeiLandmarks(frame: frame)
        let station = Map3DTaipeiLandmark.taipeiMainStation
        // With it, decision 457's central Taipei and decision 550's Shin
        // Kong Life Tower within the scene; 101, the Sun Yat-sen Memorial
        // Hall and the Grand Hotel are not.
        XCTAssertTrue(Set(built.keys).isSuperset(of: [station, .shinKongLifeTower, .northGate, .presidentialOffice, .chiangKaiShekMemorialHall]))
        XCTAssertTrue(built.keys.allSatisfy {
            ![.taipei101, .sunYatSenMemorialHall, .grandHotel, .kaohsiungMainStation, .kaohsiung85SkyTower,
              .changhuaRoundhouse, .greatHarborBridge, .gushanFerryTerminal, .cijinFerryTerminal].contains($0)
        })
        let taken = try XCTUnwrap(built[station])
        XCTAssertEqual(triangles(builder.nearMeshes), built.keys.reduce(0) { $0 + $1.model(full: true).indices.count / 3 })
        XCTAssertEqual(triangles(builder.farMeshes), built.keys.reduce(0) { $0 + $1.model(full: false).indices.count / 3 })
        XCTAssertTrue(builder.closeMeshes.isEmpty)
        XCTAssertTrue(builder.keptColours.contains(Self.wall))
        // Its 184 m by 160 m of ground: three 64 m cells each way at least.
        XCTAssertGreaterThanOrEqual(taken.count, 9)
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        XCTAssertTrue(taken.contains(builder.chunk(of: middle)))
        let walls = builder.nearMeshes.values.flatMap(\.vertices).filter { $0.color == Self.wall }
        let xs = walls.map(\.x), zs = walls.map(\.z)
        XCTAssertEqual(((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, middle.x, accuracy: 15)
        XCTAssertEqual(((zs.min() ?? 0) + (zs.max() ?? 0)) / 2, middle.z, accuracy: 15)
    }

    /// Track on the ground through it: not built. Under it, in a tunnel as
    /// the real station's: built.
    func testNotOnTheTrack() throws {
        let world = GameWorld.newGame(anchor: anchor)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var builder = builder(world)
        let middle = builder.point(x: frame.middleX, y: frame.middleY, height: 0)
        let line = stride(from: Float(-300), through: 300, by: 2).map { middle + Map3DPoint($0, 0, 30) }
        builder.trackLines = [(line, .surface)]
        XCTAssertNil(builder.addTaipeiLandmarks(frame: frame)[.taipeiMainStation])
        XCTAssertFalse(builder.nearMeshes.values.contains { $0.vertices.contains { $0.color == Self.wall } })
        var under = self.builder(world)
        under.trackLines = [(line, .tunnel)]
        XCTAssertNotNil(under.addTaipeiLandmarks(frame: frame)[.taipeiMainStation])
        // 120 m off, clear of it.
        var beside = self.builder(world)
        beside.trackLines = [(line.map { $0 + Map3DPoint(0, 0, 90) }, .surface)]
        XCTAssertNotNil(beside.addTaipeiLandmarks(frame: frame)[.taipeiMainStation])
    }

    /// A station of the player's beside it is built as Taipei Main
    /// Station, so the station kit would draw its own Taipei there: where
    /// the landmark stands, it draws none.
    func testTheKitsTaipeiGivesWay() throws {
        let start = GameWorld.newGame(anchor: anchor)
        let empty = Map3DScene(world: start)
        let off = Int64(150 * WorldCoordinate.unitsPerMetre), across = Int64(3_000 * WorldCoordinate.unitsPerMetre)
        let y = Int64(empty.originY) - off, x = Int64(empty.originX)
        let world = try newGameLine(through: [PlanPoint(x: x - across, y: y), PlanPoint(x: x, y: y), PlanPoint(x: x + across, y: y)], in: start)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        // The kit's buildings: Taipei's, and the line's two other
        // stations' 3 km off.
        var kit = builder
        let all = kit.addStations(snapshot, frame: frame)
        XCTAssertNotNil(builder.addTaipeiLandmarks(frame: frame)[.taipeiMainStation])
        let others = builder.addStations(snapshot, frame: frame, drawnElsewhere: [.taipei])
        XCTAssertTrue(others.isStrictSubset(of: all))
        let middle = builder.chunk(of: builder.point(x: frame.middleX, y: frame.middleY, height: 0))
        // Within 8 cells (512 m) of the middle's.
        func near(_ cells: Set<Map3DScene.ChunkKey>) -> Bool {
            cells.contains { abs($0.column - middle.column) <= 8 && abs($0.row - middle.row) <= 8 }
        }
        XCTAssertTrue(near(all), "the kit's Taipei, by the middle")
        XCTAssertFalse(near(others))
        // The scene: the landmark's walls, all of them.
        let station = Map3DTaipeiLandmark.taipeiMainStation
        let expected = (station.model(full: true).vertices + station.model(full: false).vertices).filter { $0.color == Self.wall }.count
        XCTAssertEqual(walls(Map3DScene(world: world)), expected)
    }

    private func walls(_ scene: Map3DScene) -> Int {
        scene.chunks.reduce(0) { $0 + ($1.mesh.vertices + $1.farWithBoxes.vertices).filter { $0.color == Self.wall }.count }
    }

    /// The scene draws it on a real-world map, its colours as they are
    /// (not paled), and none on a map of nowhere.
    func testTheSceneTakesIt() {
        let station = Map3DTaipeiLandmark.taipeiMainStation
        let expected = (station.model(full: true).vertices + station.model(full: false).vertices).filter { $0.color == Self.wall }.count
        XCTAssertGreaterThan(expected, 0)
        XCTAssertEqual(walls(Map3DScene(world: GameWorld.newGame(anchor: anchor))), expected)
        XCTAssertEqual(walls(Map3DScene(world: GameWorld.newGame())), 0)
    }
}
