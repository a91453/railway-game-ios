import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 458: the Kenney conifers, bush clumps and tank, their files in
/// the app and their stand-ins in the pack, and where the scene puts them.
final class Map3DSceneryPropsTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let tiles: Result<BaseMapTiles, Error> = Result {
        try BaseMapTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan.pmtiles"), options: .alwaysMapped))
    }

    private static func file(_ prop: Map3DSceneryProp) -> URL {
        root.appendingPathComponent("RailwayGameApp/Resources/Models/\(prop.fileName).\(Map3DSceneryProp.fileExtension)")
    }

    private static var files: [Map3DSceneryProp: URL] {
        Dictionary(uniqueKeysWithValues: Map3DSceneryProp.allCases.map { ($0, file($0)) })
    }

    /// Each stand-in is in the pack, its box the file's size, its foot on
    /// the ground and its middle over the origin.
    func testTheStandInsAreInThePackAtTheFilesSize() throws {
        let pack = Map3DModelPack.standard
        for prop in Map3DSceneryProp.allCases {
            let index = try XCTUnwrap(pack.index(of: prop.modelName), prop.rawValue)
            let model = pack.models[index]
            XCTAssertFalse(model.vertices.isEmpty, prop.rawValue)
            let size = prop.size
            XCTAssertEqual(model.maximum.x - model.minimum.x, size.length, accuracy: 0.001, prop.rawValue)
            XCTAssertEqual(model.maximum.y - model.minimum.y, size.width, accuracy: 0.001, prop.rawValue)
            XCTAssertEqual(model.minimum.z, 0, prop.rawValue)
            XCTAssertEqual(model.maximum.z, size.height, accuracy: 0.001, prop.rawValue)
            let low = model.vertices.map(\.position.z).min() ?? -1, high = model.vertices.map(\.position.z).max() ?? -1
            XCTAssertEqual(low, 0, accuracy: 0.01, prop.rawValue)
            XCTAssertEqual(high, size.height, accuracy: 0.01, prop.rawValue)
            XCTAssertEqual(Map3DScene.Builder.sceneryModels[prop], index)
        }
        // The conifers' and bushes' leaves take the instance's green.
        for prop in Map3DSceneryProp.conifers + Map3DSceneryProp.bushClumps {
            let model = try XCTUnwrap(pack.models.first { $0.name == prop.modelName })
            XCTAssertTrue(model.vertices.contains { $0.color >> 24 == 0 }, prop.rawValue)
        }
    }

    /// Read from the app's files, each piece takes its stand-in's place, at
    /// its index and in its box, with the triangles `tools/kenney-props/`
    /// wrote and its leaves the instance's colour; the tank's are its own.
    func testTheFilesTakeTheStandInsPlaces() throws {
        let standard = Map3DModelPack.standard
        let pack = Map3DSceneryProp.pack(standard, files: Self.files)
        XCTAssertEqual(pack.models.count, standard.models.count)
        let triangles: [Map3DSceneryProp: Int] = [.pineTall: 136, .pine: 88, .pineYoung: 64, .bushes: 120, .bushesLarge: 180, .tank: 332]
        for prop in Map3DSceneryProp.allCases {
            let index = try XCTUnwrap(standard.index(of: prop.modelName))
            let model = pack.models[index]
            XCTAssertEqual(model.name, prop.modelName)
            XCTAssertEqual(model.vertices.count, (triangles[prop] ?? 0) * 3, prop.rawValue)
            XCTAssertEqual(model.minimum, standard.models[index].minimum, prop.rawValue)
            XCTAssertEqual(model.maximum, standard.models[index].maximum, prop.rawValue)
            let size = prop.size
            XCTAssertEqual(model.vertices.map(\.position.z).max() ?? 0, size.height, accuracy: 0.01, prop.rawValue)
            XCTAssertEqual(model.vertices.map(\.position.x).max() ?? 0, size.length / 2, accuracy: 0.01, prop.rawValue)
            let tinted = model.vertices.filter { $0.color >> 24 == 0 }.count
            if prop == .tank {
                XCTAssertEqual(tinted, 0)
            } else {
                // Leaves, and a trunk or nothing else.
                XCTAssertGreaterThan(tinted, model.vertices.count / 2, prop.rawValue)
            }
        }
        // The rest of the pack is as it was.
        let scenery = Set(Map3DSceneryProp.allCases.map(\.modelName))
        for (old, new) in zip(standard.models, pack.models) where !scenery.contains(old.name) {
            XCTAssertEqual(old.vertices, new.vertices, old.name)
        }
        // A missing file leaves its stand-in.
        let missing = Map3DSceneryProp.pack(standard, files: [.tank: Self.root.appendingPathComponent("no-such.m3dmodel")])
        let tank = try XCTUnwrap(standard.index(of: Map3DSceneryProp.tank.modelName))
        XCTAssertEqual(missing.models[tank].vertices, standard.models[tank].vertices)
    }

    /// No conifer below 400 m, a growing share above it, most from 1,400 m.
    func testConifersGrowHigherUp() {
        XCTAssertEqual(Map3DScene.Builder.coniferShare(atHeight: 0), 0)
        XCTAssertEqual(Map3DScene.Builder.coniferShare(atHeight: 400), 0)
        XCTAssertEqual(Map3DScene.Builder.coniferShare(atHeight: 900), 0.425, accuracy: 0.0001)
        XCTAssertEqual(Map3DScene.Builder.coniferShare(atHeight: 1400), 0.85, accuracy: 0.0001)
        XCTAssertEqual(Map3DScene.Builder.coniferShare(atHeight: 3000), 0.85, accuracy: 0.0001)
    }

    /// The saving quality leaves the bush clumps out with the small street
    /// furniture; the conifers and tanks stay.
    func testSavingLeavesTheBushesOut() throws {
        let pack = Map3DModelPack.standard
        let left = Map3DProp.modelsLeftOut(.saving)
        for prop in Map3DSceneryProp.allCases {
            let index = try XCTUnwrap(pack.index(of: prop.modelName))
            XCTAssertEqual(left.contains(index), Map3DSceneryProp.bushClumps.contains(prop), prop.rawValue)
        }
    }

    private static func instances(_ chunk: Map3DScene.Chunk, of props: [Map3DSceneryProp]) -> Int {
        let indices = Set(props.compactMap { Map3DScene.Builder.sceneryModels[$0] })
        return chunk.props.filter { indices.contains($0.model) }.count
    }

    private static func instances(_ scene: Map3DScene, of props: [Map3DSceneryProp]) -> [Map3DInstance] {
        let indices = Set(props.compactMap { Map3DScene.Builder.sceneryModels[$0] })
        return scene.chunks.flatMap(\.props).filter { indices.contains($0.model) }
    }

    /// In the mountains (Alishan, about 2,200 m) the base map's woods hold
    /// conifers, all of them above 400 m; round Taipei Main Station (a few
    /// metres up) there are none. The same every time.
    func testAMountainSceneHasConifersAndTheCityHasNone() throws {
        let tiles = try Self.tiles.get()
        let mountain = try XCTUnwrap(GeoAnchor(latitudeDegrees: 23.5106, longitudeDegrees: 120.8045))
        let heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        func world(_ anchor: GeoAnchor) throws -> GameWorld {
            var world = GameWorld.newGame(anchor: anchor)
            try world.mapGround()
            return world
        }
        let high = Map3DScene(world: try world(mountain), baseMap: tiles, heights: heights)
        let conifers = Self.instances(high, of: Map3DSceneryProp.conifers)
        XCTAssertGreaterThan(conifers.count, 50)
        // About 220 at most on a 512 m chunk (decision 458).
        XCTAssertLessThanOrEqual(high.chunks.map { Self.instances($0, of: Map3DSceneryProp.conifers) }.max() ?? 0, 230)
        XCTAssertTrue(conifers.allSatisfy { $0.transform[13] > 400 })
        XCTAssertEqual(Self.instances(Map3DScene(world: try world(mountain), baseMap: tiles, heights: heights), of: Map3DSceneryProp.conifers).map(\.transform),
                       conifers.map(\.transform))

        let taipei = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170))
        let city = Map3DScene(world: try world(taipei), baseMap: tiles, heights: heights)
        XCTAssertTrue(Self.instances(city, of: Map3DSceneryProp.conifers).isEmpty)
        // A blank map has none of them.
        XCTAssertTrue(Self.instances(Map3DScene(world: GameWorld.newGame()), of: Map3DSceneryProp.conifers + Map3DSceneryProp.bushClumps).isEmpty)
    }

    /// The workshops' and sawtooth halls' yards (a 40 m lot) have one or
    /// two tanks beside the hall, within the yard and clear of the hall
    /// and the office; the warehouses, brick plants and small lots none,
    /// and nothing from afar.
    func testFactoryYardsHaveTanksBesideTheHall() throws {
        let world = GameWorld.newGame()
        let tank = try XCTUnwrap(Map3DScene.Builder.sceneryModels[.tank])
        var yards = 0
        for side: Float in [40, 24] {
            for column in Int32(0)..<32 {
                var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
                builder.target = .near
                builder.addFactory(base: .zero, side: side, seed: (column, 7))
                let tanks = builder.props.values.flatMap { $0 }.filter { $0.model == tank }
                guard !tanks.isEmpty else { continue }
                XCTAssertEqual(side, 40, "lot \(column)")
                XCTAssertLessThanOrEqual(tanks.count, 2)
                yards += 1
                let lot = side - 4
                let buildings = (builder.meshes.values.flatMap(\.vertices) + builder.nearMeshes.values.flatMap(\.vertices)).filter { $0.y > 0.5 }
                for placed in tanks {
                    let box = try XCTUnwrap(placed.bounds(in: .standard))
                    XCTAssertTrue(box.min.x >= -lot / 2 - 0.01 && box.max.x <= lot / 2 + 0.01 && box.min.z >= -lot / 2 - 0.01 && box.max.z <= lot / 2 + 0.01,
                                  "lot \(column): \(box)")
                    XCTAssertFalse(buildings.contains { $0.x > box.min.x + 0.2 && $0.x < box.max.x - 0.2 && $0.z > box.min.z + 0.2 && $0.z < box.max.z - 0.2 },
                                   "lot \(column): a building stands in the tank")
                }
                var far = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
                far.target = .far
                far.addFactory(base: .zero, side: side, seed: (column, 7))
                XCTAssertTrue(far.props.values.flatMap { $0 }.allSatisfy { $0.model != tank })
            }
        }
        XCTAssertGreaterThan(yards, 4)
    }

    /// The demo's station buildings have bush clumps on their plazas, the
    /// same every time.
    func testTheDemosStationPlazasHaveBushes() {
        let scene = Map3DScene(world: DemoWorld.make(in: .english))
        let bushes = Self.instances(scene, of: Map3DSceneryProp.bushClumps)
        XCTAssertFalse(bushes.isEmpty)
        XCTAssertEqual(Self.instances(Map3DScene(world: DemoWorld.make(in: .english)), of: Map3DSceneryProp.bushClumps).map(\.transform),
                       bushes.map(\.transform))
    }
}
