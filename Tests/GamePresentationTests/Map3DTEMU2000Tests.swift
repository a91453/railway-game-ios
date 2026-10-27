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
        XCTAssertLessThanOrEqual(formation.triangleCount, Map3DModelFile.maximumTriangles)
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

    func testStaticModelsAreStillRegistered() {
        let pack = Map3DModelPack.unbaked
        for unit in Map3DTEMU2000.Unit.allCases {
            XCTAssertNotNil(pack.index(of: "temu2000-\(unit.rawValue)"))
        }
        XCTAssertNotNil(pack.index(of: "temu2000-formation"))
    }

    // MARK: The operating Puyuma (decision 426)

    private let pack = Map3DModelPack.unbaked  // the recipes before decision 439's shade

    private func models(_ key: String) throws -> [Map3DModelPack.Model] {
        try XCTUnwrap(pack.layout(forType: key, count: 8)).map { pack.models[$0.model] }
    }

    /// The operating Puyuma is the TEMU2000's units in its own order:
    /// every car carries the unit's vertices, not the scene kit's
    /// `01_TRA_modern_3x2-02`.
    func testTheOperatingPuyumaIsMadeOfTEMU2000Units() throws {
        let cars = try models("puyuma")
        XCTAssertEqual(cars.map(\.name), ["set-puyuma-head", "set-puyuma-car", "set-puyuma-panto", "set-puyuma-centre",
                                          "set-puyuma-centre", "set-puyuma-pantoBack", "set-puyuma-car", "set-puyuma-tail"])
        // The units in the static formation's order, front first.
        let expected: [Map3DTEMU2000.Unit] = Map3DTEMU2000.order.reversed()
        // The cab units and two lamps (24 triangles) each; the others as they are.
        for (index, unit) in expected.enumerated() {
            let unitModel = Map3DTEMU2000.model(unit)
            let lamps = unit == .leading || unit == .trailing ? 24 : 0
            XCTAssertEqual(cars[index].triangleCount, unitModel.triangleCount + lamps, "car \(index + 1) \(unit)")
            if lamps == 0 && Map3DTEMU2000.rotations[Map3DTEMU2000.order.count - 1 - index] == 0 {
                XCTAssertEqual(cars[index].vertices, unitModel.vertices, "car \(index + 1) \(unit)")
            }
        }
        XCTAssertEqual(cars[0].vertices.prefix(Map3DTEMU2000.model(.leading).vertices.count), Map3DTEMU2000.model(.leading).vertices[...])
        XCTAssertEqual(cars[7].vertices.prefix(Map3DTEMU2000.model(.trailing).vertices.count), Map3DTEMU2000.model(.trailing).vertices[...])
        XCTAssertNotEqual(cars[1].vertices, Map3DTEMU1000.model(.middle).vertices)
        // Each car is as long as its unit, laid end to end like the Taroko's.
        let layout = try XCTUnwrap(pack.layout(forType: "puyuma", count: 8))
        XCTAssertEqual(layout.count, 8)
        XCTAssertTrue(layout.allSatisfy { $0.gap == 0 })
        XCTAssertEqual(layout.reduce(0) { $0 + $1.length }, 163.76, accuracy: 0.05)
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

    /// White lamps lit at the front's real end, red at the back's; none on
    /// the cars between.
    func testTheLampsAreAtTheRealEndsOfTheCabCars() throws {
        for key in ["puyuma", "puyumaFar"] {
            let cars = try models(key)
            for index in 1...6 { XCTAssertFalse(cars[index].vertices.contains(where: \.glows), "\(key) car \(index + 1)") }
            let front = cars[0].vertices.filter(\.glows), back = cars[7].vertices.filter(\.glows)
            // Two lamps of twelve triangles each.
            XCTAssertEqual(front.count, 72, key)
            XCTAssertEqual(back.count, 72, key)
            // Their faces in the lamp's colour (a box shades its other sides).
            XCTAssertTrue(front.contains { $0.color == Map3DTrainStyle.headlamp }, key)
            XCTAssertTrue(back.contains { $0.color == Map3DPalette.lantern }, key)
            let tip = Map3DTEMU2000.model(.leading, far: key == "puyumaFar").maximum.x
            XCTAssertTrue(front.allSatisfy { $0.x > tip }, "\(key): in front of the nose, not inside it")
            XCTAssertTrue(back.allSatisfy { $0.x < -tip }, key)
            XCTAssertTrue(front.allSatisfy { abs($0.y) < 0.5 && $0.z > 0.7 && $0.z < 1.5 }, "\(key): on the face")
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
            XCTAssertTrue(far.vertices.contains { $0.color == Map3DTEMU2000.teal }, "\(unit): the waist stripe")
            XCTAssertTrue(far.vertices.contains { $0.color == Map3DTEMU2000.glass }, "\(unit)")
        }
        XCTAssertEqual(Map3DTEMU2000.model(.tep, far: true).name, "temu2000-tep-far")
    }

    /// The light set is lighter than the near one, and the eight cars
    /// cost no more than the Taroko's, near and far (decision 420).
    func testTheEightCarSetCostsAboutAsMuchAsTheTaroko() throws {
        func triangles(_ key: String) throws -> Int { try models(key).reduce(0) { $0 + $1.triangleCount } }
        let near = try triangles("puyuma"), far = try triangles("puyumaFar")
        XCTAssertEqual(near, 14_860)
        XCTAssertEqual(far, 5_500)
        XCTAssertLessThan(far * 5, near * 2)
        XCTAssertLessThan(Double(near), Double(try triangles("taroko")) * 1.10)
        XCTAssertLessThanOrEqual(far, try triangles("tarokoFar") + 50)
    }

    /// The near units are as #1292 made them: the far switch only adds.
    func testTheNearUnitsAreUnchanged() {
        XCTAssertEqual(Map3DTEMU2000.Unit.allCases.map { Map3DTEMU2000.model($0).triangleCount }, [2394, 1624, 1776, 1636, 2346])
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
        // Measured on main before decision 426 (FNV-1a over every vertex's bits).
        XCTAssertEqual(hash, 8599538914451188106)
    }
}
