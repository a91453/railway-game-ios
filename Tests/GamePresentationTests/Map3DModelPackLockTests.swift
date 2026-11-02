import Foundation
@testable import GamePresentation
import XCTest

/// Decision 546: the model pack, made on every core at once, is the pack
/// made one model after another, to the bit. Every model of
/// ``Map3DModelPack/standard`` and ``Map3DModelPack/studies`` against
/// `tools/train-models/hashes.lock.json` (FNV-1a of every vertex field,
/// `tools/train-models/export.swift`), and the order the renderer reads
/// them in (a model's index, a car's lamps and windows' model) pinned.
final class Map3DModelPackLockTests: XCTestCase {
    /// `export.swift`'s `hash`.
    static func hash(_ model: Map3DModelPack.Model) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for v in model.vertices {
            for word in [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern, v.nx.bitPattern, v.ny.bitPattern, v.nz.bitPattern,
                         v.color, v.u.bitPattern, v.v.bitPattern, v.layer.bitPattern] {
                for shift in stride(from: 0, to: 32, by: 8) { h = (h ^ UInt64((word >> UInt32(shift)) & 0xFF)) &* 0x100000001b3 }
            }
        }
        return String(h, radix: 16)
    }

    static func digest(_ words: [String]) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in words.joined(separator: "\n").utf8 { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    func testEveryModelIsAsLocked() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/train-models/hashes.lock.json")
        let lock = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let locked = try XCTUnwrap(lock["models"] as? [String: [String: Any]])
        let models = Map3DModelPack.standard.models + Map3DModelPack.studies.models
        // Decision 467's two stand-ins came after the lock was last
        // written and were never added to it (the app draws their files);
        // `testTheOrderAndTheLampsAreAsBefore` pins them with the rest.
        let unlocked: Set<String> = ["scenery-postBoxes", "scenery-busStopPole"]
        XCTAssertEqual(Set(models.map(\.name)).subtracting(unlocked), Set(locked.keys))
        var wrong: [String] = []
        for model in models where !unlocked.contains(model.name) {
            let entry = locked[model.name]
            if entry?["hash"] as? String != Self.hash(model) || entry?["triangles"] as? Int != model.triangleCount { wrong.append(model.name) }
        }
        XCTAssertEqual(wrong, [], "models unlike hashes.lock.json")
    }

    /// The standard pack's models in their order with every vertex, each
    /// running car's lamps and windows' model, and the destination signs,
    /// as main (a037d9e) made them one after another.
    func testTheOrderAndTheLampsAreAsBefore() {
        let pack = Map3DModelPack.standard
        XCTAssertEqual(Self.digest(pack.models.map(\.name)), "eaba9cce2262e775")
        XCTAssertEqual(Self.digest(pack.models.map { $0.name + " " + Self.hash($0) }), "7fa2bcfdfee73399")
        let lamps = pack.lights.keys.sorted().map { index -> String in
            let car = pack.lights[index]!
            let vertices = car.front.head + car.front.tail + car.back.head + car.back.tail
            let model = Map3DModelPack.Model(name: "", vertices: vertices, minimum: .zero, maximum: .zero)
            return "\(index) \(car.windows ?? -1) \(Self.hash(model))"
        }
        XCTAssertEqual(lamps.count, 304)
        XCTAssertEqual(Self.digest(lamps), "e3e7512b745f5ef2")
        XCTAssertEqual(Self.digest(pack.headSigns.keys.sorted().map { "\($0) \(pack.headSigns[$0]!)" }), "a422495a9c229fba")
    }

    /// What making the pack costs, step by step: the recipes, the glass
    /// marked, the shade baked, the lamps and windows (decision 546's
    /// table). `MAP3D_PACK_REPORT=1 swift test -c release -Xswiftc
    /// -enable-testing --filter Map3DModelPackLockTests/testThePacksTime`.
    func testThePacksTime() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MAP3D_PACK_REPORT"] != nil, "MAP3D_PACK_REPORT=1 to measure")
        let clock = ContinuousClock()
        func seconds(_ duration: Duration) -> String {
            let s = Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
            return String(format: "%.2f s", s)
        }
        var unbaked: Map3DModelPack?
        let recipes = clock.measure { unbaked = Map3DModelPack(styles: Map3DTrainStyle.all, baked: false) }
        let models = unbaked!.models
        var marked: [Map3DModelPack.Model] = []
        let marking = clock.measure { marked = Map3DTrainMaterial.marked(models) }
        var baked: [Map3DModelPack.Model] = []
        let baking = clock.measure { baked = Map3DTrainOcclusion.baked(marked) }
        let lighting = clock.measure { _ = Map3DTrainLights.split(baked, recipes: models) }
        let whole = clock.measure { _ = Map3DModelPack(styles: Map3DTrainStyle.all) }
        print("model pack: recipes \(seconds(recipes)), glass \(seconds(marking)), shade \(seconds(baking)), lamps \(seconds(lighting)); whole \(seconds(whole)) on \(ProcessInfo.processInfo.activeProcessorCount) cores")
    }
}
