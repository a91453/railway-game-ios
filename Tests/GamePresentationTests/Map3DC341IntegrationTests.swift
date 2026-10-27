import XCTest
@testable import GamePresentation

/// Decision 433: the Taipei Metro's high-capacity train (key `metroC381`,
/// the player's A, B, L and D metros and the real trains of Taipei's
/// lines) runs #1323's C341 units, near and far, on half its trains (the
/// odd-numbered); the other half and every other city's metro stay the
/// C381.
final class Map3DC341IntegrationTests: XCTestCase {
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

    /// The units each car of a `count`-car train is: a DM at the front, the
    /// rear DM at the back, T and M between them over and over, the back
    /// half the front half's mirror image.
    private func units(_ count: Int) -> [Map3DC341.Unit] {
        let cycle: [Map3DC341.Unit] = [.t, .m]
        return (0..<count).map { index in
            if index == 0 { return .dm }
            if index == count - 1 { return .rear }
            return cycle[(min(index, count - 1 - index) - 1) % 2]
        }
    }

    // MARK: The set

    func testTheSixCarSetIsTheStaticFormation() throws {
        XCTAssertEqual(units(6), Map3DC341.arrangement)
        for far in [false, true] {
            let key = far ? "metroC341Far" : "metroC341"
            let set = try XCTUnwrap(Map3DTrainSet.named(key))
            XCTAssertTrue(set.ownLengths, key)
            XCTAssertNil(set.fixedCars, key)
            let laid = try cars(key, 6)
            XCTAssertEqual(laid.count, 6, key)
            for (index, unit) in Map3DC341.arrangement.enumerated() {
                XCTAssertTrue(sameShape(laid[index], Map3DC341.model(unit, far: far)), "\(key) car \(index + 1) \(unit)")
            }
        }
        XCTAssertEqual(Map3DTrainSet.byKey["metroC341"]?.far, "metroC341Far")
        XCTAssertNil(Map3DTrainSet.byKey["metroC341Far"]?.far)
        let names = try XCTUnwrap(pack.layout(forType: "metroC341", count: 6)).map { pack.models[$0.model].name }
        XCTAssertEqual(names, ["set-metroC341-head", "set-metroC341-car", "set-metroC341-centre", "set-metroC341-centre",
                               "set-metroC341-car", "set-metroC341-tail"])
        // Not the scene kit's C381 (`02_HSR_MRT_3x2-02`).
        XCTAssertEqual(try cars("metroC341", 6)[0].triangleCount, Map3DC341.model(.dm).triangleCount)
    }

    /// Every other length, two cars up: a DM at each end, T and M between.
    func testAnyLengthKeepsTheCycleAndMirrorsTheBackHalf() throws {
        for count in 2...13 {
            for far in [false, true] {
                let laid = try cars(far ? "metroC341Far" : "metroC341", count)
                XCTAssertEqual(laid.count, count)
                for (index, unit) in units(count).enumerated() {
                    XCTAssertTrue(sameShape(laid[index], Map3DC341.model(unit, far: far)), "\(count) cars, car \(index + 1): \(unit)")
                }
            }
        }
        XCTAssertEqual(units(2), [.dm, .rear])
        XCTAssertEqual(units(3), [.dm, .t, .rear])
        XCTAssertEqual(units(4), [.dm, .t, .t, .rear])
        XCTAssertEqual(units(5), [.dm, .t, .m, .t, .rear])
        XCTAssertEqual(units(7), [.dm, .t, .m, .t, .m, .t, .rear])
    }

    /// Each car is as long as its unit, laid end to end.
    func testEachCarIsItsOwnLength() throws {
        for key in ["metroC341", "metroC341Far"] {
            let layout = try XCTUnwrap(pack.layout(forType: key, count: 6))
            XCTAssertTrue(layout.allSatisfy { $0.gap == 0 }, key)
            for (car, unit) in zip(layout, Map3DC341.arrangement) {
                XCTAssertEqual(car.length, Map3DC341.model(unit, far: key.hasSuffix("Far")).length, accuracy: 0.001, "\(key) \(unit)")
                XCTAssertTrue((23.0...24.0).contains(car.length), "\(key) \(unit): \(car.length) m")
            }
        }
    }

