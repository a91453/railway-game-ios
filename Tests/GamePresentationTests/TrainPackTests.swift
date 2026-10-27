import XCTest
@testable import GamePresentation

/// Decision 338: the train pack's sets are drawn as before them until the
/// pack is unlocked, which only a test build's switch does for now.
final class TrainPackTests: XCTestCase {
    private func names(_ pack: Map3DModelPack, _ key: String, _ count: Int) -> [String] {
        (0..<count).map { car in
            guard let index = pack.modelIndex(forType: key, carIndex: car, count: count) else { return "-" }
            return pack.models[index].name + (pack.isTurned(forType: key, carIndex: car, count: count) ? " turned" : "")
        }
    }

    func testEveryPackSetIsASet() {
        for key in TrainPack.sets { XCTAssertNotNil(Map3DTrainSet.byKey[key], key) }
    }

    func testALockedPackDrawsTheTrainsAsBefore() {
        var pack = Map3DModelPack.standard
        pack.locked = TrainPack.locked(unlocked: false)
        XCTAssertEqual(names(pack, "", 3), ["commuter-cab", "commuter-car", "commuter-cab turned"])
        // Decision 338, later: the light metro stays the green tram.
        XCTAssertEqual(names(pack, "C", 3), ["set-greenTram-head", "set-greenTram-car", "set-greenTram-tail"])
        // Decision 399: four cars of it too, and the linear-motor metro the
        // C381, each 20 m a car.
        XCTAssertEqual(names(pack, "C", 4), ["set-greenTram-head", "set-greenTram-car", "set-greenTram-car", "set-greenTram-tail"])
        XCTAssertNil(pack.layout(forType: "C", count: 4))
        XCTAssertEqual(names(pack, "L", 2), ["set-metroC381-head", "set-metroC381-tail"])
        XCTAssertNil(pack.layout(forType: "L", count: 2))
        // The steam trains are outside it.
        XCTAssertNotNil(pack.layout(forType: "SUMMER", count: 3))
        // The sets outside the pack stay as they are.
        XCTAssertEqual(names(pack, "", 2), ["set-greenCommuter-head", "set-greenCommuter-tail"])
        XCTAssertEqual(names(pack, "C", 2), ["set-greenTram-head", "set-greenTram-tail"])
        XCTAssertEqual(names(pack, "dieselExpress", 1), ["set-dieselRailcar-single"])
        pack.locked = TrainPack.locked(unlocked: true)
        XCTAssertEqual(names(pack, "", 3), ["set-threeCarUrban-head", "set-threeCarUrban-car", "set-threeCarUrban-tail"])
        XCTAssertEqual(names(pack, "C", 2), ["set-fiveSectionLRT-head", "set-fiveSectionLRT-tail"])
        XCTAssertEqual(names(pack, "C", 3), ["set-sevenSectionLRT-head", "set-sevenSectionLRT-car", "set-sevenSectionLRT-tail"])
        XCTAssertEqual(names(pack, "C", 1), ["set-greenTram-single"], "one car, or five and more, stay the tram")
        XCTAssertEqual(names(pack, "C", 5), ["set-greenTram-head", "set-greenTram-car", "set-greenTram-car", "set-greenTram-car", "set-greenTram-tail"])
        // Decision 399: the four-car metro and the seven-section car.
        XCTAssertEqual(names(pack, "L", 2), ["set-fourCarMetro-head", "set-fourCarMetro-tail"])
        XCTAssertNotNil(pack.layout(forType: "C", count: 4))
    }

    func testOnlyATestBuildsSwitchUnlocksIt() {
        XCTAssertTrue(TrainPack.isUnlocked(testBuild: true, switchOn: true))
        XCTAssertFalse(TrainPack.isUnlocked(testBuild: true, switchOn: false))
        XCTAssertFalse(TrainPack.isUnlocked(testBuild: false, switchOn: true), "the App Store's build ignores the switch")
    }

