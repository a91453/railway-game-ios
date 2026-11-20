import XCTest
@testable import GamePresentation

/// Decision 893: the local studio's Fukuoka Airport line, Nanakuma line
/// and Kaizuka line trains, and the garage that lists every train a map draws.
final class Map3DFukuokaTrainsTests: XCTestCase {
    func testEveryAirportLineUnitDecodesNearAndFarInTheSameFrame() throws {
        for unit in Map3DFukuokaAirportLine.Unit.allCases {
            let near = try XCTUnwrap(Map3DFukuokaAirportLine.model(unit), unit.rawValue)
            let far = try XCTUnwrap(Map3DFukuokaAirportLine.model(unit, far: true), unit.rawValue)
            XCTAssertEqual(near.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01)
            XCTAssertEqual(near.maximum.y - near.minimum.y, 2.80, accuracy: 0.02, "\(unit.rawValue) is 2.80 m wide")
            // The wheels' flanges a little under the rail's top.
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.03, unit.rawValue)
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount + 1_000, unit.rawValue)
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), unit.rawValue)
        }
    }

    func testEveryKaizukaLineUnitDecodesNearAndFarInTheSameFrame() throws {
        for unit in Map3DFukuokaKaizukaLine.Unit.allCases {
            let near = try XCTUnwrap(Map3DFukuokaKaizukaLine.model(unit), unit.rawValue)
            let far = try XCTUnwrap(Map3DFukuokaKaizukaLine.model(unit, far: true), unit.rawValue)
            XCTAssertEqual(near.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01)
            XCTAssertEqual(near.maximum.y - near.minimum.y, 2.67, accuracy: 0.02, "\(unit.rawValue) is 2.67 m wide")
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.03, unit.rawValue)
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, unit.rawValue)
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), unit.rawValue)
        }
    }

    /// The Airport line's band is the registered sky blue, its skirt the
    /// roof's silver: white over a sky-blue band in every car's middle.
    func testTheAirportLineIsWhiteWithASkyBlueBand() throws {
        XCTAssertEqual(Map3DPalette.skyBlue, Map3DColor.rgb(0xBFE3E5))
        for unit in Map3DFukuokaAirportLine.Unit.allCases {
            let middle = try XCTUnwrap(Map3DFukuokaAirportLine.model(unit)).vertices.filter { abs($0.x) < 5 }
            XCTAssertFalse(middle.filter { $0.color == Map3DPalette.skyBlue && $0.z > 1.8 && $0.z < 2.9 }.isEmpty, unit.rawValue)
            XCTAssertFalse(middle.filter { $0.color == Map3DPalette.cityConcreteWalls[4] && $0.z > 1 && $0.z < 1.8 }.isEmpty, unit.rawValue)
            XCTAssertFalse(middle.filter { $0.color == Map3DPalette.tankBlue && $0.z > 3.2 }.isEmpty, "\(unit.rawValue): the blue roof line")
        }
        // The cab's lamps at its front: white headlamps and red tail lamps.
        let cab = try XCTUnwrap(Map3DFukuokaAirportLine.model(.cab))
        let front = Map3DFukuokaAirportLine.Unit.cab.pitch / 2 - 1
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let xs = cab.vertices.filter { $0.color == lens }.map(\.x)
            XCTAssertFalse(xs.isEmpty)
            XCTAssertGreaterThan(xs.min() ?? 0, front, "its lamps at the cab end")
        }
    }

    /// Six cars as the real trains run: cab, pantograph car, two middle
    /// cars, pantograph car, cab, the back half turned round.
    func testTheAirportLinesSixCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DFukuokaAirportLine.key
        let names = try (0..<6).map { car in
            let index = try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: 6))
            return pack.models[index].name
        }
        XCTAssertEqual(names, ["head", "panto", "car", "carBack", "pantoBack", "tail"].map { "set-\(key)-\($0)" })
        let layout = try XCTUnwrap(pack.layout(forType: key, count: 6))
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 20.435 * 2 + 20.0 * 4, accuracy: 0.1, "120.9 m")
    }

    /// Two cars, the motor car in front and the trailer turned round.
    func testTheKaizukaLinesTwoCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DFukuokaKaizukaLine.key
        let names = try (0..<2).map { car in
            let index = try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: 2))
            return pack.models[index].name
        }
        XCTAssertEqual(names, ["head", "tail"].map { "set-\(key)-\($0)" })
        let layout = try XCTUnwrap(pack.layout(forType: key, count: 2))
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 39.0, accuracy: 0.1)
    }

    func testEveryNanakumaLineUnitDecodesNearAndFarInTheSameFrame() throws {
        for unit in Map3DFukuokaNanakumaLine.Unit.allCases {
            let near = try XCTUnwrap(Map3DFukuokaNanakumaLine.model(unit), unit.rawValue)
            let far = try XCTUnwrap(Map3DFukuokaNanakumaLine.model(unit, far: true), unit.rawValue)
            XCTAssertEqual(near.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(far.length, near.length, accuracy: 0.01)
            XCTAssertEqual(near.maximum.y - near.minimum.y, 2.49, accuracy: 0.03, "\(unit.rawValue) is 2.49 m wide")
            XCTAssertEqual(near.minimum.z, 0, accuracy: 0.03, unit.rawValue)
            // The operator's highest point, the lowered pantograph too.
            XCTAssertEqual(near.maximum.z, 3.145, accuracy: 0.01, unit.rawValue)
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, unit.rawValue)
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), unit.rawValue)
        }
    }

    /// A white body, a green window band with the lime line along its top
    /// (some 0.18 m, 2.70 to 2.87 m up), the pale blue band at its foot.
    func testTheNanakumaLineHasItsGreenBandAndLimeLine() throws {
        XCTAssertEqual(Map3DPalette.lime, Map3DColor.rgb(0xA8D430))
        for unit in Map3DFukuokaNanakumaLine.Unit.allCases {
            let middle = try XCTUnwrap(Map3DFukuokaNanakumaLine.model(unit)).vertices.filter { abs($0.x) < 4 && abs($0.y) > 1 }
            let lime = middle.filter { $0.color == Map3DPalette.lime }.map(\.z)
            XCTAssertFalse(lime.isEmpty, unit.rawValue)
            XCTAssertEqual((lime.max() ?? 0) - (lime.min() ?? 0), 0.18, accuracy: 0.04, "\(unit.rawValue): the lime line 0.18 m")
            XCTAssertFalse(middle.filter { $0.color == Map3DPalette.gymGreen && $0.z > 1.5 && $0.z < 2.7 }.isEmpty, unit.rawValue)
            XCTAssertFalse(middle.filter { $0.color == Map3DPalette.skyBlue && $0.z < 1 }.isEmpty, unit.rawValue)
        }
    }

    /// Four cars as the real trains run: cab, two middle cars, cab.
    func testTheNanakumaLinesFourCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DFukuokaNanakumaLine.key
        let names = try (0..<4).map { car in
            let index = try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: 4))
            return pack.models[index].name
        }
        XCTAssertEqual(names, ["head", "car", "carBack", "tail"].map { "set-\(key)-\($0)" })
        let layout = try XCTUnwrap(pack.layout(forType: key, count: 4))
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 16.75 * 2 + 16.5 * 2, accuracy: 0.1, "66.5 m")
    }

    /// The Kaizuka line's red band is the tail lamps' red. Its lamps are
    /// lit by material: no band face is lit, near or far, in the model or
    /// in the lamps the game lights at night, and its tail lamps are the
    /// taillamp material's faces alone.
    func testTheKaizukaLinesRedBandNeverLights() throws {
        for unit in Map3DFukuokaKaizukaLine.Unit.allCases {
            for far in [false, true] {
                let model = try XCTUnwrap(Map3DFukuokaKaizukaLine.model(unit, far: far))
                let red = model.vertices.filter { $0.color == Map3DPalette.lantern }
                let lit = red.filter(\.glows)
                // The band: its red faces that are not lit, along the whole car.
                let band = red.filter { !$0.glows }
                XCTAssertFalse(band.isEmpty, unit.rawValue)
                XCTAssertGreaterThan(band.map(\.x).max() ?? 0, 6)
                XCTAssertLessThan(band.map(\.x).min() ?? 0, -6)
                // The tail lamps: lit, at the cab end.
                XCTAssertFalse(lit.isEmpty, unit.rawValue)
                XCTAssertGreaterThan(lit.map(\.x).min() ?? 0, unit.pitch / 2 - 1, "\(unit.rawValue): the tail lamps at the cab")
                XCTAssertFalse(model.vertices.contains { $0.glows && $0.color != Map3DPalette.lantern && $0.color != Map3DTrainStyle.headlamp })
            }
        }
        let pack = Map3DModelPack.standard
        for key in [Map3DFukuokaKaizukaLine.key, Map3DFukuokaKaizukaLine.key + "Far"] {
            let set = try XCTUnwrap(Map3DTrainSet.all.first { $0.key == key })
            for (name, front) in [(set.headName, true), (set.tailName, false)] {
                let index = try XCTUnwrap(pack.index(of: name), name)
                let recipe = Map3DModelPack.unbaked.models[index]
                let lamps = try XCTUnwrap(pack.lights[index], name).lamps(atFront: front)
                let tailFaces = recipe.vertices.filter { $0.glows && $0.color == Map3DPalette.lantern }.count
                XCTAssertEqual(lamps.tail.count, tailFaces, "\(name): the tail lamps are the taillamp faces, no band face")
                XCTAssertTrue(lamps.tail.allSatisfy { front ? $0.x > recipe.maximum.x - 1 : $0.x < recipe.minimum.x + 1 }, name)
            }
        }
    }

    /// The real lines the game sells and draws with a set of their own:
    /// that set is in the garage's list, so whatever runs on a map can be
    /// looked at there (GARAGE-MISSING-OVERSEAS).
    func testEveryRegisteredTrainAndEveryRealLinesTrainIsInTheGarage() {
        for registration in Map3DTrainRegistry.trains {
            for set in registration.sets where set.far != nil {
                XCTAssertNotNil(Map3DShowcase.entry(set.key), "\(registration.id): \(set.key) not in the garage")
            }
        }
        for line in RealBranchLine.overseasLines {
            let key = Map3DRealTrains.formation(system: line.system, id: line.network, name: line.network).key
            guard !key.isEmpty, key != "metroGeneric" else { continue }
            XCTAssertNotNil(Map3DShowcase.entry(key), "\(line.system) \(line.network): \(key) not in the garage")
        }
        // Each overseas map's trains under its country.
        XCTAssertEqual(Map3DShowcase.entry(Map3DFukuokaAirportLine.key)?.category, .japan)
        XCTAssertEqual(Map3DShowcase.entry(Map3DFukuokaKaizukaLine.key)?.category, .japan)
        XCTAssertEqual(Map3DShowcase.entry(Map3DFukuokaNanakumaLine.key)?.category, .japan)
        XCTAssertEqual(Map3DShowcase.entry(Map3DFinlandSr2.key)?.category, .finland)
        for key in [Map3DMTRAirportLine.expressKey, Map3DMTRAirportLine.tungChungKey, Map3DMTRUrbanLine.key, Map3DMTRTuenMaLine.key,
                    Map3DMTREastRailLine.key, Map3DMTRSouthIslandLine.key, Map3DMTRDisneylandLine.key] {
            XCTAssertEqual(Map3DShowcase.entry(key)?.category, .hongKong, key)
        }
    }
}
