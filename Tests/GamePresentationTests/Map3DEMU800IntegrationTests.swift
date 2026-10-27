import XCTest
@testable import GamePresentation

/// Decision 432: the Taiwan Railway local train (key `emu800`) runs #1320's
/// EMU800 units, near and far, and half of them (the odd-numbered) are
/// #1312's EMU500, near and far.
final class Map3DEMU800IntegrationTests: XCTestCase {
    private let pack = Map3DModelPack.standard

    private func cars(_ key: String, _ count: Int) throws -> [Map3DModelPack.Model] {
        try XCTUnwrap(pack.layout(forType: key, count: count), key).map { pack.models[$0.model] }
    }

    /// The same triangles in the same places; a cab car's lamp lenses are
    /// lit in place, so their colours are not compared.
    private func sameShape(_ car: Map3DModelPack.Model, _ unit: Map3DModelPack.Model) -> Bool {
        car.vertices.count == unit.vertices.count
            && zip(car.vertices, unit.vertices).allSatisfy { $0.x == $1.x && $0.y == $1.y && $0.z == $1.z }
    }

    private func lit(_ model: Map3DModelPack.Model) -> [Map3DVertex] { model.vertices.filter(\.glows) }

    // MARK: EMU800

    /// The units each car of a `count`-car train is: the cab car at the
    /// front, then EMA, EP, EMB over and over, the back half the front
    /// half's mirror image, turned round.
    private func eightHundred(_ count: Int) -> [(role: Map3DEMU800.Role, reversed: Bool)] {
        let cycle: [Map3DEMU800.Role] = [.ema, .ep, .emb]
        return (0..<count).map { index in
            let near = min(index, count - 1 - index)
            return (near == 0 ? .ed : cycle[(near - 1) % 3], index * 2 >= count)
        }
    }

    func testTheEightCarSetIsTheStaticFormation() throws {
        XCTAssertEqual(eightHundred(8).map(\.role), Map3DEMU800.sequence)
        XCTAssertEqual(eightHundred(8).map(\.reversed), Map3DEMU800.placements.map(\.reversed))
        for far in [false, true] {
            let key = far ? "emu800Far" : "emu800"
            let set = try XCTUnwrap(Map3DTrainSet.named(key))
            XCTAssertTrue(set.ownLengths, key)
            let laid = try cars(key, 8)
            XCTAssertEqual(laid.count, 8, key)
            for (index, (role, reversed)) in eightHundred(8).enumerated() {
                XCTAssertTrue(sameShape(laid[index], Map3DEMU800.model(role, reversed: reversed, light: far)), "\(key) car \(index + 1) \(role)")
            }
            // Not the scene kit's `01_TRA_modern_3x2-04`.
            XCTAssertEqual(laid[0].triangleCount, Map3DEMU800.model(.ed, light: far).triangleCount, key)
        }
        XCTAssertEqual(Map3DTrainSet.byKey["emu800"]?.far, "emu800Far")
        let names = try XCTUnwrap(pack.layout(forType: "emu800", count: 8)).map { pack.models[$0.model].name }
        XCTAssertEqual(names, ["set-emu800-head", "set-emu800-car", "set-emu800-panto", "set-emu800-centre",
                               "set-emu800-centreBack", "set-emu800-pantoBack", "set-emu800-carBack", "set-emu800-tail"])
    }

    /// Each car is as long as its unit, laid end to end like the Puyuma's.
    func testEachCarIsItsOwnLength() throws {
        let layout = try XCTUnwrap(pack.layout(forType: "emu800", count: 8))
        XCTAssertTrue(layout.allSatisfy { $0.gap == 0 })
        let expected = eightHundred(8).map { Map3DEMU800.model($0.role, reversed: $0.reversed).length }
        for (car, length) in zip(layout, expected) { XCTAssertEqual(car.length, length, accuracy: 0.001) }
        // The cab cars reach on to their couplers.
        XCTAssertEqual(layout[0].length, 21.51, accuracy: 0.01)
        XCTAssertEqual(layout[1].length, 20.3, accuracy: 0.01)
    }

