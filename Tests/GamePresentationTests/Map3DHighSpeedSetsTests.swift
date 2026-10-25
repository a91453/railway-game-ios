import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 408: the high-speed trains two sets, #1201's 700T and the
/// N700S-G (the author's mesh), each car its own length; #900's light 700T drawn past the
/// 700T's reach; #1201's E200 the Chu-Kuang's locomotive.
final class Map3DHighSpeedSetsTests: XCTestCase {
    private let pack = Map3DModelPack.standard

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

    /// The N700S-G: the author's own mesh with fewer triangles, its cab
    /// at both ends (turned round at the back), its D car under the
    /// pantographs on the fourth and ninth, each car its own length, lit
    /// white at the head and red at the tail.
    func testTheN700SGIsTheAuthorsMesh() throws {
        let cars = try layout("n700sG", 12)
        XCTAssertEqual(cars.map(\.0), ["set-n700sG-head", "set-n700sG-car", "set-n700sG-car", "set-n700sG-panto"]
            + Array(repeating: "set-n700sG-car", count: 4) + ["set-n700sG-panto", "set-n700sG-car", "set-n700sG-car", "set-n700sG-tail"])
        XCTAssertTrue(cars.allSatisfy { $0.2 == 0 })
        for (name, unit) in [("head", Map3DN700SG.Unit.a), ("car", .c), ("panto", .d), ("tail", .a)] {
            let mesh = try XCTUnwrap(Map3DN700SG.mesh(unit), "\(unit) decodes")
            let car = try model("set-n700sG-" + name)
            XCTAssertEqual(car.triangleCount, mesh.triangleCount, name)
            // As long as the light rebuild of the same unit, on the rail,
            // as wide and tall as the 700T.
            XCTAssertEqual(car.length, Map3DN700SG.length(unit), accuracy: 0.05, name)
            XCTAssertEqual(car.minimum.z, 0, accuracy: 0.01, "\(name) stands on the rail")
            XCTAssertEqual(car.maximum.y, 1.71, accuracy: 0.02, name)
        }
        XCTAssertEqual(cars.reduce(0) { $0 + $1.1 }, 300.6, accuracy: 0.5)
        // The tail is the cab turned round.
        let head = try model("set-n700sG-head"), tail = try model("set-n700sG-tail")
        XCTAssertEqual(tail.minimum.x, -head.maximum.x, accuracy: 1e-3)
        // Every colour the palette's or the 700T car's (its bogies, shaded
        // face by face): the line's green, which the 700T does not have, the
        // 700T's white.
        let bogies = try model("set-highSpeed-car").vertices.map(\.color)
        let palette = Set(Map3DN700SG.meshPalette + bogies + [Map3DTrainStyle.headlamp, Map3DPalette.lantern])
        for name in ["head", "car", "panto", "tail"] {
            XCTAssertTrue(try model("set-n700sG-" + name).vertices.allSatisfy { palette.contains($0.color) }, name)
        }
        XCTAssertTrue(try model("set-n700sG-car").vertices.contains { $0.color == Map3DN700SG.green })
        XCTAssertTrue(try model("set-n700sG-car").vertices.contains { $0.color == Map3DTrainShapeRefresh.highSpeedBodyColor })
        XCTAssertFalse(try model("set-highSpeed-car").vertices.contains { $0.color & 0xFFFFFF == Map3DN700SG.green & 0xFFFFFF })
        // The 700T's bogies where the author's stood: its tyres, none of the
        // author's wheels.
        for name in ["head", "car", "panto"] {
            let car = try model("set-n700sG-" + name)
            XCTAssertTrue(car.vertices.contains { $0.color == Map3DStreetModel.tyre }, name)
        }
        XCTAssertEqual(Map3DN700SG.bogieCentres[.a], [-9.11, 4.56])
        XCTAssertEqual(Map3DN700SG.bogieCentres[.c], [-9.0, 9.0])
        // D's pantograph covers stand above the C car's roof.
        XCTAssertGreaterThan(try model("set-n700sG-panto").maximum.z, try model("set-n700sG-car").maximum.z + 0.3)
        let lamps = head.vertices.filter(\.glows), backLamps = tail.vertices.filter(\.glows)
        XCTAssertFalse(lamps.isEmpty)
        XCTAssertTrue(lamps.allSatisfy { $0.color == Map3DTrainStyle.headlamp && $0.x > 0 })
        XCTAssertFalse(backLamps.isEmpty)
        XCTAssertTrue(backLamps.allSatisfy { $0.color == Map3DPalette.lantern && $0.x < 0 })
        for count in 1...16 {
            for car in 0..<count { XCTAssertNotNil(pack.modelIndex(forType: "n700sG", carIndex: car, count: count), "\(count) cars, car \(car)") }
        }
    }

