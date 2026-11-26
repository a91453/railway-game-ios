import XCTest
@testable import GamePresentation

/// Decision 998 (continued): the Nishi-Kyushu Shinkansen's N700S Kamome,
/// the owner's old Kamome cars cut by the local studio into faces of the
/// palette's colours.
final class Map3DN700SKamomeTests: XCTestCase {
    private typealias Kamome = Map3DN700SKamome
    private let white = Map3DTrainShapeRefresh.highSpeedBodyColor

    /// Each triangle of `model`: its colour and its centre.
    private func faces(_ model: Map3DModelPack.Model) -> [(colour: UInt32, x: Float, y: Float, z: Float)] {
        stride(from: 0, to: model.vertices.count, by: 3).map { start in
            let corners = model.vertices[start ..< start + 3]
            return (model.vertices[start].color, corners.map(\.x).reduce(0, +) / 3, corners.map(\.y).reduce(0, +) / 3,
                    corners.map(\.z).reduce(0, +) / 3)
        }
    }

    /// The real cars' size: 25 m from coupling to coupling, the cab car
    /// 27.35 m, 3.36 m wide and 3.60 m to the roof; the pantograph car's
    /// cover over its roof at its back.
    func testTheThreeUnitsDecodeAtTheRealSize() throws {
        XCTAssertEqual(Kamome.Unit.allCases.map { Kamome.model($0)?.triangleCount }, [3448, 3447, 3567])
        for unit in Kamome.Unit.allCases {
            let model = try XCTUnwrap(Kamome.model(unit), unit.rawValue)
            XCTAssertEqual(model.length, unit.pitch, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(model.maximum.y - model.minimum.y, 3.36, accuracy: 0.02, "\(unit.rawValue) is 3.36 m wide")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.03, unit.rawValue)
            XCTAssertTrue(Kamome.registration.triangles.contains(model.triangleCount), unit.rawValue)
            XCTAssertTrue(Kamome.registration.length.contains(model.length), unit.rawValue)
            let plain: ClosedRange<Float> = unit == .cab ? -11 ... -7 : unit == .pantograph ? 2...8 : -2...2
            let roof = model.vertices.filter { plain.contains($0.x) && $0.color == white }.map(\.z).max()
            XCTAssertEqual(try XCTUnwrap(roof), 3.60, accuracy: unit == .pantograph ? 0.05 : 0.01, unit.rawValue)
        }
        let pantograph = try XCTUnwrap(Kamome.model(.pantograph))
        XCTAssertEqual(pantograph.maximum.z, 4.645, accuracy: 0.01, "the cover, under the 5.2 m wire")
        let cover = pantograph.vertices.filter { $0.z > 3.9 }.map(\.x)
        XCTAssertLessThan(cover.reduce(0, +) / Float(max(cover.count, 1)), -1, "the cover at the car's back")
    }

    /// The wheels stand on standard-gauge rails: 1,435 mm between the
    /// rails' inner faces, the wheels' outer faces a little wider.
    func testTheWheelsStandOnStandardGauge() throws {
        for unit in Kamome.Unit.allCases {
            let low = try XCTUnwrap(Kamome.model(unit)).vertices.filter { $0.z < 0.05 }
            XCTAssertFalse(low.isEmpty, unit.rawValue)
            XCTAssertTrue(low.allSatisfy { $0.color == Map3DPalette.dark }, "\(unit.rawValue): only the wheels reach the rail")
            let widest = low.map { abs($0.y) }.max() ?? 0
            XCTAssertGreaterThan(widest, 1.435 / 2, unit.rawValue)
            XCTAssertLessThan(widest, 1.435 / 2 + 0.2, unit.rawValue)
        }
    }