    /// Whatever the train's length, from two cars up: a cab car at each
    /// end, the cars between in the cycle, the back half turned round.
    func testAnyLengthKeepsTheCycleAndMirrorsTheBackHalf() throws {
        for count in 2...13 {
            for far in [false, true] {
                let laid = try cars(far ? "emu800Far" : "emu800", count)
                XCTAssertEqual(laid.count, count)
                for (index, (role, reversed)) in eightHundred(count).enumerated() {
                    XCTAssertTrue(sameShape(laid[index], Map3DEMU800.model(role, reversed: reversed, light: far)),
                                  "\(count) cars, car \(index + 1): \(role) \(reversed ? "reversed" : "")")
                }
            }
        }
        // The front half cycles on: ten cars are ED EMA EP EMB EMA, then the mirror; an odd count has the next car in the middle.
        XCTAssertEqual(eightHundred(10).map(\.role), [.ed, .ema, .ep, .emb, .ema, .ema, .emb, .ep, .ema, .ed])
        XCTAssertEqual(eightHundred(7).map(\.role), [.ed, .ema, .ep, .emb, .ep, .ema, .ed])
    }

    func testThePantographsAreOnTheEPCarsOnly() throws {
        for count in [4, 8, 11] {
            for key in ["emu800", "emu800Far"] {
                let laid = try cars(key, count)
                for (index, car) in laid.enumerated() {
                    XCTAssertEqual(car.maximum.z > 5, eightHundred(count)[index].role == .ep, "\(key), \(count) cars, car \(index + 1)")
                }
            }
        }
        // The eight: cars 3 and 6.
        let eight = try cars("emu800", 8)
        let front = eight[2].vertices.filter { $0.z > 5 }, back = eight[5].vertices.filter { $0.z > 5 }
        XCTAssertFalse(front.isEmpty)
        XCTAssertFalse(back.isEmpty)
        // The back one is the front one turned round: the mirror image.
        XCTAssertEqual(front.map(\.x).reduce(0, +) / Float(front.count), -back.map(\.x).reduce(0, +) / Float(back.count), accuracy: 0.01)
    }

    /// The cab's two lamps: white at the front, red at the back; none on
    /// the cars between.
    func testTheFrontLampsAreWhiteAndTheBackLampsRed() throws {
        for key in ["emu800", "emu800Far"] {
            let laid = try cars(key, 8)
            let head = lit(laid[0]), tail = lit(laid[7])
            XCTAssertFalse(head.isEmpty, key)
            XCTAssertTrue(head.allSatisfy { $0.x > 4 && $0.color == Map3DTrainStyle.headlamp }, "\(key) head")
            XCTAssertFalse(tail.isEmpty, key)
            XCTAssertTrue(tail.allSatisfy { $0.x < -4 && $0.color == Map3DPalette.lantern }, "\(key) tail")
            for index in 1...6 { XCTAssertTrue(lit(laid[index]).isEmpty, "\(key) car \(index + 1)") }
            // The same lenses at both ends of the head, one end lit.
            XCTAssertEqual(head.count, tail.count, key)
        }
    }

    // MARK: The local trains three ways (decision 435)

