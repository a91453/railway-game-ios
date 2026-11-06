import Foundation
@testable import GamePresentation
import XCTest

/// Decision 575: the Maokong Gondola's static 3D studies.
final class Map3DCableCarTests: XCTestCase {
    private func triangles(_ model: Map3DModelPack.Model) -> [[Map3DVertex]] {
        stride(from: 0, to: model.vertices.count, by: 3).map { Array(model.vertices[$0..<$0 + 3]) }
    }

    /// Decision 575 續 (CABLEMAP): the 13 the 3D map draws (with the
    /// rope's metre) in the game's pack, the other 7 in the studies;
    /// decision 615: and the 8 Sun Moon Lake cabins drawn too.
    func testTheModelsAreTwentyEightNamedModelsInThePacks() {
        let models = Map3DCableCar.models
        XCTAssertEqual(models.count, 28)
        XCTAssertEqual(Map3DCableCar.drawn.count, 21)
        XCTAssertEqual(Set(models.map(\.name)).count, 28)
        let drawn = Set(Map3DCableCar.drawn.map(\.name))
        for model in models {
            XCTAssertTrue(model.name.hasPrefix("cablecar-"), model.name)
            let pack = drawn.contains(model.name) ? Map3DModelPack.standard : Map3DModelPack.studies
            let other = drawn.contains(model.name) ? Map3DModelPack.studies : Map3DModelPack.standard
            XCTAssertNotNil(pack.index(of: model.name), model.name)
            XCTAssertNil(other.index(of: model.name), "one pack only: \(model.name)")
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
            XCTAssertEqual(m.maximum.z, 0.24, accuracy: 0.05, "\(kind): the opener lever over the grip")
            // The floor is cabinDrop below, the crystal's bearers a hand lower.
            XCTAssertEqual(m.minimum.z, -Map3DCableCar.cabinDrop, accuracy: 0.1, "\(kind)")
            XCTAssertEqual(m.length, Map3DCableCar.cabinLength, accuracy: 0.06)
            XCTAssertEqual(m.maximum.y - m.minimum.y, Map3DCableCar.cabinWidth, accuracy: 0.06)
            // The bent hanger swings out to the left (+y) between the roof and the grip.
            let hanger = m.vertices.filter { $0.y > 0.3 && $0.y < 0.6 && $0.z < -0.4 && $0.z > -1.0 }
            XCTAssertGreaterThan(hanger.count, 12, "\(kind): the arm")
            XCTAssertGreaterThan(m.triangleCount, 300)
            XCTAssertLessThan(m.triangleCount, 4_000)
        }
    }

    func testOnlyTheCrystalCabinHasAGlassFloor() {
        func glassFacingDown(_ kind: Map3DCableCar.Cabin, far: Bool) -> Int {
            // The 48 mm panel's underside, in the study's green.
            let down = Map3DCableCar.model(kind, far: far).vertices.filter { (v: Map3DVertex) -> Bool in
                v.nz < -0.9 && v.color == CableParts.Paint.green && abs(v.z - (CableParts.cabinFloor - 0.048)) < 0.02
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
        for kind in Map3DCableCar.Support.allCases { pair(Map3DCableCar.model(kind), Map3DCableCar.model(kind, far: true)) }
        for kind in Map3DCableCar.Cabin.allCases {
            let near = Map3DCableCar.model(kind), far = Map3DCableCar.model(kind, far: true)
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(kind): under half")
        }
    }

    func testEveryPartIsMadeOfClosedSolids() {
        for far in [false, true] {
            let parts: [(String, CableSolids)] = [
                ("standard", .cabin(crystal: false, far: far)), ("crystal", .cabin(crystal: true, far: far)),
                ("platform", .platform(far: far)), ("gate", .gate(far: far)), ("queue", .queue(far: far)),
                ("catwalk", .catwalk(far: far)), ("kiosk", .kiosk(far: far)),
            ]
            for (name, part) in parts { XCTAssertEqual(part.openSolids(), [], "\(name) far \(far)") }
        }
    }

    func testTheCabinFloorIsLevelWithThePlatformInAStation() {
        XCTAssertEqual(Map3DCableCar.stationRopeHeight + CableParts.cabinFloor, Map3DCableCar.platformHeight, accuracy: 1e-4)
        for kind in Map3DCableCar.Station.allCases {
            let m = Map3DCableCar.model(kind)
            // Platform tops (0.60) are there, the old 0.90 ones are not.
            XCTAssertGreaterThan(m.vertices.filter { abs($0.z - 0.60) < 0.001 && $0.nz > 0.9 }.count, 6, "\(kind)")
            XCTAssertEqual(m.vertices.filter { abs($0.z - 0.90) < 0.001 && $0.nz > 0.9 && abs($0.y) < 1.7 }.count, 0, "\(kind)")
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
