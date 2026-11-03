import XCTest
@testable import GamePresentation

/// Decision 560: the Taiwan Railway local train (key `emu800`) is drawn as
/// #1730's EMU700 too, near and far, as many of them as the EMU700's share
/// of the four fleets' cars.
final class Map3DEMU700IntegrationTests: XCTestCase {
    private var pack: Map3DModelPack { .standard }

    private func cars(_ key: String, _ count: Int) throws -> [Map3DModelPack.Model] {
        try XCTUnwrap(pack.layout(forType: key, count: count), key).map { pack.models[$0.model] }
    }

    /// The same triangles in the same places (a cab car's lamp lenses are
    /// lit in place, so colours are not compared).
    private func sameShape(_ car: Map3DModelPack.Model, _ unit: Map3DModelPack.Model) -> Bool {
        car.vertices.count == unit.vertices.count
            && zip(car.vertices, unit.vertices).allSatisfy { $0.x == $1.x && $0.y == $1.y && $0.z == $1.z }
    }

    /// The units each car of a `count`-car train is: the EMC at each end,
    /// then EP, ET and EM over and over, the back half the front's mirror
    /// image, every car of it turned round; the middle car of an odd count
    /// the front's.
    private func sevenHundred(_ count: Int) -> [(role: Map3DEMU700.Role, turned: Bool)] {
        let cycle: [Map3DEMU700.Role] = [.ep, .et, .em]
        return (0..<count).map { index in
            let near = min(index, count - 1 - index)
            return (near == 0 ? .emc : cycle[(near - 1) % 3], index * 2 >= count)
        }
    }

    private func unit(_ role: Map3DEMU700.Role, far: Bool, turned: Bool) -> Map3DModelPack.Model {
        let model = Map3DEMU700.model(role, far: far)
        return turned ? model.turned : model
    }

    // MARK: The set

    func testTheSetsHeadIsTheEMU700sEMC() throws {
        for far in [false, true] {
            let key = far ? "emu700Far" : "emu700"
            let set = try XCTUnwrap(Map3DTrainSet.named(key), key)
            XCTAssertEqual(set.key, key)
            XCTAssertTrue(set.ownLengths, key)
            XCTAssertNil(set.fixedCars, "the player's trains are as long as their cars")
            XCTAssertTrue(sameShape(try cars(key, 8)[0], Map3DEMU700.model(.emc, far: far)), key)
        }
        XCTAssertEqual(Map3DTrainSet.byKey["emu700"]?.far, "emu700Far")
        XCTAssertNil(Map3DTrainSet.byKey["emu700Far"]?.far)
        XCTAssertFalse(TrainPack.sets.contains("emu700"))
        XCTAssertTrue(Map3DTrainMaterial.isStainless("set-emu700-head"))
        XCTAssertTrue(Map3DTrainMaterial.isStainless("set-emu700Far-car"))
    }

    /// Eight cars are #1730's static formation (`docs/art/tra-emu700/configuration.json`):
    /// EMC EP ET EM | EM ET EP EMC, the back four turned round once.
    func testTheEightCarSetIsTheStaticFormation() throws {
        XCTAssertEqual(sevenHundred(8).map(\.role), [.emc, .ep, .et, .em, .em, .et, .ep, .emc])
        XCTAssertEqual(sevenHundred(8).map(\.turned), [false, false, false, false, true, true, true, true])
        XCTAssertEqual(Map3DEMU700.formationCars, 8)
        for far in [false, true] {
            let laid = try cars(far ? "emu700Far" : "emu700", 8)
            for (index, car) in sevenHundred(8).enumerated() {
                XCTAssertTrue(sameShape(laid[index], unit(car.role, far: far, turned: car.turned)), "\(far) \(index)")
            }
        }
    }

