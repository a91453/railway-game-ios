import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 446: Taipei's three scooters close up, and the rows parked in
/// front of the shops.
final class Map3DScootersTests: XCTestCase {
    private let pack = Map3DModelPack.standard

    private func model(_ kind: Map3DStreetModel) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: kind.modelName))]
    }

    func testTheThreeScootersAreTheirRealSizes() throws {
        for (kind, height, length) in [
            (Map3DStreetModel.stepScooter, Float(1.68), Float(1.85)), (.stepScooterPair, 1.68, 1.85), (.electricScooter, 1.68, 1.85),
            (.deliveryScooter, 1.68, 1.85),
        ] {
            let shape = try model(kind)
            XCTAssertEqual(shape.minimum.z, 0, accuracy: 0.01, "\(kind) stands on the ground")
            XCTAssertEqual(shape.maximum.z, height, accuracy: 0.08, "\(kind): the rider's helmet")
            XCTAssertEqual(shape.length, length, accuracy: 0.15, "\(kind)")
            XCTAssertLessThan(shape.maximum.y - shape.minimum.y, 0.9, "\(kind): a scooter's handlebar and the rider's elbows")
            XCTAssertTrue((300...460).contains(shape.triangleCount), "\(kind): \(shape.triangleCount) triangles")
            // Its paint takes the instance's colour; its lamps glow.
            XCTAssertTrue(shape.vertices.contains { $0.color >> 24 == 0 }, "\(kind)")
            XCTAssertTrue(shape.vertices.contains { $0.layer == Map3DVertex.glowing }, "\(kind)")
        }
        // The delivery box stands higher and farther back than a top case.
        func top(behind x: Float, _ kind: Map3DStreetModel) throws -> Float {
            try model(kind).vertices.filter { $0.x < x && $0.color >> 24 != 0 }.map(\.z).max() ?? 0
        }
        XCTAssertGreaterThan(try top(behind: -0.95, .deliveryScooter), try top(behind: -0.95, .stepScooter) + 0.1)
    }

    func testFarAwayAScooterIsItsBlock() {
        XCTAssertEqual(Map3DStreetModel.stepScooter.far, .scooter)
        XCTAssertEqual(Map3DStreetModel.electricScooter.far, .scooter)
        XCTAssertEqual(Map3DStreetModel.deliveryScooter.far, .scooter)
        XCTAssertEqual(Map3DStreetModel.stepScooterPair.far, .scooterPair)
        XCTAssertEqual(Map3DStreetModel.car.far, .car)
        XCTAssertTrue([Map3DStreetModel.stepScooter, .stepScooterPair, .electricScooter, .deliveryScooter].allSatisfy(\.isScooter))
        // Three in five the step-through, a quarter the e-scooter, the rest
        // delivering; two up, the step-through.
        XCTAssertEqual(Map3DStreetLife.scooter(.scooter, pick: 0.3), .stepScooter)
        XCTAssertEqual(Map3DStreetLife.scooter(.scooter, pick: 0.7), .electricScooter)
        XCTAssertEqual(Map3DStreetLife.scooter(.scooter, pick: 0.9), .deliveryScooter)
        XCTAssertEqual(Map3DStreetLife.scooter(.scooterPair, pick: 0.9), .stepScooterPair)
        XCTAssertEqual(Map3DStreetLife.scooter(.car, pick: 0.1), .car)
    }

    func testAParkedScooterIsSmall() {
        for kind in Map3DScooter.Kind.allCases {
            var mesh = Map3DMesh()
            Map3DScooter.addParked(&mesh, kind: kind, paint: Map3DColor.rgb(0xD9473F), topCase: true)
            XCTAssertTrue((50...70).contains(mesh.triangleCount), "\(kind): \(mesh.triangleCount)")
            let bounds = try? XCTUnwrap(mesh.bounds)
            XCTAssertEqual(bounds?.min.y ?? 1, 0, accuracy: 0.01, "\(kind) on the ground")
            XCTAssertLessThan(bounds?.max.y ?? 9, 1.35, "\(kind)")
            XCTAssertEqual((bounds?.max.x ?? 0) - (bounds?.min.x ?? 0), 1.8, accuracy: 0.15, "\(kind)")
        }
    }

    func testARowLeavesTheDoorOpenAndClearsThePillars() {
        XCTAssertTrue(Map3DScooter.rowSlots(width: 3).isEmpty, "too narrow for a row and a door")
        for width: Float in [4, 4.6, 5.5, 7, 9] {
            let slots = Map3DScooter.rowSlots(width: width)
            XCTAssertFalse(slots.isEmpty, "\(width)")
            XCTAssertEqual(slots, slots.sorted())
            // Clear of the pillars (0.4 m at 0.25 m in from each end) by a
            // handlebar's half and a little.
            XCTAssertLessThanOrEqual(slots.map(abs).max() ?? 0, width / 2 - 0.85 + 1e-4)
            // The door: 1.2 m in the middle, a handlebar's half either side.
            XCTAssertGreaterThanOrEqual(slots.map(abs).min() ?? 0, 0.93 - 1e-4, "\(width)")
            // 0.78 m apart on each side.
            for side in [slots.filter { $0 < 0 }, slots.filter { $0 > 0 }] {
                for (a, b) in zip(side, side.dropFirst()) { XCTAssertEqual(b - a, Map3DScooter.rowSpacing, accuracy: 1e-4) }
            }
        }
    }

    func testARowStandsInsideTheArcadeAndIsTheSameEveryTime() {
        let front = Map3DPoint(10, 0, 20)
        let facing = Map3DPoint(0, 0, 1)
        var rows = 0, scooters = 0
        for house in 0..<200 {
            let r = { (salt: Int32) in map3DRandom(Int32(house), 7, salt: salt) }
            var mesh = Map3DMesh(), again = Map3DMesh()
            Map3DScooter.addParkedRow(&mesh, front: front, facing: facing, width: 6, r: r)
            Map3DScooter.addParkedRow(&again, front: front, facing: facing, width: 6, r: r)
            XCTAssertEqual(mesh.vertices, again.vertices)
            guard let bounds = mesh.bounds else { continue }
            rows += 1
            scooters += mesh.triangleCount
            // Under the arcade: behind its edge, short of the shop's
            // counter (0.6 m out from its back wall), within the pillars.
            XCTAssertLessThanOrEqual(bounds.max.z, front.z)
            XCTAssertGreaterThan(bounds.min.z, front.z - Map3DScene.Builder.arcadeDepth + 0.9)
            XCTAssertGreaterThan(bounds.min.x, front.x - 3 + 0.4)
            XCTAssertLessThan(bounds.max.x, front.x + 3 - 0.4)
        }
        // Half the houses have a row.
        XCTAssertEqual(Double(rows) / 200, 0.5, accuracy: 0.08)
        XCTAssertGreaterThan(scooters, 0)
    }

    func testOnlyAnArcadeHasARow() {
        var arcade = Map3DMesh(), plain = Map3DMesh()
        for house in 0..<20 {
            let r = { (salt: Int32) in map3DRandom(Int32(house), 3, salt: salt) }
            Map3DScene.Builder.addStreetLevel(&arcade, front: .zero, facing: Map3DPoint(1, 0, 0), width: 6, groundFloor: 3.6, wall: 0xFF_FFFF,
                                              shop: true, arcade: true, r: r)
            Map3DScene.Builder.addStreetLevel(&plain, front: .zero, facing: Map3DPoint(1, 0, 0), width: 6, groundFloor: 3.6, wall: 0xFF_FFFF,
                                              shop: true, arcade: false, r: r)
        }
        let tyre = Map3DScooter.parkedTyre
        XCTAssertTrue(arcade.vertices.contains { $0.color == tyre })
        XCTAssertFalse(plain.vertices.contains { $0.color == tyre })
        // Vehicles, they keep their colours in the city's look (decision
        // 370), which leaves the houses' colours pale.
        for colour in Map3DScooter.parked { XCTAssertEqual(Map3DLook.colour(colour), colour) }
    }

    // MARK: - On the streets

    private func straightRoad() throws -> Map3DStreetLife {
        let path = try XCTUnwrap(Map3DStreetLife.Path([Map3DPoint(0, 0, 0), Map3DPoint(400, 0, 0)]))
        var life = Map3DStreetLife()
        life.lanes = [Map3DStreetLife.Lane(path: path, half: 4, twoWay: true, speed: 11, perHundred: 6, scooters: true, seed: (1, 2))]
        return life
    }

    func testCloseUpTheThreeRideAndFarTheirBlocks() throws {
        let life = try straightRoad()
        let index = { (kind: Map3DStreetModel) in self.pack.index(of: kind.modelName) }
        let detailed = Set([Map3DStreetModel.stepScooter, .stepScooterPair, .electricScooter, .deliveryScooter].compactMap(index))
        let blocks = Set([Map3DStreetModel.scooter, .scooterPair].compactMap(index))
        let near = life.frame(target: Map3DPoint(200, 0, 0), distance: 150, time: 77, detail: .full, activity: .init())
        let kinds = Set(near.instances.map(\.model))
        for kind in [Map3DStreetModel.stepScooter, .electricScooter, .deliveryScooter] {
            XCTAssertTrue(kinds.contains(try XCTUnwrap(index(kind))), "\(kind)")
        }
        XCTAssertFalse(near.instances.contains { blocks.contains($0.model) }, "all within reach of the eye")
        let far = life.frame(target: Map3DPoint(200, 0, 0), distance: 600, time: 77, detail: .full, activity: .init())
        XCTAssertFalse(far.instances.contains { detailed.contains($0.model) })
        XCTAssertTrue(far.instances.contains { blocks.contains($0.model) })
        // The same moment, the same scooters.
        let again = life.frame(target: Map3DPoint(200, 0, 0), distance: 150, time: 77, detail: .full, activity: .init())
        XCTAssertEqual(again.instances.map(\.model), near.instances.map(\.model))
        XCTAssertEqual(again.instances.map(\.floats), near.instances.map(\.floats))
    }

    func testSomeScootersRideInTwos() throws {
        let life = try straightRoad()
        let frame = life.frame(target: Map3DPoint(200, 0, 0), distance: 150, time: 77, detail: .full, activity: .init())
        let scooters = Set([Map3DStreetModel.stepScooter, .stepScooterPair, .electricScooter, .deliveryScooter]
            .compactMap { pack.index(of: $0.modelName) })
        let east = frame.instances.filter { scooters.contains($0.model) && $0.transform[0] > 0.9 }.map { ($0.transform[12], $0.transform[14]) }
        // A scooter 0.7 m nearer the middle and 2.3 m behind another.
        let twos = east.filter { a in east.contains { b in abs(b.0 - a.0 - 2.3) < 0.05 && abs(b.1 - a.1 - 0.7) < 0.05 } }
        XCTAssertGreaterThan(twos.count, 0)
        // Nothing overlaps: the same side within a scooter's width, a
        // scooter's length apart.
        for (i, a) in east.enumerated() {
            for b in east[(i + 1)...] where abs(a.1 - b.1) < 0.6 {
                XCTAssertGreaterThan(abs(a.0 - b.0), 2)
            }
        }
    }

    /// Decision 446's frame cost, for the decision: run with
    /// `MOTION_BUDGET_REPORT=1`.
    func testReportTheFrameCost() throws {
        guard ProcessInfo.processInfo.environment["MOTION_BUDGET_REPORT"] == "1" else { throw XCTSkip("MOTION_BUDGET_REPORT=1 to run") }
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let scene = Map3DScene(world: world)
        let life = scene.streetLife
        let spot = try XCTUnwrap(life.spots.first { $0.kind == .platform })
        let middle = spot.path.at(spot.path.length / 2).point
        let activity = Map3DStreetLife.Activity(world: world)
        let triangles = pack.models.map(\.triangleCount)
        let scooterModels = Set(Map3DStreetModel.allCases.filter(\.isScooter).compactMap { pack.index(of: $0.modelName) })
        let detailed = Set([Map3DStreetModel.stepScooter, .stepScooterPair, .electricScooter, .deliveryScooter].compactMap { pack.index(of: $0.modelName) })
        let taipei = try Map3DFrameCostReportTests.taipeiScene()
        func bytes(_ scene: Map3DScene) -> Int {
            scene.chunks.flatMap { [$0.mesh, $0.far, $0.close, $0.standIn, $0.shadows] }
                .reduce(0) { $0 + $1.vertices.count * MemoryLayout<Map3DVertex>.stride + $1.indices.count * MemoryLayout<UInt32>.stride }
        }
        for (name, each) in [("two towns", scene), ("Taipei", taipei)] {
            print("\(name) close layer: \(each.chunks.map(\.close.triangleCount).reduce(0, +)) triangles, \(each.chunks.map(\.close.vertices.count).reduce(0, +)) vertices in \(each.chunks.count) chunks; the busiest four chunks' \(each.chunks.map(\.close.triangleCount).sorted().suffix(4).reduce(0, +)); all its meshes \(bytes(each) / 1_000_000) MB")
        }
        for distance: Float in [150, 300, 600] {
            let frame = life.frame(target: middle, distance: distance, time: 1_000, detail: .full, activity: activity)
            let start = Date()
            for step in 0..<50 { _ = life.frame(target: middle, distance: distance, time: 1_000 + Double(step) / 30, detail: .full, activity: activity) }
            let ms = Date().timeIntervalSince(start) * 1_000 / 50
            print(String(format: "%4.0f m: %d people, %d vehicles, %d scooters (%d close up), %d triangles, %.2f ms", distance, frame.people, frame.vehicles,
                         frame.instances.filter { scooterModels.contains($0.model) }.count, frame.instances.filter { detailed.contains($0.model) }.count,
                         frame.instances.map { triangles[$0.model] }.reduce(0, +), ms))
        }
    }
}
