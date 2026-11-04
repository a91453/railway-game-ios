import Foundation
@testable import GamePresentation
import XCTest

/// Decision 575: the Maokong Gondola's static 3D studies.
final class Map3DCableCarTests: XCTestCase {
    private func triangles(_ model: Map3DModelPack.Model) -> [[Map3DVertex]] {
        stride(from: 0, to: model.vertices.count, by: 3).map { Array(model.vertices[$0..<$0 + 3]) }
    }

    func testTheStudiesAreThirteenNamedModelsInThePack() {
        let models = Map3DCableCar.models
        XCTAssertEqual(models.count, 13)
        XCTAssertEqual(Set(models.map(\.name)).count, 13)
        for model in models {
            XCTAssertTrue(model.name.hasPrefix("cablecar-"), model.name)
            XCTAssertNotNil(Map3DModelPack.studies.index(of: model.name), model.name)
            XCTAssertNil(Map3DModelPack.standard.index(of: model.name), "studies only: \(model.name)")
            XCTAssertEqual(model.vertices.count % 3, 0)
            XCTAssertTrue(model.vertices.allSatisfy { v in
                [v.x, v.y, v.z, v.nx, v.ny, v.nz].allSatisfy { $0.isFinite } && abs(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz - 1) < 0.01
            }, model.name)
        }
    }

    func testTheModelsAreTheSameEveryTimeTheyAreMade() {
        let a = Map3DCableCar.models, b = Map3DCableCar.models
        for (x, y) in zip(a, b) { XCTAssertEqual(x.vertices, y.vertices, x.name) }
    }

    func testACabinHangsFromItsRopeAtTheOrigin() {
        for kind in Map3DCableCar.Cabin.allCases {
            let m = Map3DCableCar.model(kind)
            // The grip is on the rope (z 0), the carriage wheels just over it.
            XCTAssertEqual(m.maximum.z, 0.11, accuracy: 0.03, "\(kind)")
            // The floor is cabinDrop below, the crystal's bearers a hand lower.
            XCTAssertEqual(m.minimum.z, -Map3DCableCar.cabinDrop, accuracy: 0.1, "\(kind)")
            XCTAssertEqual(m.length, 2.3, accuracy: 0.2, "roof slab over the body")
            XCTAssertEqual(m.maximum.y - m.minimum.y, Map3DCableCar.cabinWidth + 0.1, accuracy: 0.1)
            // A hanger runs on the rope's axis from the grip to the roof.
            let hanger = m.vertices.filter { abs($0.y) < 0.08 && $0.z < -0.3 && $0.z > -1.6 }
            XCTAssertGreaterThan(hanger.count, 12, "\(kind): the arm")
            XCTAssertGreaterThan(m.triangleCount, 300)
            XCTAssertLessThan(m.triangleCount, 4_000)
        }
    }

    func testOnlyTheCrystalCabinHasAGlassFloor() {
        func glassFacingDown(_ kind: Map3DCableCar.Cabin, far: Bool) -> Int {
            let floor = -Map3DCableCar.cabinDrop
            let down = Map3DCableCar.model(kind, far: far).vertices.filter { (v: Map3DVertex) -> Bool in
                v.nz < -0.9 && v.color == Map3DColor.shaded(CableColor.glass, 0.7) && abs(v.z - (floor + 0.04)) < 0.02
            }
            return down.count / 3
        }
        for far in [false, true] {
            XCTAssertGreaterThan(glassFacingDown(.crystal, far: far), 0, "far \(far)")
            XCTAssertEqual(glassFacingDown(.standard, far: far), 0, "far \(far)")
        }
    }

