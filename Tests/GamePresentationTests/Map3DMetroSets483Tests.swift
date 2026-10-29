import XCTest
@testable import GamePresentation

/// Decision 483: #1454's Kaohsiung Siemens study and #1437's Taichung
/// Green line study run as sets of their own, near and far: the first cab
/// at the front, the second turned round at the back (Kaohsiung's T
/// between), as many cars as the real trains whatever the count, the two
/// cities' real lines drawn as them.
final class Map3DMetroSets483Tests: XCTestCase {
    private let pack = Map3DModelPack.standard

    private func cars(_ key: String, _ count: Int) throws -> [Map3DModelPack.Model] {
        try XCTUnwrap(pack.layout(forType: key, count: count), key).map { pack.models[$0.model] }
    }

    /// The same triangles in the same places (the lit lenses are recoloured).
    private func sameShape(_ car: Map3DModelPack.Model, _ unit: Map3DModelPack.Model) -> Bool {
        car.vertices.count == unit.vertices.count
            && zip(car.vertices, unit.vertices).allSatisfy { $0.x == $1.x && $0.y == $1.y && $0.z == $1.z }
    }

    func testAsManyCarsAsTheRealTrains() throws {
        for count in [1, 2, 3, 6] {
            XCTAssertEqual(try cars("kaohsiung", count).map(\.name),
                           ["set-kaohsiung-head", "set-kaohsiung-car", "set-kaohsiung-tail"], "\(count)")
            XCTAssertEqual(try cars("kaohsiungFar", count).map(\.name),
                           ["set-kaohsiungFar-head", "set-kaohsiungFar-car", "set-kaohsiungFar-tail"], "\(count)")
            XCTAssertEqual(try cars("taichungGreen", count).map(\.name), ["set-taichungGreen-head", "set-taichungGreen-tail"], "\(count)")
            XCTAssertEqual(try cars("taichungGreenFar", count).map(\.name),
                           ["set-taichungGreenFar-head", "set-taichungGreenFar-tail"], "\(count)")
        }
        let kaohsiung = try XCTUnwrap(pack.layout(forType: "kaohsiung", count: 3))
        XCTAssertTrue(kaohsiung.allSatisfy { $0.gap == 0 })
        XCTAssertEqual(kaohsiung.reduce(0) { $0 + $1.length }, 65.3, accuracy: 1)
        let taichung = try XCTUnwrap(pack.layout(forType: "taichungGreen", count: 2))
        XCTAssertEqual(taichung.reduce(0) { $0 + $1.length }, 44.3, accuracy: 1)
        XCTAssertFalse(pack.isTurned(forType: "kaohsiung", carIndex: 2, count: 3), "DM2 is its own model")
        XCTAssertFalse(pack.isTurned(forType: "taichungGreen", carIndex: 1, count: 2), "DM2 is its own model")
    }

    func testTheCarsAreTheStudiesUnits() throws {
        for far in [false, true] {
            let k = try cars(far ? "kaohsiungFar" : "kaohsiung", 3)
            XCTAssertTrue(sameShape(k[0], Map3DKaohsiung.model(.dm1, far: far)), "DM1 far \(far)")
            XCTAssertTrue(sameShape(k[1], Map3DKaohsiung.model(.t, far: far)), "T far \(far)")
            XCTAssertTrue(sameShape(k[2], Map3DKaohsiung.model(.dm2, far: far).turned), "DM2 far \(far)")
            let t = try cars(far ? "taichungGreenFar" : "taichungGreen", 2)
            XCTAssertTrue(sameShape(t[0], Map3DTaichungGreen.model(.dm1, far: far)), "green DM1 far \(far)")
            XCTAssertTrue(sameShape(t[1], Map3DTaichungGreen.model(.dm2, far: far).turned), "green DM2 far \(far)")
        }
    }

    /// Decision 449 finds each cab's lamps from its lenses: headlamps and
    /// tail lamps at the cab end, none on Kaohsiung's T.
    func testTheCabsHaveLampsAtTheirFronts() throws {
        for (key, count) in [("kaohsiung", 3), ("kaohsiungFar", 3), ("taichungGreen", 2), ("taichungGreenFar", 2)] {
            let laid = try XCTUnwrap(pack.layout(forType: key, count: count), key)
            let head = try XCTUnwrap(pack.lights[laid[0].model], key)
            XCTAssertFalse(head.front.head.isEmpty, "\(key) head lamps")
            XCTAssertFalse(head.front.tail.isEmpty, "\(key) head tail lamps")
            let tail = try XCTUnwrap(pack.lights[laid[count - 1].model], key)
            XCTAssertFalse(tail.back.head.isEmpty, "\(key) tail car's lamps at the back")
            XCTAssertFalse(tail.back.tail.isEmpty, "\(key) tail car's tail lamps at the back")
        }
    }

    func testTheNearSetsAreDrawnNearOnlyAndTheFarSetsBeyond() {
        XCTAssertEqual(Map3DTrainSet.named("kaohsiung")?.far, "kaohsiungFar")
        XCTAssertEqual(Map3DTrainSet.named("taichungGreen")?.far, "taichungGreenFar")
        XCTAssertTrue(Map3DTrainSet.nearOnly.isSuperset(of: ["kaohsiung", "taichungGreen"]))
    }
}
