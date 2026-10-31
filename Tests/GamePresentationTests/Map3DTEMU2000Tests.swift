import XCTest
@testable import GamePresentation

final class Map3DTEMU2000Tests: XCTestCase {
    func testFiveIndependentUnitsAndSourcedEightCarAssembly() {
        let units = Map3DTEMU2000.Unit.allCases
        XCTAssertEqual(units.count, 5)
        XCTAssertEqual(Map3DTEMU2000.order, [
            .trailing, .tema, .tep, .temb, .temb, .tep, .tema, .leading
        ])
        XCTAssertEqual(Map3DTEMU2000.centres.count, 8)
        XCTAssertEqual(Map3DTEMU2000.rotations.count, 8)
        XCTAssertEqual(Map3DTEMU2000.rotations[5], .pi, accuracy: 0.0001,
                       "Second TEP pantograph must face toward the far TED")
        XCTAssertTrue(Map3DTEMU2000.rotations.enumerated().allSatisfy { $0.offset == 5 || $0.element == 0 })
        XCTAssertEqual(Map3DTEMU2000.formationLength, 168.390, accuracy: 0.001)
        XCTAssertEqual(Map3DTEMU2000.leadingOverallLength, 22.095, accuracy: 0.001)
        XCTAssertEqual(Map3DTEMU2000.intermediateOverallLength, 20.700, accuracy: 0.001)

        let parts = units.map(Map3DTEMU2000.model)
        let formation = Map3DTEMU2000.formation()
        XCTAssertEqual(formation.triangleCount,
                       Map3DTEMU2000.order.reduce(0) { $0 + Map3DTEMU2000.model($1).triangleCount })
        // Revision-2's eight cars pass one model file's limit; the export
        // tools write the formation as an assembly of the units instead
        // (`tools/temu2000/assembly-spec.json`).
        XCTAssertGreaterThan(formation.triangleCount, Map3DModelFile.maximumTriangles)
        XCTAssertEqual(formation.minimum.z, 0, accuracy: 0.012)
        // 168.39 m is the coupled train envelope; visible carbody ends can
        // stop at the 21.745 m TED body length inside the coupler envelope.
        XCTAssertGreaterThan(formation.length, 167.9)
        XCTAssertLessThanOrEqual(formation.length, Map3DTEMU2000.formationLength + 0.05)
        XCTAssertTrue(parts.allSatisfy { abs($0.minimum.z) < 0.012 })
        XCTAssertGreaterThan(Map3DTEMU2000.model(.tep).maximum.z,
                             Map3DTEMU2000.model(.tema).maximum.z + 0.2)
        XCTAssertNotEqual(Map3DTEMU2000.model(.leading).vertices,
                          Map3DTEMU1000.model(.leading).vertices,
                          "TEMU2000 must have its own native shape")
    }

    func testStaticModelsAreStillRegistered() throws {
        // K1-1: in the tools' pack, not the game's.
        let pack = Map3DModelPack.unbakedStudies
        XCTAssertNil(Map3DModelPack.unbaked.index(of: "temu2000-formation"))
        for unit in Map3DTEMU2000.Unit.allCases {
            for far in [false, true] {
                let name = "temu2000-\(unit.rawValue)" + (far ? "-far" : "")
                let index = try XCTUnwrap(pack.index(of: name), name)
                // Decision 484: the studies are the operating units, their
                // lamps drawn unlit.
                XCTAssertEqual(pack.models[index].vertices, Map3DTEMU2000.model(unit, far: far).vertices, name)
                XCTAssertFalse(pack.models[index].vertices.contains(where: \.glows), name)
            }
        }
        XCTAssertNotNil(pack.index(of: "temu2000-formation"))
    }

    // MARK: The operating Puyuma (decisions 426, 484)

    private var pack: Map3DModelPack { .unbaked }  // the recipes before decision 439's shade

    private func models(_ key: String) throws -> [Map3DModelPack.Model] {
        try XCTUnwrap(pack.layout(forType: key, count: 8)).map { pack.models[$0.model] }
    }

