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

    /// The near Taroko is as it was on main: the far switch only adds.
    func testTheNearTarokoIsUnchanged() {
        XCTAssertEqual(Map3DTEMU1000.Unit.allCases.map { Map3DTEMU1000.model($0).triangleCount }, Self.mainTriangles)
        XCTAssertEqual(digest(Map3DTEMU1000.Unit.allCases), Self.mainDigest)
    }

    /// Measured on main before decision 420.
    private static let mainTriangles = [2583, 1408, 1512, 2583]
    private static let mainDigest: UInt64 = 930026698743816318

    /// FNV-1a over every vertex's bits, the same on every run.
    private func digest(_ units: [Map3DTEMU1000.Unit]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ word: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) { hash = (hash ^ UInt64((word >> UInt32(shift)) & 0xFF)) &* 0x100_0000_01b3 }
        }
        for unit in units {
            for v in Map3DTEMU1000.model(unit).vertices {
                for f in [v.x, v.y, v.z, v.nx, v.ny, v.nz] { mix(f.bitPattern) }
                mix(v.color)
            }
        }
        return hash
    }
}
