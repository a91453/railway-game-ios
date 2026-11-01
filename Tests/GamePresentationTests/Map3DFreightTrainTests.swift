import Foundation
@testable import GameCore
import XCTest
@testable import GamePresentation

/// Decision 539: a freight line's train is drawn as the R200 and container
/// wagons whatever its type, blows the diesel's horn, and the R200
/// Chu-Kuang is no longer offered to a new train while a save's trains of
/// it keep it.
final class Map3DFreightTrainTests: XCTestCase {
    private var pack: Map3DModelPack { .standard }

    /// A straight line from A to B with a `cars`-car train of `type` on it,
    /// a freight line when `freight`.
    private func world(freight: Bool, type: TrainType? = .emu3000, cars: Int = 8) throws -> (GameWorld, TrainID) {
        var world = try makeWorld(width: 128_000, height: 65_536, balance: 100_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 4_096, y: 32_768))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 118_784, y: 32_768))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let alpha = try world.buildStation(named: "A", at: PlanPoint(x: 8_192, y: 33_280)).id
        try world.addTrackPlatform(alpha, on: edge, from: 0, to: 8_192)
        let beta = try world.buildStation(named: "B", at: PlanPoint(x: 110_592, y: 33_280)).id
        try world.addTrackPlatform(beta, on: edge, from: 106_000, to: 114_688)
        world.enableFreight()
        let line = try world.createLine(named: "Goods", stops: [alpha, beta]).id
        if freight { try world.setLineFreight(line, to: true) }
        let train = try world.purchaseTrain(named: "Goods 1").id
        try world.setTrainType(train, to: type)
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: 64_000))
        try world.assignTrain(train, to: line)
        return (world, train)
    }

    private func frame(_ world: GameWorld, eyeAbove height: Float) throws -> Map3DTrains.Frame {
        let scene = Map3DScene(world: world), motion = TrainMotion(world: world, time: 0), heights = Map3DTrains.Heights(world: world)
        let boxes = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: nil, eye: nil)
        let first = try XCTUnwrap(boxes.boxes.vertices.first?.position)
        return Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: pack, eye: first + Map3DPoint(0, height, 0))
    }

    func testAFreightTrainIsTheR200AndItsWagonsNearAndFar() throws {
        let (world, _) = try world(freight: true)
        XCTAssertTrue(world.isFreightTrain(world.trains[0].id))
        let near = try frame(world, eyeAbove: 100)
        let names = near.instances.map { pack.models[$0.model].name }
        XCTAssertEqual(names, ["set-R200CK-head", "set-FREIGHT-car", "set-FREIGHT-fourth", "set-FREIGHT-centre",
                               "set-FREIGHT-centre", "set-FREIGHT-fourth", "set-FREIGHT-car", "set-FREIGHT-tail"],
                       "the R200, the wagons' loads cycling from each end, the last wagon the tail")
        XCTAssertTrue(near.boxes.isEmpty)
        let far = try frame(world, eyeAbove: 700)
        XCTAssertEqual(far.instances.map { pack.models[$0.model].name },
                       ["set-R200CKFar-head"] + names.dropFirst().map { $0.replacingOccurrences(of: "FREIGHT", with: "FREIGHTFar") })
    }

    func testAPassengerLineKeepsItsOwnTrain() throws {
        let (world, _) = try world(freight: false, cars: 12)
        let near = try frame(world, eyeAbove: 100)
        XCTAssertTrue(near.instances.allSatisfy { pack.models[$0.model].name.hasPrefix("set-emu3000-") })
    }

    func testTheWagonsShapeAndBudget() throws {
        for load in Map3DContainerWagon.Load.allCases {
            let near = Map3DContainerWagon.model(load), far = Map3DContainerWagon.model(load, far: true)
            XCTAssertEqual(near.length, 14.2, accuracy: 0.05, "\(load) over its couplers")
            XCTAssertEqual(far.length, near.length, accuracy: 0.001, "\(load): the far wagon in the same frame")
            XCTAssertEqual(far.maximum.z, near.maximum.z, accuracy: 0.02, "\(load): as tall")
            XCTAssertEqual(near.maximum.z, 1.12 + 2.591 + 0.015, accuracy: 0.01, "\(load): an ISO container on a 1.12 m floor")
            XCTAssertLessThanOrEqual(near.triangleCount, 4_100, "\(load)")
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(load): the far one under half")
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), "\(load): the far colours the near's")
            XCTAssertEqual(near.vertices.contains(where: \.glows), load == .tail, "\(load): only the tail lamp glows")
            for model in [near, far] {
                let glass = Set(model.vertices.map(\.color).filter(Map3DTrainLights.isGlass)).map { String($0, radix: 16) }
                XCTAssertEqual(glass, [], "\(load): no window to light at night, no colour of the trains' glass")
            }
        }
    }

    func testAFreightTrainBlowsTheDieselHorn() throws {
        let (freight, train) = try world(freight: true)
        let car = try XCTUnwrap(freight.train(id: train))
        XCTAssertEqual(TrainHorn.of(car), .electric, "an EMU3000 by its type")
        XCTAssertEqual(TrainHorn.of(car, in: freight), .diesel, "behind an R200 on a freight line")
        let (passenger, other) = try world(freight: false)
        XCTAssertEqual(TrainHorn.of(try XCTUnwrap(passenger.train(id: other)), in: passenger), .electric)
    }

    func testTheR200ChuKuangIsNoLongerOfferedButAnOldOneKeepsIt() async throws {
        let (world, train) = try world(freight: false, type: .r200ChuKuang)
        XCTAssertTrue(TrainType.offered.contains(.r200ChuKuang), "GameCore keeps the type")
        XCTAssertFalse(world.offeredTrainTypes.contains(.r200ChuKuang))
        XCTAssertFalse(RollingStockCatalog(world: world).entries.contains { $0.type == .r200ChuKuang })
        XCTAssertTrue(world.offeredTrainTypes.contains(.r100ChuKuang), "the R100 Chu-Kuang is still sold")
        // A save's R200 Chu-Kuang loads as it was and is drawn as before.
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertEqual(loaded.train(id: train)?.type, .r200ChuKuang)
        let near = try frame(loaded, eyeAbove: 100)
        XCTAssertEqual(near.instances.first.map { pack.models[$0.model].name }, "set-R200CK-head")
        await MainActor.run {
            let session = GameSession(world: loaded)
            let choices = session.trainTypeMenuChoices(for: train).map(\.id)
            XCTAssertEqual(choices.last, .r200ChuKuang, "its own type, listed last")
            XCTAssertEqual(choices.filter { $0 == .r200ChuKuang }.count, 1)
            XCTAssertFalse(session.trainTypeCardChoices.contains { $0.id == .r200ChuKuang })
        }
    }
}