    /// The operating Puyuma is the TEMU2000's units in its own order:
    /// every car carries the unit's vertices, not the scene kit's
    /// `01_TRA_modern_3x2-02`; the cab cars' with their lenses lit
    /// (decision 484), nothing added.
    func testTheOperatingPuyumaIsMadeOfTEMU2000Units() throws {
        let cars = try models("puyuma")
        XCTAssertEqual(cars.map(\.name), ["set-puyuma-head", "set-puyuma-car", "set-puyuma-panto", "set-puyuma-centre",
                                          "set-puyuma-centre", "set-puyuma-pantoBack", "set-puyuma-car", "set-puyuma-tail"])
        // The units in the static formation's order, front first.
        let expected: [Map3DTEMU2000.Unit] = Map3DTEMU2000.order.reversed()
        for (index, unit) in expected.enumerated() {
            let cab = unit == .leading || unit == .trailing
            let unitModel = Map3DTEMU2000.model(unit, far: false, lamps: cab)
            XCTAssertEqual(cars[index].triangleCount, Map3DTEMU2000.model(unit).triangleCount, "car \(index + 1) \(unit)")
            if Map3DTEMU2000.rotations[Map3DTEMU2000.order.count - 1 - index] == 0 {
                XCTAssertEqual(cars[index].vertices, unitModel.vertices, "car \(index + 1) \(unit)")
            }
        }
        XCTAssertNotEqual(cars[1].vertices, Map3DTEMU1000.model(.middle).vertices)
        // Each car is as long as its unit, laid end to end like the Taroko's.
        let layout = try XCTUnwrap(pack.layout(forType: "puyuma", count: 8))
        XCTAssertEqual(layout.count, 8)
        XCTAssertTrue(layout.allSatisfy { $0.gap == 0 })
        XCTAssertEqual(layout.reduce(0) { $0 + $1.length }, 165.26, accuracy: 0.05)
        // Whatever the train's length, the formation is the eight units.
        XCTAssertEqual(try XCTUnwrap(pack.layout(forType: "puyuma", count: 3)).count, 8)
    }

    /// The pantographs are on the two TEP cars (3 and 6), the second one
    /// turned round as in the static formation: both point outwards.
    func testThePantographsAreOnTheTwoTEPCarsPointingOutwards() throws {
        let cars = try models("puyuma")
        let roof = Map3DTEMU2000.model(.tema).maximum.z + 0.2
        for (index, car) in cars.enumerated() {
            let high = car.vertices.filter { $0.z > roof }
            XCTAssertEqual(!high.isEmpty, index == 2 || index == 5, "car \(index + 1)")
        }
        let front = cars[2].vertices.filter { $0.z > roof }, back = cars[5].vertices.filter { $0.z > roof }
        XCTAssertGreaterThan(front.map(\.x).reduce(0, +) / Float(front.count), 5, "the front TEP's pantograph toward the front")
        XCTAssertLessThan(back.map(\.x).reduce(0, +) / Float(back.count), -5, "the back TEP's toward the back")
        XCTAssertEqual(cars[2].maximum.z, Map3DTEMU2000.model(.tep).maximum.z, accuracy: 0.001)
        XCTAssertEqual(cars[5].maximum.z, Map3DTEMU2000.model(.tep).maximum.z, accuracy: 0.001)
    }

    /// Decision 484: each cab car's own lenses lit, on its nose: the
    /// upper lamps and the pods' outer lamps white, the pods' inner markers
    /// red; none on the cars between. Decision 449's lights find both kinds
    /// at the nose end of each cab car.
    func testTheLampsAreTheCabCarsOwnLenses() throws {
        for key in ["puyuma", "puyumaFar"] {
            let cars = try models(key)
            for index in 1...6 { XCTAssertFalse(cars[index].vertices.contains(where: \.glows), "\(key) car \(index + 1)") }
            for (index, nose) in [(0, Float(1)), (7, Float(-1))] {
                let lit = cars[index].vertices.filter(\.glows)
                XCTAssertFalse(lit.isEmpty, "\(key) car \(index + 1)")
                XCTAssertEqual(Set(lit.map(\.color)), [Map3DTrainStyle.headlamp, Map3DPalette.lantern], "\(key) car \(index + 1)")
                // On the sloped face, between the pods and the forehead.
                XCTAssertTrue(lit.allSatisfy { $0.x * nose > 8 && $0.z > 2.1 && $0.z < 3.7 && abs($0.y) < 1.0 },
                              "\(key) car \(index + 1): on the face")
                // Left and right alike.
                XCTAssertEqual(lit.filter { $0.y > 0 }.count, lit.filter { $0.y < 0 }.count, "\(key) car \(index + 1)")
                let lights = Map3DTrainLights.car(cars[index])
                let lamps = lights.lamps(atFront: nose > 0)
                XCTAssertFalse(lamps.head.isEmpty, "\(key) car \(index + 1): headlamps")
                XCTAssertFalse(lamps.tail.isEmpty, "\(key) car \(index + 1): tail lamps")
            }
        }
    }