    /// The Kamome's livery: a white body, a red skirt, one thin red line
    /// under the windows, and no colour that is not the palette's (no new
    /// one).
    func testTheBodyIsWhiteOverARedSkirtWithTheThinRedLine() throws {
        XCTAssertEqual(Kamome.meshPalette, [
            white, Map3DPalette.trainRed, Map3DPalette.steel, Map3DTrainStyle.glass,
            Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern, white,
        ])
        for unit in Kamome.Unit.allCases {
            let model = try XCTUnwrap(Kamome.model(unit))
            XCTAssertTrue(Set(model.vertices.map(\.color)).isSubset(of: Set(Kamome.meshPalette)), unit.rawValue)
            // The side wall behind the cab's nose (every car's back half).
            let side = faces(model).filter { $0.x > -8 && $0.x < -1 && abs($0.y) > 1.6 }
            let line = side.filter { $0.colour == Map3DPalette.trainRed && $0.z > 1.2 }.map(\.z)
            XCTAssertFalse(line.isEmpty, unit.rawValue)
            // 5.9 cm, 1.59 to 1.65 m over the rail.
            XCTAssertEqual(line.min() ?? 0, 1.60, accuracy: 0.02, unit.rawValue)
            XCTAssertEqual(line.max() ?? 0, 1.64, accuracy: 0.02, unit.rawValue)
            let glass = side.filter { $0.colour == Map3DTrainStyle.glass }.map(\.z)
            XCTAssertLessThan(line.max() ?? 9, glass.min() ?? 0, "\(unit.rawValue): the line under the windows")
            XCTAssertTrue(side.contains { $0.colour == white && $0.z > 2.0 }, unit.rawValue)
            XCTAssertFalse(side.filter { $0.colour == Map3DPalette.trainRed && $0.z < 0.75 }.isEmpty, "\(unit.rawValue): the red skirt")
        }
    }

    /// Between two cars a hood of the body's outline, white over the red
    /// skirt (no red up its sides: the studio's review), its mouth 2 cm
    /// short of the joint in the middle and a shallow V from above; only
    /// the coupler's tip at the joint.
    func testTheHoodsCloseTheGapBetweenCars() throws {
        for unit in Kamome.Unit.allCases {
            let model = try XCTUnwrap(Kamome.model(unit))
            let half = unit.pitch / 2
            for end: Float in unit.isCab ? [-1] : [-1, 1] {
                let name = "\(unit.rawValue) \(end)"
                func mouth(_ vertex: Map3DVertex) -> Float { half - 0.02 - abs(vertex.y) * 0.025 }
                let hood = model.vertices.filter { $0.x * end > half - 0.29 && $0.color != Map3DPalette.dark }
                XCTAssertFalse(hood.isEmpty, name)
                XCTAssertEqual(hood.map { $0.x * end }.max() ?? 0, half - 0.02, accuracy: 0.002, "\(name): 2 cm short in the middle")
                XCTAssertTrue(hood.allSatisfy { $0.x * end <= mouth($0) + 0.002 }, "\(name): the V")
                XCTAssertEqual(hood.map { abs($0.y) }.max() ?? 0, 1.68, accuracy: 0.01, "\(name): as wide as the body")
                XCTAssertTrue(hood.allSatisfy { $0.color == white || ($0.color == Map3DPalette.trainRed && $0.z < 0.8) }, "\(name): white over the red skirt")
                XCTAssertEqual(model.vertices.map { $0.x * end }.max() ?? 0, half, accuracy: 0.001, "\(name): the coupler")
            }
        }
    }

    /// Two cars turned 3 degrees to each other on a curve, each half that
    /// about their joint, keep their hoods apart; only the couplers' tips
    /// touch.
    func testTheHoodsKeepApartOnACurve() throws {
        let turn = Float(1.5) * .pi / 180
        for unit in Kamome.Unit.allCases {
            let model = try XCTUnwrap(Kamome.model(unit))
            let half = unit.pitch / 2
            for end: Float in unit.isCab ? [-1] : [-1, 1] {
                var nearest = -Float.infinity
                for vertex in model.vertices where vertex.x * end > half - 0.4 {
                    let behind = vertex.x * end - half
                    if abs(behind) < 0.0005 && abs(vertex.y) < 0.0005 { continue }   // the coupler's tip
                    nearest = max(nearest, behind * cos(turn) + abs(vertex.y) * sin(turn))
                }
                XCTAssertLessThan(nearest, -0.015, "\(unit.rawValue) \(end): \(nearest)")
            }
        }
    }

