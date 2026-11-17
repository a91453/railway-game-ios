import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 794: the winter event's trees and lights on the 3D map
/// (``Map3DWinterLights``).
final class Map3DWinterLightsTests: XCTestCase {
    private let calendar = WinterEvent.calendar(in: TimeZone(identifier: "Asia/Taipei")!)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static let demoWorld = DemoWorld.make(in: .english)
    private static let demo = Map3DScene(world: demoWorld)

    /// What a frame seen from `eye` on `date` holds.
    private func frame(_ lights: Map3DWinterLights, eye: Map3DPoint, on date: Date, switchedOn: Bool = true,
                       pack: Map3DModelPack = .standard) -> Map3DTrains.Frame {
        var frame = Map3DTrains.Frame()
        lights.add(to: &frame, pack: pack, eye: eye, at: date, switchedOn: switchedOn, calendar: calendar)
        return frame
    }

    /// Out of the event's dates, or with the settings' switch off, not
    /// one is drawn; in December with it on, they are.
    func testNoneOutsideTheEventOrWithTheSwitchOff() throws {
        let lights = Self.demo.winterLights
        let eye = try XCTUnwrap(lights.placements.first).point + Map3DPoint(0, 30, 0)
        for day in [date(2026, 11, 30, 23), date(2027, 1, 7, 0), date(2027, 6, 1), date(2027, 11, 15)] {
            XCTAssertTrue(frame(lights, eye: eye, on: day).instances.isEmpty, "\(day)")
        }
        for day in [date(2026, 12, 1, 0), date(2026, 12, 24), date(2027, 1, 6, 23)] {
            XCTAssertTrue(frame(lights, eye: eye, on: day, switchedOn: false).instances.isEmpty, "\(day) switched off")
            XCTAssertFalse(frame(lights, eye: eye, on: day).instances.isEmpty, "\(day)")
        }
    }

    /// The demo's map: every station building has its lights along its
    /// front, no more than ``Map3DWinterLights/mostStringsAFront`` each,
    /// hung at its eaves; no big tree off a real-world map; the same
    /// every time it is built.
    func testTheDemoMapsStations() {
        let placements = Self.demo.winterLights.placements
        let strings = placements.filter { $0.decor == .lightString }
        XCTAssertFalse(strings.isEmpty)
        XCTAssertFalse(placements.contains { $0.decor == .treeLarge })
        XCTAssertTrue(placements.allSatisfy { [.lightString, .treeMedium].contains($0.decor) })
        // Lengths of one front side by side, 4 m apart, end to end.
        var fronts: [[Map3DWinterLights.Placement]] = []
        for string in strings {
            if let last = fronts.last?.last, abs((string.point - last.point).length - 4) < 0.01 {
                fronts[fronts.count - 1].append(string)
            } else {
                fronts.append([string])
            }
        }
        XCTAssertTrue(fronts.allSatisfy { $0.count <= Map3DWinterLights.mostStringsAFront }, "\(fronts.map(\.count))")
        let ground = Self.demo.drawnGround
        for string in strings {
            let height = string.point.y - ground.height(x: string.point.x, z: string.point.z, world: Self.demoWorld)
            XCTAssertGreaterThanOrEqual(height, Map3DWinterLights.lowestString)
            XCTAssertLessThanOrEqual(height, Map3DWinterLights.highestString + 0.5)
        }
        XCTAssertEqual(Map3DScene(world: DemoWorld.make(in: .english)).winterLights, Self.demo.winterLights)
    }

