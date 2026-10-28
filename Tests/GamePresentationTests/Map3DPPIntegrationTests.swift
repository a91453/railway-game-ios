import GameCore
import XCTest
@testable import GamePresentation

/// PP coaches have one operating contact, the push-pull set, drawn since
/// decision 425 with an E500 at each end.
final class Map3DPPIntegrationTests: XCTestCase {
    private let pack = Map3DModelPack.unbaked  // the recipes before decision 439's shade

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
                // K1-1: the static roles are the tools' pack's.
                let study = Map3DModelPack.unbakedStudies
                XCTAssertEqual(payload(study.models[try XCTUnwrap(study.index(of: standalone.name), standalone.name)]), payload(standalone))
                XCTAssertNil(Map3DTrainSet.named(standalone.name), "special roles are static assets, not new operating types")
            }
        }
    }

    /// Decision 425: an E500 at each end since the E1000 left service.
    func testAnE500IsAtBothEndsForEveryCarCount() throws {
        for key in ["pushPull", "pushPullFar"] {
            let set = try XCTUnwrap(Map3DTrainSet.named(key))
            let original = Map3DE500.model(far: key.hasSuffix("Far"))
            XCTAssertEqual(payload(try model(set.headName)), payload(original))
            XCTAssertNil(pack.index(of: set.tailName), "the last power car is the head turned around")
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
        // Decision 430: the E500CK's coaches are the Chu-Kuang coach's now
        // (Map3DChuKuangIntegrationTests); the Ming-Ri's and the Formosa
        // Star's are as they were.
        let existing: [(String, Map3DTrainSet.Coach)] = [
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
        XCTAssertEqual(TrainPack.sets, ["threeCarUrban", "fiveSectionLRT", "sevenSectionLRT", "fourCarMetro", "blueSeven", "n700sG", "pushPullE1000"])
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

    /// Decision 427: the train pack's E1000 look has an E1000 at each end of
    /// the same PP coaches, near and far; the far set has fewer triangles.
    func testTheE1000LookIsE1000AtBothEndsOfTheSamePPCoaches() throws {
        for far in [false, true] {
            let key = far ? "pushPullE1000Far" : "pushPullE1000"
            let set = try XCTUnwrap(Map3DTrainSet.named(key))
            XCTAssertTrue(set.ownLengths)
            XCTAssertEqual(set.far, far ? nil : "pushPullE1000Far")
            XCTAssertEqual(payload(try model(set.headName)), payload(Map3DE1000.model(far: far)))
            XCTAssertEqual(payload(try model(set.middleName)), payload(Map3DPPPassenger.model(.ppt1000, far: far)))
            XCTAssertNil(pack.index(of: set.tailName), "the last power car is the head turned around")
            for count in [1, 2, 3, 12] {
                for car in 0..<count {
                    let atEnd = car == 0 || car == count - 1
                    let expected = try XCTUnwrap(pack.index(of: atEnd ? set.headName : set.middleName))
                    XCTAssertEqual(pack.modelIndex(forType: key, carIndex: car, count: count), expected)
                    XCTAssertEqual(pack.isTurned(forType: key, carIndex: car, count: count), count > 1 && car == count - 1)
                }
            }
        }
        let near = try model("set-pushPullE1000-head"), far = try model("set-pushPullE1000Far-head")
        XCTAssertLessThan(far.triangleCount, near.triangleCount)
        XCTAssertLessThan(try model("set-pushPullE1000Far-car").triangleCount, try model("set-pushPullE1000-car").triangleCount)
        XCTAssertTrue(Map3DTrainSet.nearOnly.contains("pushPullE1000"))
    }

    /// Decision 427: near 500 m the E1000 look's own model, from there its far set.
    func testTheE1000LookSwitchesToItsFarSetAtTheSameDistance() throws {
        for unit in ["head", "car"] {
            let near = try XCTUnwrap(pack.index(of: "set-pushPullE1000-" + unit))
            let far = try XCTUnwrap(pack.index(of: "set-pushPullE1000Far-" + unit))
            XCTAssertEqual(pack.model(near, forType: "pushPullE1000", count: 12, at: 499), near)
            XCTAssertEqual(pack.model(near, forType: "pushPullE1000", count: 12, at: 500), far)
            XCTAssertNil(pack.model(near, forType: "pushPullE1000", count: 12, at: 900))
        }
    }
}