    /// Decision 435 replaced the odd and even numbers with the three
    /// fleets' shares (``Map3DTrainSet/localTrain(number:)``); the EMU500 is
    /// still one of them, the EMU800 another.
    func testSomeLocalTrainsAreEMU500AndSomeEMU800() {
        for number in [2, 7, 1_107, -1] { XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: number), "emu500", "\(number)") }
        for number in [5, 8, 1_108, -3] { XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: number), "emu800", "\(number)") }
        // The real trains' number is the one at the end of their key.
        XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: Map3DTrainSet.number(ofRealTrain: "tra-1107")), "emu500")
        XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: Map3DTrainSet.number(ofRealTrain: "tra-1108")), "emu800")
        // Not locked behind the train pack, and no other train is touched.
        XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: 7, locked: TrainPack.sets), "emu500")
        XCTAssertFalse(TrainPack.sets.contains("emu500"))
        // (Decision 433: the odd-numbered metro is the C341 now, `Map3DC341IntegrationTests`.)
        for key in ["taroko", "puyuma", "dieselExpress", "pushPull", "emu500", ""] {
            XCTAssertEqual(Map3DTrainSet.variant(of: key, number: 1), key == "pushPull" ? "pushPullE1000" : key, key)
        }
        XCTAssertEqual(Map3DTrainSet.variant(of: "emu500", number: 2), "emu500")
        XCTAssertEqual(Map3DTrainSet.variant(of: "highSpeed", number: 1), "n700sG", "decision 408 is as it was")
    }

    /// The units each car of a `count`-car EMU500 is: the EMC at the front,
    /// then EP, ET, EM over and over (the EM turned round, its cab toward
    /// the car behind it), the back half the front half's mirror image,
    /// turned round: two four-car units coupled cab to cab.
    private func fiveHundred(_ count: Int) -> [(unit: Map3DEMU500.Unit, turned: Bool)] {
        let cycle: [Map3DEMU500.Unit] = [.ep, .et, .em]
        return (0..<count).map { index in
            let near = min(index, count - 1 - index)
            let unit: Map3DEMU500.Unit = near == 0 ? .emc : cycle[(near - 1) % 3]
            return (unit, (unit == .em) != (index * 2 >= count))
        }
    }

    func testTheEightCarEMU500IsTwoFourCarUnitsCoupledCabToCab() throws {
        // One unit as the static formation has it: EMC EP ET EM, the EM turned round.
        XCTAssertEqual(fiveHundred(8).prefix(4).map(\.unit), Map3DEMU500.order)
        XCTAssertEqual(fiveHundred(8).prefix(4).map(\.turned), Map3DEMU500.rotations.map { $0 != 0 })
        // The other unit: the first one reversed, the two EMs' cabs facing each other.
        XCTAssertEqual(fiveHundred(8).suffix(4).map(\.unit), Map3DEMU500.order.reversed())
        XCTAssertEqual(fiveHundred(8).map(\.turned), [false, false, false, true, false, true, true, true])
        for far in [false, true] {
            let key = far ? "emu500Far" : "emu500"
            let set = try XCTUnwrap(Map3DTrainSet.named(key))
            XCTAssertTrue(set.ownLengths, key)
            let laid = try cars(key, 8)
            XCTAssertEqual(laid.count, 8)
            for (index, (unit, turned)) in fiveHundred(8).enumerated() {
                let model = Map3DEMU500.model(unit, far: far)
                XCTAssertTrue(sameShape(laid[index], turned ? model.turned : model), "\(key) car \(index + 1) \(unit)")
            }
        }
        XCTAssertEqual(Map3DTrainSet.byKey["emu500"]?.far, "emu500Far")
        let names = try XCTUnwrap(pack.layout(forType: "emu500", count: 8)).map { pack.models[$0.model].name }
        XCTAssertEqual(names, ["set-emu500-head", "set-emu500-panto", "set-emu500-centre", "set-emu500-car",
                               "set-emu500-carBack", "set-emu500-centreBack", "set-emu500-pantoBack", "set-emu500-tail"])
        // Each car its own length, touching the next.
        let layout = try XCTUnwrap(pack.layout(forType: "emu500", count: 8))
        XCTAssertTrue(layout.allSatisfy { $0.gap == 0 })
        for (car, (unit, _)) in zip(layout, fiveHundred(8)) {
            XCTAssertEqual(car.length, Map3DEMU500.model(unit).length, accuracy: 0.001, "\(unit)")
        }
    }

    func testAnyLengthOfEMU500KeepsTheCycleAndMirrorsTheBackHalf() throws {
        for count in 2...13 {
            for far in [false, true] {
                let laid = try cars(far ? "emu500Far" : "emu500", count)
                XCTAssertEqual(laid.count, count)
                for (index, (unit, turned)) in fiveHundred(count).enumerated() {
                    let model = Map3DEMU500.model(unit, far: far)
                    XCTAssertTrue(sameShape(laid[index], turned ? model.turned : model), "\(count) cars, car \(index + 1): \(unit)")
                }
            }
        }
        // The cab cars are the ends: the EMC at both, turned round at the back.
        XCTAssertEqual(fiveHundred(6).map(\.unit), [.emc, .ep, .et, .et, .ep, .emc])
    }

    func testTheEMU500PantographIsOnTheEPCarsOnly() throws {
        let roof = Map3DEMU500.model(.et).maximum.z + 0.3
        for count in [4, 8, 11] {
            for key in ["emu500", "emu500Far"] {
                for (index, car) in try cars(key, count).enumerated() {
                    XCTAssertEqual(car.maximum.z > roof, fiveHundred(count)[index].unit == .ep, "\(key), \(count) cars, car \(index + 1)")
                }
            }
        }
        // The eight: cars 2 and 7, the pantograph on the half of the car away from the cab at the end.
        let eight = try cars("emu500", 8)
        let front = eight[1].vertices.filter { $0.z > roof }, back = eight[6].vertices.filter { $0.z > roof }
        XCTAssertFalse(front.isEmpty)
        XCTAssertFalse(back.isEmpty)
        XCTAssertLessThan(front.map(\.x).reduce(0, +) / Float(front.count), 0, "the front EP's pantograph at the back of its car")
        XCTAssertGreaterThan(back.map(\.x).reduce(0, +) / Float(back.count), 0, "turned round with it")
    }

    func testTheEMU500LampsAreWhiteAtTheFrontAndRedAtTheBack() throws {
        for key in ["emu500", "emu500Far"] {
            let laid = try cars(key, 8)
            let head = lit(laid[0]), tail = lit(laid[7])
            XCTAssertFalse(head.isEmpty, key)
            XCTAssertTrue(head.allSatisfy { $0.x > 4 && $0.color == Map3DTrainStyle.headlamp }, "\(key) head")
            XCTAssertFalse(tail.isEmpty, key)
            XCTAssertTrue(tail.allSatisfy { $0.x < -4 && $0.color == Map3DPalette.lantern }, "\(key) tail")
            XCTAssertEqual(head.count, tail.count, key)
            // The cabs coupled in the middle stay dark.
            for index in 1...6 { XCTAssertTrue(lit(laid[index]).isEmpty, "\(key) car \(index + 1)") }
        }
    }

    // MARK: Near, far and a box

    func testNearThenFarThenABox() throws {
        for (code, count) in [("emu800", 8), ("emu500", 8)] {
            XCTAssertEqual(Map3DTrainSet.reach(of: code), Map3DTrainSet.tramReach, code)
            for unit in ["head", "car", "tail", "panto", "centre", "carBack", "pantoBack", "centreBack"] {
                guard let near = pack.index(of: "set-\(code)-\(unit)") else { XCTFail("\(code) \(unit)"); continue }
                XCTAssertEqual(pack.model(near, forType: code, count: count, at: 100), near, "\(code) \(unit)")
                XCTAssertEqual(pack.model(near, forType: code, count: count, at: 700), pack.index(of: "set-\(code)Far-\(unit)"), "\(code) \(unit)")
                XCTAssertNil(pack.model(near, forType: code, count: count, at: 1_000), "\(code) \(unit)")
            }
        }
    }

    /// The far cars are the near cars lighter: the same box, the same
    /// paint, a good deal fewer triangles.
    func testTheFarCarsAreTheSameCarsLighter() throws {
        for code in ["emu800", "emu500"] {
            for unit in ["head", "car", "tail", "panto", "centre", "carBack", "pantoBack", "centreBack"] {
                let near = pack.models[try XCTUnwrap(pack.index(of: "set-\(code)-\(unit)"))]
                let far = pack.models[try XCTUnwrap(pack.index(of: "set-\(code)Far-\(unit)"))]
                // The EMU800's light cars leave out the gangway frames, 9 cm at the ends.
                XCTAssertEqual(far.minimum.x, near.minimum.x, accuracy: 0.1, "\(code) \(unit)")
                XCTAssertEqual(far.maximum.x, near.maximum.x, accuracy: 0.1, "\(code) \(unit)")
                XCTAssertEqual(far.maximum.z, near.maximum.z, accuracy: 0.05, "\(code) \(unit)")
                XCTAssertEqual(far.minimum.z, 0, accuracy: 0.05, "\(code) \(unit)")
                XCTAssertLessThan(far.triangleCount * 2, near.triangleCount * 1, "\(code) \(unit): \(far.triangleCount) of \(near.triangleCount)")
                // The livery is there (a box's underside is a shade of its colour).
                let colours = Set(far.vertices.map(\.color))
                for livery in code == "emu800" ? [Map3DEMU800.navy, Map3DEMU800.yellow, Map3DEMU800.bodyColor] : [Map3DEMU500.accent, Map3DEMU500.silver] {
                    XCTAssertTrue(colours.contains(livery), "\(code) \(unit)")
                }
            }
        }
    }

    /// Every vertex field, FNV-1a, to pin a model as it was on main.
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

    /// The EMU800 as #1320 made it, near and its existing `far`: only the
    /// `light` version is added to the file. (Hashes and triangle counts
    /// of main's models.)
    func testTheEMU800NearAndFarCarsAreAsTheyWere() {
        let near: [Map3DEMU800.Role: (Int, String)] = [.ed: (11_506, "4963906d22906b97"), .ema: (5_200, "72af84ac4ade481e"),
                                                       .ep: (5_372, "dbe7c2914b0c1326"), .emb: (5_212, "15c759e0812d1166")]
        let far: [Map3DEMU800.Role: (Int, String)] = [.ed: (6_046, "ff7c370fbbfd852b"), .ema: (2_916, "eff481f4a1e1d6e"),
                                                      .ep: (3_088, "7cfb04aea34d81dc"), .emb: (2_928, "ff6706ba6e09e056")]
        for role in Map3DEMU800.Role.allCases {
            let n = Map3DEMU800.model(role), f = Map3DEMU800.model(role, far: true)
            XCTAssertEqual(n.triangleCount, near[role]?.0, "\(role)")
            XCTAssertEqual(hash(n), near[role]?.1, "\(role)")
            XCTAssertEqual(f.triangleCount, far[role]?.0, "\(role) far")
            XCTAssertEqual(hash(f), far[role]?.1, "\(role) far")
            XCTAssertEqual(hash(Map3DEMU800.model(role, light: false)), near[role]?.1, "\(role)")
        }
    }

    /// The EMU500's near cars are #1312's as they were: only a far version
    /// is added to the file.
    func testTheEMU500NearCarsAreAsTheyWere() {
        let expected: [Map3DEMU500.Unit: (Int, String)] = [.emc: (4_548, "c622d4729f9bf28e"), .ep: (2_944, "9f7fc99095debe4a"),
                                                           .et: (2_840, "bbc20c3603682bd5"), .em: (4_548, "c622d4729f9bf28e")]
        for unit in Map3DEMU500.Unit.allCases {
            XCTAssertEqual(Map3DEMU500.model(unit).triangleCount, expected[unit]?.0, "\(unit)")
            XCTAssertEqual(hash(Map3DEMU500.model(unit)), expected[unit]?.1, "\(unit)")
        }
        XCTAssertEqual(hash(Map3DEMU500.formation()), "6c52052f859d9cd1")
        XCTAssertEqual(Map3DEMU500.model(.emc).vertices, Map3DEMU500.model(.emc, far: false).vertices)
        XCTAssertEqual(Map3DEMU500.formation().triangleCount, Map3DEMU500.order.reduce(0) { $0 + Map3DEMU500.model($1).triangleCount })
        XCTAssertNotNil(pack.index(of: "emu500-formation"))
        XCTAssertEqual(pack.models.last?.name, Map3DLowFloorBus.routeModel().name, "the route bus is still the last model")
    }

    // MARK: Triangles (decision 432)

    func testTheTriangleBudget() throws {
        func total(_ key: String, count: Int = 8) throws -> Int { try cars(key, count).reduce(0) { $0 + $1.triangleCount } }
        // The cars of the old set: #900's recipe, near and far, as main drew it.
        let oldNearCar = Map3DTrainSet.multipleUnit("emu800", asset: "01_TRA_modern_3x2-04", body: 0xBBC6C9, band: 0x214F90, face: 0x214F90)
            .build().middle?.triangleCount ?? 0
        XCTAssertGreaterThan(oldNearCar, 0)
        // The old head was 2,467 triangles and the old middle car 1,592: a far car is no heavier.
        let oldHead = Map3DTrainSet.multipleUnit("emu800", asset: "01_TRA_modern_3x2-04", body: 0xBBC6C9, band: 0x214F90, face: 0x214F90)
            .build().head.triangleCount
        XCTAssertEqual(oldHead, 2_467)
        XCTAssertEqual(oldNearCar, 1_592)
        for key in ["emu800Far", "emu500Far"] {
            for unit in ["head", "car", "panto", "centre", "tail", "carBack", "pantoBack", "centreBack"] {
                let model = pack.models[try XCTUnwrap(pack.index(of: "set-\(key)-\(unit)"), "\(key) \(unit)")]
                // The EMU500's EM car has a cab too, so it is compared with the old cab car.
                let cab = unit == "head" || unit == "tail" || key == "emu500Far" && unit.hasPrefix("car")
                XCTAssertLessThanOrEqual(model.triangleCount, cab ? oldHead : oldNearCar, "\(key) \(unit)")
            }
        }
        let eight = (try total("emu800"), try total("emu800Far"), try total("emu500"), try total("emu500Far"))
        XCTAssertLessThan(eight.1, eight.0)
        XCTAssertLessThan(eight.3, eight.2)
        // A whole far train is no heavier than the old near one (14,486).
        XCTAssertLessThanOrEqual(eight.1, 2 * oldHead + 6 * oldNearCar)
        XCTAssertLessThanOrEqual(eight.3, 2 * oldHead + 6 * oldNearCar)
    }

    /// Only on request: the numbers decision 432 gives. `MAP3D_FRAME_REPORT=1`.
    func testTheCost() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let old = Map3DTrainSet.multipleUnit("emu800", asset: "01_TRA_modern_3x2-04", body: 0xBBC6C9, band: 0x214F90, face: 0x214F90).build()
        let oldFar = Map3DTrainSet.multipleUnit("emu800Far", asset: "01_TRA_modern_3x2-04", body: 0xBBC6C9, band: 0x214F90, face: 0x214F90, detail: .far).build()
        print("old emu800 near: head \(old.head.triangleCount) car \(old.middle?.triangleCount ?? 0) tail \(old.tail?.triangleCount ?? 0)")
        print("old emu800 far: head \(oldFar.head.triangleCount) car \(oldFar.middle?.triangleCount ?? 0) tail \(oldFar.tail?.triangleCount ?? 0)")
        let oldTotal = old.head.triangleCount + 6 * (old.middle?.triangleCount ?? 0) + (old.tail?.triangleCount ?? 0)
        print("old emu800 eight cars near \(oldTotal)")
        for key in ["emu800", "emu800Far", "emu500", "emu500Far"] {
            let laid = try cars(key, 8)
            print("\(key): cars \(laid.map(\.triangleCount)) total \(laid.reduce(0) { $0 + $1.triangleCount }) x\(Double(laid.reduce(0) { $0 + $1.triangleCount }) / Double(oldTotal))")
        }
        for role in Map3DEMU800.Role.allCases { print("EMU800 \(role): near \(Map3DEMU800.model(role).triangleCount) far \(Map3DEMU800.model(role, far: true).triangleCount) light \(Map3DEMU800.model(role, light: true).triangleCount)") }
        for unit in Map3DEMU500.Unit.allCases { print("EMU500 \(unit): near \(Map3DEMU500.model(unit).triangleCount) far \(Map3DEMU500.model(unit, far: true).triangleCount)") }
    }
}
