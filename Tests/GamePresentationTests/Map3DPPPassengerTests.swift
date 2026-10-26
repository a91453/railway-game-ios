import XCTest
@testable import GamePresentation

final class Map3DPPPassengerTests: XCTestCase {
    func testIndependentRolesNearFarAtCommonRailDatum() {
        var payloads = Set<[Map3DVertex]>()
        for role in Map3DPPPassenger.roles {
            for far in [false, true] {
                let model = Map3DPPPassenger.model(role, far: far)
                XCTAssertEqual(model.name, "pp-" + role.rawValue + (far ? "-far" : ""))
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.00001)
                XCTAssertEqual(model.length, 20.300, accuracy: 0.0001)
                XCTAssertLessThanOrEqual(model.maximum.z, 4.0431)
                XCTAssertLessThan(model.triangleCount, far ? 4100 : 15000)
                XCTAssertGreaterThan(model.triangleCount, 1000)
                for v in model.vertices {
                    XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite)
                    XCTAssertEqual(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz, 1, accuracy: 0.0001)
                }
            }
            payloads.insert(Map3DPPPassenger.model(role).vertices)
        }
        XCTAssertEqual(payloads.count, 4, "the special roles cannot be duplicate standard-car payloads")
    }

    func testActualBodyEndShowsCurvedRoofAndSourcedWidth() {
        for far in [false, true] {
            let m = Map3DPPPassenger.model(.ppt1000, far: far)
            let roof = m.vertices.filter { abs(abs($0.x) - Map3DPPPassenger.bodyHalfLength) < 0.00001 && $0.z >= 3.2999 }
            XCTAssertEqual(roof.map { abs($0.y) }.max()!, 2.885 / 2, accuracy: 0.0001)
            XCTAssertEqual(roof.map(\.z).max()!, 3.82, accuracy: 0.0001)
            XCTAssertTrue(roof.contains { abs($0.y) > 0.6 && abs($0.y) < 1.3 && $0.z > 3.45 && $0.z < 3.80 })
            XCTAssertLessThan(roof.filter { $0.z > 3.72 }.map { abs($0.y) }.max()!, 1.0)
        }
    }

    func testEightActualTiresTouchRailAndCouplerUsesCommonDatum() {
        for far in [false, true] {
            let model = Map3DPPPassenger.model(.ppm2500, far: far)
            let tires = model.vertices.filter { $0.color == Map3DStreetModel.tyre }
            for bogie: Float in [-7.15, 7.15] {
                for dx: Float in [-1.25, 1.25] {
                    for side: Float in [-1, 1] {
                        let wheel = tires.filter { abs($0.x - bogie - dx) <= 0.431 && $0.y * side > 0.49 }
                        XCTAssertFalse(wheel.isEmpty)
                        XCTAssertEqual(wheel.map(\.z).min()!, 0, accuracy: 0.00001)
                        XCTAssertEqual(wheel.map(\.z).max()!, 0.86, accuracy: 0.00001)
                    }
                }
            }
            for end: Float in [-1, 1] {
                let tip = model.vertices.filter { abs($0.x - end * Map3DPPPassenger.couplingHalfLength) < 0.00001 }
                XCTAssertFalse(tip.isEmpty)
                XCTAssertEqual((tip.map(\.z).min()! + tip.map(\.z).max()!) / 2, Map3DPPPassenger.couplerHeight, accuracy: 0.00001)
            }
        }
    }
}
