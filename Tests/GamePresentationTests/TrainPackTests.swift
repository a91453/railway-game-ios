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

    func testTheCityBusKeepsTheLock() {
        var pack = Map3DModelPack.standard
        pack.locked = TrainPack.sets
        let bus = pack.models[pack.index(of: Map3DStreetModel.allCases[0].modelName) ?? 0]
        XCTAssertEqual(pack.replacing(bus).locked, TrainPack.sets)
    }
}
