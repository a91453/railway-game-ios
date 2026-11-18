import Foundation
@testable import GameCore
import XCTest
@testable import GamePresentation

/// Decision 837: a freight train is drawn as it is loaded, and a station's
/// freight yard is seen in 3D (FREIGHT_DEEPENING F1).
final class Map3DFreightLookTests: XCTestCase {
    private var pack: Map3DModelPack { .standard }

    /// A straight line from A to B, a freight line with an 8-car train on
    /// it, and a freight yard at A.
    private func world() throws -> (world: GameWorld, train: TrainID, alpha: StationID) {
        var world = try makeWorld(width: 128_000, height: 65_536, balance: 100_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 4_096, y: 32_768))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 118_784, y: 32_768))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let alpha = try world.buildStation(named: "A", at: PlanPoint(x: 30_000, y: 33_280)).id
        try world.addTrackPlatform(alpha, on: edge, from: 20_000, to: 40_000)
        let beta = try world.buildStation(named: "B", at: PlanPoint(x: 110_592, y: 33_280)).id
        try world.addTrackPlatform(beta, on: edge, from: 106_000, to: 114_688)
        world.enableFreight()
        world.enableBuildingMaterials()
        let line = try world.createLine(named: "Goods", stops: [alpha, beta]).id
        try world.setLineFreight(line, to: true)
        let train = try world.purchaseTrain(named: "Goods 1").id
        try world.setTrainType(train, to: .emu3000)
        try world.setTrainCars(train, to: 8)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: 64_000))
        try world.assignTrain(train, to: line)
        return (world, train, alpha)
    }

    private func names(_ world: GameWorld) throws -> [String] {
        let scene = Map3DScene(world: world), motion = TrainMotion(world: world, time: 0), heights = Map3DTrains.Heights(world: world)
        let boxes = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: nil, eye: nil)
        let first = try XCTUnwrap(boxes.boxes.vertices.first?.position)
        let near = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: pack, eye: first + Map3DPoint(0, 100, 0))
        return near.instances.map { pack.models[$0.model].name }
    }

    func testTheLoadIsTheKindCarriedMost() throws {
        let station = StationID(rawValue: 1), train = TrainID(rawValue: 1)
        XCTAssertEqual(Map3DFreightLoad.of(nil), .empty)
        XCTAssertEqual(Map3DFreightLoad.of(TrainCargo(train: train, groups: [])), .empty)
        XCTAssertEqual(Map3DFreightLoad.of(TrainCargo(train: train, groups: [CargoGroup(origin: station, kind: .goods, tons: 40)])), .goods)
        XCTAssertEqual(Map3DFreightLoad.of(TrainCargo(train: train, groups: [CargoGroup(origin: station, kind: .materials, tons: 40)])), .materials)
        let mixed = TrainCargo(train: train, groups: [CargoGroup(origin: station, kind: .goods, tons: 40),
                                                      CargoGroup(origin: StationID(rawValue: 2), kind: .materials, tons: 41)])
        XCTAssertEqual(Map3DFreightLoad.of(mixed), .materials)
        let tie = TrainCargo(train: train, groups: [CargoGroup(origin: station, kind: .goods, tons: 40),
                                                    CargoGroup(origin: station, kind: .materials, tons: 40)])
        XCTAssertEqual(Map3DFreightLoad.of(tie), .goods, "goods on a tie")
    }

    func testAFreightTrainIsDrawnAsItIsLoaded() throws {
        var (world, train, alpha) = try world()
        let empty = try names(world)
        XCTAssertEqual(empty, ["set-R200CK-head"] + Array(repeating: "set-FREIGHTEMPTY-car", count: 6) + ["set-FREIGHTEMPTY-tail"],
                       "empty: the R200 and the bare flat wagons")
        world.freight?.loads = [TrainCargo(train: train, groups: [CargoGroup(origin: alpha, kind: .materials, tons: 300)])]
        XCTAssertEqual(try names(world), ["set-R200CK-head", "set-FREIGHTBULK-car", "set-FREIGHTBULK-centre", "set-FREIGHTBULK-car",
                                          "set-FREIGHTBULK-car", "set-FREIGHTBULK-centre", "set-FREIGHTBULK-car", "set-FREIGHTBULK-tail"],
                       "building materials: the hopper wagons, black and rust-doored in turn")
        world.freight?.loads = [TrainCargo(train: train, groups: [CargoGroup(origin: alpha, kind: .goods, tons: 300)])]
        XCTAssertEqual(try names(world).dropFirst().first, "set-FREIGHT-car", "goods: decision 539's containers")
    }

    func testTheWagonsShapeAndBudget() throws {
        for wagon in Map3DFreightWagons.Wagon.allCases {
            let near = Map3DFreightWagons.model(wagon), far = Map3DFreightWagons.model(wagon, far: true)
            let isHopper = Map3DFreightHopper.file(wagon) != nil
            XCTAssertEqual(near.length, isHopper ? 12.0 : 14.2, accuracy: 0.05,
                           "\(wagon) over its couplers: the hopper 12 m, the bare wagon as the container wagon")
            XCTAssertEqual(far.length, near.length, accuracy: 0.001, "\(wagon)")
            // The bare wagon's near hand brake wheel stands 0.1 m over its
            // floor; the rest as tall near and far.
            XCTAssertEqual(far.maximum.z, near.maximum.z, accuracy: wagon == .empty ? 0.11 : 0.02, "\(wagon): as tall")
            XCTAssertLessThanOrEqual(near.triangleCount, 4_100, "\(wagon)")
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(wagon): the far one under half")
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), "\(wagon): the far colours the near's")
            XCTAssertEqual(near.vertices.contains(where: \.glows), wagon == .emptyTail || wagon == .stoneTail, "\(wagon): only the tail lamp glows")
            for model in [near, far] {
                let glass = Set(model.vertices.map(\.color).filter(Map3DTrainLights.isGlass)).map { String($0, radix: 16) }
                XCTAssertEqual(glass, [], "\(wagon): no window to light at night")
                // No face marked glass either (#2417: only real glass
                // lights), so nothing but the tail lamp lights after dark.
                XCTAssertFalse(Map3DTrainMaterial.marksOwnGlass(model), "\(wagon)")
                XCTAssertNil(Map3DTrainLights.windowModel(of: model), "\(wagon): no lit windows")
                XCTAssertFalse(Map3DTrainMaterial.marked(model).vertices.contains { $0.layer == Map3DVertex.trainGlass || $0.layer == Map3DVertex.trainGlassLit },
                               "\(wagon): the pack's marking finds no glass")
            }
        }
        // A stone wagon is the studio's hopper: 2.84 m wide, its stone
        // 3.21 m over the rail, 0.27 m over its sides, lower than a
        // container wagon with a high cube on it.
        let stone = Map3DFreightWagons.model(.stone), box = Map3DContainerWagon.model(.forty)
        XCTAssertLessThan(stone.maximum.z, box.maximum.z)
        XCTAssertEqual(stone.maximum.z, 3.2127, accuracy: 0.01)
        XCTAssertEqual(stone.maximum.y - stone.minimum.y, 2.84, accuracy: 0.01)
        XCTAssertEqual(stone.minimum.z, 0, accuracy: 0.001)
        XCTAssertTrue(stone.vertices.contains { $0.color == Map3DFreightWagons.stone })
        XCTAssertTrue(Map3DFreightWagons.model(.stoneGreen).vertices.contains { $0.color == Map3DContainerWagon.rust }, "the 35B1000's doors")
        XCTAssertFalse(stone.vertices.contains { $0.color == Map3DContainerWagon.rust })
        // The tail lamp at the back end, lit.
        let tail = Map3DFreightWagons.model(.stoneTail)
        XCTAssertTrue(tail.vertices.filter(\.glows).allSatisfy { $0.x < tail.minimum.x + 0.5 && $0.color == Map3DPalette.lantern })
        XCTAssertEqual(Map3DFreightWagons.model(.empty).maximum.z, 1.12, accuracy: 0.2, "bare: no higher than its floor and its fittings")
    }

    func testAYardStandsBesideItsStationAwayFromTheBuildingAndClearOfTheTrack() throws {
        var (world, _, alpha) = try world()
        XCTAssertEqual(Map3DFreightYard.signature(of: world), [])
        XCTAssertTrue(Map3DScene(world: world).freightYards.isEmpty)
        try world.buildFreightFacility(at: alpha)
        XCTAssertEqual(Map3DFreightYard.signature(of: world), [alpha.rawValue * 2])
        let scene = Map3DScene(world: world)
        let yard = try XCTUnwrap(scene.freightYards.first)
        XCTAssertEqual(scene.freightYards.count, 1)
        XCTAssertEqual(yard.station, alpha)
        XCTAssertEqual(yard.product, .goods)
        // The track runs along +x at the station; the yard beside it,
        // facing away across the line, its back clear of the track.
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let track = Map3DPoint(Float((30_000 - scene.originX) / metre), 0, Float((32_768 - scene.originY) / metre))
        XCTAssertLessThan(abs(yard.forward.x), 0.01)
        let across = (Map3DPoint(yard.centre.x, 0, yard.centre.z) - track).dot(yard.forward)
        XCTAssertGreaterThan(across - Map3DFreightYard.depth / 2, 2.5, "its back clear of the track")
        XCTAssertLessThan(across, 40, "beside the platforms, not far off")
        // Switched to building materials: a stone yard, which tells the
        // scene to be built again.
        try world.setFreightProduct(at: alpha, to: .materials)
        XCTAssertEqual(Map3DFreightYard.signature(of: world), [alpha.rawValue * 2 + 1])
        XCTAssertEqual(Map3DScene(world: world).freightYards.first?.product, .materials)
    }

    func testTheYardsBudgetAndLook() {
        for product in CargoKind.allCases {
            let near = Map3DFreightYard.mesh(product), far = Map3DFreightYard.farMesh(product)
            XCTAssertLessThanOrEqual(near.triangleCount, 15_000, "\(product): the works kit's scene budget")
            XCTAssertLessThan(far.triangleCount * 10, near.triangleCount, "\(product): far, a few boxes")
            let bounds = try! XCTUnwrap(near.bounds)
            XCTAssertLessThanOrEqual(bounds.max.x - bounds.min.x, Map3DFreightYard.depth + 0.01, "\(product): within its paving")
            XCTAssertLessThanOrEqual(bounds.max.z - bounds.min.z, Map3DFreightYard.length + 0.01, "\(product)")
            XCTAssertLessThan(bounds.max.y, 8, "\(product): lower than the station's roofs")
        }
        // The container yard's boxes are the trains'; the stone yard's
        // heaps are the stone wagons' grey and the sand.
        XCTAssertTrue(Map3DFreightYard.mesh(.goods).vertices.contains { $0.color == Map3DContainerWagon.rust })
        XCTAssertTrue(Map3DFreightYard.mesh(.materials).vertices.contains { $0.color == Map3DFreightWagons.stone })
    }
}
