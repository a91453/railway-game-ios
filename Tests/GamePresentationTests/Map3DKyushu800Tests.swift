import XCTest
@testable import GamePresentation

/// Decision 978: the Kyushu Shinkansen's 800 series, the owner's old cars
/// cut into faces of the palette's colours.
final class Map3DKyushu800Tests: XCTestCase {
    /// Each triangle of `model`: its colour and its centre.
    private func faces(_ model: Map3DModelPack.Model) -> [(colour: UInt32, x: Float, y: Float, z: Float)] {
        stride(from: 0, to: model.vertices.count, by: 3).map { start in
            let corners = model.vertices[start ..< start + 3]
            return (model.vertices[start].color, corners.map(\.x).reduce(0, +) / 3, corners.map(\.y).reduce(0, +) / 3,
                    corners.map(\.z).reduce(0, +) / 3)
        }
    }

    func testBothUnitsDecodeAtTheRealSize() throws {
        for unit in Map3DKyushu800.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushu800.model(unit), unit.rawValue)
            XCTAssertEqual(model.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(model.maximum.y - model.minimum.y, 3.38, accuracy: 0.02, "\(unit.rawValue) is 3.38 m wide")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.03, unit.rawValue)
            XCTAssertEqual(model.maximum.z, 3.65, accuracy: 0.01, "\(unit.rawValue): the roof 3.65 m up")
            XCTAssertTrue(Map3DKyushu800.registration.triangles.contains(model.triangleCount), unit.rawValue)
            XCTAssertTrue(Map3DKyushu800.registration.length.contains(model.length), unit.rawValue)
        }
        // The real cars: the middle car 25 m, the cab car 27.35 m (the old
        // cab car made longer as a whole, not its nose alone).
        XCTAssertEqual(Map3DKyushu800.Unit.middle.pitch, 25)
        XCTAssertEqual(Map3DKyushu800.Unit.cab.pitch, 27.35)
    }

    /// The wheels stand on standard-gauge rails: 1,435 mm between the
    /// rails' inner faces, the wheels' outer faces a little wider.
    func testTheWheelsStandOnStandardGauge() throws {
        for unit in Map3DKyushu800.Unit.allCases {
            let low = try XCTUnwrap(Map3DKyushu800.model(unit)).vertices.filter { $0.z < 0.05 }
            XCTAssertFalse(low.isEmpty, unit.rawValue)
            XCTAssertTrue(low.allSatisfy { $0.color == Map3DPalette.dark }, "\(unit.rawValue): only the wheels reach the rail")
            let widest = low.map { abs($0.y) }.max() ?? 0
            XCTAssertGreaterThan(widest, 1.435 / 2, unit.rawValue)
            XCTAssertLessThan(widest, 1.435 / 2 + 0.2, unit.rawValue)
        }
    }

    /// The real livery: a white body under a red roof, the thin red line
    /// along its side under the windows, a grey skirt, and no colour that
    /// is not the palette's.
    func testTheBodyIsWhiteUnderARedRoofWithTheRedLine() throws {
        let colours: Set<UInt32> = [
            Map3DPalette.tileWhite, Map3DPalette.trainRed, Map3DPalette.steel, Map3DTrainStyle.glass,
            Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern,
        ]
        for unit in Map3DKyushu800.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushu800.model(unit))
            XCTAssertTrue(Set(model.vertices.map(\.color)).isSubset(of: colours), unit.rawValue)
            let all = faces(model)
            // The straight body's side walls, behind the nose.
            let side = all.filter { $0.x < 0 && abs($0.y) > 1.6 }
            XCTAssertFalse(side.filter { $0.colour == Map3DPalette.tileWhite && $0.z > 2.6 }.isEmpty, unit.rawValue)
            let line = side.filter { $0.colour == Map3DPalette.trainRed }.map(\.z)
            XCTAssertFalse(line.isEmpty, unit.rawValue)
            let glass = side.filter { $0.colour == Map3DTrainStyle.glass }.map(\.z)
            XCTAssertFalse(glass.isEmpty, unit.rawValue)
            XCTAssertLessThan(line.max() ?? 9, glass.min() ?? 0, "\(unit.rawValue): the line under the windows")
            // As thin as the real one: some 5 cm.
            XCTAssertLessThan((line.max() ?? 9) - (line.min() ?? 0), 0.06, unit.rawValue)
            // The roof's flat top is red from side to side.
            let roof = all.filter { $0.x < 0 && $0.z > 3.6 && abs($0.y) < 1.3 }
            XCTAssertFalse(roof.isEmpty, unit.rawValue)
            XCTAssertTrue(roof.allSatisfy { $0.colour == Map3DPalette.trainRed }, "\(unit.rawValue): the red roof")
            XCTAssertFalse(all.filter { $0.colour == Map3DPalette.steel && $0.z < 1 }.isEmpty, "\(unit.rawValue): the grey skirt")
            // Each door has its frame (the old texture's thin line around the
            // panel), up the wall above the red line.
            XCTAssertFalse(all.filter { $0.colour == Map3DPalette.steel && $0.z > 1.6 && $0.z < 3.3 }.isEmpty, "\(unit.rawValue): the door frames")
        }
    }

    /// The glass is marked face by face, so the pack guesses none; the
    /// cab's lamps are on its nose under the dark cab mask, and the middle
    /// car has none.
    func testTheGlassTheMaskAndTheLampsAreMarked() throws {
        for unit in Map3DKyushu800.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushu800.model(unit))
            XCTAssertTrue(Map3DTrainMaterial.marksOwnGlass(model), unit.rawValue)
        }
        let cab = faces(try XCTUnwrap(Map3DKyushu800.model(.cab)))
        let pitch = Map3DKyushu800.Unit.cab.pitch
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let xs = cab.filter { $0.colour == lens }.map(\.x)
            XCTAssertFalse(xs.isEmpty)
            XCTAssertGreaterThan(xs.min() ?? 0, pitch * 0.2, "the lamps on the nose")
        }
        // The headlamps above the tail lamps, both sides of the nose.
        let head = cab.filter { $0.colour == Map3DTrainStyle.headlamp }
        let tail = cab.filter { $0.colour == Map3DPalette.lantern }
        XCTAssertGreaterThan(head.map(\.z).min() ?? 0, tail.map(\.z).max() ?? 9)
        XCTAssertTrue(head.contains { $0.y > 0.3 } && head.contains { $0.y < -0.3 })
        // The windscreen over the nose, on the car's centre line too, in
        // the dark mask that reaches the roof.
        XCTAssertFalse(cab.filter { $0.colour == Map3DTrainStyle.glass && $0.x > 6 && abs($0.y) < 0.3 }.isEmpty)
        XCTAssertFalse(cab.filter { $0.colour == Map3DPalette.dark && $0.x > 4 && $0.z > 3.3 }.isEmpty)
        let middle = try XCTUnwrap(Map3DKyushu800.model(.middle))
        XCTAssertTrue(middle.vertices.allSatisfy { $0.color != Map3DTrainStyle.headlamp && $0.color != Map3DPalette.lantern })
    }

    /// Six cars as the real trains run, a cab at each end, the head's
    /// white lamps and the tail's red lamps lit.
    func testTheSixCarsAreLaidAsTheRealTrains() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DKyushu800.key
        let cars = Map3DKyushu800.cars
        XCTAssertEqual(cars, 6)
        let models = try (0..<cars).map { car in
            pack.models[try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: cars))]
        }
        XCTAssertEqual(models.map(\.name), (["head"] + Array(repeating: "car", count: 4) + ["tail"]).map { "set-\(key)-\($0)" })
        let layout = try XCTUnwrap(pack.layout(forType: key, count: cars))
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 27.35 * 2 + 25.0 * 4, accuracy: 0.1, "154.7 m")
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
    /// Shinkansen's odd-numbered trains are drawn as it, six cars, the
    /// others as the N700 series' eight.
    func testTheGarageAndTheKyushuShinkansenUseIt() throws {
        let entry = try XCTUnwrap(Map3DShowcase.entry(Map3DKyushu800.key))
        XCTAssertEqual(entry.category, .japan)
        XCTAssertEqual(entry.defaultCars, 6)
        XCTAssertEqual(entry.fewestCars, 6)
        XCTAssertEqual(entry.gauge, 1.435)
        let line = Map3DRealTrains.formation(system: "kyushushinkansen", id: "KS", name: "KS")
        XCTAssertEqual(line.alternate, Map3DKyushu800.key)
        for number in [1, 3, 301] {
            XCTAssertEqual(Map3DRealTrains.formation(of: line, system: "kyushushinkansen", number: number),
                           .init(key: Map3DKyushu800.key, cars: 6), "\(number)")
        }
        for number in [2, 4, 300] {
            XCTAssertEqual(Map3DRealTrains.formation(of: line, system: "kyushushinkansen", number: number),
                           .init(key: Map3DKyushuN700.key, cars: 8), "\(number)")
        }
    }

    /// Each door (its frame, its panel and the window in it) is cut out of
    /// the wall along its outline, at the place ``Map3DKyushu800/doors(_:)``
    /// gives, so that it can be moved apart from the wall one day (the same
    /// guard as the N700S's).
    func testEachDoorIsAPieceOfItsOwn() throws {
        XCTAssertEqual(Map3DKyushu800.Unit.allCases.map { Map3DKyushu800.doors($0).count }, [2, 2])
        XCTAssertEqual(Map3DKyushu800.doors(.cab).map(\.crew), [true, false])
        for unit in Map3DKyushu800.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushu800.model(unit))
            // The side walls' triangles.
            var walls: [(points: [Map3DPoint], color: UInt32)] = []
            for first in stride(from: 0, to: model.vertices.count, by: 3) {
                let points = model.vertices[first..<first + 3].map { Map3DPoint($0.x, $0.y, $0.z) }
                if points.allSatisfy({ abs($0.y) > 1.5 }) { walls.append((points, model.vertices[first].color)) }
            }
            for door in Map3DKyushu800.doors(unit) {
                XCTAssertGreaterThan(door.x.upperBound - door.x.lowerBound, 0.7, unit.rawValue)
                XCTAssertGreaterThan(door.z.upperBound - door.z.lowerBound, 1.8, unit.rawValue)
                for side in [Float(1), -1] {
                    var own = 0, glass = 0, frame = 0
                    for (triangle, color) in walls where triangle[0].y * side > 0 {
                        if triangle.allSatisfy({ door.contains($0) }) {
                            own += 1
                            if color == Map3DTrainStyle.glass { glass += 1 }
                            if color == Map3DPalette.steel { frame += 1 }
                        } else if !door.crew {
                            // (The driver's door has a slanted top: its
                            // box is only its place.)
                            XCTAssertFalse(triangle.contains { door.contains($0, margin: -0.01) },
                                           "\(unit.rawValue): a triangle crosses the door at x \(door.x)")
                        }
                    }
                    XCTAssertGreaterThan(own, 12, "\(unit.rawValue): the door at x \(door.x), side \(side): \(own)")
                    XCTAssertGreaterThan(glass, 0, unit.rawValue)
                    XCTAssertGreaterThan(frame, 5, "\(unit.rawValue): \(frame)")
                }
            }
        }
    }
}