    /// The third rail: no pantograph on any car, and the units' own
    /// colours, not the line's.
    func testNoPantographAndTheUnitsOwnColours() throws {
        for key in ["metroC341", "metroC341Far"] {
            for count in [2, 6, 9] {
                for car in try cars(key, count) {
                    XCTAssertLessThan(car.maximum.z, 3.8, "\(key), \(count) cars")
                    XCTAssertTrue(car.vertices.allSatisfy { $0.color >> 24 == 0xFF }, "\(key), \(count) cars: the band is not the line's")
                }
            }
            let set = try XCTUnwrap(Map3DTrainSet.named(key))
            XCTAssertTrue(set.pantographCars.isEmpty, key)
            XCTAssertNil(pack.index(of: set.pantographName), key)
            XCTAssertNil(pack.index(of: set.pantographBackName), key)
        }
    }

    /// The lamp lenses: white at the front, red at the back; none on the
    /// cars between.
    func testTheFrontLampsAreWhiteAndTheBackLampsRed() throws {
        for key in ["metroC341", "metroC341Far"] {
            let laid = try cars(key, 6)
            let head = lit(laid[0]), tail = lit(laid[5])
            XCTAssertFalse(head.isEmpty, key)
            XCTAssertTrue(head.allSatisfy { $0.x > 4 && $0.color == Map3DTrainStyle.headlamp }, "\(key) head")
            XCTAssertFalse(tail.isEmpty, key)
            XCTAssertTrue(tail.allSatisfy { $0.x < -4 && $0.color == Map3DPalette.lantern }, "\(key) tail")
            for index in 1...4 { XCTAssertTrue(lit(laid[index]).isEmpty, "\(key) car \(index + 1)") }
        }
    }

    // MARK: Which trains

