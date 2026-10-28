import XCTest
@testable import GamePresentation

/// Decision 435: the Taiwan Railway local train (key `emu800`) is drawn as
/// #1339's EMU900 too, near and far, as many of them as the EMU900's share
/// of the three fleets' cars; the EMU500 and EMU800 the rest.
final class Map3DEMU900IntegrationTests: XCTestCase {
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

    /// The recipe's lit lamps (decision 449 lights a running car's in the
    /// pack only at its train's ends).
    private func lit(_ model: Map3DModelPack.Model) -> [Map3DVertex] {
        Map3DModelPack.unbaked.models[pack.index(of: model.name)!].vertices.filter(\.glows)
    }

    /// The units each car of a `count`-car train is: the ED at each end,
    /// then the toilet EM, the compressor EP, the SIV EM and the crew EM
    /// over and over, the back half the front half's mirror image, turned
    /// round, but the accessible EP where the front has the crew EM.
    private func nineHundred(_ count: Int) -> [(role: Map3DEMU900.Role, reversed: Bool)] {
        let front: [Map3DEMU900.Role] = [.emToilet, .epCompressor, .emSIV, .emCrew]
        let back: [Map3DEMU900.Role] = [.emToilet, .epCompressor, .emSIV, .epAccessible]
        return (0..<count).map { index in
            let near = min(index, count - 1 - index), reversed = index * 2 >= count
            return (near == 0 ? .ed : (reversed ? back : front)[(near - 1) % 4], reversed)
        }
    }

    // MARK: The set

    func testTheSetsHeadIsTheEMU900sED() throws {
        for far in [false, true] {
            let key = far ? "emu900Far" : "emu900"
            let set = try XCTUnwrap(Map3DTrainSet.named(key), key)
            XCTAssertEqual(set.key, key)
            XCTAssertTrue(set.ownLengths, key)
            let head = try XCTUnwrap(pack.models(forType: key), key).head
            XCTAssertEqual(pack.models[head].name, set.headName)
            XCTAssertTrue(sameShape(try cars(key, 10)[0], Map3DEMU900.model(.ed, light: far)), key)
        }
        XCTAssertEqual(Map3DTrainSet.byKey["emu900"]?.far, "emu900Far")
        XCTAssertNil(Map3DTrainSet.byKey["emu900Far"]?.far)
        XCTAssertFalse(TrainPack.sets.contains("emu900"))
    }

    func testTheTenCarSetIsTheStaticFormation() throws {
        XCTAssertEqual(nineHundred(10).map(\.role), Map3DEMU900.sequence)
        XCTAssertEqual(nineHundred(10).map(\.reversed), Map3DEMU900.placements.map(\.reversed))
        for far in [false, true] {
            let key = far ? "emu900Far" : "emu900"
            let laid = try cars(key, 10)
            XCTAssertEqual(laid.count, 10)
            for (index, placement) in Map3DEMU900.placements.enumerated() {
                XCTAssertTrue(sameShape(laid[index], Map3DEMU900.model(placement.role, reversed: placement.reversed, light: far)),
                              "\(key) car \(index + 1) \(placement.role)")
            }
        }
        let names = try XCTUnwrap(pack.layout(forType: "emu900", count: 10)).map { pack.models[$0.model].name }
        XCTAssertEqual(names, ["set-emu900-head", "set-emu900-car", "set-emu900-panto", "set-emu900-centre", "set-emu900-fourth",
                               "set-emu900-fourthBack", "set-emu900-centreBack", "set-emu900-pantoBack", "set-emu900-carBack", "set-emu900-tail"])
        // Each car its own length, touching the next: 205.56 m in all, as the static formation.
        let layout = try XCTUnwrap(pack.layout(forType: "emu900", count: 10))
        XCTAssertTrue(layout.allSatisfy { $0.gap == 0 })
        for (car, placement) in zip(layout, Map3DEMU900.placements) {
            XCTAssertEqual(car.length, Map3DEMU900.model(placement.role).length, accuracy: 0.001, "\(placement.role)")
        }
    }

    /// Whatever the train's length, from two cars up.
    func testAnyLengthKeepsTheCycleAndMirrorsTheBackHalf() throws {
        for count in 2...13 {
            for far in [false, true] {
                let laid = try cars(far ? "emu900Far" : "emu900", count)
                XCTAssertEqual(laid.count, count)
                for (index, (role, reversed)) in nineHundred(count).enumerated() {
                    XCTAssertTrue(sameShape(laid[index], Map3DEMU900.model(role, reversed: reversed, light: far)),
                                  "\(count) cars, car \(index + 1): \(role) \(reversed ? "reversed" : "")")
                }
            }
        }
        // The counts decision 435 lists.
        XCTAssertEqual(nineHundred(2).map(\.role), [.ed, .ed])
        XCTAssertEqual(nineHundred(4).map(\.role), [.ed, .emToilet, .emToilet, .ed])
        XCTAssertEqual(nineHundred(6).map(\.role), [.ed, .emToilet, .epCompressor, .epCompressor, .emToilet, .ed])
        XCTAssertEqual(nineHundred(8).map(\.role), [.ed, .emToilet, .epCompressor, .emSIV, .emSIV, .epCompressor, .emToilet, .ed])
        XCTAssertEqual(nineHundred(9).map(\.role), [.ed, .emToilet, .epCompressor, .emSIV, .emCrew, .emSIV, .epCompressor, .emToilet, .ed])
        XCTAssertEqual(nineHundred(12).map(\.role), [.ed, .emToilet, .epCompressor, .emSIV, .emCrew, .emToilet,
                                                     .emToilet, .epAccessible, .emSIV, .epCompressor, .emToilet, .ed])
    }