    /// WINTER-LIGHTS-2: on every kind of station building the lights hang
    /// on the building itself: none over the forecourt (the last six
    /// metres of its bounds, four metres past each end), each on a face
    /// (something of the building just behind its line), alike on both
    /// sides of a building alike on both sides, no more than
    /// ``Map3DWinterLights/mostStringsAFront``.
    func testTheLightsHangOnEveryKindOfBuilding() throws {
        for profile in Map3DStationKit.Profile.allCases where Map3DStationKit.hasHouse(profile) {
            let all = Map3DStationKit.stations.filter { $0.profile == profile }
            var kinds = Array(all.prefix(1))
            if let first = all.first, let other = all.first(where: { $0.seed % 7 % 2 != first.seed % 7 % 2 }) { kinds.append(other) }
            for station in kinds {
                for expansion in [nil, StationExpansion.concourse, .hall] {
                    var kit = StationKitBuilder()
                    kit.house(station, expansion: expansion)
                    let bounds = try XCTUnwrap(kit.mesh.bounds)
                    let strings = Map3DWinterLights.strings(on: kit.mesh)
                    let name = "\(profile.rawValue) \(station.name) \(String(describing: expansion))"
                    XCTAssertFalse(strings.isEmpty, name)
                    XCTAssertLessThanOrEqual(strings.count, Map3DWinterLights.mostStringsAFront, name)
                    let middle = (bounds.min.z + bounds.max.z) / 2, half = (bounds.max.z - bounds.min.z) / 2
                    for string in strings {
                        XCTAssertLessThanOrEqual(string.x, bounds.max.x - 6 + Map3DWinterLights.stringOut + 0.01, "\(name): over the forecourt")
                        XCTAssertLessThanOrEqual(abs(string.z - middle) + Map3DWinterLights.stringLength / 2, half - 4 + 0.26, "\(name): past the building's end")
                        XCTAssertGreaterThanOrEqual(string.y, Map3DWinterLights.lowestString, name)
                        XCTAssertLessThanOrEqual(string.y, Map3DWinterLights.highestString + 0.01, name)
                        // Something of the building within half a metre behind the line, at its middle.
                        let behind = kit.mesh.vertices.contains { vertex in
                            vertex.x >= string.x - Map3DWinterLights.stringOut - 0.5 && vertex.x <= string.x
                                && abs(vertex.y - string.y) <= 3 && abs(vertex.z - string.z) <= 40
                        }
                        XCTAssertTrue(behind, "\(name): hangs in the air")
                    }
                    // The kit's plain buildings are alike on both sides.
                    if [.regional, .halt, .banqiao, .nangang, .hualien, .zuoying, .highSpeed].contains(profile) {
                        let offsets = strings.map { ($0.z - middle) }.sorted()
                        for (a, b) in zip(offsets, offsets.reversed()) { XCTAssertEqual(a, -b, accuracy: 0.01, name) }
                    }
                }
            }
        }
        // The kit's exit: along each long edge of its canopy, under its top.
        var exit = StationKitBuilder()
        exit.part(.undergroundExit)
        let top = try XCTUnwrap(exit.mesh.bounds).max
        for string in Map3DWinterLights.exitStrings {
            XCTAssertLessThan(string.y, top.y)
            XCTAssertEqual(abs(string.z), top.z, accuracy: 0.3)
        }
    }

    /// The most a frame draws stays in the budget, and a frame over the
    /// busiest spot of the demo draws no more; the trees go to their far
    /// models past ``Map3DWinterLights/treeNearReach`` and are gone past
    /// ``Map3DWinterLights/treeFarReach``, the lights past
    /// ``Map3DWinterLights/stringReach``.
    func testTheBudgetAndTheReaches() throws {
        XCTAssertLessThanOrEqual(Map3DWinterLights.mostTriangles, 42_000)
        let pack = Map3DModelPack.standard
        let lights = Self.demo.winterLights, day = date(2026, 12, 20)
        for placement in lights.placements {
            let drawn = frame(lights, eye: placement.point, on: day, pack: pack)
            let triangles = drawn.instances.reduce(0) { $0 + pack.models[$1.model].triangleCount }
            XCTAssertLessThanOrEqual(triangles, Map3DWinterLights.mostTriangles)
        }
        let tree = Map3DWinterLights(placements: [.init(decor: .treeLarge, point: .zero, forward: Map3DPoint(1, 0, 0)),
                                                  .init(decor: .lightString, point: .zero, forward: Map3DPoint(1, 0, 0))])
        func names(_ away: Float) -> [String] {
            frame(tree, eye: Map3DPoint(away, 0, 0), on: day, pack: pack).instances.map { pack.models[$0.model].name }.sorted()
        }
        XCTAssertEqual(names(100), [Map3DWinterDecor.lightString.modelName, Map3DWinterDecor.treeLarge.modelName])
        XCTAssertEqual(names(Map3DWinterLights.treeNearReach + 10), [Map3DWinterDecor.treeLargeFar.modelName])
        XCTAssertEqual(names(Map3DWinterLights.treeFarReach + 10), [])
        // The nearest are drawn, no more than the most.
        let many = Map3DWinterLights(placements: (0..<200).map {
            .init(decor: $0 % 2 == 0 ? .treeMedium : .lightString, point: Map3DPoint(Float($0), 0, 0), forward: Map3DPoint(1, 0, 0))
        })
        let crowd = frame(many, eye: .zero, on: day, pack: pack).instances
        XCTAssertEqual(crowd.filter { pack.models[$0.model].name == Map3DWinterDecor.treeMedium.modelName }.count, Map3DWinterLights.mostTrees)
        XCTAssertEqual(crowd.filter { pack.models[$0.model].name == Map3DWinterDecor.lightString.modelName }.count, Map3DWinterLights.mostStrings)
        XCTAssertTrue(crowd.allSatisfy { $0.transform[12] < 200 })
    }

