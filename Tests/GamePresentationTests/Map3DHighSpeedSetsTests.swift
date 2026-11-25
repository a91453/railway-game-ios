import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 408: the high-speed trains two sets, #1201's 700T and the
/// N700S-G (decision 979: the owner's old N700S in its place,
/// `Map3DN700STests`), each car its own length; #900's light 700T drawn
/// past the 700T's reach; #1201's E200 the Chu-Kuang's locomotive.
final class Map3DHighSpeedSetsTests: XCTestCase {
    private var pack: Map3DModelPack { .unbaked }  // the recipes before decision 439's shade

    private func model(_ name: String) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: name), name)]
    }

    private func layout(_ key: String, _ count: Int) throws -> [(String, Float, Float)] {
        try XCTUnwrap(pack.layout(forType: key, count: count), key).map { (pack.models[$0.model].name, $0.length, $0.gap) }
    }

    /// The 700T: #1201's cab, middle, pantograph and tail cars, twelve at
    /// their own lengths, the pantographs on the fourth and ninth.
    func testThe700TIsTheRefreshedModel() throws {
        let cars = try layout("HSR", 12)
        XCTAssertEqual(cars.map(\.0), ["set-highSpeed-head", "set-highSpeed-car", "set-highSpeed-car", "set-highSpeed-panto"]
            + Array(repeating: "set-highSpeed-car", count: 4) + ["set-highSpeed-panto", "set-highSpeed-car", "set-highSpeed-car", "set-highSpeed-tail"])
        for (name, refresh) in [("head", "refresh-700t-cab"), ("car", "refresh-700t-middle"), ("panto", "refresh-700t-panto"), ("tail", "refresh-700t-tail")] {
            let car = try model("set-highSpeed-" + name), source = Map3DTrainShapeRefresh.model(refresh)
            XCTAssertEqual(car.triangleCount, source.triangleCount, "\(name): #1201's shape as it is")
            XCTAssertEqual(car.length, source.length, accuracy: 1e-4, name)
            XCTAssertEqual(cars.first { $0.0 == "set-highSpeed-" + name }?.1 ?? 0, source.length, accuracy: 1e-3, "\(name): its own length")
        }
        XCTAssertEqual(cars.reduce(0) { $0 + $1.1 }, 305.3, accuracy: 0.5)
        // Lit white at the head's nose, red at the tail's.
        let head = try model("set-highSpeed-head").vertices.filter(\.glows), tail = try model("set-highSpeed-tail").vertices.filter(\.glows)
        XCTAssertFalse(head.isEmpty)
        XCTAssertTrue(head.allSatisfy { $0.color == Map3DTrainStyle.headlamp && $0.x > 0 })
        XCTAssertFalse(tail.isEmpty)
        XCTAssertTrue(tail.allSatisfy { $0.color == Map3DPalette.lantern && $0.x < 0 })
        XCTAssertFalse(try model("set-highSpeed-car").vertices.contains(where: \.glows), "no lamps between")
    }

    /// Half the high-speed trains, the odd-numbered, are the N700S; a
    /// real train by its run's number; other types as they were.
    func testWhichTrainsAreTheN700S() {
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1), "n700s")
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 2), "HSR")
        XCTAssertEqual(Map3DTrainSet.variant(of: "highSpeed", number: 7), "n700s")
        XCTAssertEqual(Map3DTrainSet.variant(of: "EMU3000", number: 1), "EMU3000")
        XCTAssertEqual(Map3DTrainSet.variant(of: "", number: 3), "")
        XCTAssertEqual(Map3DTrainSet.number(ofRealTrain: "thsr-12"), 12)
        XCTAssertEqual(Map3DTrainSet.number(ofRealTrain: "thsr7"), 7)
        XCTAssertEqual(Map3DTrainSet.number(ofRealTrain: "thsr"), 0)
        XCTAssertNotNil(pack.models(forType: "n700s"))
    }

    /// Within 500 m the 700T, on to 900 m its light cars (decision 422) car for car,
    /// beyond that a box.
    func testThe700TFarSet() throws {
        XCTAssertEqual(Map3DTrainSet.reach(of: "HSR"), Map3DTrainSet.tramReach)
        for name in ["head", "car", "panto", "tail"] {
            let near = try XCTUnwrap(pack.index(of: "set-highSpeed-" + name))
            XCTAssertEqual(pack.model(near, forType: "HSR", count: 12, at: 100), near, name)
            XCTAssertEqual(pack.model(near, forType: "HSR", count: 12, at: 700), pack.index(of: "set-highSpeedFar-" + name), name)
            XCTAssertNil(pack.model(near, forType: "HSR", count: 12, at: 1_000), name)
        }
        let far = try model("set-highSpeedFar-car"), near = try model("set-highSpeed-car")
        XCTAssertLessThan(far.triangleCount * 5, near.triangleCount, "a fifth of the triangles")
        // A whole 700T is over eight times the light one's triangles (decision 422).
        let cars = try XCTUnwrap(pack.layout(forType: "HSR", count: 12))
        let whole = cars.reduce(0) { $0 + pack.models[$1.model].triangleCount }
        let light = try cars.reduce(0) { $0 + pack.models[try XCTUnwrap(pack.farModel(of: $1.model, forType: "HSR", count: 12))].triangleCount }
        XCTAssertGreaterThan(whole, 8 * light)
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