    // MARK: Its light version (decision 426)

    func testNearWithin500MetresThenFarThenABox() {
        XCTAssertEqual(Map3DTrainSet.reach(of: "puyuma"), Map3DTrainSet.tramReach)
        XCTAssertTrue(Map3DTrainSet.nearOnly.contains("puyuma"))
        for unit in ["head", "car", "panto", "centre", "pantoBack", "tail"] {
            let near = pack.index(of: "set-puyuma-\(unit)")
            XCTAssertNotNil(near, unit)
            guard let near else { continue }
            XCTAssertEqual(pack.model(near, forType: "puyuma", count: 8, at: 100), near, unit)
            XCTAssertEqual(pack.model(near, forType: "puyuma", count: 8, at: 700), pack.index(of: "set-puyumaFar-\(unit)"), unit)
            XCTAssertNotNil(pack.index(of: "set-puyumaFar-\(unit)"), unit)
            XCTAssertNil(pack.model(near, forType: "puyuma", count: 8, at: 1_000), unit)
        }
    }

    func testTheFarUnitsAreTheSameCarsLighter() {
        for unit in Map3DTEMU2000.Unit.allCases {
            let near = Map3DTEMU2000.model(unit), far = Map3DTEMU2000.model(unit, far: true)
            // The same box, the tyres on the rail: a train laid from the
            // near cars fits the far ones.
            XCTAssertEqual(far.minimum.x, near.minimum.x, accuracy: 0.02, "\(unit)")
            XCTAssertEqual(far.maximum.x, near.maximum.x, accuracy: 0.02, "\(unit)")
            XCTAssertEqual(far.maximum.z, near.maximum.z, accuracy: 0.05, "\(unit)")
            XCTAssertEqual(far.minimum.z, 0, accuracy: 0.012, "\(unit)")
            // Under 45 % of the triangles in the near car's own colours.
            XCTAssertLessThan(far.triangleCount * 20, near.triangleCount * 9, "\(unit): \(far.triangleCount) of \(near.triangleCount)")
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), "\(unit)")
            XCTAssertTrue(far.vertices.contains { $0.color == Map3DTEMU2000.band }, "\(unit): the waist band")
            XCTAssertTrue(far.vertices.contains { $0.color == Map3DTEMU2000.glass }, "\(unit)")
        }
        XCTAssertEqual(Map3DTEMU2000.model(.tep, far: true).name, "temu2000-tep-far")
    }

    /// The light set is lighter than the near one, and both are within
    /// the rolling-stock budget (`tools/train-models/budgets.json`):
    /// under 20,000 triangles a car near, under half the near car far.
    /// Decision 484: revision-2's cab noses cost more than the Taroko's
    /// (about 1.8 times the eight cars), still far under the budget.
    func testTheEightCarSetIsWithinTheBudget() throws {
        let near = try models("puyuma"), far = try models("puyumaFar")
        let nearTriangles = near.reduce(0) { $0 + $1.triangleCount }, farTriangles = far.reduce(0) { $0 + $1.triangleCount }
        XCTAssertEqual(nearTriangles, 25_040)
        XCTAssertEqual(farTriangles, 10_400)
        XCTAssertLessThan(farTriangles * 20, nearTriangles * 9)
        for (n, f) in zip(near, far) {
            XCTAssertLessThanOrEqual(n.triangleCount, 20_000, n.name)
            XCTAssertLessThan(f.triangleCount * 2, n.triangleCount, f.name)
        }
        XCTAssertLessThanOrEqual(farTriangles, 120_000)
    }

    /// The near units are #1456's revision-2 (decision 484).
    func testTheNearUnitsAreUnchanged() {
        XCTAssertEqual(Map3DTEMU2000.Unit.allCases.map { Map3DTEMU2000.model($0).triangleCount }, [6980, 1800, 1952, 1812, 6932])
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ word: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) { hash = (hash ^ UInt64((word >> UInt32(shift)) & 0xFF)) &* 0x100_0000_01b3 }
        }
        for unit in Map3DTEMU2000.Unit.allCases {
            for v in Map3DTEMU2000.model(unit).vertices {
                for f in [v.x, v.y, v.z, v.nx, v.ny, v.nz] { mix(f.bitPattern) }
                mix(v.color)
            }
        }
        // Measured on #1456's revision-2 (FNV-1a over every vertex's bits).
        XCTAssertEqual(hash, 7293891619195826796)
    }
}
