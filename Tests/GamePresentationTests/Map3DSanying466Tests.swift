import XCTest
@testable import GamePresentation

/// Decision 466: #1422's Sanying study runs as a set of its own, near and
/// far: cab A at the front, cab B turned round at the back, two cars
/// whatever the train's count, the Sanying line's real trains drawn as it.
final class Map3DSanying466Tests: XCTestCase {
    private var pack: Map3DModelPack { .standard }

    private func cars(_ key: String, _ count: Int) throws -> [Map3DModelPack.Model] {
        try XCTUnwrap(pack.layout(forType: key, count: count), key).map { pack.models[$0.model] }
    }

    /// The same triangles in the same places (the lit lenses are recoloured).
    private func sameShape(_ car: Map3DModelPack.Model, _ unit: Map3DModelPack.Model) -> Bool {
        car.vertices.count == unit.vertices.count
            && zip(car.vertices, unit.vertices).allSatisfy { $0.x == $1.x && $0.y == $1.y && $0.z == $1.z }
    }

    func testTwoCarsWhateverTheCount() throws {
        for count in [1, 2, 3, 6] {
            XCTAssertEqual(try cars("sanying", count).map(\.name), ["set-sanying-head", "set-sanying-tail"], "\(count)")
            XCTAssertEqual(try cars("sanyingFar", count).map(\.name), ["set-sanyingFar-head", "set-sanyingFar-tail"], "\(count)")
        }
        let laid = try XCTUnwrap(pack.layout(forType: "sanying", count: 2))
        XCTAssertTrue(laid.allSatisfy { $0.gap == 0 })
        XCTAssertEqual(laid.reduce(0) { $0 + $1.length }, 35.4, accuracy: 0.6)
        XCTAssertEqual(pack.models(forType: "sanying")?.middle, pack.models(forType: "sanying")?.head, "no middle car")
        XCTAssertFalse(pack.isTurned(forType: "sanying", carIndex: 1, count: 2), "cab B is its own model")
    }

    func testTheCarsAreTheStudysUnits() throws {
        for far in [false, true] {
            let laid = try cars(far ? "sanyingFar" : "sanying", 2)
            XCTAssertTrue(sameShape(laid[0], Map3DSanying.model(.a, far: far)), "A far \(far)")
            XCTAssertTrue(sameShape(laid[1], Map3DSanying.model(.b, far: far).turned), "B far \(far)")
        }
    }

    func testTheLampsAreLitAtTheTrainsEnds() throws {
        func lit(_ car: Map3DModelPack.Model) -> [Map3DVertex] { car.vertices.filter { $0.layer == Map3DVertex.glowing } }
        let unbaked = Map3DModelPack.unbaked
        for key in ["sanying", "sanyingFar"] {
            let laid = try XCTUnwrap(unbaked.layout(forType: key, count: 2), key).map { unbaked.models[$0.model] }
            XCTAssertFalse(lit(laid[0]).isEmpty, key)
            XCTAssertTrue(lit(laid[0]).allSatisfy { $0.x > 4 && $0.color == Map3DTrainStyle.headlamp }, "\(key) head")
            XCTAssertFalse(lit(laid[1]).isEmpty, key)
            XCTAssertTrue(lit(laid[1]).allSatisfy { $0.x < -4 && $0.color == Map3DPalette.lantern }, "\(key) tail")
        }
    }

    func testTheNearSetIsDrawnNearOnlyAndTheFarSetBeyond() {
        XCTAssertEqual(Map3DTrainSet.named("sanying")?.far, "sanyingFar")
        XCTAssertTrue(Map3DTrainSet.nearOnly.contains("sanying"))
        XCTAssertEqual(Map3DTrainSet.sanyingKey, "sanying")
    }
}