    /// The mesh's bytes: a broken one decodes to nothing, so the set falls
    /// back to the light rebuild; B and E are not drawn near.
    func testTheN700SGMeshDecoding() {
        XCTAssertNil(Map3DN700SG.mesh(.b))
        XCTAssertNil(Map3DN700SG.mesh(.e))
        // One vertex, one triangle of it: no area, nothing to draw.
        let flat: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertNil(Map3DN700SG.decodedMesh(flat, named: "x"))
        // Three vertices, one triangle, palette 2 (the glass).
        var good: [UInt8] = [3, 0] + [0, 0, 0, 0, 0, 0] + [0xE8, 3, 0, 0, 0, 0] + [0, 0, 0xE8, 3, 0, 0] + [1, 0] + [0, 0, 1, 0, 2, 0, 2]
        let model = Map3DN700SG.decodedMesh(good, named: "x")
        XCTAssertEqual(model?.triangleCount, 1)
        XCTAssertEqual(model?.vertices.first?.color, Map3DTrainStyle.glass)
        XCTAssertEqual(model?.maximum.x ?? 0, 1, accuracy: 1e-6)
        good[good.count - 1] = UInt8(Map3DN700SG.meshPalette.count)
        XCTAssertNil(Map3DN700SG.decodedMesh(good, named: "x"), "a palette index past the end")
        XCTAssertNil(Map3DN700SG.decodedMesh(Array(good.dropLast()), named: "x"), "cut short")
        XCTAssertNil(Map3DN700SG.decodedMesh(good + [0], named: "x"), "bytes left over")
    }

    /// The N700S-G's far set: the light rebuild of the author's units, car
    /// for car from 500 m to 900 m.
    func testTheN700SGFarSet() throws {
        XCTAssertEqual(Map3DTrainSet.reach(of: "n700sG"), Map3DTrainSet.tramReach)
        for name in ["head", "car", "panto", "tail"] {
            let near = try XCTUnwrap(pack.index(of: "set-n700sG-" + name))
            XCTAssertEqual(pack.model(near, forType: "n700sG", count: 12, at: 100), near, name)
            XCTAssertEqual(pack.model(near, forType: "n700sG", count: 12, at: 700), pack.index(of: "set-n700sGFar-" + name), name)
            XCTAssertNil(pack.model(near, forType: "n700sG", count: 12, at: 1_000), name)
        }
        let counts = Map3DN700SG.Unit.allCases.map { Map3DN700SG.model($0).triangleCount }
        XCTAssertTrue((900...1_400).contains(counts[0]), "the far cab \(counts[0]) triangles")
        for count in counts.dropFirst() { XCTAssertTrue((350...550).contains(count), "a far middle car \(count) triangles") }
        for unit in Map3DN700SG.Unit.allCases {
            let model = Map3DN700SG.model(unit)
            XCTAssertTrue(model.vertices.contains { $0.color == Map3DN700SG.green }, "\(unit): the green line")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.1, "\(unit) stands on the rail")
            XCTAssertEqual(model.length, Map3DN700SG.length(unit), accuracy: 0.05, "\(unit)")
        }
        let tail = try model("set-n700sGFar-tail").vertices.filter(\.glows)
        XCTAssertTrue(tail.allSatisfy { $0.color == Map3DPalette.lantern && $0.x < 0 })
        let d = Map3DN700SG.model(.d), back = Map3DN700SG.reversed(.d)
        XCTAssertEqual(back.minimum.x, -d.maximum.x, accuracy: 1e-4)
    }

    /// Half the high-speed trains, the odd-numbered, are the N700S-G; a
    /// real train by its run's number; other types as they were.
    func testWhichTrainsAreTheN700SG() {
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1), "n700sG")
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 2), "HSR")
        XCTAssertEqual(Map3DTrainSet.variant(of: "highSpeed", number: 7), "n700sG")
        XCTAssertEqual(Map3DTrainSet.variant(of: "EMU3000", number: 1), "EMU3000")
        XCTAssertEqual(Map3DTrainSet.variant(of: "", number: 3), "")
        XCTAssertEqual(Map3DTrainSet.number(ofRealTrain: "thsr-12"), 12)
        XCTAssertEqual(Map3DTrainSet.number(ofRealTrain: "thsr7"), 7)
        XCTAssertEqual(Map3DTrainSet.number(ofRealTrain: "thsr"), 0)
        XCTAssertNotNil(pack.models(forType: "n700sG"))
    }

    /// Within 500 m the 700T, on to 900 m #900's light 700T car for car,
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
        // A whole 700T is under ten times the light one's triangles.
        let cars = try XCTUnwrap(pack.layout(forType: "HSR", count: 12))
        let whole = cars.reduce(0) { $0 + pack.models[$1.model].triangleCount }
        let light = try cars.reduce(0) { $0 + pack.models[try XCTUnwrap(pack.farModel(of: $1.model, forType: "HSR", count: 12))].triangleCount }
        XCTAssertLessThan(whole, 10 * light)
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
}
