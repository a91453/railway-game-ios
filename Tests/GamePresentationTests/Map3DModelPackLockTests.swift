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
    ///
    /// Decision 782: the registered trains' models (``Map3DTrainRegistry``)
    /// are left out of every digest here, and the indices are counted as
    /// if they were not in the pack, so a new train changes none of these
    /// values; each train's own models and lamps are pinned by its lock
    /// file (`testEveryRegisteredTrainIsAsLocked`).
    func testTheOrderAndTheLampsAreAsBefore() {
        let full = Map3DModelPack.standard
        let registered = full.models.indices.filter { Map3DTrainRegistry.registration(ofModel: full.models[$0].name) != nil }
        /// A model's index with the registered trains' models before it
        /// left out.
        func coreIndex(_ index: Int) -> Int { index - registered.prefix { $0 < index }.count }
        let isRegistered = Set(registered)
        let models = full.models.indices.filter { !isRegistered.contains($0) }.map { full.models[$0] }
        var lights: [Int: Map3DTrainLights.Car] = [:]
        for (index, car) in full.lights where !isRegistered.contains(index) {
            var car = car
            car.windows = car.windows.map(coreIndex)
            lights[coreIndex(index)] = car
        }
        let pack = (models: models, lights: lights,
                    headSigns: Dictionary(uniqueKeysWithValues: full.headSigns.map { (coreIndex($0.key), $0.value) }))
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
        // Decision 743: Hong Kong's vehicles after its signals.
        let hongKong = Map3DHongKongSignal.drawn.map(\.name) + Map3DHongKongVehicles.models.map(\.modelName)
        let hk = Set(hongKong)
        // Decision 787: the close-up commuter's two models after Hong
        // Kong's vehicles, before the route bus; left out with them (the
        // whole pack's names and hashes and the windows' indices move by 2,
        // the rest as before).
        let commuter = Map3DCommuterFigure.models.map(\.modelName)
        let figures = Set(commuter)
        // Decision 794: the winter event's five models after the commuter,
        // before the route bus; left out with them (the whole pack's names
        // and hashes and the windows' indices move by 5, the rest as before).
        let winterNames = Map3DWinterLights.drawn.map(\.name)
        let winter = Set(winterNames)
        // Decision 831: Santa's sleigh's stand-in after the winter
        // decorations, before the route bus; left out with them (the
        // whole pack's names and hashes and the windows' indices move by
        // 1, the rest as before).
        let santa = Set([SantaFlight.Model.name])
        // Decision 838: Taiwan's SUV's and yellow taxi's stand-ins after
        // the sleigh, before the route bus; left out with them (the whole
        // pack's names and hashes and the windows' indices move by 2, the
        // rest as before).
        let taiwanCars = Set(Map3DTaiwanCars.drawn.map(\.name))
        // Decision 840: the Santa Claus village's reindeer after Taiwan's
        // cars, before the route bus; left out with them (the whole pack's
        // names and hashes and the windows' indices move by 6, the rest as
        // before).
        let herd = Set(Map3DReindeerHerd.drawn.map(\.name))
        // Decision 846: the pedestrian signals with no countdown's box
        // after the reindeer, before the route bus; left out with them (the
        // whole pack's names and hashes and the windows' indices move by 3,
        // the rest as before).
        let plain = Set(Map3DPedestrianSignal.plainDrawn.map(\.name))
        // Decision 846's later note: Finland's street furniture after them,
        // before the route bus; left out with them (the whole pack's names
        // and hashes and the windows' indices move by 10, the rest as
        // before).
        let finland = Set(Map3DFinlandStreet.drawn.map(\.name))
        // Decision 889: the yellow tit's four poses after Finland's street
        // furniture, before the route bus; left out with them (the whole
        // pack's names and hashes and the windows' indices move by 4, the
        // rest as before).
        let tits = Set(Map3DYellowTit.drawn.map(\.name))
        // Decision 767: the coal bunker's stand-in after the other scenery
        // props: every model after it, the cars' windows and the head
        // signs move by one, so the digests are made again; the models
        // themselves are as they were (`hashes.lock.json`).
        // The owner's old red commuter car (Map3DRedCommuter), the last set:
        // its three cars and their windows before the cable car (every
        // model after them, the windows' indices and the signs move by
        // six, so the digests are made again; 3 lamp sets more).
        // Decision 825: the E200 drawn from photographs, its far version
        // and the Ming-Ri's E200 with it (the same names and order; their
        // models and the head lamps are new, `hashes.lock.json`).
        let firstCable = pack.models.firstIndex { cable.contains($0.name) }!
        let before = pack.models.filter { !cable.contains($0.name) && !ferry.contains($0.name) && !air.contains($0.name) && !coach.contains($0.name) && !hk.contains($0.name)
            && !figures.contains($0.name) && !winter.contains($0.name) && !santa.contains($0.name) && !taiwanCars.contains($0.name) && !herd.contains($0.name)
            && !plain.contains($0.name) && !finland.contains($0.name) && !tits.contains($0.name) }
        XCTAssertEqual(Self.digest(before.map(\.name)), "45d52b8e433922ec")
        // Decision 891: the red commuter car's body and band in the
        // palette's colours (its three models in `hashes.lock.json`).
        XCTAssertEqual(Self.digest(before.map { $0.name + " " + Self.hash($0) }), "df4c94de0c488712")
        XCTAssertEqual(Array(pack.models[firstCable..<firstCable + cable.count].map(\.name)), Map3DCableCar.drawn.map(\.name))
        XCTAssertEqual(Array(pack.models[firstCable + cable.count..<firstCable + cable.count + ferry.count].map(\.name)),
                       Map3DFerry.drawn.map(\.name))
        XCTAssertEqual(Array(pack.models[firstCable + cable.count + ferry.count..<firstCable + cable.count + ferry.count + air.count].map(\.name)),
                       Map3DAircraft.drawn.map(\.name))
        let firstCoach = firstCable + cable.count + ferry.count + air.count
        XCTAssertEqual(Array(pack.models[firstCoach..<firstCoach + coach.count].map(\.name)), Map3DCoaches.drawn.map(\.name))
        let firstHK = firstCoach + coach.count
        XCTAssertEqual(Array(pack.models[firstHK..<firstHK + hk.count].map(\.name)), hongKong)
        XCTAssertEqual(Array(pack.models[firstHK + hk.count..<firstHK + hk.count + figures.count].map(\.name)), commuter)
        let firstWinter = firstHK + hk.count + figures.count
        XCTAssertEqual(Array(pack.models[firstWinter..<firstWinter + winter.count].map(\.name)), winterNames)
        XCTAssertEqual(pack.models[firstWinter + winter.count].name, SantaFlight.Model.name)
        XCTAssertEqual(Array(pack.models[firstWinter + winter.count + 1..<firstWinter + winter.count + 1 + taiwanCars.count].map(\.name)),
                       Map3DTaiwanCars.drawn.map(\.name))
        let firstHerd = firstWinter + winter.count + 1 + taiwanCars.count
        XCTAssertEqual(Array(pack.models[firstHerd..<firstHerd + herd.count].map(\.name)), Map3DReindeerHerd.drawn.map(\.name))
        XCTAssertEqual(Array(pack.models[firstHerd + herd.count..<firstHerd + herd.count + plain.count].map(\.name)),
                       Map3DPedestrianSignal.plainDrawn.map(\.name))
        let firstFinland = firstHerd + herd.count + plain.count
        XCTAssertEqual(Array(pack.models[firstFinland..<firstFinland + finland.count].map(\.name)), Map3DFinlandStreet.Unit.allCases.map(\.rawValue))
        let firstTit = firstFinland + finland.count
        XCTAssertEqual(Array(pack.models[firstTit..<firstTit + tits.count].map(\.name)), Map3DYellowTit.Pose.allCases.map(\.rawValue))
        // Decision 840: the reindeer after Taiwan's cars (the whole
        // pack's names, hashes and lamps' window indices move).
        // Decision 846: and the pedestrian signals with no countdown's box
        // after the reindeer; its later note: and Finland's street
        // furniture after them; its fourth later note: and its second
        // batch (shelter, double street light, give-way sign) after those.
        // Decision 889: and the yellow tit's four poses after those.
        XCTAssertEqual(Self.digest(pack.models.map(\.name)), "99a1b0d684533022")
        // Decision 840: and the studio's sleigh in the stand-in's place
        // (the same name and order; its model is new, `hashes.lock.json`);
        // its later amendment: dark brown antlers, the sleigh's team brown.
        XCTAssertEqual(Self.digest(pack.models.map { $0.name + " " + Self.hash($0) }), "f50ffcfe27436175")
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
        XCTAssertEqual(lamps(movingBack: 0).count, 373)
        XCTAssertEqual(Self.digest(lamps(movingBack: cable.count + ferry.count + air.count + coach.count + hk.count + figures.count + winter.count
                                                          + santa.count + taiwanCars.count + herd.count + plain.count + finland.count + tits.count)), "71b8c8010a530da0")
        // Decision 889: the windows after the cable car move by the
        // yellow tit's 4.
        XCTAssertEqual(Self.digest(lamps(movingBack: 0)), "f1759087474b4aa0")
        XCTAssertEqual(Self.digest(pack.headSigns.keys.sorted().map { "\($0) \(pack.headSigns[$0]!)" }), "a436d2fecc70c5aa")
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
