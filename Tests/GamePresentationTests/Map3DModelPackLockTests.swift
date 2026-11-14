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
            // With what it is now, for the lock (the hashes are Linux's:
            // a Mac's differ in the last bit of a sine).
            if entry?["hash"] as? String != Self.hash(model) || entry?["triangles"] as? Int != model.triangleCount {
                wrong.append("\(model.name) \(Self.hash(model)) \(model.triangleCount)")
            }
        }
        XCTAssertEqual(wrong, [], "models unlike hashes.lock.json")
    }

    /// The standard pack's models in their order with every vertex, each
    /// running car's lamps and windows' model, and the destination signs,
    /// as main (a037d9e) made them one after another. Decision 554 added
    /// the Hai-Feng and Shan-Lan sets last (16 cars, 16 lamp sets); with
    /// them left out, the names, hashes, lamps and signs are main e7cb277's
    /// to the digest. Decision 558 added the Wenhu line's VAL256 and 370
    /// sets, near and far, after them (32 cars, 16 lamp sets); decision 560
    /// the EMU700 sets after those (16 cars, 16 lamp sets, no sign:
    /// `Map3DHeadSigns.services` has no `emu700`); decision 561 the
    /// Taoyuan Airport MRT's 1000 and 2000 sets after those (18 cars, 18
    /// lamp sets, no sign). The models before them are as they were
    /// (`hashes.lock.json`).
    func testTheOrderAndTheLampsAreAsBefore() {
        let pack = Map3DModelPack.standard
        // Decision 575 續 (CABLEMAP): the cable car's 13 models just
        // before the route bus, and the windows' models after (which each move 13 on);
        // with them left out and the windows moved back, all as before.
        // Decision 585 PR-3 (FERRY3): the ferries' 6 models right after
        // them, before the route bus; left out with the cable car's.
        // Decision 615: the cable car's 8 Sun Moon Lake cabins after its
        // 13 and its cabins' glass see-through: the whole pack's names and
        // hashes and the windows' indices move, the rest as before.
        let cable = Set(Map3DCableCar.drawn.map(\.name))
        let ferry = Set(Map3DFerry.drawn.map(\.name))
        // Decision 699: the 12 aircraft and airfield vehicles right after
        // the ferries, before the route bus; left out with them (the
        // whole pack's names and hashes and the windows' indices move by
        // 12, the rest as before).
        let air = Set(Map3DAircraft.drawn.map(\.name))
        // Decision 708: the 14 coaches and 2 coach stops right after the
        // aircraft, before the route bus; left out with them (the whole
        // pack's names and hashes and the windows' indices move by 16,
        // the rest as before).
        let coach = Set(Map3DCoaches.drawn.map(\.name))
        // Decision 732: Hong Kong's four traffic signals right after the
        // coaches, before the route bus; left out with them (the whole
        // pack's names and hashes and the windows' indices move by 4, the
        // rest as before).
        let hk = Set(Map3DHongKongSignal.drawn.map(\.name))
        let firstCable = pack.models.firstIndex { cable.contains($0.name) }!
        let before = pack.models.filter { !cable.contains($0.name) && !ferry.contains($0.name) && !air.contains($0.name) && !coach.contains($0.name) && !hk.contains($0.name) }
        XCTAssertEqual(Self.digest(before.map(\.name)), "27484d82f073fb79")
        XCTAssertEqual(Self.digest(before.map { $0.name + " " + Self.hash($0) }), "25d1ff1a4a7bd8cd")
        XCTAssertEqual(Array(pack.models[firstCable..<firstCable + cable.count].map(\.name)), Map3DCableCar.drawn.map(\.name))
        XCTAssertEqual(Array(pack.models[firstCable + cable.count..<firstCable + cable.count + ferry.count].map(\.name)),
                       Map3DFerry.drawn.map(\.name))
        XCTAssertEqual(Array(pack.models[firstCable + cable.count + ferry.count..<firstCable + cable.count + ferry.count + air.count].map(\.name)),
                       Map3DAircraft.drawn.map(\.name))
        let firstCoach = firstCable + cable.count + ferry.count + air.count
        XCTAssertEqual(Array(pack.models[firstCoach..<firstCoach + coach.count].map(\.name)), Map3DCoaches.drawn.map(\.name))
        let firstHK = firstCoach + coach.count
        XCTAssertEqual(Array(pack.models[firstHK..<firstHK + hk.count].map(\.name)), Map3DHongKongSignal.drawn.map(\.name))
        XCTAssertEqual(Self.digest(pack.models.map(\.name)), "c33a95bfe45acce0")
        XCTAssertEqual(Self.digest(pack.models.map { $0.name + " " + Self.hash($0) }), "46ae231a92e959f2")
        func lamps(movingBack moved: Int) -> [String] {
            pack.lights.keys.sorted().map { index -> String in
                let car = pack.lights[index]!
                let vertices = car.front.head + car.front.tail + car.back.head + car.back.tail
                let model = Map3DModelPack.Model(name: "", vertices: vertices, minimum: .zero, maximum: .zero)
                let windows = car.windows.map { $0 > firstCable ? $0 - moved : $0 } ?? -1
                return "\(index) \(windows) \(Self.hash(model))"
            }
        }
        XCTAssertLessThan(pack.lights.keys.max()!, firstCable)
        XCTAssertEqual(lamps(movingBack: 0).count, 370)
        XCTAssertEqual(Self.digest(lamps(movingBack: cable.count + ferry.count + air.count + coach.count + hk.count)), "7da72c10c44b91fb")
        XCTAssertEqual(Self.digest(lamps(movingBack: 0)), "75e224c69941d34f")
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
