import XCTest
@testable import GamePresentation

/// Decision 420: the Taroko and the EMU800 have light versions made in
/// code, drawn car for car from 500 m out as decision 408's far sets are.
final class Map3DFarSets420Tests: XCTestCase {
    private let pack = Map3DModelPack.standard

    private func model(_ name: String) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: name), name)]
    }

    func testNearWithin500MetresThenFarThenABox() throws {
        for (code, count) in [("taroko", 8), ("emu800", 8)] {
            XCTAssertEqual(Map3DTrainSet.reach(of: code), Map3DTrainSet.tramReach, code)
            for unit in ["head", "car", "tail", "panto"] {
                guard let near = pack.index(of: "set-\(code)-\(unit)") else { continue }
                XCTAssertEqual(pack.model(near, forType: code, count: count, at: 100), near, "\(code) \(unit)")
                XCTAssertEqual(pack.model(near, forType: code, count: count, at: 700), pack.index(of: "set-\(code)Far-\(unit)"), "\(code) \(unit)")
                XCTAssertNil(pack.model(near, forType: code, count: count, at: 1_000), "\(code) \(unit)")
            }
        }
    }

    func testTheFarCarsAreTheSameCarsLighter() throws {
        for code in ["taroko", "emu800"] {
            for unit in ["head", "car", "tail", "panto"] {
                guard pack.index(of: "set-\(code)-\(unit)") != nil else { continue }
                let near = try model("set-\(code)-\(unit)"), far = try model("set-\(code)Far-\(unit)")
                // The same box: a train laid from the near cars fits the far ones.
                XCTAssertEqual(far.minimum.x, near.minimum.x, accuracy: 0.02, "\(code) \(unit)")
                XCTAssertEqual(far.maximum.x, near.maximum.x, accuracy: 0.02, "\(code) \(unit)")
                XCTAssertEqual(far.maximum.z, near.maximum.z, accuracy: 0.05, "\(code) \(unit)")
                XCTAssertEqual(far.minimum.z, 0, accuracy: 0.1, "\(code) \(unit)")
                // Under half the triangles, in the near car's own colours.
                XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(code) \(unit): \(far.triangleCount) of \(near.triangleCount)")
                XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), "\(code) \(unit)")
                // The band is still there.
                XCTAssertEqual(Set(far.vertices.map(\.color)).contains(code == "taroko" ? Map3DTEMU1000.band : Map3DColor.rgb(0x214F90)), true, "\(code) \(unit)")
            }
            // The head's lamps still lit at its front.
            let head = try model("set-\(code)Far-head")
            XCTAssertTrue(head.vertices.contains { $0.glows && $0.x > 4 }, code)
        }
    }

    /// The operating near set still uses the authored near cars after a
    /// deliberate art revision. Its cab cars add the set's running lamps.
    func testTheNearTarokoUsesTheAuthoredCars() throws {
        let units: [(String, Map3DTEMU1000.Unit, Bool)] = [
            ("head", .leading, true), ("car", .middle, false),
            ("tail", .trailing, true), ("panto", .pantograph, false)
        ]
        for (name, unit, hasRunningLamps) in units {
            let authored = Map3DTEMU1000.model(unit)
            let staticCar = try model(authored.name)
            let operatingCar = try model("set-taroko-\(name)")
            XCTAssertEqual(staticCar.vertices, authored.vertices, name)
            XCTAssertEqual(operatingCar.minimum.x, authored.minimum.x, name)
            XCTAssertEqual(operatingCar.maximum.x, authored.maximum.x, name)
            XCTAssertGreaterThanOrEqual(operatingCar.vertices.count, authored.vertices.count, name)
            XCTAssertEqual(Array(operatingCar.vertices.prefix(authored.vertices.count)), authored.vertices, name)
            XCTAssertEqual(operatingCar.vertices.count > authored.vertices.count, hasRunningLamps, name)
        }
    }
}