    /// Every other count: the cycle, the mirror image, the odd middle car the front's.
    func testOtherCounts() throws {
        let roles: [Int: [Map3DEMU700.Role]] = [
            1: [.emc], 2: [.emc, .emc], 3: [.emc, .ep, .emc], 4: [.emc, .ep, .ep, .emc],
            5: [.emc, .ep, .et, .ep, .emc], 6: [.emc, .ep, .et, .et, .ep, .emc],
            7: [.emc, .ep, .et, .em, .et, .ep, .emc],
            10: [.emc, .ep, .et, .em, .ep, .ep, .em, .et, .ep, .emc],
            12: [.emc, .ep, .et, .em, .ep, .et, .et, .ep, .em, .et, .ep, .emc],
        ]
        for (count, expected) in roles {
            XCTAssertEqual(sevenHundred(count).map(\.role), expected, "\(count)")
            for far in [false, true] {
                let laid = try cars(far ? "emu700Far" : "emu700", count)
                XCTAssertEqual(laid.count, count)
                for (index, car) in sevenHundred(count).enumerated() {
                    XCTAssertTrue(sameShape(laid[index], unit(car.role, far: far, turned: car.turned)), "\(count) \(far) \(index)")
                }
            }
        }
    }

    /// Each car at its own length, touching the next: 163.286 m for eight.
    func testTheCarsAtTheirOwnLengths() throws {
        let layout = try XCTUnwrap(pack.layout(forType: "emu700", count: 8))
        let length = layout.reduce(Float(0)) { $0 + $1.length }
        XCTAssertEqual(length, 2 * Map3DEMU700.pitch(.emc) + 6 * Map3DEMU700.pitch(.ep), accuracy: 0.7)
    }

    /// The pantographs on the EPs (the second and seventh of eight), raised.
    func testThePantographsAreOnTheEPs() throws {
        let laid = try cars("emu700", 8)
        let raised = laid.indices.filter { laid[$0].maximum.z > 4.8 }
        XCTAssertEqual(raised, [1, 6])
    }

    /// The lamps: the head car's lenses lit at its front, the tail car's at
    /// its back, no middle car with any (in the recipe, before decision 449
    /// lights each frame's ends).
    func testTheLampsAtTheTwoEndsOnly() throws {
        for key in ["emu700", "emu700Far"] {
            let laid = try cars(key, 8)
            func glowing(_ model: Map3DModelPack.Model) -> [Map3DVertex] {
                Map3DModelPack.unbaked.models[pack.index(of: model.name)!].vertices.filter(\.glows)
            }
            let head = glowing(laid[0]), tail = glowing(laid[7])
            XCTAssertFalse(head.isEmpty, key)
            XCTAssertFalse(tail.isEmpty, key)
            XCTAssertTrue(head.allSatisfy { $0.x > 0 }, key)
            XCTAssertTrue(tail.allSatisfy { $0.x < 0 }, key)
            for car in laid[1...6] { XCTAssertTrue(glowing(car).isEmpty, "\(key) \(car.name)") }
        }
    }

    // MARK: Near, far and a box

    private static let units = ["head", "car", "panto", "centre", "centreBack", "pantoBack", "carBack", "tail"]

    func testNearThenFarThenABox() throws {
        XCTAssertEqual(Map3DTrainSet.reach(of: "emu700"), Map3DTrainSet.tramReach)
        for unit in Self.units {
            let near = try XCTUnwrap(pack.index(of: "set-emu700-\(unit)"), unit)
            XCTAssertEqual(pack.model(near, forType: "emu700", count: 8, at: 100), near, unit)
            XCTAssertEqual(pack.model(near, forType: "emu700", count: 8, at: 700), pack.index(of: "set-emu700Far-\(unit)"), unit)
            XCTAssertNil(pack.model(near, forType: "emu700", count: 8, at: 1_000), unit)
        }
    }

