import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 408: the high-speed trains two sets, the 700T (decision 988:
/// the owner's old 700 series cars in the place of #1201's recipe and its
/// light far cars, `Map3DTHSR700TTests`) and the N700S-G (decision 979:
/// the owner's old N700S in its place, `Map3DN700STests`), each car its
/// own length; #1201's E200 the Chu-Kuang's locomotive.
final class Map3DHighSpeedSetsTests: XCTestCase {
    private var pack: Map3DModelPack { .unbaked }  // the recipes before decision 439's shade

    private func model(_ name: String) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: name), name)]
    }

    private func layout(_ key: String, _ count: Int) throws -> [(String, Float, Float)] {
        try XCTUnwrap(pack.layout(forType: key, count: count), key).map { (pack.models[$0.model].name, $0.length, $0.gap) }
    }

    /// The 700T: the owner's old cars (``Map3DTHSR700T``), twelve at
    /// their own lengths, the pantographs on the fourth and ninth, the
    /// back half turned round.
    func testThe700TIsTheOwnersOldCars() throws {
        let cars = try layout("HSR", 12)
        XCTAssertEqual(cars.map(\.0), ["head", "car", "car", "panto", "car", "car", "carBack", "carBack", "pantoBack", "carBack", "carBack", "tail"]
            .map { "set-highSpeed-" + $0 })
        for (name, unit) in [("head", Map3DTHSR700T.Unit.cab), ("car", .middle), ("panto", .pantograph), ("tail", .cab), ("carBack", .middle), ("pantoBack", .pantograph)] {
            let car = try model("set-highSpeed-" + name), source = try XCTUnwrap(Map3DTHSR700T.model(unit))
            XCTAssertEqual(car.triangleCount, source.triangleCount, "\(name): the old car as the tool cut it")
            XCTAssertEqual(car.length, Map3DTHSR700T.length(unit), accuracy: 0.01, name)
            XCTAssertEqual(cars.first { $0.0 == "set-highSpeed-" + name }?.1 ?? 0, Map3DTHSR700T.length(unit), accuracy: 0.01, "\(name): its own length")
        }
        XCTAssertEqual(cars.reduce(0) { $0 + $1.1 }, 304, accuracy: 0.1)
        // Lit white at the head's nose, red at the tail's.
        let head = try model("set-highSpeed-head").vertices.filter(\.glows), tail = try model("set-highSpeed-tail").vertices.filter(\.glows)
        XCTAssertFalse(head.isEmpty)
        XCTAssertTrue(head.allSatisfy { $0.color == Map3DTrainStyle.headlamp && $0.x > 0 })
        XCTAssertFalse(tail.isEmpty)
        XCTAssertTrue(tail.allSatisfy { $0.color == Map3DPalette.lantern && $0.x < 0 })
        XCTAssertFalse(try model("set-highSpeed-car").vertices.contains(where: \.glows), "no lamps between")
    }

    /// Half the high-speed trains, the odd-numbered, are the N700S; other
    /// types as they were. TAP-FREEZE-151: the Taiwan High Speed Rail's
    /// own trains (the 700T's key) are all 700Ts, odd-numbered too.
    func testWhichTrainsAreTheN700S() {
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1), "n700s")
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 2), "HSR")
        XCTAssertEqual(Map3DTrainSet.variant(of: "highSpeed", number: 7), "highSpeed")
        XCTAssertEqual(Map3DRealTrains.variantKey(system: "thsr", key: Map3DRealTrains.formation(system: "thsr", id: "THSR", name: "台灣高鐵").key, number: 7), Map3DTHSR700T.key)
        XCTAssertEqual(RealLineStock.setKey(ofRealLine: "thsr:HSR").map { Map3DTrainSet.variant(of: $0, number: 7) }, Map3DTHSR700T.key)
        XCTAssertEqual(Map3DTrainSet.variant(of: "EMU3000", number: 1), "EMU3000")
        XCTAssertEqual(Map3DTrainSet.variant(of: "", number: 3), "")
        XCTAssertEqual(Map3DTrainSet.number(ofRealTrain: "thsr-12"), 12)
        XCTAssertEqual(Map3DTrainSet.number(ofRealTrain: "thsr7"), 7)
        XCTAssertEqual(Map3DTrainSet.number(ofRealTrain: "thsr"), 0)
        XCTAssertNotNil(pack.models(forType: "n700s"))
    }

    /// Decision 988: a 700T car is under two thousand triangles, so it is
    /// drawn as itself as far as any train's model (the light far cars of
    /// decision 422 are gone), beyond that a box.
    func testThe700THasNoFarSet() throws {
        XCTAssertEqual(Map3DTrainSet.reach(of: "HSR"), Map3DTrains.modelReach)
        XCTAssertNil(pack.index(of: "set-highSpeedFar-head"))
        for name in ["head", "car", "panto", "tail"] {
            let near = try XCTUnwrap(pack.index(of: "set-highSpeed-" + name))
            XCTAssertEqual(pack.model(near, forType: "HSR", count: 12, at: 100), near, name)
            XCTAssertEqual(pack.model(near, forType: "HSR", count: 12, at: 700), near, name)
            XCTAssertNil(pack.model(near, forType: "HSR", count: 12, at: Map3DTrains.modelReach + 100), name)
        }
    }

    /// #1201's E200 heads the Chu-Kuang, its lamps lit at the front.
    func testTheE200IsTheRefreshedModel() throws {
        let head = try model("set-E200CK-head")
        XCTAssertEqual(head.triangleCount, Map3DTrainShapeRefresh.model("refresh-e200").triangleCount)
        let lamps = head.vertices.filter(\.glows)
        XCTAssertFalse(lamps.isEmpty)
        XCTAssertTrue(lamps.allSatisfy { $0.color == Map3DTrainStyle.headlamp && $0.x > 0 })
        XCTAssertEqual(try XCTUnwrap(pack.modelIndex(forType: "E200CK", carIndex: 0, count: 4)), pack.index(of: "set-E200CK-head"))
    }

    /// Decision 825: the E200 drawn from photographs, orange below and
    /// ivory above, with a light version of its own from 500 m out
    /// (before it the far set drew the whole near locomotive).
    func testTheE200IsOrangeAndIvoryWithItsOwnFarVersion() throws {
        let near = Map3DTrainShapeRefresh.model("refresh-e200")
        let far = Map3DTrainShapeRefresh.model("refresh-e200", far: true)
        XCTAssertEqual(far.name, "refresh-e200-far")
        XCTAssertLessThan(far.triangleCount * 2, near.triangleCount)
        for model in [near, far] {
            let colours = Set(model.vertices.map(\.color))
            XCTAssertTrue(colours.contains(Map3DTrainShapeRefresh.e200Orange), model.name)
            XCTAssertTrue(colours.contains(Map3DTrainShapeRefresh.e200Ivory), model.name)
            XCTAssertTrue(colours.contains(Map3DG12.hazard), model.name)
        }
        let nearHead = try model("set-E200CK-head"), farHead = try model("set-E200CKFar-head")
        XCTAssertEqual(farHead.triangleCount, far.triangleCount)
        XCTAssertFalse(farHead.vertices.filter(\.glows).isEmpty)
        // The far version keeps the near one's box (tools/train-models/check.mjs).
        let top = { (m: Map3DModelPack.Model) in m.vertices.map(\.z).max() ?? 0 }
        let length = { (m: Map3DModelPack.Model) in m.vertices.map(\.x).max() ?? 0 }
        XCTAssertEqual(top(farHead), top(nearHead), accuracy: 0.05)
        XCTAssertEqual(length(farHead), length(nearHead), accuracy: 0.1)
        let index = try XCTUnwrap(pack.modelIndex(forType: "E200CK", carIndex: 0, count: 4))
        XCTAssertEqual(pack.model(index, forType: "E200CK", count: 4, at: 700), pack.index(of: "set-E200CKFar-head"))
    }
}
