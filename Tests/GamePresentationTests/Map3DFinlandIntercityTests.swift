import XCTest
@testable import GamePresentation

/// Decision 864: the local studio's Finnish Sr2 locomotive and intercity
/// double-deck coach, and Rovaniemi's trains made of them.
final class Map3DFinlandIntercityTests: XCTestCase {
    func testBothDecodeNearAndFarInTheSameFrame() throws {
        let pairs: [(String, Map3DModelPack.Model?, Map3DModelPack.Model?, Float, Float)] = [
            ("sr2", Map3DFinlandSr2.model(), Map3DFinlandSr2.model(far: true), 19.02, 3.0),
            ("coach", Map3DFinlandDoubleDeck.model(), Map3DFinlandDoubleDeck.model(far: true), 26.40, 3.2),
        ]
        for (label, near, far, length, width) in pairs {
            let near = try XCTUnwrap(near, label), far = try XCTUnwrap(far, label)
            XCTAssertEqual(near.length, length, accuracy: 0.01, label)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01, label)
            XCTAssertEqual(near.maximum.y - near.minimum.y, width, accuracy: 0.02, label)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.03, "\(label) stands on the rail")
            XCTAssertEqual(far.maximum.z, near.maximum.z, accuracy: 0.01, label)
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(label): the far model less than half")
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), label)
        }
    }

    /// The Sr2's cab windows are dark: they mirror the sky, the doors'
    /// frames do not, and nothing of it lights as a window at night. Its
    /// lamps are at both ends.
    func testTheSr2HasNoLitWindowsAndLampsAtBothEnds() throws {
        let sr2 = try XCTUnwrap(Map3DFinlandSr2.model())
        let glass = sr2.vertices.filter { $0.layer == Map3DVertex.trainGlass }
        XCTAssertFalse(glass.isEmpty, "the windscreens mirror")
        XCTAssertTrue(glass.allSatisfy { abs($0.x) > 6.9 }, "only the cabs' windows")
        XCTAssertFalse(sr2.vertices.contains { $0.color == Map3DTrainStyle.glass })
        XCTAssertNil(Map3DTrainLights.windowModel(of: sr2), "no window lights at night")
        XCTAssertNotNil(Map3DTrainLights.windowModel(of: try XCTUnwrap(Map3DFinlandDoubleDeck.model())), "the coach's do")
        let lamps = sr2.vertices.filter { $0.color == Map3DTrainStyle.headlamp }.map(\.x)
        XCTAssertGreaterThan(lamps.max() ?? 0, 8.5)
        XCTAssertLessThan(lamps.min() ?? 0, -8.5)
    }

    /// The coach's windows are its glass material's faces, two rows of
    /// them, the upper deck's above 3 m.
    func testTheCoachHasTwoRowsOfWindows() throws {
        let coach = try XCTUnwrap(Map3DFinlandDoubleDeck.model())
        let glass = coach.vertices.filter { $0.layer == Map3DVertex.trainGlass && abs($0.x) < 6 }
        XCTAssertTrue(glass.contains { $0.z > 3 }, "the upper deck's windows")
        XCTAssertTrue(glass.contains { $0.z < 2 }, "the lower deck's windows")
        XCTAssertTrue(coach.vertices.contains { $0.color == Map3DPalette.crown && abs($0.x) < 4 }, "the green band")
    }

    /// The Sr2 at the front, six coaches behind, the last one's tail lamps
    /// lit, each car at its own length.
    func testRovaniemisTrainIsTheSr2AndSixCoaches() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DFinlandSr2.key
        let count = Map3DFinlandSr2.cars
        let names = try (0..<count).map { car in
            pack.models[try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: count))].name
        }
        XCTAssertEqual(names, ["set-\(key)-head"] + Array(repeating: "set-\(key)-car", count: 5) + ["set-\(key)-tail"])
        let layout = try XCTUnwrap(pack.layout(forType: key, count: count))
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 19.02 + 26.40 * 6, accuracy: 0.1, "177.42 m")
        XCTAssertEqual(Map3DRealTrains.formation(system: "vr", id: "KJA", name: "KJA"), .init(key: key, cars: count))
    }
}
