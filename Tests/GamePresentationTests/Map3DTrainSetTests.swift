import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 318: the trains that were drawn as boxes, with models built
/// from the scene kit's train recipes, one per car.
final class Map3DTrainSetTests: XCTestCase {
    private let pack = Map3DModelPack.standard

    /// Every set's cars are in the pack: a car's length and width, on the
    /// rail, up to a lowered pantograph's height, in their own colours (none
    /// takes the line's but the metro's band), lit at the right end.
    func testEverySetsCarsAreInThePack() throws {
        let lineColoured: Set = ["metroC381", "wenhu"]
        for set in Map3DTrainSet.all {
            var names = [set.headName, set.middleName]
            for name in [set.tailName, set.singleName, set.pantographName] where pack.index(of: name) != nil { names.append(name) }
            for name in names {
                let model = pack.models[try XCTUnwrap(pack.index(of: name), name)]
                XCTAssertTrue((100...3_000).contains(model.triangleCount), "\(name): \(model.triangleCount) triangles")
                // #900's 700T is 24 m, its Wenhu car 12.6 m; drawn at the
                // train's car length.
                let length: ClosedRange<Float> = set.key == "highSpeed" ? 23...25 : set.key == "wenhu" ? 12...13.5 : 17...22.5
                XCTAssertTrue(length.contains(model.length), "\(name): \(model.length) m long")
                XCTAssertTrue((2.6...3.5).contains(model.maximum.y - model.minimum.y), "\(name): \(model.maximum.y - model.minimum.y) m wide")
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.1, "\(name) stands on the rail")
                XCTAssertTrue((3.4...4.6).contains(model.maximum.z), "\(name): \(model.maximum.z) m tall")
                if lineColoured.contains(set.key) {
                    XCTAssertTrue(model.vertices.contains { $0.color >> 24 == 0 }, "\(name): the band is the line's colour")
                } else {
                    XCTAssertTrue(model.vertices.allSatisfy { $0.color >> 24 == 0xFF }, "\(name) keeps its own colours")
                }
                XCTAssertTrue(model.vertices.allSatisfy { abs(Map3DPoint($0.nx, $0.ny, $0.nz).length - 1) < 1e-3 }, name)
            }
            let middle = (pack.models[try XCTUnwrap(pack.index(of: set.headName))].minimum.x
                + pack.models[try XCTUnwrap(pack.index(of: set.headName))].maximum.x) / 2
            let head = pack.models[try XCTUnwrap(pack.index(of: set.headName))]
            XCTAssertTrue(head.vertices.contains { $0.glows && $0.x > middle + 4 }, "\(set.key): the head's lamps at the front")
            XCTAssertFalse(head.vertices.contains { $0.glows && $0.x < middle - 4 }, "\(set.key): none at its back")
            if let tail = pack.index(of: set.tailName).map({ pack.models[$0] }) {
                XCTAssertTrue(tail.vertices.contains { $0.glows && $0.x < -4 }, "\(set.key): the tail's lamps at the back")
                XCTAssertFalse(tail.vertices.contains { $0.glows && $0.x > 4 }, "\(set.key): none at its front")
            }
            if let single = pack.index(of: set.singleName).map({ pack.models[$0] }) {
                XCTAssertTrue(single.vertices.contains { $0.glows && $0.x > 4 } && single.vertices.contains { $0.glows && $0.x < -4 },
                              "\(set.key): a railcar alone has a cab at each end")
            }
        }
    }

    /// The types that were boxes now have their models; maglev, skyrail,
    /// monorail and steam still have none.
    func testTheTypesThatWereBoxes() {
        for code in ["E200CK", "E500CK", "R100CK", "R200CK", "BLUE"] {
            XCTAssertNotNil(pack.models(forType: code), code)
        }
        for code in ["MAGLEV", "SKYRAIL", "MONORAIL", "STEAM"] {
            XCTAssertNil(pack.models(forType: code), code)
        }
    }

    /// A train's key: its type's when the type has a style or a set, else
    /// its performance's set (the Chu-Kuang presets are their types'), else
    /// its type's.
    func testATrainsKey() {
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .tiltingPuyuma), "puyuma")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .tiltingTaroko), "taroko")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .dieselRailcar), "dieselExpress", "the same curves")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .r100ChuKuang), "R100CK")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .standard), "")
        XCTAssertEqual(Map3DTrainSet.key(type: .emu3000, performance: .tiltingPuyuma), "EMU3000", "the type's style first")
        XCTAssertEqual(Map3DTrainSet.key(type: .blueTrain, performance: .r100ChuKuang), "BLUE")
        XCTAssertEqual(Map3DTrainSet.key(type: .steam, performance: .steam), "STEAM")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .metroC381), "metroC381")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .metro), "metroC381", "a metro is a C381")
    }

    /// Which model each car is: a hauled set's locomotive, coaches and lit
    /// last coach; the push-pull set's power car at both ends; a railcar
    /// alone, or its two cab cars; the others' last car their head turned.
    func testEachCarsModel() throws {
        func names(_ key: String, _ count: Int) -> [String] {
            (0..<count).map { car in
                guard let index = pack.modelIndex(forType: key, carIndex: car, count: count) else { return "-" }
                return pack.models[index].name + (pack.isTurned(forType: key, carIndex: car, count: count) ? " turned" : "")
            }
        }
        XCTAssertEqual(names("R100CK", 4), ["set-R100CK-head", "set-R100CK-car", "set-R100CK-car", "set-R100CK-tail"])
        XCTAssertEqual(names("pushPull", 3), ["set-pushPull-head", "set-pushPull-car", "set-pushPull-head turned"])
        XCTAssertEqual(names("dieselExpress", 1), ["set-dieselRailcar-single"], "a DR1000 alone")
        XCTAssertEqual(names("dieselExpress", 2), ["set-dieselRailcar-head", "set-dieselRailcar-tail"])
        XCTAssertEqual(names("dieselExpress", 3), ["set-dieselExpress-head", "set-dieselExpress-car", "set-dieselExpress-tail"], "a DR3100 set")
        XCTAssertEqual(names("puyuma", 3), ["set-puyuma-head", "set-puyuma-car", "set-puyuma-tail"])
        XCTAssertEqual(names("", 3), ["commuter-cab", "commuter-car", "commuter-cab turned"])
        // As #900 has them (the author, 2026-10-21): the 700T with its two
        // pantograph cars, the EMU3000, every metro size a C381.
        XCTAssertEqual(names("HSR", 1), ["set-highSpeed-head"])
        XCTAssertEqual(names("HSR", 12), ["set-highSpeed-head", "set-highSpeed-car", "set-highSpeed-car", "set-highSpeed-panto"]
            + Array(repeating: "set-highSpeed-car", count: 4) + ["set-highSpeed-panto", "set-highSpeed-car", "set-highSpeed-car", "set-highSpeed-tail"])
        XCTAssertEqual(names("EMU3000", 3), ["set-emu3000-head", "set-emu3000-car", "set-emu3000-tail"])
        for code in ["A", "B", "C", "L", "D"] {
            XCTAssertEqual(names(code, 2), ["set-metroC381-head", "set-metroC381-tail"], code)
        }
        XCTAssertEqual(names("APM", 2), ["set-wenhu-head", "set-wenhu-tail"])
    }

    /// The 3D map asks each train of the world for its key.
    func testTheMapAsksForTheKey() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let heights = Map3DTrains.Heights(world: world)
        XCTAssertFalse(world.trains.isEmpty)
        for train in world.trains where train.position != nil {
            XCTAssertEqual(heights.type(of: train.id), Map3DTrainSet.key(type: train.type, performance: train.performance))
        }
    }

    /// The models are the same every time they are made.
    func testTheSetsAreTheSameEveryTime() {
        for set in Map3DTrainSet.all {
            XCTAssertEqual(set.models().map(\.vertices), set.models().map(\.vertices), set.key)
        }
    }
}
