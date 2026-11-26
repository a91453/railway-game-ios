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
            Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern, Map3DPalette.steel, Map3DPalette.mtrCream,
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

    /// Every door has its seams round it (the owner, 2026-11-25: a door's
    /// small window must not float on the wall): thin steel-grey lines on
    /// the side walls, some 1.9 m high, the door between them the body's
    /// colour; the cab car has its crew door and two doors a side, the
    /// middle car a door at each end a side.
    func testEveryDoorHasItsSeams() throws {
        for unit in Map3DKyushuN700.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushuN700.model(unit))
            let seams = model.vertices.filter { $0.color == Map3DPalette.steel }
            XCTAssertFalse(seams.isEmpty, unit.rawValue)
            XCTAssertTrue(seams.allSatisfy { abs($0.y) > 1.3 }, "\(unit.rawValue): the seams on the side walls")
            let height = (seams.map(\.z).max() ?? 0) - (seams.map(\.z).min() ?? 0)
            XCTAssertEqual(height, 1.9, accuracy: 0.25, unit.rawValue)
            for side: Float in [-1, 1] {
                // The seams' upright lines, by where they stand along the car: two a door.
                let uprights = Set(seams.filter { $0.y * side > 0 }.map { ($0.x * 4).rounded() / 4 })
                XCTAssertGreaterThanOrEqual(uprights.count, unit.isCab ? 6 : 4, "\(unit.rawValue) side \(side)")
            }
            // Each door's window stands between a door's seams.
            let glass = model.vertices.filter { $0.color == Map3DTrainStyle.glass && abs($0.y) > 1.3 }
            let doorWindows = glass.filter { $0.z > 3.0 }
            for window in doorWindows {
                XCTAssertTrue(seams.contains { abs($0.x - window.x) < 0.6 && $0.y * window.y > 0 }, "\(unit.rawValue): a door's window with no seam beside it")
            }
        }
    }

    /// Each door is a piece of its own: no triangle is partly a door's and
    /// partly the wall's, on either side, so a door can be moved apart
    /// from the wall (to open at a station) without the mesh cut again.
    /// Each has its seams and its window with it, and its box holds its
    /// faces and no whole face of the wall's (488 faces of the cab car's
    /// six doors, 404 of the middle car's four, as the tool reports them).
    func testEachDoorIsAPieceOfItsOwn() throws {
        XCTAssertEqual(Map3DKyushuN700.Unit.allCases.map { Map3DKyushuN700.doors($0).count }, [3, 2])
        XCTAssertEqual(Map3DKyushuN700.doors(.cab).map(\.crew), [true, false, false])
        XCTAssertEqual(Map3DKyushuN700.doors(.middle).map(\.crew), [false, false])
        for unit in Map3DKyushuN700.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushuN700.model(unit))
            // The side walls' triangles.
            var walls: [(points: [Map3DPoint], color: UInt32)] = []
            for first in stride(from: 0, to: model.vertices.count, by: 3) {
                let points = model.vertices[first..<first + 3].map { Map3DPoint($0.x, $0.y, $0.z) }
                if points.allSatisfy({ abs($0.y) > 1.5 }) { walls.append((points, model.vertices[first].color)) }
            }
            // Every seam is some door's: the seams are the doors' outlines.
            let seams = walls.filter { $0.color == Map3DPalette.steel }
            XCTAssertFalse(seams.isEmpty, unit.rawValue)
            for seam in seams {
                XCTAssertTrue(Map3DKyushuN700.doors(unit).contains { door in seam.points.allSatisfy { door.contains($0) } },
                              "\(unit.rawValue): a seam that is no door's")
            }
            var faces = 0
            for door in Map3DKyushuN700.doors(unit) {
                XCTAssertGreaterThan(door.x.upperBound - door.x.lowerBound, 0.6, unit.rawValue)
                XCTAssertGreaterThan(door.z.upperBound - door.z.lowerBound, 1.6, unit.rawValue)
                for side in [Float(1), -1] {
                    var own = 0, glass = 0, seam = 0
                    for (triangle, color) in walls where triangle[0].y * side > 0 {
                        if triangle.allSatisfy({ door.contains($0) }) {
                            own += 1
                            if color == Map3DTrainStyle.glass { glass += 1 }
                            if color == Map3DPalette.steel { seam += 1 }
                        } else if !door.crew {
                            // (The driver's door is on the nose's taper,
                            // where its outline is not square to the car:
                            // the tool's node is its piece, this box only
                            // its place. A passenger door's outline leans
                            // up to 2.2 cm in its height, as the old
                            // texture lies on the wall.)
                            XCTAssertFalse(triangle.contains { door.contains($0, margin: -0.03) },
                                           "\(unit.rawValue): a triangle crosses the door at x \(door.x)")
                        }
                    }
                    faces += own
                    XCTAssertGreaterThan(own, 40, "\(unit.rawValue): the door at x \(door.x), side \(side)")
                    XCTAssertGreaterThan(glass, 0, unit.rawValue)
                    XCTAssertGreaterThan(seam, 5, unit.rawValue)
                }
            }
            XCTAssertEqual(faces, unit.isCab ? 488 : 404, "\(unit.rawValue): the doors' faces")
        }
    }

    /// Decision 977, section 8: the real cars' proportions, the windows
    /// as the ruler. The windows 1.04 m apart as the seats are (the cab
    /// car's 1.03 m, its nose kept the old one's shape), fourteen a side on
    /// the cab car (the real car 8 has fourteen) and twenty on the middle
    /// car; the middle car's doors 0.94 m from its ends to their middle
    /// (the real car's 0.74 m), and the nose's tip 8.5 m ahead of the
    /// driver's door's middle (the real car's about 8.0 m).
    func testTheCarsAreAtTheRealCarsProportions() throws {
        for unit in Map3DKyushuN700.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushuN700.model(unit))
            for side: Float in [-1, 1] {
                // The windows along the car: the glass triangles of the
                // side wall, the doors' own windows left out, each window
                // the triangles whose spans along the car touch.
                let doors = Map3DKyushuN700.doors(unit)
                var spans: [(low: Float, high: Float)] = []
                for first in stride(from: 0, to: model.vertices.count, by: 3) {
                    let points = model.vertices[first..<first + 3]
                    guard points.allSatisfy({ $0.color == Map3DTrainStyle.glass && $0.y * side > 1.6 }) else { continue }
                    let low = points.map(\.x).min() ?? 0, high = points.map(\.x).max() ?? 0
                    if doors.contains(where: { $0.x.contains((low + high) / 2) }) { continue }
                    spans.append((low, high))
                }
                var windows: [(low: Float, high: Float)] = []
                for span in spans.sorted(by: { $0.low < $1.low }) {
                    if let last = windows.last, span.low <= last.high + 0.005 {
                        windows[windows.count - 1].high = max(last.high, span.high)
                    } else {
                        windows.append(span)
                    }
                }
                // The cab car's small window by its back door is not one of the seats'.
                let seats = windows.filter { $0.high - $0.low > 0.5 }
                XCTAssertEqual(seats.count, unit.isCab ? 14 : 20, "\(unit.rawValue) side \(side)")
                let middles = seats.map { ($0.low + $0.high) / 2 }
                let pitch = ((middles.last ?? 0) - (middles.first ?? 0)) / Float(max(middles.count - 1, 1))
                XCTAssertEqual(pitch, unit.isCab ? 1.03 : 1.04, accuracy: 0.01, "\(unit.rawValue) side \(side)")
            }
        }
        let middleDoor = try XCTUnwrap(Map3DKyushuN700.doors(.middle).first)
        XCTAssertEqual(12.5 - (middleDoor.x.lowerBound + middleDoor.x.upperBound) / 2, 0.94, accuracy: 0.01)
        let crew = try XCTUnwrap(Map3DKyushuN700.doors(.cab).first)
        XCTAssertEqual(27.35 / 2 - (crew.x.lowerBound + crew.x.upperBound) / 2, 8.46, accuracy: 0.05)
    }

    /// The bogies stand where the real car's do (3.75 m from a coupling
    /// face, 17.5 m apart; the cab car's front one 6.10 m behind the nose's
    /// tip), and each sits in the middle of the opening in the skirts that
    /// shows its wheels (the owner, 2026-11-26: the openings had stretched
    /// with the body and the wheels stood at one end of them).
    func testTheWheelsAreInTheMiddleOfTheirOpenings() throws {
        for unit in Map3DKyushuN700.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushuN700.model(unit))
            let half = unit.pitch / 2
            let wheels = model.vertices.filter { $0.color == Map3DPalette.dark && $0.z < 0.3 }.map(\.x).sorted()
            var axles: [[Float]] = []
            for x in wheels {
                if let last = axles.last?.last, x - last < 0.8 { axles[axles.count - 1].append(x) } else { axles.append([x]) }
            }
            XCTAssertEqual(axles.count, 4, unit.rawValue)
            guard axles.count == 4 else { continue }
            // The skirts' foot along the side walls: where the openings begin and end.
            let feet = model.vertices.filter { $0.color == Map3DPalette.kyushuWhiteBlue && abs($0.z - 0.378) < 0.01 && abs($0.y) > 1.1 }.map(\.x)
            var centres: [Float] = []
            for pair in [axles[0] + axles[1], axles[2] + axles[3]] {
                let low = pair.min() ?? 0, high = pair.max() ?? 0, centre = (low + high) / 2
                centres.append(centre)
                let front = try XCTUnwrap(feet.filter { $0 < low }.max(), unit.rawValue)
                let back = try XCTUnwrap(feet.filter { $0 > high }.min(), unit.rawValue)
                XCTAssertEqual((front + back) / 2, centre, accuracy: 0.01, "\(unit.rawValue): the opening's middle is the bogie's")
                XCTAssertEqual(back - front, 4.40, accuracy: 0.05, unit.rawValue)
            }
            XCTAssertEqual(centres[1] - centres[0], 17.5, accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(centres[0], -half + 3.75, accuracy: 0.01, unit.rawValue)
            if unit.isCab {
                XCTAssertEqual(half - centres[1], 6.10, accuracy: 0.01, "the front bogie 6.10 m behind the nose's tip")
            }
        }
    }

    /// Between two cars a full-width hood in the real train's beige, flush
    /// with the body from the skirts to the roof, so the gap between two
    /// cars is not seen through (the old cars had only a narrow gangway,
    /// 0.6 m of open air beside it); only the couplers' wedges are dark.
    /// The cab car has it at its back, the middle car at both ends.
    func testAGangwayHoodClosesTheGapBetweenTwoCars() throws {
        for unit in Map3DKyushuN700.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushuN700.model(unit))
            let half = unit.pitch / 2
            for end: Float in unit.isCab ? [-1] : [-1, 1] {
                let hood = model.vertices.filter { $0.color == Map3DPalette.mtrCream && $0.x * end > 0 }
                XCTAssertFalse(hood.isEmpty, "\(unit.rawValue) end \(end)")
                // Within 4 cm of the coupling plane at the middle, as wide
                // as the body and from near the skirts to near the roof.
                XCTAssertGreaterThan(hood.map { $0.x * end }.max() ?? 0, half - 0.04, unit.rawValue)
                XCTAssertLessThanOrEqual(hood.map { $0.x * end }.max() ?? 0, half - 0.02 + 0.001, unit.rawValue)
                XCTAssertEqual((hood.map(\.y).max() ?? 0) - (hood.map(\.y).min() ?? 0), 3.36, accuracy: 0.05, unit.rawValue)
                XCTAssertGreaterThan((hood.map(\.z).max() ?? 0) - (hood.map(\.z).min() ?? 0), 2.5, unit.rawValue)
            }
            if unit.isCab {
                XCTAssertTrue(model.vertices.allSatisfy { $0.color != Map3DPalette.mtrCream || $0.x < 0 }, "no hood at the nose")
            }
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
        // The headlamps outside, the tail lamps beside them towards the nose's centre line.
        func side(_ lens: UInt32) -> Float {
            let ys = cab.vertices.filter { $0.color == lens }.map { abs($0.y) }
            return ys.reduce(0, +) / Float(max(ys.count, 1))
        }
        XCTAssertGreaterThan(side(Map3DTrainStyle.headlamp), side(Map3DPalette.lantern) + 0.1)
        // The aerial's fin on the roof is a closed plate 2.5 cm thick, seen from either side.
        let fin = cab.vertices.filter { $0.z > 3.61 }
        XCTAssertFalse(fin.filter { $0.ny > 0.9 }.isEmpty)
        XCTAssertFalse(fin.filter { $0.ny < -0.9 }.isEmpty)
        XCTAssertEqual((fin.map(\.y).max() ?? 0) - (fin.map(\.y).min() ?? 0), 0.025, accuracy: 0.002)
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
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 27.35 * 2 + 25.0 * 6, accuracy: 0.1, "204.7 m, as the real train")
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
        // Decision 978: the line's other fleet is the 800 series.
        XCTAssertEqual(Map3DRealTrains.formation(system: "kyushushinkansen", id: "KS", name: "KS"),
                       .init(key: Map3DKyushuN700.key, cars: 8, alternate: Map3DKyushu800.key))
    }
}