    /// The bulbs light only at night: they are the models' lit vertices,
    /// which the shader lights by the night's lights and ``Map3DGlow``
    /// glows only when there are some; at noon there are none, at nine in
    /// the evening there are.
    func testTheBulbsLightOnlyAtNight() throws {
        let noon = Map3DLighting(minute: 12 * 60), evening = Map3DLighting(minute: 21 * 60)
        XCTAssertFalse(Map3DGlow.shows(lights: noon.lights))
        XCTAssertTrue(Map3DGlow.shows(lights: evening.lights))
        let pack = Map3DModelPack.standard
        for decor in Map3DWinterDecor.allCases {
            let index = try XCTUnwrap(pack.index(of: decor.modelName), decor.rawValue)
            let model = pack.models[index]
            let lit = model.vertices.filter { $0.layer == Map3DVertex.glowing }
            XCTAssertFalse(lit.isEmpty, decor.rawValue)
            let bulbs = Set(Map3DWinterDecor.Material.allCases.filter(\.isBulb).map(\.colour))
            XCTAssertTrue(Set(lit.map(\.color)).isSubset(of: bulbs), "\(decor.rawValue): only the bulbs")
            XCTAssertLessThan(lit.count, model.vertices.count, "\(decor.rawValue): the tree itself is unlit")
            XCTAssertFalse(Map3DGlow.spots(of: model).isEmpty, decor.rawValue)
        }
    }

    /// The pack holds the five models after the commuter, before the route
    /// bus, as decision 790 made them.
    func testThePackHoldsTheModels() throws {
        let pack = Map3DModelPack.standard
        let names = pack.models.map(\.name)
        let first = try XCTUnwrap(names.firstIndex(of: Map3DWinterDecor.treeMedium.modelName))
        XCTAssertEqual(Array(names[first..<first + 5]), Map3DWinterDecor.allCases.map(\.modelName))
        XCTAssertEqual(names[first - 1], Map3DStreetModel.commuterWalking.modelName)
        // Decision 831: then Santa's sleigh, then the route bus.
        XCTAssertEqual(names[first + 5], SantaFlight.Model.name)
        XCTAssertEqual(names[first + 6], Map3DLowFloorBus.routeModel().name)
        for decor in Map3DWinterDecor.allCases {
            XCTAssertEqual(pack.models[first + decor.index].triangleCount, try XCTUnwrap(decor.model).triangleCount)
        }
    }