    func testThePantographsAreOnTheEPCarsFacingOut() throws {
        let roof = Map3DEMU900.model(.emSIV).maximum.z + 0.3
        for count in [4, 8, 10, 11] {
            for key in ["emu900", "emu900Far"] {
                for (index, car) in try cars(key, count).enumerated() {
                    XCTAssertEqual(car.maximum.z > roof, nineHundred(count)[index].role.hasPantograph, "\(key), \(count) cars, car \(index + 1)")
                }
            }
        }
        // The ten: cars 3 and 6 in the front half and cars 6 and 8 in the back, the back half's turned round.
        let ten = try cars("emu900", 10)
        func middle(_ car: Int) -> Float {
            let top = ten[car].vertices.filter { $0.z > roof }
            return top.map(\.x).reduce(0, +) / Float(top.count)
        }
        XCTAssertEqual(middle(2), -middle(7), accuracy: 0.01, "the back compressor EP the front one turned round")
        XCTAssertEqual(middle(5), -Map3DEMU900.model(.epAccessible).vertices.filter { $0.z > roof }.map(\.x).reduce(0, +)
                       / Float(Map3DEMU900.model(.epAccessible).vertices.filter { $0.z > roof }.count), accuracy: 0.01)
    }

    func testTheFrontLampsAreWhiteAndTheBackLampsRed() throws {
        for key in ["emu900", "emu900Far"] {
            let laid = try cars(key, 10)
            let head = lit(laid[0]), tail = lit(laid[9])
            XCTAssertFalse(head.isEmpty, key)
            XCTAssertTrue(head.allSatisfy { $0.x > 4 && $0.color == Map3DTrainStyle.headlamp }, "\(key) head")
            XCTAssertFalse(tail.isEmpty, key)
            XCTAssertTrue(tail.allSatisfy { $0.x < -4 && $0.color == Map3DPalette.lantern }, "\(key) tail")
            XCTAssertEqual(head.count, tail.count, key)
            // The model's own lenses, lit in place: no lamp boxes added.
            XCTAssertEqual(laid[0].vertices.count, Map3DEMU900.model(.ed, light: key == "emu900Far").vertices.count, key)
            for index in 1...8 { XCTAssertTrue(lit(laid[index]).isEmpty, "\(key) car \(index + 1)") }
        }
    }

    // MARK: Which trains are EMU900s

