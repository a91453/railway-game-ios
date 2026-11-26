import XCTest
@testable import GamePresentation

/// Decision 989: the 700 series in its own paint, the owner's old cars at
/// the 700T's size (decision 988), a train of the garage.
final class Map3DSeries700Tests: XCTestCase {
    private let white = Map3DTrainShapeRefresh.highSpeedBodyColor
    private let blue = Map3DPalette.shinkansenBlue

    func testTheFiveUnitsDecodeAtTheRealSize() throws {
        XCTAssertEqual(Map3DSeries700.Unit.allCases.count, 5)
        for unit in Map3DSeries700.Unit.allCases {
            let model = try XCTUnwrap(Map3DSeries700.model(unit), unit.rawValue)
            XCTAssertEqual(model.length, Map3DSeries700.length(unit), accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(model.length, unit.isCab ? 27 : 25, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(model.maximum.y - model.minimum.y, 3.38, accuracy: 0.02, "\(unit.rawValue) is 3.38 m wide")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.03, unit.rawValue)
            XCTAssertTrue(Map3DSeries700.triangles.contains(model.triangleCount), "\(unit.rawValue): \(model.triangleCount)")
            // (The roof's faces run the car's length: its corners are at the car's ends.)
            let plain: ClosedRange<Float> = unit.isCab ? -13.5 ... -7 : unit == .pantograph ? 2...12.5 : -12.5...12.5
            let roof = model.vertices.filter { plain.contains($0.x) && $0.color == white }.map(\.z).max()
            XCTAssertEqual(try XCTUnwrap(roof), 3.65, accuracy: 0.01, unit.rawValue)
            // The wheels on standard-gauge rails.
            let low = model.vertices.filter { $0.z < 0.05 }
            XCTAssertTrue(low.allSatisfy { $0.color == Map3DPalette.dark }, "\(unit.rawValue): only the wheels reach the rail")
            let widest = low.map { abs($0.y) }.max() ?? 0
            XCTAssertGreaterThan(widest, 1.435 / 2, unit.rawValue)
            XCTAssertLessThan(widest, 1.435 / 2 + 0.2, unit.rawValue)
        }
        XCTAssertEqual(try XCTUnwrap(Map3DSeries700.model(.pantograph)).maximum.z, 4.61, accuracy: 0.02)
    }

    /// The bogies stand where the real car's do (3.75 m from a coupling
    /// face, 17.5 m apart), and each sits in the middle of the opening in
    /// the skirts that shows its wheels, as wide as the others (the owner, 2026-11-26: the openings stood 0.14 to 0.19 m to one
    /// side of their wheels, and the cab car's front one was 0.6 m
    /// narrower than the back one and so shallow that the wheels' tops
    /// were hidden).
    func testTheWheelsAreInTheMiddleOfTheirOpenings() throws {
        for unit in Map3DSeries700.Unit.allCases {
            let model = try XCTUnwrap(Map3DSeries700.model(unit))
            let half = Map3DSeries700.length(unit) / 2
            let wheels = model.vertices.filter { $0.color == Map3DPalette.dark && $0.z < 0.3 }.map(\.x).sorted()
            var axles: [[Float]] = []
            for x in wheels {
                if let last = axles.last?.last, x - last < 0.8 { axles[axles.count - 1].append(x) } else { axles.append([x]) }
            }
            XCTAssertEqual(axles.count, 4, unit.rawValue)
            guard axles.count == 4 else { continue }
            // The skirts along the side walls: their foot, where each
            // opening begins and ends, and everything else that is low.
            let side = model.vertices.filter { $0.color != Map3DPalette.dark && abs($0.y) > 1.3 }
            let feet = side.filter { abs($0.z - 0.444) < 0.003 }.map(\.x)
            var centres: [Float] = []
            for pair in [axles[0] + axles[1], axles[2] + axles[3]] {
                let low = pair.min() ?? 0, high = pair.max() ?? 0, centre = (low + high) / 2
                centres.append(centre)
                let back = try XCTUnwrap(feet.filter { $0 < low }.max(), unit.rawValue)
                let front = try XCTUnwrap(feet.filter { $0 > high }.min(), "\(unit.rawValue): the skirt runs over the bogie")
                XCTAssertEqual((front + back) / 2, centre, accuracy: 0.01, "\(unit.rawValue): the opening's middle is the bogie's")
                XCTAssertEqual(front - back, 4.26, accuracy: 0.01, "\(unit.rawValue): every opening as wide as the others")
                // The opening's top: the floor, 0.96 m above the rail, or
                // over the cab car's front bogie 0.70 m, a strip of the
                // nose's skirt left above the wheels as on the real car.
                let top = side.filter { $0.x > back + 0.05 && $0.x < front - 0.05 && $0.z > 0.5 }.map(\.z).min() ?? 0
                XCTAssertGreaterThan(top, 0.69, "\(unit.rawValue): the whole wheel shows")
            }
            XCTAssertEqual(centres[1] - centres[0], 17.5, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(centres[0], -half + 3.75, accuracy: 0.01, unit.rawValue)
            if !unit.isCab {
                XCTAssertEqual(centres[1], half - 3.75, accuracy: 0.01, unit.rawValue)
            }
        }
    }

    /// Its own paint: a white body, a broad blue band and a thin blue line
    /// under the windows (the old cars' heights, at the real car's
    /// height), a grey skirt, and no colour that is not the palette's:
    /// none of the 700T's orange.
    func testTheBodyIsWhiteWithTheBlueBandAndLine() throws {
        XCTAssertEqual(Map3DSeries700.meshPalette, [
            white, blue, blue, Map3DPalette.tankStand, Map3DTrainStyle.glass,
            Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern, Map3DPalette.steel,
        ])
        for unit in Map3DSeries700.Unit.allCases {
            let model = try XCTUnwrap(Map3DSeries700.model(unit))
            XCTAssertTrue(Set(model.vertices.map(\.color)).isSubset(of: Set(Map3DSeries700.meshPalette)), unit.rawValue)
            XCTAssertFalse(model.vertices.contains { $0.color == Map3DTrainShapeRefresh.highSpeedBandColor }, unit.rawValue)
            // The side wall between the doors, every car's back half.
            let side = model.vertices.filter { $0.x > -8 && $0.x < -1 && abs($0.y) > 1.68 }
            let painted = side.filter { $0.color == blue }.map(\.z).sorted()
            XCTAssertEqual(try XCTUnwrap(painted.first), 1.671, accuracy: 0.01, "\(unit.rawValue): the line's foot")
            XCTAssertEqual(try XCTUnwrap(painted.last), 1.988, accuracy: 0.01, "\(unit.rawValue): the band's top")
            // White between the line and the band.
            XCTAssertFalse(painted.contains { $0 > 1.72 && $0 < 1.78 }, unit.rawValue)
            XCTAssertTrue(painted.contains { abs($0 - 1.716) < 0.005 } && painted.contains { abs($0 - 1.784) < 0.005 }, unit.rawValue)
            let glass = side.filter { $0.color == Map3DTrainStyle.glass }.map(\.z)
            XCTAssertGreaterThan(try XCTUnwrap(glass.min()), 1.99, "\(unit.rawValue): the band under the windows")
            XCTAssertFalse(model.vertices.filter { $0.color == Map3DPalette.tankStand && $0.z < 1 }.isEmpty, "\(unit.rawValue): the grey skirt")
        }
    }

    /// The cab cars: the band starts in a point before the driver's door
    /// and the nose before it is all white; the driver's door is drawn
    /// (the 700T has none); the two cab cars are one nose with two bodies,
    /// the front one's back door a car's door from its end, the back
    /// one's at its end, with two more windows.
    func testTheCabCarsNoseAndDoors() throws {
        let cab = try XCTUnwrap(Map3DSeries700.model(.cab)), tail = try XCTUnwrap(Map3DSeries700.model(.tail))
        for model in [cab, tail] {
            let crew = try XCTUnwrap(Map3DSeries700.doors(model.name == cab.name ? .cab : .tail).first)
            XCTAssertTrue(crew.crew)
            let tip = try XCTUnwrap(model.vertices.filter { $0.color == blue }.map(\.x).max())
            XCTAssertGreaterThan(tip, crew.x.upperBound + 1, "\(model.name): the band starts before the driver's door")
            XCTAssertLessThan(tip, crew.x.upperBound + 2.5, model.name)
            XCTAssertFalse(model.vertices.contains { $0.x > tip + 0.01 && $0.color != white && $0.z > 1.2 && abs($0.y) > 1.0 },
                           "\(model.name): the nose's sides before the band are white")
            XCTAssertEqual(model.maximum.x, 13.5, accuracy: 0.01)
            XCTAssertEqual(model.maximum.x - Map3DSeries700.doors(model.name == cab.name ? .cab : .tail)[1].x.upperBound,
                           6.736 * 12.5 / 10.501, accuracy: 0.01, "\(model.name): the nose has no stretch of its own")
        }
        XCTAssertEqual(Map3DSeries700.doors(.cab)[1], Map3DSeries700.doors(.tail)[1])
        XCTAssertEqual(Map3DSeries700.doors(.cab)[1].x, Map3DTHSR700T.doors(.cab)[0].x, "the 700T's front door")
        XCTAssertLessThan(Map3DSeries700.doors(.tail)[2].x.lowerBound, Map3DSeries700.doors(.cab)[2].x.lowerBound - 2)
        // The cabin's windows: the glass on a wall at the windows' height
        // (its triangles, joined where they touch), each window's two
        // edges. The doors' windows and the small one are taller.
        func windows(_ unit: Map3DSeries700.Unit) throws -> [Float] {
            let model = try XCTUnwrap(Map3DSeries700.model(unit))
            var spans: [ClosedRange<Float>] = []
            for first in stride(from: 0, to: model.vertices.count, by: 3) {
                let corners = model.vertices[first..<first + 3]
                guard corners.allSatisfy({ $0.y > 1.68 && $0.color == Map3DTrainStyle.glass && $0.z > 2.055 && $0.z < 2.565 }) else { continue }
                spans.append((corners.map(\.x).min() ?? 0)...(corners.map(\.x).max() ?? 0))
            }
            var merged: [ClosedRange<Float>] = []
            for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if let last = merged.last, span.lowerBound <= last.upperBound + 0.002 {
                    merged[merged.count - 1] = last.lowerBound...max(last.upperBound, span.upperBound)
                } else {
                    merged.append(span)
                }
            }
            // (A corner of a door's window can be this low too.)
            let doors = Map3DSeries700.doors(unit)
            return merged.flatMap { [$0.lowerBound, $0.upperBound] }.filter { x in !doors.contains { $0.x.contains(x) } }
        }
        let front = try windows(.cab), back = try windows(.tail), middle = try windows(.middle)
        // (The wide-windowed car's small window, at its far end, apart.)
        let wide = try windows(.green).filter { $0 < 10.5 }
        XCTAssertEqual(front.count, 28, "fourteen windows a side")
        XCTAssertEqual(back.count, 32, "sixteen windows a side")
        XCTAssertEqual(middle.count, 40, "twenty windows a side")
        XCTAssertEqual(wide.count, 34, "seventeen wide windows a side")
        // And its small window, taller, at the end away from its door.
        let small = try XCTUnwrap(Map3DSeries700.model(.green)).vertices.filter { $0.color == Map3DTrainStyle.glass && abs($0.y) > 1.68 && $0.z > 2.6 }
        XCTAssertFalse(small.isEmpty)
        XCTAssertTrue(small.allSatisfy { $0.x > 10.5 || Map3DSeries700.doors(.green)[0].x.contains($0.x) })
        XCTAssertTrue(small.contains { $0.x > 10.5 })
        for edges in [front, back] {
            XCTAssertEqual(edges[1] - edges[0], middle[1] - middle[0], accuracy: 0.002, "a window's width")
            XCTAssertEqual(edges[2] - edges[0], middle[2] - middle[0], accuracy: 0.002, "the windows' spacing")
        }
        // The wide windows: wider and farther apart than the middle car's.
        XCTAssertGreaterThan(wide[1] - wide[0], middle[1] - middle[0] + 0.1)
        XCTAssertEqual(wide[2] - wide[0], 1.16, accuracy: 0.01, "the wide windows' spacing")
    }

    /// Each door is a piece of its own: no triangle is partly a door's and
    /// partly the wall's, on either side; each has its frame and its
    /// window, and the band runs through the passenger doors.
    func testEachDoorIsAPieceOfItsOwn() throws {
        XCTAssertEqual(Map3DSeries700.Unit.allCases.map { Map3DSeries700.doors($0).count }, [3, 3, 2, 1, 2])
        XCTAssertEqual(Map3DSeries700.doors(.cab).map(\.crew), [true, false, false])
        for unit in Map3DSeries700.Unit.allCases {
            let model = try XCTUnwrap(Map3DSeries700.model(unit))
            var walls: [(points: [Map3DPoint], color: UInt32)] = []
            for first in stride(from: 0, to: model.vertices.count, by: 3) {
                let points = model.vertices[first..<first + 3].map { Map3DPoint($0.x, $0.y, $0.z) }
                if points.allSatisfy({ abs($0.y) > 1.6 }) { walls.append((points, model.vertices[first].color)) }
            }
            for door in Map3DSeries700.doors(unit) {
                XCTAssertGreaterThan(door.x.upperBound - door.x.lowerBound, door.crew ? 0.5 : 0.7, unit.rawValue)
                XCTAssertGreaterThan(door.z.upperBound - door.z.lowerBound, 1.4, unit.rawValue)
                for side in [Float(1), -1] {
                    var own = 0, glass = 0, frame = 0, band = 0
                    for (triangle, color) in walls where triangle[0].y * side > 0 {
                        if triangle.allSatisfy({ door.contains($0) }) {
                            own += 1
                            if color == Map3DTrainStyle.glass { glass += 1 }
                            if color == Map3DPalette.steel { frame += 1 }
                            if color == blue { band += 1 }
                        } else {
                            XCTAssertFalse(triangle.contains { door.contains($0, margin: -0.01) },
                                           "\(unit.rawValue): a triangle crosses the door at x \(door.x)")
                        }
                    }
                    XCTAssertGreaterThan(own, 20, "\(unit.rawValue): the door at x \(door.x), side \(side)")
                    XCTAssertGreaterThan(glass, 0, unit.rawValue)
                    XCTAssertGreaterThan(frame, 5, unit.rawValue)
                    XCTAssertGreaterThan(band, 0, "\(unit.rawValue): the band runs through the door")
                }
            }
        }
    }

    /// The joints are the old car's inset ones, no hood (the studio's
    /// review, 2026-11-25: the 700 series has none; the hood came with the
    /// N700): at each coupled end the body stops short of the coupling,
    /// only the dark gangway between.
    func testTheJointsAreInset() throws {
        for unit in Map3DSeries700.Unit.allCases {
            let model = try XCTUnwrap(Map3DSeries700.model(unit))
            let half = Map3DSeries700.length(unit) / 2
            for end: Float in unit.isCab ? [-1] : [-1, 1] {
                let body = model.vertices.filter { $0.color != Map3DPalette.dark }.map { $0.x * end }
                XCTAssertLessThan(try XCTUnwrap(body.max()), half - 0.1, "\(unit.rawValue) \(end): inset")
            }
        }
    }

    /// The glass is marked as the windows; the cab cars' lamps are on
    /// their noses and the other cars have none.
    func testTheGlassAndTheLampsAreMarked() throws {
        for unit in Map3DSeries700.Unit.allCases {
            let model = try XCTUnwrap(Map3DSeries700.model(unit))
            XCTAssertTrue(Map3DTrainMaterial.marksOwnGlass(model), unit.rawValue)
            let lamps = model.vertices.filter { $0.color == Map3DTrainStyle.headlamp || $0.color == Map3DPalette.lantern }
            XCTAssertEqual(lamps.isEmpty, !unit.isCab, unit.rawValue)
            XCTAssertTrue(lamps.allSatisfy { $0.x > Map3DSeries700.pitch * 0.3 }, "\(unit.rawValue): the lamps on the nose")
            // Its windscreen and its lamps are apart, as the old car's
            // (the 700T's black mask over both is the 700T's own).
            if unit.isCab { Map3DTHSR700TTests.assertTheRedLampsAreOutside(model) }
            XCTAssertFalse(unit.isCab && model.vertices.contains { $0.color == Map3DPalette.dark && $0.x > 7 && $0.z > 2 && abs($0.y) < 1.2 },
                           unit.rawValue)
        }
    }

    /// Sixteen cars as the real train's: a cab car at each end (the back
    /// one the other end's car, turned round), the cars under a pantograph
    /// fifth and twelfth, the cars with wide windows eighth to tenth, each
    /// car 25 m (the cab cars 27 m) with no gap; the ends' lamps lit.
    func testTheSixteenCarsAreLaid() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DSeries700.key
        let laid = try XCTUnwrap(pack.layout(forType: key, count: 16))
        XCTAssertEqual(laid.map { pack.models[$0.model].name },
                       ["head", "car", "car", "car", "panto", "car", "car", "centre", "centre", "centre", "carBack", "pantoBack",
                        "carBack", "carBack", "carBack", "tail"].map { "set-\(key)-\($0)" })
        XCTAssertTrue(laid.allSatisfy { $0.gap == 0 })
        XCTAssertEqual(laid.map(\.length).reduce(0, +), 14 * 25 + 2 * 27, accuracy: 0.1)
        // The two pantographs face each other.
        let roof = pack.models[laid[1].model].maximum.z
        func pantograph(_ car: Int) -> Float {
            let high = pack.models[laid[car].model].vertices.filter { $0.z > roof + 0.1 }.map(\.x)
            return high.reduce(0, +) / Float(max(high.count, 1))
        }
        XCTAssertLessThan(pantograph(4), -1)
        XCTAssertGreaterThan(pantograph(11), 1)
        // The back cab car is the other end's, its nose at the train's back.
        let tail = pack.models[laid[15].model], other = try XCTUnwrap(Map3DSeries700.model(.tail))
        XCTAssertEqual(tail.triangleCount, other.triangleCount)
        XCTAssertEqual(tail.minimum.x, -other.maximum.x, accuracy: 1e-3)
        for count in 1...16 {
            for car in 0..<count { XCTAssertNotNil(pack.modelIndex(forType: key, carIndex: car, count: count), "\(count) cars, car \(car)") }
        }
        let set = try XCTUnwrap(Map3DTrainSet.byKey[key])
        let head = try XCTUnwrap(pack.lights[try XCTUnwrap(pack.index(of: set.headName))]).lamps(atFront: true)
        XCTAssertFalse(head.head.isEmpty)
        XCTAssertTrue(head.head.allSatisfy { $0.color == Map3DTrainStyle.headlamp && $0.x > 5 })
        let back = try XCTUnwrap(pack.lights[try XCTUnwrap(pack.index(of: set.tailName))]).lamps(atFront: false)
        XCTAssertFalse(back.tail.isEmpty)
        XCTAssertTrue(back.tail.allSatisfy { $0.color == Map3DPalette.lantern && $0.x < -5 })
    }