    /// A plaza's big tree stands on its plaza on Taiwan's map (Banqiao) and
    /// on Hong Kong's (Tsim Sha Tsui), moved no farther than
    /// ``Map3DWinterLights/plazaSearch``; the Santa Claus village is on
    /// neither.
    func testThePlazasTrees() throws {
        let banqiao = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0141, longitudeDegrees: 121.4637))
        let taiwan = GameWorld.newGame(anchor: banqiao)
        let hongKong = GameWorld.newOverseasGame(try HongKongBaseMapTests.ground())
        for (world, plaza, landmarks) in [(taiwan, "banqiao", false), (hongKong, "tsim-sha-tsui", true)] {
            let frame = try XCTUnwrap(RealWorldFrame(world: world))
            let spot = try XCTUnwrap(Map3DWinterLights.plazas.first { $0.name == plaza })
            let place = frame.worldPosition(latitude: spot.latitude, longitude: spot.longitude)
            let metre = Double(WorldCoordinate.unitsPerMetre), reach = 1_500 * metre
            let region = WorldRegion(minX: place.x - reach, minY: place.y - reach, maxX: place.x + reach, maxY: place.y + reach)
            var builder = Map3DScene.Builder(originX: place.x, originY: place.y, region: region, world: world, heights: nil)
            if landmarks { _ = builder.addHongKongLandmarks(frame: frame) }
            builder.addWinterDecor(frame: frame)
            let trees = builder.winterDecor.filter { $0.decor == .treeLarge }
            XCTAssertEqual(trees.count, 1, plaza)
            let tree = try XCTUnwrap(trees.first)
            XCTAssertLessThanOrEqual(Map3DPoint(tree.point.x, 0, tree.point.z).length, Map3DWinterLights.plazaSearch + 0.01, plaza)
            XCTAssertFalse(builder.underLandmark(tree.point), plaza)
            // XMAS-TREE-SIZE: as big as it has room for, and its planter
            // on no station building or shop.
            XCTAssertEqual(tree.scale, Map3DWinterLights.plazaTreeScales[0], plaza)
            XCTAssertTrue(builder.isClearOfBuildings(tree.point, radius: Map3DWinterLights.plazaTreeFoot * tree.scale), plaza)
        }
    }

    /// XMAS-TREE-SIZE: a big station's tree is drawn as big as its plaza
    /// has room for: on the demo's plazas, shops across them, 12 m (the
    /// 15 m one's planter would reach the shops' awnings); on a plaza with
    /// nothing across, 15 m; and a frame draws it at its size.
    func testAStationsTreeIsAsBigAsItsPlaza() throws {
        let trees = Self.demo.winterLights.placements.filter { $0.decor == .treeMedium }
        XCTAssertFalse(trees.isEmpty)
        XCTAssertTrue(trees.allSatisfy { Map3DWinterLights.stationTreeScales.contains($0.scale) }, "\(trees.map(\.scale))")
        XCTAssertTrue(trees.allSatisfy { $0.scale == 2 }, "\(trees.map(\.scale))")
        // With nothing across the plaza, the biggest; a shop across it,
        // 12 m; the plaza no deeper than the model's own planter, 6 m.
        let banqiao = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0141, longitudeDegrees: 121.4637))
        let world = GameWorld.newGame(anchor: banqiao)
        let metre = Double(WorldCoordinate.unitsPerMetre), reach = 500 * metre
        let place = try XCTUnwrap(RealWorldFrame(world: world)).worldPosition(latitude: 25.0141, longitude: 121.4637)
        let x = place.x, y = place.y
        func scale(shopFrom near: Float?) -> Float? {
            let region = WorldRegion(minX: x - reach, minY: y - reach, maxX: x + reach, maxY: y + reach)
            var builder = Map3DScene.Builder(originX: x, originY: y, region: region, world: world, heights: nil)
            builder.stationFronts = [(centre: .zero, forward: Map3DPoint(1, 0, 0), depth: 20, wide: 40, top: 10, big: true, strings: [])]
            builder.houseFootprints = [[Map3DPoint(-10, 0, -20), Map3DPoint(10, 0, -20), Map3DPoint(10, 0, 20), Map3DPoint(-10, 0, 20)]]
            if let near {
                builder.shopFootprints = [[Map3DPoint(10 + near, 0, -3), Map3DPoint(30, 0, -3), Map3DPoint(30, 0, 3), Map3DPoint(10 + near, 0, 3)]]
            }
            builder.addWinterDecor(frame: nil)
            return builder.winterDecor.first { $0.decor == .treeMedium }?.scale
        }
        XCTAssertEqual(scale(shopFrom: nil), 2.5)
        XCTAssertEqual(scale(shopFrom: 12.1), 2)
        XCTAssertEqual(scale(shopFrom: 10.2), 1)
        XCTAssertNil(scale(shopFrom: 9))
        XCTAssertTrue(Self.demo.winterLights.placements.filter { $0.decor == .lightString }.allSatisfy { $0.scale == 1 })
        let tree = try XCTUnwrap(trees.first)
        let pack = Map3DModelPack.standard
        let drawn = frame(Map3DWinterLights(placements: [tree]), eye: tree.point + Map3DPoint(0, 30, 0), on: date(2026, 12, 20), pack: pack)
        let instance = try XCTUnwrap(drawn.instances.first)
        let up = Map3DPoint(instance.transform[8], instance.transform[9], instance.transform[10])
        XCTAssertEqual(up.length, tree.scale, accuracy: 0.001)
    }

    /// XMAS-TREE-SIZE: how far a point is from a building's outline.
    func testTheDistanceToAnOutline() {
        let square = [Map3DPoint(0, 0, 0), Map3DPoint(10, 0, 0), Map3DPoint(10, 0, 10), Map3DPoint(0, 0, 10)]
        XCTAssertEqual(Map3DScene.Builder.distance(from: Map3DPoint(5, 0, 5), to: square), 0)
        XCTAssertEqual(Map3DScene.Builder.distance(from: Map3DPoint(13, 0, 5), to: square), 3, accuracy: 0.001)
        XCTAssertEqual(Map3DScene.Builder.distance(from: Map3DPoint(13, 0, 14), to: square), 5, accuracy: 0.001)
        XCTAssertEqual(Map3DScene.Builder.distance(from: Map3DPoint(13, 0, 14), to: square.reversed()), 5, accuracy: 0.001)
        XCTAssertEqual(Map3DScene.Builder.distance(from: Map3DPoint(5, 0, 5), to: square.reversed()), 0)
    }

    /// A plaza's tree is moved to the nearest clear spot, and left out
    /// when none is near.
    func testAPlazasTreeMovesClear() {
        let middle = Map3DPoint(100, 0, 50)
        XCTAssertEqual(Map3DScene.Builder.plazaSpot(round: middle) { _ in true }, middle)
        let moved = Map3DScene.Builder.plazaSpot(round: middle) { ($0 - middle).length > 10 }
        XCTAssertEqual(moved.map { ($0 - middle).length } ?? 0, 16, accuracy: 0.01)
        XCTAssertNil(Map3DScene.Builder.plazaSpot(round: middle) { _ in false })
    }
}

private extension Map3DWinterDecor {
    var index: Int { Self.allCases.firstIndex(of: self)! }
}