    func testTheLocalTrainsSplitThreeWays() {
        // Seven times the number's remainder by 20: 0 to 8 the EMU900, 9 to 14 the EMU500, 15 to 19 the EMU800.
        let expected: [Int: String] = [0: "emu900", 1: "emu900", 2: "emu500", 3: "emu900", 4: "emu900", 5: "emu800",
                                       6: "emu900", 7: "emu500", 8: "emu800", 9: "emu900", 10: "emu500", 11: "emu800",
                                       12: "emu900", 13: "emu500", 14: "emu800", 15: "emu900", 16: "emu500", 17: "emu800",
                                       18: "emu900", 19: "emu500"]
        for (number, key) in expected {
            XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: number), key, "\(number)")
            XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: number + 2_000), key, "\(number + 2_000)")
        }
        // 9, 6 and 5 in every 20, as the fleets' cars (520, 344, 296).
        let counts = Dictionary(grouping: 0..<20) { Map3DTrainSet.variant(of: "emu800", number: $0) }.mapValues(\.count)
        XCTAssertEqual(counts, ["emu900": 9, "emu500": 6, "emu800": 5])
        XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: -3), "emu800")
        // Not locked behind the train pack.
        XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: 1, locked: TrainPack.sets), "emu900")
        for key in ["emu900", "emu500", "taroko", "puyuma"] { XCTAssertEqual(Map3DTrainSet.variant(of: key, number: 1), key, key) }
    }

    /// The player's trains: a train of the local train's type numbered so
    /// is drawn as each of the three.
    func testThePlayersLocalTrainsAreEachOfTheThree() throws {
        for (number, key) in [(1, "emu900"), (2, "emu500"), (5, "emu800")] {
            XCTAssertEqual(Map3DTrainSet.variant(of: "emu800", number: number), key)
            XCTAssertNotNil(pack.layout(forType: key, count: 8), key)
        }
    }

    /// The real trains: by the number at the end of their key; the EMU900
    /// ten cars, the others the line's eight.
    func testTheRealLocalTrainsAreEachOfTheThree() {
        let line = Map3DRealTrains.Formation(key: "emu800", cars: 8)
        for (train, key, count) in [("tra-1106", "emu900", 10), ("tra-1107", "emu500", 8), ("tra-1108", "emu800", 8)] {
            let formation = Map3DRealTrains.formation(of: line, system: "tra", number: Map3DTrainSet.number(ofRealTrain: train))
            XCTAssertEqual(formation, .init(key: key, cars: count), train)
        }
        // The other lines are as they were.
        let railcar = Map3DRealTrains.Formation(key: "dieselRailcar", cars: 3)
        XCTAssertEqual(Map3DRealTrains.formation(of: railcar, system: "tra", number: 1_106), railcar)
        let metro = Map3DRealTrains.Formation(key: "metroC381", cars: 6)
        XCTAssertEqual(Map3DRealTrains.formation(of: metro, system: "trtc", number: 1), .init(key: "metroC341", cars: 6))
    }

    // MARK: Near, far and a box

    private static let units = ["head", "car", "panto", "centre", "fourth", "fourthBack", "centreBack", "pantoBack", "carBack", "tail"]

    func testNearThenFarThenABox() throws {
        XCTAssertEqual(Map3DTrainSet.reach(of: "emu900"), Map3DTrainSet.tramReach)
        for unit in Self.units {
            let near = try XCTUnwrap(pack.index(of: "set-emu900-\(unit)"), unit)
            XCTAssertEqual(pack.model(near, forType: "emu900", count: 10, at: 100), near, unit)
            XCTAssertEqual(pack.model(near, forType: "emu900", count: 10, at: 700), pack.index(of: "set-emu900Far-\(unit)"), unit)
            XCTAssertNil(pack.model(near, forType: "emu900", count: 10, at: 1_000), unit)
        }
    }

    /// A far car is no heavier than a car of the old `emu800` near (#900's
    /// recipe): 2,467 a cab car, 1,592 the others.
    func testTheFarTriangleBudget() throws {
        let old = Map3DTrainSet.multipleUnit("emu800", asset: "01_TRA_modern_3x2-04", body: 0xBBC6C9, band: 0x214F90, face: 0x214F90).build()
        XCTAssertEqual(old.head.triangleCount, 2_467)
        XCTAssertEqual(old.middle?.triangleCount, 1_592)
        for unit in Self.units {
            let far = pack.models[try XCTUnwrap(pack.index(of: "set-emu900Far-\(unit)"), unit)]
            XCTAssertLessThanOrEqual(far.triangleCount, unit == "head" || unit == "tail" ? 2_467 : 1_592, unit)
        }
        let ten = try cars("emu900Far", 10).reduce(0) { $0 + $1.triangleCount }
        XCTAssertLessThanOrEqual(ten, 2 * 2_467 + 8 * 1_592)
    }

    /// Every vertex field, FNV-1a, as `Map3DEMU900Tests` pins them.
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

    /// The EMU900's near and light units are #1339's as they were on main.
    func testTheNearAndLightUnitsAreAsTheyWere() {
        let near: [Map3DEMU900.Role: (Int, String)] = [
            .ed: (9_256, "1c1b03af655d024a"), .emToilet: (5_080, "77beb47b4062c431"), .emSIV: (5_040, "e14b040e50d14de5"),
            .emCrew: (4_992, "fa95f9430ea49585"), .epCompressor: (5_264, "bf2256208d78dbc6"), .epAccessible: (5_176, "2f57b4c48c8c920e"),
        ]
        let light: [Map3DEMU900.Role: (Int, String)] = [
            .ed: (2_188, "490003b967e88746"), .emToilet: (908, "864067e5141ee7"), .emSIV: (880, "2d62dc15b0994ded"),
            .emCrew: (868, "ee2e4bec215ae3a1"), .epCompressor: (1_092, "576cbb355e826acd"), .epAccessible: (1_052, "29ad776ec37250eb"),
        ]
        for role in Map3DEMU900.Role.allCases {
            XCTAssertEqual(Map3DEMU900.model(role).triangleCount, near[role]?.0, "\(role)")
            XCTAssertEqual(hash(Map3DEMU900.model(role)), near[role]?.1, "\(role)")
            XCTAssertEqual(Map3DEMU900.model(role, light: true).triangleCount, light[role]?.0, "\(role) light")
            XCTAssertEqual(hash(Map3DEMU900.model(role, light: true)), light[role]?.1, "\(role) light")
        }
        XCTAssertEqual(pack.models.last(where: { !$0.name.hasPrefix(Map3DTrainLights.prefix) })?.name, Map3DLowFloorBus.routeModel().name, "the route bus is still the last model")
    }

    /// Only on request: the numbers decision 435 gives. `MAP3D_FRAME_REPORT=1`.
    func testTheCost() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        for key in ["emu900", "emu900Far", "emu800", "emu800Far", "emu500", "emu500Far"] {
            for count in [8, 10] {
                let laid = try cars(key, count)
                print("\(key) \(count): cars \(laid.map(\.triangleCount)) total \(laid.reduce(0) { $0 + $1.triangleCount })")
            }
        }
    }
}