    func testEveryFarVersionIsLighterAndInTheNearOnesFrame() {
        func pair(_ near: Map3DModelPack.Model, _ far: Map3DModelPack.Model) {
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount * 2 - 1, near.name)
            XCTAssertLessThanOrEqual(far.triangleCount, near.triangleCount, near.name)
            XCTAssertEqual(far.minimum.x, near.minimum.x, accuracy: 0.15, near.name)
            XCTAssertEqual(far.maximum.x, near.maximum.x, accuracy: 0.15, near.name)
            XCTAssertEqual(far.minimum.z, near.minimum.z, accuracy: 0.15, near.name)
            XCTAssertEqual(far.maximum.z, near.maximum.z, accuracy: 0.45, near.name)
        }
        for kind in Map3DCableCar.Cabin.allCases { pair(Map3DCableCar.model(kind), Map3DCableCar.model(kind, far: true)) }
        pair(Map3DCableCar.tower(), Map3DCableCar.tower(far: true))
        for kind in Map3DCableCar.Station.allCases { pair(Map3DCableCar.model(kind), Map3DCableCar.model(kind, far: true)) }
        for kind in Map3DCableCar.Cabin.allCases {
            let near = Map3DCableCar.model(kind), far = Map3DCableCar.model(kind, far: true)
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(kind): under half")
        }
    }

    func testTheTowerCarriesTwoSheaveBatteriesOverTheTwoRopes() {
        let tower = Map3DCableCar.tower()
        XCTAssertEqual(tower.minimum.z, 0, accuracy: 0.001)
        XCTAssertEqual(tower.maximum.z, Map3DCableCar.ropeHeight(ofTower: Map3DCableCar.towerHeight), accuracy: 0.05)
        // Wheels' tops (the rope's height) lie on both rope lanes, only.
        let top = Map3DCableCar.ropeHeight(ofTower: Map3DCableCar.towerHeight)
        let lanes = Set(tower.vertices.filter { $0.z > top - 0.03 }.map { ($0.y / 0.5).rounded() })
        XCTAssertTrue(lanes.allSatisfy { abs($0 * 0.5) > 2.2 && abs($0 * 0.5) < 3.1 }, "\(lanes)")
        XCTAssertTrue(lanes.contains { $0 > 0 } && lanes.contains { $0 < 0 })
        XCTAssertLessThan(tower.triangleCount, 4_000)
        let low = Map3DCableCar.tower(height: 9)
        XCTAssertEqual(low.maximum.z, Map3DCableCar.ropeHeight(ofTower: 9), accuracy: 0.05)
    }

    func testARopeHangsInAParabolaBetweenTwoPoints() {
        let a = Map3DPoint(0, 50, 0), b = Map3DPoint(120, 62, 40)
        let line = Map3DCableCar.ropePoints(from: a, to: b, sag: 2.4, segments: 12)
        XCTAssertEqual(line.count, 13)
        XCTAssertEqual((line.first! - a).length, 0, accuracy: 1e-5)
        XCTAssertEqual((line.last! - b).length, 0, accuracy: 1e-5)
        let chord = (a + b) * 0.5
        XCTAssertEqual(line[6].y, chord.y - 2.4, accuracy: 1e-4)
        XCTAssertEqual(line[6].x, chord.x, accuracy: 1e-4)
        let straight = Map3DCableCar.ropePoints(from: a, to: b, sag: 0, segments: 4)
        for (i, p) in straight.enumerated() {
            XCTAssertEqual((p - (a + (b - a) * (Float(i) / 4))).length, 0, accuracy: 1e-4)
        }
        XCTAssertEqual(Map3DCableCar.ropePoints(from: a, to: b, sag: 1, segments: 0).count, 2)
    }

    func testTheSpanIsTwoRopesWithTheSagInTheMiddle() {
        let span = Map3DCableCar.span(length: 60, sag: 1.1)
        XCTAssertEqual(span.length, 60, accuracy: 0.2)
        XCTAssertEqual(span.minimum.z, -1.1, accuracy: 0.15)
        XCTAssertEqual(span.maximum.z, 0, accuracy: 0.1)
        let ys = Set(span.vertices.map { ($0.y / 0.25).rounded() * 0.25 })
        XCTAssertTrue(ys.contains { abs($0 - 2.6) < 0.26 } && ys.contains { abs($0 + 2.6) < 0.26 })
    }

    func testTheStationsHaveRopePortalsAndTheCornerStationTurnsTheLine() {
        let through = Map3DCableCar.model(.through), terminal = Map3DCableCar.model(.terminal), corner = Map3DCableCar.model(.corner)
        // Through: symmetric about the line; a portal lets each lane's rope in.
        XCTAssertEqual(through.minimum.y, -through.maximum.y, accuracy: 0.01)
        XCTAssertEqual(through.minimum.x, -through.maximum.x, accuracy: 0.01)
        XCTAssertTrue(through.vertices.contains { abs(abs($0.x) - 11) < 0.01 && abs($0.y) < 1.4 }, "the end wall is there")
        let laneBlocked = through.vertices.contains { abs(abs($0.x) - 11) < 0.01 && abs(abs($0.y) - 2.6) < 0.5 && $0.z > 0.5 && $0.z < 4.6 }
        XCTAssertFalse(laneBlocked, "the rope's lane through the end wall is open")
        // Terminal: closed at the front wall, with the bullwheel lying in it.
        XCTAssertTrue(terminal.vertices.contains { abs($0.x - 11) < 0.01 && abs($0.y) < 0.5 && $0.z > 1 })
        XCTAssertGreaterThan(terminal.triangleCount, through.triangleCount)
        // Corner: leaves to the right (−y) by cornerAngle.
        XCTAssertLessThan(corner.minimum.y, -6)
        XCTAssertGreaterThan(corner.minimum.y, -14)
        XCTAssertGreaterThan(corner.maximum.y, 4)
        let tip = corner.vertices.filter { $0.y < -8 }
        XCTAssertFalse(tip.isEmpty)
        XCTAssertEqual(Map3DCableCar.cornerAngle, 0.4189, accuracy: 0.001)
        for m in [through, terminal, corner] {
            XCTAssertEqual(m.minimum.z, 0, accuracy: 0.001, m.name)
            XCTAssertEqual(m.maximum.z, 6.6 + 1.7, accuracy: 0.6, m.name)
            XCTAssertLessThan(m.triangleCount, 6_000, m.name)
        }
    }

    func testTheTrianglesReport() {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { return }
        for m in Map3DCableCar.models { print("cablecar", m.name, m.triangleCount, m.minimum, m.maximum) }
    }
}