    /// A train of the garage, on standard gauge, with no far set; no
    /// line's trains are drawn with it, and the 700T keeps its place.
    func testItIsATrainOfTheGarage() throws {
        let key = Map3DSeries700.key
        XCTAssertEqual(Map3DTrainRegistry.registration(ofSet: key)?.id, Map3DSeries700.registration.id)
        let set = try XCTUnwrap(Map3DTrainSet.byKey[key])
        XCTAssertNil(set.far)
        XCTAssertFalse(Map3DTrainSet.nearOnly.contains(key))
        let entry = try XCTUnwrap(Map3DShowcase.entry(key))
        XCTAssertEqual(entry.category, .highSpeed)
        XCTAssertEqual(entry.defaultCars, 16)
        XCTAssertEqual(entry.gauge, 1.435)
        XCTAssertEqual(entry.name(in: .traditionalChinese), "700 系")
        XCTAssertEqual(entry.name(in: .english), "700 Series")
        XCTAssertEqual(Map3DTrainSet.named("HSR")?.key, Map3DTHSR700T.key)
        for number in 0..<8 { XCTAssertNotEqual(Map3DTrainSet.variant(of: "HSR", number: number), key) }
        XCTAssertFalse(TrainPack.sets.contains(key))
        XCTAssertNil(TrainPaintFamily.named(set: key))
    }
}