    /// A far car is under half its near car (decision 420's rule; the
    /// dispatch said the EMU700's own `far` units, so not decision 432's
    /// lighter bar of the old near car), and the far train under
    /// `budgets.json`'s 120,000 at twelve cars.
    func testTheFarTriangleBudget() throws {
        for unit in Self.units {
            let near = pack.models[try XCTUnwrap(pack.index(of: "set-emu700-\(unit)"), unit)]
            let far = pack.models[try XCTUnwrap(pack.index(of: "set-emu700Far-\(unit)"), unit)]
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, unit)
        }
        XCTAssertEqual(try cars("emu700", 8).reduce(0) { $0 + $1.triangleCount }, 63_664)
        XCTAssertEqual(try cars("emu700Far", 8).reduce(0) { $0 + $1.triangleCount }, 31_384)
        XCTAssertLessThanOrEqual(try cars("emu700Far", 12).reduce(0) { $0 + $1.triangleCount }, 120_000)
        XCTAssertLessThanOrEqual(try cars("emu700", 12).reduce(0) { $0 + $1.triangleCount }, 240_000)
    }

    /// Every vertex field, FNV-1a, as the other integration tests pin them.
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

    /// The EMU700's units are #1730's as they were on main (the recipe is
    /// not touched; `hashes.lock.json` pins the studies' pack hashes too).
    func testTheUnitsAreAsTheyWere() {
        for role in Map3DEMU700.Role.allCases {
            for far in [false, true] {
                let unit = Map3DEMU700.model(role, far: far)
                XCTAssertEqual("\(unit.triangleCount) \(hash(unit))", Self.unitPins["\(role.rawValue)\(far ? "-far" : "")"], "\(role) \(far)")
            }
        }
    }

    private static let unitPins: [String: String] = [
        "emc": "13740 3438b3170939e460", "emc-far": "6728 d5d48cfdbb796820",
        "ep": "6104 68de81d19f121a61", "ep-far": "3040 3903c00f746f0d94",
        "et": "5988 5eef50de72d9248a", "et-far": "2964 ab96c22df321b3a7",
        "em": "6000 38e78fc6efcd97e2", "em-far": "2960 b3e53ab87df8b715",
    ]

    // MARK: Which trains are EMU700s

    /// The real trains: an EMU700 eight cars, whatever the line's count.
    func testTheRealEMU700IsEightCars() {
        for cars in [4, 6, 8, 10] {
            let line = Map3DRealTrains.Formation(key: "emu800", cars: cars)
            XCTAssertEqual(Map3DRealTrains.formation(of: line, system: "tra", number: 1_111), .init(key: "emu700", cars: 8), "\(cars)")
            XCTAssertEqual(Map3DRealTrains.formation(of: line, system: "tra", number: 1_108), .init(key: "emu800", cars: cars), "\(cars)")
        }
    }

    /// Numbers one after another are never three of one kind in a row.
    func testNoRunOfOneKind() {
        let kinds = (0..<200).map { Map3DTrainSet.localTrain(number: $0) }
        for start in 0..<(kinds.count - 2) {
            XCTAssertFalse(kinds[start] == kinds[start + 1] && kinds[start + 1] == kinds[start + 2], "\(start)")
        }
    }

    func testTheShowcase() throws {
        let entry = try XCTUnwrap(Map3DShowcase.catalog.first { $0.key == "emu700" })
        XCTAssertEqual(entry.defaultCars, 8)
        XCTAssertNotNil(pack.layout(forType: "emu700", count: entry.defaultCars))
    }

    /// Only on request: the numbers decision 560 gives. `MAP3D_FRAME_REPORT=1`.
    func testTheCost() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        for role in Map3DEMU700.Role.allCases {
            for far in [false, true] {
                let unit = Map3DEMU700.model(role, far: far)
                print("unit \(role.rawValue)\(far ? "-far" : ""): \(unit.triangleCount) \(hash(unit))")
            }
        }
        for key in ["emu700", "emu700Far"] {
            for count in [8, 10] {
                let laid = try cars(key, count)
                print("\(key) \(count): cars \(laid.map(\.triangleCount)) total \(laid.reduce(0) { $0 + $1.triangleCount })")
            }
        }
    }
}