    /// The glass is marked face by face; the cab's white and red lamps are
    /// on its nose, the same on each side; the other cars have none.
    func testTheGlassAndTheLampsAreMarked() throws {
        for unit in Kamome.Unit.allCases {
            XCTAssertTrue(Map3DTrainMaterial.marksOwnGlass(try XCTUnwrap(Kamome.model(unit))), unit.rawValue)
        }
        let cab = try XCTUnwrap(Kamome.model(.cab))
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let lamps = cab.vertices.filter { $0.color == lens }
            XCTAssertGreaterThan(lamps.map(\.x).min() ?? 0, Kamome.Unit.cab.pitch * 0.3, "the lamps on the nose")
            for sign in [Float(1), -1] {
                XCTAssertEqual(lamps.filter { $0.y * sign > 0.5 }.count, 3 * 9, "\(lens) on the \(sign) shoulder")
            }
        }
        XCTAssertFalse(cab.vertices.filter { $0.color == Map3DTrainStyle.glass && $0.x > 5.5 && abs($0.y) < 0.3 }.isEmpty, "the windscreen")
        XCTAssertFalse(cab.vertices.filter { $0.color == Map3DPalette.dark && $0.x > 6 && $0.z > 2.5 }.isEmpty, "the black cab mask")
        for unit in [Kamome.Unit.middle, .pantograph] {
            let model = try XCTUnwrap(Kamome.model(unit))
            XCTAssertTrue(model.vertices.allSatisfy { $0.color != Map3DTrainStyle.headlamp && $0.color != Map3DPalette.lantern }, unit.rawValue)
        }
    }

    /// Each door is a piece of its own: its run of triangles (the studio's
    /// node of it) is all inside its box, on its own wall, in the door's
    /// white with its window and grey frame; the runs follow the body's
    /// triangles to the model's last; and outside the driver's door (on
    /// the nose's taper, its box only its place) no wall triangle lies in
    /// a door's box, so a door can be moved apart from the wall one day.
    func testEachDoorIsAPieceOfItsOwn() throws {
        XCTAssertEqual(Kamome.Unit.allCases.map { Kamome.doors($0).count }, [6, 4, 4])
        XCTAssertEqual(Kamome.doors(.cab).map(\.crew), [true, true, false, false, false, false])
        for unit in Kamome.Unit.allCases {
            let model = try XCTUnwrap(Kamome.model(unit))
            let doors = Kamome.doors(unit)
            XCTAssertEqual(doors.map(\.side), Array(repeating: [Float(1), -1], count: doors.count / 2).flatMap { $0 }, unit.rawValue)
            let runs = doors.map { $0.triangles(side: $0.side) }.sorted { $0.lowerBound < $1.lowerBound }
            XCTAssertEqual(runs.last?.upperBound, model.triangleCount, unit.rawValue)
            for (run, next) in zip(runs, runs.dropFirst()) { XCTAssertEqual(run.upperBound, next.lowerBound, unit.rawValue) }
            let owned = Set(runs.flatMap { Array($0) })
            func corners(_ triangle: Int) -> [Map3DPoint] {
                model.vertices[3 * triangle..<3 * triangle + 3].map { Map3DPoint($0.x, $0.y, $0.z) }
            }
            for door in doors {
                let name = "\(unit.rawValue): the door at x \(door.x), side \(door.side)"
                let own = door.triangles(side: door.side)
                XCTAssertGreaterThan(own.count, 40, name)
                var glass = 0, frame = 0, panel = 0
                for triangle in own {
                    XCTAssertTrue(corners(triangle).allSatisfy { door.contains($0) }, name)
                    switch model.vertices[3 * triangle].color {
                    case Map3DTrainStyle.glass: glass += 1
                    case Map3DPalette.steel: frame += 1
                    case white: panel += 1
                    default: break
                    }
                }
                XCTAssertGreaterThan(glass, 0, name)
                XCTAssertGreaterThan(frame, 5, name)
                XCTAssertGreaterThan(panel, 5, name)
                guard !door.crew else { continue }
                for triangle in 0..<model.triangleCount where !owned.contains(triangle) {
                    XCTAssertFalse(corners(triangle).allSatisfy { door.contains($0) }, "\(name): the wall's triangle \(triangle) on it")
                }
            }
        }
    }

    /// Six cars as the real train runs them: the cab car at each end, the
    /// pantograph car second and fifth with the two pantographs facing
    /// each other, 154.7 m in all; the head's white lamps and the tail's
    /// red ones lit.
    func testTheSixCarsAreLaidAsTheRealTrain() throws {
        let pack = Map3DModelPack.standard
        let key = Kamome.key
        XCTAssertEqual(Kamome.cars, 6)
        let laid = try XCTUnwrap(pack.layout(forType: key, count: 6))
        XCTAssertEqual(laid.map { pack.models[$0.model].name },
                       ["head", "panto", "car", "carBack", "pantoBack", "tail"].map { "set-\(key)-\($0)" })
        XCTAssertTrue(laid.allSatisfy { $0.gap == 0 })
        XCTAssertEqual(laid.map(\.length).reduce(0, +), 4 * 25 + 2 * 27.35, accuracy: 0.1, "154.7 m")
        func cover(_ car: Int) -> Float {
            let high = pack.models[laid[car].model].vertices.filter { $0.z > 3.9 }.map(\.x)
            return high.reduce(0, +) / Float(max(high.count, 1))
        }
        XCTAssertLessThan(cover(1), -1)
        XCTAssertGreaterThan(cover(4), 1)
        let set = try XCTUnwrap(Map3DTrainSet.byKey[key])
        let head = try XCTUnwrap(pack.lights[try XCTUnwrap(pack.index(of: set.headName))]).lamps(atFront: true)
        XCTAssertFalse(head.head.isEmpty)
        XCTAssertTrue(head.head.allSatisfy { $0.color == Map3DTrainStyle.headlamp && $0.x > 5 })
        let tail = try XCTUnwrap(pack.lights[try XCTUnwrap(pack.index(of: set.tailName))]).lamps(atFront: false)
        XCTAssertFalse(tail.tail.isEmpty)
        XCTAssertTrue(tail.tail.allSatisfy { $0.color == Map3DPalette.lantern && $0.x < -5 })
        let cars = set.build()
        XCTAssertTrue(cars.head.vertices.filter { $0.layer == Map3DVertex.glowing }.allSatisfy { $0.color == Map3DTrainStyle.headlamp })
        XCTAssertTrue(try XCTUnwrap(cars.tail).vertices.filter { $0.layer == Map3DVertex.glowing }.allSatisfy { $0.color == Map3DPalette.lantern })
        for count in 1...8 {
            for car in 0..<count { XCTAssertNotNil(pack.modelIndex(forType: key, carIndex: car, count: count), "\(count) cars, car \(car)") }
        }
    }

    /// The Nishi-Kyushu Shinkansen draws its six cars as it, and the
    /// garage lists it under Japan, on standard gauge; the Tokaido N700S
    /// keeps its own place (the train pack's high-speed set).
    func testTheNishiKyushuShinkansenAndTheGarageUseIt() throws {
        XCTAssertEqual(Map3DRealTrains.formation(system: "kyushushinkansen", id: "NK", name: "NK"), .init(key: Kamome.key, cars: 6))
        let entry = try XCTUnwrap(Map3DShowcase.entry(Kamome.key))
        XCTAssertEqual(entry.category, .japan)
        XCTAssertEqual(entry.defaultCars, 6)
        XCTAssertEqual(entry.gauge, 1.435)
        XCTAssertNil(try XCTUnwrap(Map3DTrainSet.byKey[Kamome.key]).far)
        XCTAssertTrue(TrainPack.sets.contains(Map3DN700S.key))
        XCTAssertNotNil(Map3DTrainSet.byKey[Map3DN700S.key])
    }
}