    /// Decision 338 (second later): the N700S-G is in the pack; locked,
    /// every high-speed train is the 700T, near and far; unlocked, decision
    /// 408's odd-numbered trains are the N700S-G.
    func testALockedPackDrawsEveryHighSpeedTrainAsThe700T() {
        XCTAssertTrue(TrainPack.sets.contains("n700sG"))
        var pack = Map3DModelPack.standard
        pack.locked = TrainPack.locked(unlocked: false)
        for number in 1...4 {
            let key = Map3DTrainSet.variant(of: "HSR", number: number, locked: pack.locked)
            XCTAssertEqual(key, "HSR", "train \(number)")
            XCTAssertEqual(names(pack, key, 12).first, "set-highSpeed-head")
            let head = pack.modelIndex(forType: key, carIndex: 0, count: 12)!
            let far = pack.model(head, forType: key, count: 12, at: Map3DTrainSet.tramReach + 100).map { pack.models[$0].name }
            XCTAssertEqual(far, "set-highSpeedFar-head", "train \(number) from 500 m out")
        }
        pack.locked = TrainPack.locked(unlocked: true)
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1, locked: pack.locked), "n700sG")
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 2, locked: pack.locked), "HSR")
        let head = pack.modelIndex(forType: "n700sG", carIndex: 0, count: 12)!
        XCTAssertEqual(pack.models[head].name, "set-n700sG-head")
        XCTAssertEqual(pack.model(head, forType: "n700sG", count: 12, at: Map3DTrainSet.tramReach + 100).map { pack.models[$0].name },
                       "set-n700sGFar-head")
    }

    func testTheCityBusKeepsTheLock() {
        var pack = Map3DModelPack.standard
        pack.locked = TrainPack.sets
        let bus = pack.models[pack.index(of: Map3DStreetModel.allCases[0].modelName) ?? 0]
        XCTAssertEqual(pack.replacing(bus).locked, TrainPack.sets)
    }

    /// Decision 427: the E1000 look is locked until the pack is unlocked and
    /// its own switch is on.
    func testTheE1000LookNeedsThePackAndItsOwnSwitch() {
        XCTAssertTrue(TrainPack.sets.contains("pushPullE1000"))
        let lockedPack = TrainPack.locked(unlocked: false, pushPullE1000: false)
        XCTAssertEqual(lockedPack, TrainPack.sets)
        XCTAssertEqual(TrainPack.locked(unlocked: false, pushPullE1000: true), TrainPack.sets, "the switch alone does nothing")
        XCTAssertEqual(TrainPack.locked(unlocked: true, pushPullE1000: false), ["pushPullE1000"])
        XCTAssertEqual(TrainPack.locked(unlocked: true, pushPullE1000: true), [])
        XCTAssertEqual(TrainPack.locked(unlocked: true), TrainPack.locked(unlocked: true, pushPullE1000: false), "off by default")
    }

    /// Decision 427: every push-pull Tze-Chiang, odd or even, is drawn the
    /// E500 unless the pack is unlocked with the switch on; the high-speed
    /// rule is unchanged by it.
    func testThePushPullIsAnE1000OnlyWithThePackAndTheSwitch() {
        let cases: [(unlocked: Bool, switchOn: Bool, key: String)] = [
            (false, false, "pushPull"), (false, true, "pushPull"), (true, false, "pushPull"), (true, true, "pushPullE1000"),
        ]
        for (unlocked, switchOn, expected) in cases {
            let locked = TrainPack.locked(unlocked: unlocked, pushPullE1000: switchOn)
            for number in 1...4 {
                XCTAssertEqual(Map3DTrainSet.variant(of: "pushPull", number: number, locked: locked), expected,
                               "unlocked \(unlocked), switch \(switchOn), train \(number)")
            }
            // N700S-G: odd-numbered trains, only while the pack is unlocked.
            XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1, locked: locked), unlocked ? "n700sG" : "HSR")
            XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 2, locked: locked), "HSR")
            XCTAssertEqual(Map3DTrainSet.variant(of: "taroko", number: 1, locked: locked), "taroko", "other trains are not touched")
        }
    }

    /// Decision 427: with the switch off the pushPull keeps its E500 models
    /// (near and far); with it on the E1000's, from the same lookups the
    /// two drawing paths use.
    func testThePackDrawsTheE1000OrTheE500ByItsLock() {
        var pack = Map3DModelPack.standard
        for (switchOn, head) in [(false, "set-pushPull-head"), (true, "set-pushPullE1000-head")] {
            pack.locked = TrainPack.locked(unlocked: true, pushPullE1000: switchOn)
            let key = Map3DTrainSet.variant(of: "pushPull", number: 1, locked: pack.locked)
            XCTAssertEqual(names(pack, key, 3).first, head)
            let near = pack.modelIndex(forType: key, carIndex: 0, count: 12)!
            XCTAssertEqual(pack.model(near, forType: key, count: 12, at: Map3DTrainSet.tramReach + 100).map { pack.models[$0].name },
                           head.replacingOccurrences(of: "-head", with: "Far-head"))
        }
    }
}