    func testTheOddNumberedTaipeiMetrosAreC341() {
        for number in [1, 3, 7, 1_107, 2_461, -3] {
            for key in ["metroC381", "A", "B", "D"] { XCTAssertEqual(Map3DTrainSet.variant(of: key, number: number), "metroC341", "\(key) \(number)") }
        }
        for number in [0, 2, 8, 1_108, -2] {
            for key in ["metroC381", "A", "B", "D"] { XCTAssertEqual(Map3DTrainSet.variant(of: key, number: number), key, "\(key) \(number)") }
        }
        // The linear-motor metro: the C341 while the train pack is locked (it is drawn as the C381), its own look once it is unlocked.
        XCTAssertEqual(Map3DTrainSet.variant(of: "L", number: 1, locked: TrainPack.sets), "metroC341")
        XCTAssertEqual(Map3DTrainSet.variant(of: "L", number: 2, locked: TrainPack.sets), "L")
        XCTAssertEqual(Map3DTrainSet.variant(of: "L", number: 1, locked: []), "L")
        XCTAssertEqual(Map3DTrainSet.variant(of: "L", number: 1, locked: ["pushPullE1000"]), "L")
        // Not locked behind the train pack, and no other train is touched: the light metro, the people mover, the Wenhu car.
        XCTAssertFalse(TrainPack.sets.contains("metroC341"))
        XCTAssertEqual(Map3DTrainSet.variant(of: "A", number: 1, locked: TrainPack.sets), "metroC341")
        for key in ["C", "APM", "wenhu", "greenTram", "taroko", "puyuma", "dieselExpress", "metroC341", ""] {
            XCTAssertEqual(Map3DTrainSet.variant(of: key, number: 1), key, key)
        }
        XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: 1), "emu500", "decision 432 is as it was")
        XCTAssertEqual(Map3DTrainSet.variant(of: "highSpeed", number: 1), "n700sG", "decision 408 is as it was")
    }

    /// The real trains: Taipei's lines (but the Wenhu and Circular lines,
    /// which are not the C381's set) by their run's number; Kaohsiung's,
    /// Taoyuan's and Taichung's metro trains are the C381's whatever it is.
    func testOnlyTaipeisRealMetroTrainsAreC341() {
        for number in [1, 2, 3, 4, 1_107, 1_108] {
            let key = Map3DRealTrains.variantKey(system: "trtc", key: "metroC381", number: number)
            XCTAssertEqual(key, number % 2 != 0 ? "metroC341" : "metroC381", "trtc \(number)")
            for system in ["krtc", "tymc", "tmrt"] {
                XCTAssertEqual(Map3DRealTrains.variantKey(system: system, key: "metroC381", number: number), "metroC381", "\(system) \(number)")
            }
            // The other lines' sets are as they were.
            XCTAssertEqual(Map3DRealTrains.variantKey(system: "trtc", key: "wenhu", number: number), "wenhu")
            XCTAssertEqual(Map3DRealTrains.variantKey(system: "krtc", key: "greenTram", number: number), "greenTram")
            XCTAssertEqual(Map3DRealTrains.variantKey(system: "tra", key: "emu800", number: number), number % 2 != 0 ? "emu500" : "emu800")
            XCTAssertEqual(Map3DRealTrains.variantKey(system: "thsr", key: "highSpeed", number: number), number % 2 != 0 ? "n700sG" : "highSpeed")
        }
        // The formations themselves are as they were: the same key, the same cars.
        XCTAssertEqual(Map3DTrainSet.number(ofRealTrain: "trtc-1107"), 1_107)
    }

    // MARK: Near, far and a box

    func testNearThenFarThenABox() throws {
        XCTAssertEqual(Map3DTrainSet.reach(of: "metroC341"), Map3DTrainSet.tramReach)
        for unit in ["head", "car", "centre", "tail"] {
            let near = try XCTUnwrap(pack.index(of: "set-metroC341-\(unit)"), unit)
            XCTAssertEqual(pack.model(near, forType: "metroC341", count: 6, at: 100), near, unit)
            XCTAssertEqual(pack.model(near, forType: "metroC341", count: 6, at: 700), pack.index(of: "set-metroC341Far-\(unit)"), unit)
            XCTAssertNil(pack.model(near, forType: "metroC341", count: 6, at: 1_000), unit)
        }
        // The C381 of the even-numbered is as far as it was.
        XCTAssertEqual(Map3DTrainSet.reach(of: "metroC381"), Map3DTrains.modelReach)
    }

    /// The far cars are the near cars lighter: the same box, the same
    /// paint, a good deal fewer triangles.
    func testTheFarCarsAreTheSameCarsLighter() throws {
        for unit in Map3DC341.Unit.allCases {
            let near = Map3DC341.model(unit), far = Map3DC341.model(unit, far: true)
            // The far car leaves out the low coupler step, 11 cm at the end.
            XCTAssertEqual(far.minimum.x, near.minimum.x, accuracy: 0.15, "\(unit)")
            XCTAssertEqual(far.maximum.x, near.maximum.x, accuracy: 0.15, "\(unit)")
            XCTAssertEqual(far.minimum.y, near.minimum.y, accuracy: 0.05, "\(unit)")
            XCTAssertEqual(far.maximum.y, near.maximum.y, accuracy: 0.05, "\(unit)")
            XCTAssertEqual(far.maximum.z, near.maximum.z, accuracy: 0.05, "\(unit)")
            XCTAssertEqual(far.minimum.z, 0, accuracy: 0.05, "\(unit)")
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount * 1, "\(unit): \(far.triangleCount) of \(near.triangleCount)")
            // The livery is there: the white body, the blue band, the dark panes' frames.
            let colours = Set(far.vertices.map(\.color))
            for livery in [Map3DC341.body, Map3DC341.accent, Map3DC341.mask, Map3DC341.glass] {
                XCTAssertTrue(colours.contains(livery), "\(unit)")
            }
        }
        // The rear car's tail lamps are red, near and far.
        for far in [false, true] {
            let rear = Map3DC341.model(.rear, far: far)
            XCTAssertTrue(rear.vertices.contains { $0.color == Map3DC341.tailLamp && $0.x < -11 }, "rear far \(far)")
            XCTAssertEqual(rear.name, far ? "c341-rear-far" : "c341-rear")
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

    /// The C341's near cars are #1323's as they were: only a far version is
    /// added to the file. (Hashes and triangle counts of main's models.)
    func testTheNearCarsAreAsTheyWere() {
        let expected: [Map3DC341.Unit: (Int, String)] = [.dm: (3_894, "1d3126772903596f"), .t: (3_306, "3c5d71adac8d5bed"),
                                                         .m: (3_318, "efeebcf7d2605071"), .rear: (3_894, "5c62cacb91cb8ea2")]
        for unit in Map3DC341.Unit.allCases {
            XCTAssertEqual(Map3DC341.model(unit).triangleCount, expected[unit]?.0, "\(unit)")
            XCTAssertEqual(hash(Map3DC341.model(unit)), expected[unit]?.1, "\(unit)")
            XCTAssertEqual(Map3DC341.model(unit, far: false).vertices, Map3DC341.model(unit).vertices, "\(unit)")
        }
        XCTAssertEqual(Map3DC341.formation().triangleCount, 21_036)
        XCTAssertEqual(hash(Map3DC341.formation()), "d7474750ed37008f")
        // The four static units are still in the pack, and nothing else of the C341's: the sets' cars are their own models.
        for unit in Map3DC341.Unit.allCases { XCTAssertNotNil(pack.index(of: "c341-" + unit.rawValue), "\(unit)") }
        XCTAssertNil(pack.index(of: "c341-dm-far"))
        XCTAssertEqual(pack.models.last?.name, Map3DLowFloorBus.routeModel().name, "the route bus is still the last model")
    }

    // MARK: Triangles (decision 433)

    func testTheTriangleBudget() throws {
        // The cars of the old set: #900's recipe, as main drew it.
        let old = Map3DTrainSet.multipleUnit("metroC381", asset: "02_HSR_MRT_3x2-02", lineColoured: true).build()
        let oldCab = old.head.triangleCount, oldMiddle = old.middle?.triangleCount ?? 0
        XCTAssertEqual(oldCab, 2_360)
        XCTAssertEqual(old.tail?.triangleCount, 2_360)
        XCTAssertEqual(oldMiddle, 1_800)
        // A far car is no heavier than the old near one: the cab cars against its cab car, T and M against its middle car.
        for (unit, ceiling) in [("head", oldCab), ("tail", oldCab), ("car", oldMiddle), ("centre", oldMiddle)] {
            let model = pack.models[try XCTUnwrap(pack.index(of: "set-metroC341Far-\(unit)"), unit)]
            XCTAssertLessThanOrEqual(model.triangleCount, ceiling, "\(unit): \(model.triangleCount)")
        }
        func total(_ key: String, count: Int = 6) throws -> Int { try cars(key, count).reduce(0) { $0 + $1.triangleCount } }
        XCTAssertLessThan(try total("metroC341Far"), try total("metroC341"))
        // A whole far train is no heavier than the old near one (11,920).
        XCTAssertLessThanOrEqual(try total("metroC341Far"), 2 * oldCab + 4 * oldMiddle)
        // The lit lamps are the same triangles, recoloured.
        XCTAssertEqual(try total("metroC341"), Map3DC341.arrangement.reduce(0) { $0 + Map3DC341.model($1).triangleCount })
    }

    /// Only on request: the numbers decision 433 gives. `MAP3D_FRAME_REPORT=1`.
    func testTheCost() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        let old = Map3DTrainSet.multipleUnit("metroC381", asset: "02_HSR_MRT_3x2-02", lineColoured: true).build()
        let oldTotal = 2 * old.head.triangleCount + 4 * (old.middle?.triangleCount ?? 0)
        print("old metroC381 near: head \(old.head.triangleCount) car \(old.middle?.triangleCount ?? 0) tail \(old.tail?.triangleCount ?? 0) six cars \(oldTotal)")
        for key in ["metroC341", "metroC341Far"] {
            let laid = try cars(key, 6)
            let sum = laid.reduce(0) { $0 + $1.triangleCount }
            print("\(key): cars \(laid.map(\.triangleCount)) total \(sum) x\(Double(sum) / Double(oldTotal))")
        }
        for unit in Map3DC341.Unit.allCases { print("C341 \(unit): near \(Map3DC341.model(unit).triangleCount) far \(Map3DC341.model(unit, far: true).triangleCount)") }
    }
}
