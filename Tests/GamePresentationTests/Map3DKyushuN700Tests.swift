import XCTest
@testable import GamePresentation

/// Decision 977: the Kyushu Shinkansen's N700 series, the owner's old
/// cars cut into faces of the palette's colours.
final class Map3DKyushuN700Tests: XCTestCase {
    func testBothUnitsDecodeAtTheRealSize() throws {
        for unit in Map3DKyushuN700.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushuN700.model(unit), unit.rawValue)
            XCTAssertEqual(model.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(model.maximum.y - model.minimum.y, 3.36, accuracy: 0.02, "\(unit.rawValue) is 3.36 m wide")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.03, unit.rawValue)
            XCTAssertTrue(Map3DKyushuN700.registration.triangles.contains(model.triangleCount), unit.rawValue)
        }
        // The roof 3.60 m up; the cab carries its aerial a little over it.
        XCTAssertEqual(try XCTUnwrap(Map3DKyushuN700.model(.middle)).maximum.z, 3.60, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(Map3DKyushuN700.model(.cab)).maximum.z, 3.82, accuracy: 0.02)
    }

    /// The wheels stand on standard-gauge rails: 1,435 mm between the
    /// rails' inner faces, the wheels' outer faces a little wider.
    func testTheWheelsStandOnStandardGauge() throws {
        for unit in Map3DKyushuN700.Unit.allCases {
            let low = try XCTUnwrap(Map3DKyushuN700.model(unit)).vertices.filter { $0.z < 0.05 }
            XCTAssertFalse(low.isEmpty, unit.rawValue)
            XCTAssertTrue(low.allSatisfy { $0.color == Map3DPalette.dark }, "\(unit.rawValue): only the wheels reach the rail")
            let widest = low.map { abs($0.y) }.max() ?? 0
            XCTAssertGreaterThan(widest, 1.435 / 2, unit.rawValue)
            XCTAssertLessThan(widest, 1.435 / 2 + 0.2, unit.rawValue)
        }
    }

    /// The real train's colours (the owner, 2026-11-25): a pale white-blue
    /// body down to the skirts' foot, and under the windows a navy line
    /// with a thin gold line along each edge. No colour that is not the
    /// palette's.
    func testTheBodyIsWhiteBlueWithTheNavyAndGoldLine() throws {
        XCTAssertEqual(Map3DPalette.kyushuWhiteBlue, Map3DColor.rgb(0xD8E5EB))
        XCTAssertEqual(Map3DPalette.kyushuNavy, Map3DColor.rgb(0x214168))
        XCTAssertEqual(Map3DPalette.kyushuGold, Map3DColor.rgb(0x897455))
        let colours: Set<UInt32> = [
            Map3DPalette.kyushuWhiteBlue, Map3DPalette.kyushuNavy, Map3DPalette.kyushuGold, Map3DTrainStyle.glass,
            Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern,
        ]
        XCTAssertEqual(Set(Map3DKyushuN700.meshPalette), colours)
        for unit in Map3DKyushuN700.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushuN700.model(unit))
            XCTAssertTrue(Set(model.vertices.map(\.color)).isSubset(of: colours), unit.rawValue)
            let side = model.vertices.filter { abs($0.x) < 5 && abs($0.y) > 1.5 }
            let body = side.filter { $0.color == Map3DPalette.kyushuWhiteBlue }.map(\.z)
            XCTAssertGreaterThan(body.max() ?? 0, 2.6, unit.rawValue)
            XCTAssertLessThan(body.min() ?? 9, 0.5, "\(unit.rawValue): the skirts the body's colour")
            let navy = side.filter { $0.color == Map3DPalette.kyushuNavy }.map(\.z)
            let gold = side.filter { $0.color == Map3DPalette.kyushuGold }.map(\.z)
            let glass = side.filter { $0.color == Map3DTrainStyle.glass }.map(\.z)
            XCTAssertFalse(navy.isEmpty, unit.rawValue)
            XCTAssertFalse(gold.isEmpty, unit.rawValue)
            XCTAssertFalse(glass.isEmpty, unit.rawValue)
            // The gold lines 3 cm each, the navy line 9 cm between them.
            let foot = try XCTUnwrap(gold.min()), top = try XCTUnwrap(gold.max())
            XCTAssertEqual(try XCTUnwrap(navy.min()) - foot, 0.03, accuracy: 0.006, unit.rawValue)
            XCTAssertEqual(top - (try XCTUnwrap(navy.max())), 0.03, accuracy: 0.006, unit.rawValue)
            XCTAssertEqual(top - foot, 0.153, accuracy: 0.01, unit.rawValue)
            XCTAssertLessThan(top, glass.min() ?? 0, "\(unit.rawValue): the line under the windows")
        }
    }

    /// The glass is marked face by face, so the pack guesses none; the
    /// cab's lamps are at its nose and the middle car has none.
    func testTheGlassAndTheLampsAreMarked() throws {
        for unit in Map3DKyushuN700.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushuN700.model(unit))
            XCTAssertTrue(Map3DTrainMaterial.marksOwnGlass(model), unit.rawValue)
        }
        let cab = try XCTUnwrap(Map3DKyushuN700.model(.cab))
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let xs = cab.vertices.filter { $0.color == lens }.map(\.x)
            XCTAssertFalse(xs.isEmpty)
            XCTAssertGreaterThan(xs.min() ?? 0, Map3DKyushuN700.Unit.cab.pitch * 0.2, "the lamps on the nose")
        }
        // The windscreen over the nose, on the car's centre line too.
        XCTAssertFalse(cab.vertices.filter { $0.color == Map3DTrainStyle.glass && $0.x > 6 && abs($0.y) < 0.3 }.isEmpty)
        let middle = try XCTUnwrap(Map3DKyushuN700.model(.middle))
        XCTAssertTrue(middle.vertices.allSatisfy { $0.color != Map3DTrainStyle.headlamp && $0.color != Map3DPalette.lantern })
    }

    /// Eight cars as the real trains run, a cab at each end, the head's
    /// white lamps and the tail's red lamps lit.
    func testTheEightCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DKyushuN700.key
        let cars = Map3DKyushuN700.cars
        XCTAssertEqual(cars, 8)
        let models = try (0..<cars).map { car in
            pack.models[try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: cars))]
        }
        XCTAssertEqual(models.map(\.name), (["head"] + Array(repeating: "car", count: 6) + ["tail"]).map { "set-\(key)-\($0)" })
        let layout = try XCTUnwrap(pack.layout(forType: key, count: cars))
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 24.883 * 2 + 25.0 * 6, accuracy: 0.1, "199.8 m")
        // Decision 449: the pack lights a running car's lamps only at its
        // train's ends, the head's white and the tail's red.
        let set = try XCTUnwrap(Map3DTrainSet.byKey[key])
        let head = try XCTUnwrap(pack.lights[try XCTUnwrap(pack.index(of: set.headName))]).lamps(atFront: true)
        XCTAssertFalse(head.head.isEmpty)
        XCTAssertTrue(head.head.allSatisfy { $0.color == Map3DTrainStyle.headlamp && $0.x > 5 })
        let tail = try XCTUnwrap(pack.lights[try XCTUnwrap(pack.index(of: set.tailName))]).lamps(atFront: false)
        XCTAssertFalse(tail.tail.isEmpty)
        XCTAssertTrue(tail.tail.allSatisfy { $0.color == Map3DPalette.lantern && $0.x < -5 })
    }

    /// The garage lists it under Japan, on standard gauge, and the Kyushu
    /// Shinkansen's own trains are drawn as it.
    func testTheGarageAndTheKyushuShinkansenUseIt() throws {
        let entry = try XCTUnwrap(Map3DShowcase.entry(Map3DKyushuN700.key))
        XCTAssertEqual(entry.category, .japan)
        XCTAssertEqual(entry.defaultCars, 8)
        XCTAssertEqual(entry.fewestCars, 8)
        XCTAssertEqual(entry.gauge, 1.435)
        XCTAssertEqual(Map3DRealTrains.formation(system: "kyushushinkansen", id: "KS", name: "KS"),
                       .init(key: Map3DKyushuN700.key, cars: 8))
    }
}
