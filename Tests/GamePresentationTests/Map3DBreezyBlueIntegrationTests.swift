import GameCore
import XCTest
@testable import GamePresentation

/// Decision 540: the Blue Train (`BLUE`) runs two blue R100s and #1671's
/// restored coaches, near and far, in the role order reported on
/// 2026-05-22 (`tools/tra-r100/formation.json`).
final class Map3DBreezyBlueIntegrationTests: XCTestCase {
    private let pack = Map3DModelPack.standard

    private func payload(_ model: Map3DModelPack.Model) -> [UInt32] {
        model.vertices.flatMap { v in
            [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern,
             v.nx.bitPattern, v.ny.bitPattern, v.nz.bitPattern,
             v.color, v.u.bitPattern, v.v.bitPattern, v.layer.bitPattern]
        }
    }

    private func names(_ key: String, _ count: Int) throws -> [String] {
        try XCTUnwrap(pack.layout(forType: key, count: count), key).map { pack.models[$0.model].name }
    }

    func testTheBlueTrainIsItsOwnSetNearAndFar() {
        XCTAssertEqual(Map3DTrainSet.key(type: .blueTrain, performance: .r100ChuKuang), "BLUE")
        XCTAssertEqual(Map3DTrainSet.named("BLUE")?.far, "BLUEFar")
        XCTAssertNotNil(Map3DTrainSet.named("BLUEFar"))
        XCTAssertTrue(Map3DTrainSet.nearOnly.contains("BLUE"))
        XCTAssertNil(Map3DModelPack.standard.index(of: "set-BLUE-centre"))
        XCTAssertFalse(TrainPack.sets.contains("BLUE"))
    }

    /// Six cars, the showcase's: the two locomotives as one head unit and the
    /// five coaches mixed, exhibition, long-seat, rotating-seat, mixed (the
    /// exhibition and long-seat coaches one 35TP32850 model).
    func testTheReportedFormationAtItsOwnLengths() throws {
        let laid = try XCTUnwrap(pack.layout(forType: "BLUE", count: 6))
        XCTAssertEqual(laid.map { pack.models[$0.model].name },
                       ["set-BLUE-head", "set-BLUE-car", "set-BLUE-panto", "set-BLUE-panto", "set-BLUE-fourth", "set-BLUE-tail"])
        XCTAssertEqual(laid[0].length, 2 * Map3DR100.length, accuracy: 0.02)
        for car in laid.dropFirst() { XCTAssertEqual(car.length, Map3DBreezyBlueCoaches.length, accuracy: 0.0001) }
        XCTAssertTrue(laid.allSatisfy { $0.gap == 0 })
        let unbaked = Map3DModelPack.unbaked
        for far in [false, true] {
            let key = far ? "BLUEFar" : "BLUE"
            XCTAssertTrue(try XCTUnwrap(Map3DTrainSet.named(key)).ownLengths)
            let roles: [(String, Map3DBreezyBlueCoaches.Role)] = [("car", .mixed), ("panto", .exhibition),
                                                                 ("fourth", .rotatingSeat)]
            for (unit, role) in roles {
                let model = unbaked.models[try XCTUnwrap(unbaked.index(of: "set-\(key)-\(unit)"), unit)]
                XCTAssertEqual(payload(model), payload(Map3DBreezyBlueCoaches.model(role, far: far)), "\(key) \(unit)")
            }
            // The last coach a mixed one, only its back markers lit red.
            let tail = unbaked.models[try XCTUnwrap(unbaked.index(of: "set-\(key)-tail"))]
            let mixed = Map3DBreezyBlueCoaches.model(.mixed, far: far)
            XCTAssertEqual(tail.triangleCount, mixed.triangleCount)
            let lit = tail.vertices.filter(\.glows)
            XCTAssertFalse(lit.isEmpty)
            XCTAssertTrue(lit.allSatisfy { $0.x < -9 && $0.color == Map3DPalette.lantern })
            XCTAssertEqual(tail.vertices.map(\.x), mixed.vertices.map(\.x))
        }
    }

    /// The order from the front, over again for a longer train; the last
    /// coach always a mixed one, never the locomotive turned round.
    func testOtherLengthsKeepTheOrderFromTheFront() throws {
        XCTAssertEqual(try names("BLUE", 2), ["set-BLUE-head", "set-BLUE-tail"])
        XCTAssertEqual(try names("BLUE", 3), ["set-BLUE-head", "set-BLUE-car", "set-BLUE-tail"])
        XCTAssertEqual(try names("BLUE", 9), ["set-BLUE-head", "set-BLUE-car", "set-BLUE-panto", "set-BLUE-panto", "set-BLUE-fourth",
                                              "set-BLUE-car", "set-BLUE-panto", "set-BLUE-panto", "set-BLUE-tail"])
        for count in 2...12 { XCTAssertFalse(pack.isTurned(forType: "BLUE", carIndex: count - 1, count: count)) }
    }

    /// The head unit: two R100s back to back, R122's cab end forward, R129
    /// turned round; near within 500 m, its far version to 900 m in the same
    /// box with under half the triangles.
    func testTheTwoLocomotivesAndTheirFarVersion() throws {
        let near = try XCTUnwrap(pack.index(of: "set-BLUE-head")), far = try XCTUnwrap(pack.index(of: "set-BLUEFar-head"))
        let unbaked = Map3DModelPack.unbaked
        let recipe = unbaked.models[try XCTUnwrap(unbaked.index(of: "set-BLUE-head"))]
        XCTAssertEqual(recipe.triangleCount, 2 * Map3DR100.model(livery: .breezyBlue).triangleCount)
        XCTAssertLessThanOrEqual(recipe.triangleCount, 20_000)
        XCTAssertLessThan(pack.models[far].triangleCount * 2, pack.models[near].triangleCount)
        XCTAssertEqual(pack.models[near].minimum.x, pack.models[far].minimum.x, accuracy: 0.0001)
        XCTAssertEqual(pack.models[near].maximum.x, pack.models[far].maximum.x, accuracy: 0.0001)
        XCTAssertEqual(pack.models[near].maximum.x, Map3DR100.length, accuracy: 0.01)
        XCTAssertEqual(pack.models[near].minimum.x, -Map3DR100.length, accuracy: 0.01)
        XCTAssertEqual(pack.model(near, forType: "BLUE", count: 6, at: 499), near)
        XCTAssertEqual(pack.model(near, forType: "BLUE", count: 6, at: 500), far)
        XCTAssertNil(pack.model(near, forType: "BLUE", count: 6, at: 900))
        // The recipe's lit lenses are only at the front cab end (litLenses).
        XCTAssertTrue(recipe.vertices.contains { $0.glows && $0.x > Map3DR100.length * 0.7 })
        XCTAssertFalse(recipe.vertices.contains { $0.glows && $0.x < 0 })
        // The runtime lamps: head lamps at the front, tail lamps at the back,
        // both from the R100s' own lenses.
        for at in [near, far] {
            let lights = try XCTUnwrap(pack.lights[at])
            XCTAssertFalse(lights.lamps(atFront: true).head.isEmpty)
            XCTAssertTrue(lights.lamps(atFront: true).head.allSatisfy { $0.x > Map3DR100.length * 0.7 })
            XCTAssertTrue(lights.lamps(atFront: false).tail.allSatisfy { $0.x < -Map3DR100.length * 0.7 })
        }
    }
}
