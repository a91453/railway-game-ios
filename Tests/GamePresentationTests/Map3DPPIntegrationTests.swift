import GameCore
import XCTest
@testable import GamePresentation

/// PP coaches have one existing operating contact, the E1000 push-pull
/// set. The independently exported E500 display does not change that set.
final class Map3DPPIntegrationTests: XCTestCase {
    private let pack = Map3DModelPack.standard

    private func model(_ name: String) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: name), name)]
    }

    /// Compare every vertex field, including normals, colour and material;
    /// bounds alone cannot protect the accepted locomotive's geometry.
    private func payload(_ model: Map3DModelPack.Model) -> [UInt32] {
        model.vertices.flatMap { v in
            [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern,
             v.nx.bitPattern, v.ny.bitPattern, v.nz.bitPattern, v.color,
             v.u.bitPattern, v.v.bitPattern, v.layer.bitPattern]
        }
    }

    func testOnlyTheStandardPPTIsTheOperatingMiddleRole() throws {
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .pushPull), "pushPull")
        for far in [false, true] {
            let key = far ? "pushPullFar" : "pushPull"
            let set = try XCTUnwrap(Map3DTrainSet.named(key))
            XCTAssertTrue(set.ownLengths)
            XCTAssertNil(set.fixedCars, "keep the game's existing variable car count")
            XCTAssertEqual(set.far, far ? nil : "pushPullFar")
            XCTAssertEqual(payload(try model(set.middleName)), payload(Map3DPPPassenger.model(.ppt1000, far: far)))
            for role in Map3DPPPassenger.roles {
                let standalone = Map3DPPPassenger.model(role, far: far)
                XCTAssertEqual(payload(try model(standalone.name)), payload(standalone))
                XCTAssertNil(Map3DTrainSet.named(standalone.name), "special roles are static assets, not new operating types")
            }
        }
    }

    func testTheOriginalE1000RemainsAtBothEndsForEveryCarCount() throws {
        let original = Map3DTrainLocomotive.e1000.model
        XCTAssertLessThanOrEqual(original.triangleCount, 4_100, "reuse the original power car in the far set too")
        for key in ["pushPull", "pushPullFar"] {
            let set = try XCTUnwrap(Map3DTrainSet.named(key))
            XCTAssertEqual(payload(try model(set.headName)), payload(original))
            XCTAssertNil(pack.index(of: set.tailName), "the existing last power car is the head turned around")
            for count in [1, 2, 3, 12] {
                let layout = try XCTUnwrap(pack.layout(forType: key, count: count))
                XCTAssertEqual(layout.count, count)
                for car in 0..<count {
                    let atEnd = car == 0 || car == count - 1
                    let expected = try XCTUnwrap(pack.index(of: atEnd ? set.headName : set.middleName))
                    XCTAssertEqual(pack.modelIndex(forType: key, carIndex: car, count: count), expected)
                    XCTAssertEqual(layout[car].model, expected)
                    XCTAssertEqual(layout[car].length, pack.models[expected].length)
                    XCTAssertEqual(pack.isTurned(forType: key, carIndex: car, count: count), count > 1 && car == count - 1)
                }
            }
        }
    }

    func testNearFarAndExistingBoxFallbackSelectTheSameRoles() throws {
        for unit in ["head", "car"] {
            let near = try XCTUnwrap(pack.index(of: "set-pushPull-" + unit))
            let far = try XCTUnwrap(pack.index(of: "set-pushPullFar-" + unit))
            XCTAssertEqual(pack.model(near, forType: "pushPull", count: 12, at: 499), near)
            XCTAssertEqual(pack.model(near, forType: "pushPull", count: 12, at: 500), far)
            XCTAssertEqual(pack.model(near, forType: "pushPull", count: 12, at: 899), far)
            XCTAssertNil(pack.model(near, forType: "pushPull", count: 12, at: 900))
            let a = pack.models[near], b = pack.models[far]
            XCTAssertEqual(a.minimum, b.minimum)
            XCTAssertEqual(a.maximum, b.maximum)
        }
    }

    func testExistingE500ServicesKeepTheirOriginalCoachesAndLocomotive() throws {
        // This reconstructs their existing, separately sourced coach recipes;
        // neither these coaches nor any E500 part is substituted with PP.
        let existing: [(String, Map3DTrainSet.Coach)] = [
            ("E500CK", Map3DTrainSet.coach(TrainLivery.e200ChuKuang)),
            ("MINGRI", Map3DTrainSet.coach(TrainLivery.mingRi, band: 0.38...0.43)),
            ("STAR", Map3DTrainSet.coach(TrainLivery.formosaStar, band: 0.38...0.43)),
        ]
        for (key, coach) in existing {
            for far in [false, true] {
                let old = Map3DTrainSet.e500Hauled(key, far: far, coach: coach)
                for expected in old.models() {
                    XCTAssertEqual(payload(try model(expected.name)), payload(expected), expected.name)
                }
                XCTAssertEqual(payload(old.build().head), payload(Map3DE500.model(far: far)))
            }
        }
    }

    func testTrainPackAndFallbackRulesRemainIndependentOfThePPDisplayAssets() throws {
        XCTAssertEqual(TrainPack.sets, ["threeCarUrban", "fiveSectionLRT", "sevenSectionLRT", "fourCarMetro", "blueSeven", "n700sG"])
        var locked = pack
        locked.locked = TrainPack.locked(unlocked: false)
        for count in [3, 12] {
            for car in 0..<count {
                XCTAssertEqual(locked.modelIndex(forType: "pushPull", carIndex: car, count: count),
                               pack.modelIndex(forType: "pushPull", carIndex: car, count: count))
            }
        }
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1, locked: locked.locked), "HSR")
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1), "n700sG")
        XCTAssertNil(pack.models(forType: "pp-e500-display"))
    }
}
