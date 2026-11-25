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
    /// The same words in the same order, each byte low first, as
    /// `export.swift`; without an array per vertex or a stride per word,
    /// which in this unoptimized test build took most of this class's
    /// two minutes (CIOPT-10).
    static func hash(_ model: Map3DModelPack.Model) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for v in model.vertices {
            mix(&h, v.x.bitPattern); mix(&h, v.y.bitPattern); mix(&h, v.z.bitPattern)
            mix(&h, v.nx.bitPattern); mix(&h, v.ny.bitPattern); mix(&h, v.nz.bitPattern)
            mix(&h, v.color); mix(&h, v.u.bitPattern); mix(&h, v.v.bitPattern); mix(&h, v.layer.bitPattern)
        }
        return String(h, radix: 16)
    }

    /// FNV-1a of one 32-bit word's four bytes, low first.
    private static func mix(_ h: inout UInt64, _ word: UInt32) {
        let prime: UInt64 = 0x100000001b3
        h = (h ^ UInt64(word & 0xFF)) &* prime
        h = (h ^ UInt64((word >> 8) & 0xFF)) &* prime
        h = (h ^ UInt64((word >> 16) & 0xFF)) &* prime
        h = (h ^ UInt64(word >> 24)) &* prime
    }

    static func digest(_ words: [String]) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in words.joined(separator: "\n").utf8 { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    static let toolDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("tools/train-models")

    static func lockFile(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], url.lastPathComponent)
    }

    /// Decision 782: a registered train's lock file,
    /// `tools/train-models/locks/<id>.json`.
    static func lockFile(of train: Map3DTrainRegistration) throws -> [String: Any] {
        try lockFile(toolDirectory.appendingPathComponent("locks/\(train.id).json"))
    }

    /// Decision 782: the models' hashes in `hashes.lock.json` and in every
    /// registered train's own lock file, none in two.
    static func lockedModels() throws -> [String: [String: Any]] {
        var locked = try XCTUnwrap(lockFile(toolDirectory.appendingPathComponent("hashes.lock.json"))["models"] as? [String: [String: Any]])
        for train in Map3DTrainRegistry.trains {
            let own = try XCTUnwrap(lockFile(of: train)["models"] as? [String: [String: Any]], train.id)
            XCTAssertTrue(Set(own.keys).isDisjoint(with: locked.keys), "\(train.id): its models locked twice")
            locked.merge(own) { first, _ in first }
        }
        return locked
    }

    /// Decision 782: the lamps and windows of the pack's running cars whose
    /// model `include` takes, each by its model's name and its windows'
    /// (positions move whenever any model is added before them).
    static func lamps(_ pack: Map3DModelPack, of include: (String) -> Bool) -> [String] {
        pack.lights.keys.sorted().compactMap { index -> String? in
            guard include(pack.models[index].name) else { return nil }
            let car = pack.lights[index]!
            let vertices = car.front.head + car.front.tail + car.back.head + car.back.tail
            let model = Map3DModelPack.Model(name: "", vertices: vertices, minimum: .zero, maximum: .zero)
            return "\(pack.models[index].name) \(car.windows.map { pack.models[$0].name } ?? "-") \(hash(model))"
        }
    }

    func testEveryModelIsAsLocked() throws {
        let locked = try Self.lockedModels()
        let models = Map3DModelPack.standard.models + Map3DModelPack.studies.models
        XCTAssertEqual(Set(models.map(\.name)), Set(locked.keys))
        var wrong: [String] = []
        for model in models {
            let entry = locked[model.name]
            // With what it is now, for the lock (the hashes are Linux's:
            // a Mac's differ in the last bit of a sine).
            if entry?["hash"] as? String != Self.hash(model) || entry?["triangles"] as? Int != model.triangleCount {
                wrong.append("\(model.name) \(Self.hash(model)) \(model.triangleCount)")
            }
        }
        XCTAssertEqual(wrong, [], "models unlike hashes.lock.json")
    }

    /// The standard pack's models with each running car's lamps and
    /// windows' model and each destination sign, one line a model in
    /// `tools/train-models/pack.lock.txt` (MODEL-PACK-PINS-SPLIT,
    /// 2026-11-25). It took over from the whole pack's digests of names,
    /// hashes, lamps and signs, which every pull request that added a
    /// model rewrote and so conflicted on (their history is in git). A
    /// model's bits are its hash in `hashes.lock.json`
    /// (`testEveryModelIsAsLocked`); here its lamps by their hash and its
    /// windows and sign by their model's name, not by index, so a model
    /// added anywhere changes no other model's line. The registered trains
    /// (``Map3DTrainRegistry``) are left out: their lock files pin them
    /// (`testEveryRegisteredTrainIsAsLocked`). The file is `merge=union`
    /// (`.gitattributes`): two branches that each add a model keep both
    /// lines.
    func testTheOrderAndTheLampsAreAsBefore() throws {
        let now = Self.packLines(Map3DModelPack.standard)
        // `MAP3D_WRITE_PACK_LOCK=1 swift test --filter Map3DModelPackLockTests/testTheOrderAndTheLampsAreAsBefore`
        // rewrites the file; check its diff is only the models you meant.
        if ProcessInfo.processInfo.environment["MAP3D_WRITE_PACK_LOCK"] != nil {
            try (Self.packLockHeader + now.joined(separator: "\n") + "\n").write(to: Self.packLockFile, atomically: true, encoding: .utf8)
        }
        let locked = try Self.lockedPackLines()
        XCTAssertEqual(Set(now).count, now.count, "two models of one name")
        XCTAssertEqual(Set(locked).count, locked.count, "a line twice in pack.lock.txt")
        // With what it is now, for the lock: add the missing lines, remove the stale ones.
        let missing = Set(now).subtracting(locked).sorted()
        let stale = Set(locked).subtracting(now).sorted()
        XCTAssertEqual(missing, [], "lines pack.lock.txt lacks:\n" + missing.joined(separator: "\n"))
        XCTAssertEqual(stale, [], "lines in pack.lock.txt the pack no longer makes:\n" + stale.joined(separator: "\n"))
    }

    static let packLockFile = toolDirectory.appendingPathComponent("pack.lock.txt")
    static let packLockHeader = """
        # One line a model of Map3DModelPack.standard the train registry does not own, sorted
        # (Map3DModelPackLockTests.testTheOrderAndTheLampsAreAsBefore): its name, then
        # "lamps <windows' model or -> <hash>" for a running car and "sign <sign>" for one with
        # a destination sign. merge=union (.gitattributes): add your models' lines, change no other.

        """

    /// One line a model of `pack` the registry does not own, sorted: its
    /// name, then ` lamps <windows' model or -> <hash>` for a running car
    /// and ` sign <sign>` for one with a destination sign.
    static func packLines(_ pack: Map3DModelPack) -> [String] {
        pack.models.indices.compactMap { index -> String? in
            let name = pack.models[index].name
            guard Map3DTrainRegistry.registration(ofModel: name) == nil else { return nil }
            var line = name
            if let car = pack.lights[index] {
                let vertices = car.front.head + car.front.tail + car.back.head + car.back.tail
                let lamps = Map3DModelPack.Model(name: "", vertices: vertices, minimum: .zero, maximum: .zero)
                line += " lamps \(car.windows.map { pack.models[$0].name } ?? "-") \(hash(lamps))"
            }
            if let sign = pack.headSigns[index] { line += " sign \(sign)" }
            return line
        }.sorted()
    }

    /// `pack.lock.txt`'s lines, sorted, without its `#` comments and blank lines.
    static func lockedPackLines() throws -> [String] {
        try String(contentsOf: packLockFile, encoding: .utf8).split(separator: "\n").map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }.sorted()
    }

    /// Decision 782: each registered train's models are exactly those its
    /// lock file names (the hashes themselves, `testEveryModelIsAsLocked`),
    /// and its cars' lamps and windows are as the file pins them.
    func testEveryRegisteredTrainIsAsLocked() throws {
        let pack = Map3DModelPack.standard
        for train in Map3DTrainRegistry.trains {
            let lock = try Self.lockFile(of: train)
            let locked = try XCTUnwrap(lock["models"] as? [String: [String: Any]], train.id)
            XCTAssertEqual(Set(pack.models.map(\.name).filter(train.owns)), Set(locked.keys), "\(train.id): its models")
            let lamps = Self.lamps(pack, of: train.owns)
            // With what it is now, for the lock file.
            XCTAssertEqual(lock["lampCount"] as? Int, lamps.count, "\(train.id): lampCount \(lamps.count)")
            XCTAssertEqual(lock["lamps"] as? String, Self.digest(lamps), "\(train.id): lamps \(Self.digest(lamps))")
        }
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
