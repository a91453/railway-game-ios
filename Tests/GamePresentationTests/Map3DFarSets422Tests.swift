import XCTest
@testable import GamePresentation

/// Decision 422: the 700T's far cars are made from its own near cars (its
/// recipe), and the near cars stay as they were. The N700S-G's were
/// checked here too until decision 979 replaced it with the owner's old
/// N700S, which has no far set.
final class Map3DFarSets422Tests: XCTestCase {
    private var pack: Map3DModelPack { .unbaked }  // the recipes before decision 439's shade

    private func model(_ name: String) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: name), name)]
    }

    private static let units = [
        "highSpeed": ["head", "car", "panto", "tail"],
    ]

    func testTheFarCarsAreTheNearCarsLighter() throws {
        for (key, units) in Self.units {
            for unit in units {
                let near = try model("set-\(key)-\(unit)"), far = try model("set-\(key)Far-\(unit)")
                // The same box: a train laid from the near cars fits the far
                // ones.
                XCTAssertEqual(far.minimum.x, near.minimum.x, accuracy: 0.06, "\(key) \(unit)")
                XCTAssertEqual(far.maximum.x, near.maximum.x, accuracy: 0.06, "\(key) \(unit)")
                XCTAssertEqual(far.maximum.z, near.maximum.z, accuracy: 0.1, "\(key) \(unit)")
                XCTAssertEqual(far.minimum.z, near.minimum.z, accuracy: 0.1, "\(key) \(unit)")
                // In the near car's own colours, the line among them.
                let colours = Set(far.vertices.map(\.color))
                XCTAssertTrue(colours.isSubset(of: Set(near.vertices.map(\.color))), "\(key) \(unit)")
                XCTAssertTrue(colours.contains(Map3DPalette.shopAwnings[0]), "\(key) \(unit): the line")
                // About 1,000 to 1,500 triangles a car at most, a third of the near car's or fewer.
                XCTAssertLessThanOrEqual(far.triangleCount, 1_500, "\(key) \(unit)")
                XCTAssertLessThan(far.triangleCount * 3, near.triangleCount, "\(key) \(unit): \(far.triangleCount) of \(near.triangleCount)")
            }
            // The lamps lit, white at the front and red at the back.
            let head = try model("set-\(key)Far-head").vertices.filter(\.glows)
            XCTAssertTrue(head.contains { $0.x > 4 }, key)
            XCTAssertTrue(head.allSatisfy { $0.x > 0 }, key)
            let tail = try model("set-\(key)Far-tail").vertices.filter(\.glows)
            XCTAssertFalse(tail.isEmpty, key)
            XCTAssertTrue(tail.allSatisfy { $0.color == Map3DPalette.lantern && $0.x < 0 }, key)
        }
    }

    /// The near cars are as they were on main: the far sets only change.
    func testTheNearCarsAreUnchanged() throws {
        for (key, (triangles, hash)) in Self.mainNear {
            let models = try XCTUnwrap(Map3DTrainSet.byKey[key], key).models().map { pack.models[pack.index(of: $0.name)!] }
            XCTAssertEqual(models.map(\.triangleCount), triangles, key)
            XCTAssertEqual(digest(models), hash, key)
        }
    }

    /// Measured on main before decision 422.
    private static let mainNear: [String: ([Int], UInt64)] = [
        "highSpeed": ([9126, 5602, 9126, 5730], 15067286180718250026),
    ]

    /// FNV-1a over every vertex's bits, the same on every run.
    private func digest(_ models: [Map3DModelPack.Model]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ word: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) { hash = (hash ^ UInt64((word >> UInt32(shift)) & 0xFF)) &* 0x100_0000_01b3 }
        }
        for model in models {
            for v in model.vertices {
                for f in [v.x, v.y, v.z, v.nx, v.ny, v.nz] { mix(f.bitPattern) }
                mix(v.color)
                mix(v.layer.bitPattern)
            }
        }
        return hash
    }
}
