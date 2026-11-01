import GameCore
@testable import GamePresentation
import XCTest

/// Decision 531: the Alishan Forest Railway's mountain train as the DL-38
/// and its coaches, near and far.
final class Map3DAlishanTests: XCTestCase {
    private let pack = Map3DModelPack.standard

    private func names(_ key: String, _ count: Int) -> [String] {
        (0..<count).compactMap { car in pack.modelIndex(forType: key, carIndex: car, count: count).map { pack.models[$0].name } }
    }

    /// A train of the `ALISHAN` type is the set: the locomotive at the
    /// front, the coaches behind, each its own length, and from 500 m out
    /// its light version.
    func testTheTypeIsTheSet() throws {
        XCTAssertEqual(Map3DTrainSet.key(type: .alishan, performance: .forestRailway), "ALISHAN")
        XCTAssertEqual(names("ALISHAN", 4), ["set-ALISHAN-head", "set-ALISHAN-car", "set-ALISHAN-car", "set-ALISHAN-tail"])
        XCTAssertEqual(names("ALISHAN", 1), ["set-ALISHAN-head"])
        XCTAssertEqual(Map3DTrainSet.named("ALISHAN")?.far, "ALISHANFar")
        XCTAssertEqual(Map3DTrainSet.reach(of: "ALISHAN"), Map3DTrainSet.tramReach)
        let head = try XCTUnwrap(pack.index(of: "set-ALISHAN-head"))
        XCTAssertEqual(pack.farModel(of: head, forType: "ALISHAN", count: 4).map { pack.models[$0].name }, "set-ALISHANFar-head")

        let layout = try XCTUnwrap(pack.layout(forType: "ALISHAN", count: 6))
        XCTAssertEqual(layout.map(\.length), [8.9, 13, 13, 13, 13, 13])
        XCTAssertEqual(layout.reduce(0) { $0 + $1.length }, 73.9, accuracy: 1e-3, "about the 70 m the reference gives")
        XCTAssertFalse(pack.isTurned(forType: "ALISHAN", carIndex: 5, count: 6), "the last coach has its own model")
    }

    /// The models' frames: on the rails, the 762 mm gauge's narrow cars,
    /// the far versions the near ones' frames and colours and under half
    /// their triangles.
    func testTheirFrames() throws {
        for (unit, length, width, height) in [("head", 8.9, 2.2, 3.05), ("car", 13.0, 2.276, 3.22), ("tail", 13.0, 2.276, 3.22)] as [(String, Float, Float, Float)] {
            let near = try XCTUnwrap(pack.index(of: "set-ALISHAN-\(unit)").map { pack.models[$0] })
            let far = try XCTUnwrap(pack.index(of: "set-ALISHANFar-\(unit)").map { pack.models[$0] })
            XCTAssertEqual(near.length, length, accuracy: 1e-3, unit)
            XCTAssertEqual(near.maximum.y - near.minimum.y, width, accuracy: 1e-3, unit)
            XCTAssertEqual(near.maximum.z, height, accuracy: 1e-3, unit)
            XCTAssertEqual(near.minimum.z, 0, accuracy: 1e-3, unit)
            for (a, b) in [(near.minimum, far.minimum), (near.maximum, far.maximum)] {
                XCTAssertEqual(a.x, b.x, accuracy: 1e-3, unit); XCTAssertEqual(a.y, b.y, accuracy: 1e-3, unit); XCTAssertEqual(a.z, b.z, accuracy: 1e-3, unit)
            }
            XCTAssertLessThan(far.vertices.count * 2, near.vertices.count, unit)
            XCTAssertLessThan(near.vertices.count / 3, 20_000, unit)
        }
    }

    /// The reference's colours: the red locomotive with its cream line, the
    /// cream coach with its red band; the windows the trains' glass, so
    /// they light at night.
    func testTheirColours() {
        let loco = Set(Map3DAlishan.locomotive().vertices.map(\.color))
        XCTAssertTrue(loco.isSuperset(of: [Map3DColor.rgb(0xB83230), Map3DColor.rgb(0xE9E1CF), Map3DTrainStyle.glass]))
        let coach = Set(Map3DAlishan.coach().vertices.map(\.color))
        XCTAssertTrue(coach.isSuperset(of: [Map3DColor.rgb(0xE6D7B0), Map3DColor.rgb(0xAD333A), Map3DTrainStyle.glass]))
        XCTAssertEqual(Set(Map3DAlishan.coach(far: true).vertices.map(\.color)).subtracting(coach).map { String($0, radix: 16) }, [], "the far coach's colours are the near one's")
        XCTAssertEqual(Set(Map3DAlishan.locomotive(far: true).vertices.map(\.color)).subtracting(loco).map { String($0, radix: 16) }, [], "the far locomotive's colours are the near one's")
    }

    /// At night the coaches' windows light, near and far; the
    /// locomotive's hood louvres do not (it has no saloon).
    func testTheirWindowsAtNight() {
        XCTAssertNil(Map3DTrainLights.windowModel(of: Map3DAlishan.locomotive()))
        XCTAssertNil(Map3DTrainLights.windowModel(of: Map3DAlishan.locomotive(far: true)))
        XCTAssertNotNil(Map3DTrainLights.windowModel(of: Map3DAlishan.coach()))
        XCTAssertNotNil(Map3DTrainLights.windowModel(of: Map3DAlishan.coach(far: true)))
    }

    /// The recipes are pinned: a change to a shared function shows here.
    func testTheRecipesAreUnchanged() {
        XCTAssertEqual(hash(Map3DAlishan.locomotive()), "cf92ad1c9dd33923")
        XCTAssertEqual(hash(Map3DAlishan.locomotive(far: true)), "15e35322077df838")
        XCTAssertEqual(hash(Map3DAlishan.coach()), "2edf6d8471941707")
        XCTAssertEqual(hash(Map3DAlishan.coach(far: true)), "75d9fe17deb47bb7")
    }

    private func hash(_ model: Map3DModelPack.Model) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for v in model.vertices {
            for word in [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern, v.nx.bitPattern, v.ny.bitPattern, v.nz.bitPattern,
                         v.color, v.u.bitPattern, v.v.bitPattern, v.layer.bitPattern] {
                for shift in stride(from: 0, to: 32, by: 8) { h = (h ^ UInt64((word >> UInt32(shift)) & 0xFF)) &* 0x100000001b3 }
            }
        }
        return String(h, radix: 16)
    }
}
