import GameCore
import XCTest
@testable import GamePresentation

/// Decision 986: the Keikyu New 1000 at its real 18 m
/// (``Map3DKeikyuNew1000``), the train of the type `KEIKYU1000`: the
/// general train's 20 m cars (``Map3DRedCommuter``) shortened, their wheels
/// where the gauge puts them. The middle car is shortened as a whole; the
/// cab car keeps its front (from the front door's frame forward: the small
/// window, the crew door and the nose) as it was and shortens the rest,
/// which is nearer the real car (decision 986 §4, the real-car table).
final class Map3DKeikyuNew1000At18Tests: XCTestCase {
    /// Each 18 m car beside the 20 m car it was made from, near and far.
    private func pairs() throws -> [(name: String, short: Map3DModelPack.Model, long: Map3DModelPack.Model)] {
        var pairs: [(name: String, short: Map3DModelPack.Model, long: Map3DModelPack.Model)] = []
        for far in [false, true] {
            pairs.append(("cab" + (far ? " far" : ""), try XCTUnwrap(Map3DKeikyuNew1000.cab(far: far)),
                          try XCTUnwrap(Map3DRedCommuter.cab(far: far))))
            pairs.append(("middle" + (far ? " far" : ""), try XCTUnwrap(Map3DKeikyuNew1000.middle(far: far)),
                          try XCTUnwrap(Map3DRedCommuter.middle(far: far))))
        }
        return pairs
    }

    /// Where a point of the 20 m car is on the 18 m one: the middle car
    /// nine tenths as far from its middle; the cab car's body from the rear
    /// coupler face to 7.61 m (the front door frame's front edge) shortened
    /// to 15.61 m, its front moved back a metre as it is.
    private func along(_ x: Float, cab: Bool) -> Float {
        guard cab else { return x * 0.9 }
        let front: Float = 7.61
        return x <= front ? -9 + (x + 10) * (8 + front) / (10 + front) : x - 1
    }

    /// Where along the car each wheel's foot is (the vertices under
    /// 0.30 m, below the bogie frames), front to back.
    private func wheels(_ model: Map3DModelPack.Model) -> [ClosedRange<Float>] {
        var found: [ClosedRange<Float>] = []
        for x in model.vertices.filter({ $0.z < 0.30 }).map(\.x).sorted() {
            if let last = found.last, x - last.upperBound < 0.5 {
                found[found.count - 1] = last.lowerBound...x
            } else {
                found.append(x...x)
            }
        }
        return found
    }

    /// 18.00 m from coupler to coupler; across and upward the 20 m car's
    /// own size (2.80 m wide, 3.904 m tall), its triangles (and on the near
    /// cars the 16 of the four window pillars) and its colours.
    func testEveryCarIsEighteenMetresAndOtherwiseTheTwentyMetreCars() throws {
        for (name, short, long) in try pairs() {
            XCTAssertEqual(short.minimum.x, -9.00, accuracy: 0.005, name)
            XCTAssertEqual(short.maximum.x, 9.00, accuracy: 0.005, name)
            XCTAssertEqual(short.length, Map3DKeikyuNew1000.carLength, accuracy: 0.005, name)
            XCTAssertEqual(short.minimum.y, long.minimum.y, accuracy: 0.001, name)
            XCTAssertEqual(short.maximum.y, long.maximum.y, accuracy: 0.001, name)
            XCTAssertEqual(short.maximum.y, 1.40, accuracy: 0.005, name)
            XCTAssertEqual(short.minimum.z, 0, accuracy: 0.002, name)
            XCTAssertEqual(short.maximum.z, long.maximum.z, accuracy: 0.001, name)
            XCTAssertEqual(short.triangleCount, long.triangleCount + (name.hasSuffix("far") ? 0 : 16), name)
            XCTAssertEqual(Set(short.vertices.map(\.color)), Set(long.vertices.map(\.color)), name)
            XCTAssertEqual(short.vertices.filter(\.glows).count, long.vertices.filter(\.glows).count, name)
        }
    }

    /// The wheels were moved, not squashed: each is as long as the 20 m
    /// car's, a bogie's two axles are as far apart (2.125 m), the bogie's
    /// middle is where the shortening puts the 20 m car's, and a wheel's tread
    /// stands 0.630 to 0.805 m from the middle of the track, so an axle's
    /// two wheels are 1.435 m apart, centre to centre.
    func testTheWheelsStayRoundAndOnTheGauge() throws {
        for (name, short, long) in try pairs() {
            let shortWheels = wheels(short), longWheels = wheels(long)
            XCTAssertEqual(shortWheels.count, 4, name)
            XCTAssertEqual(longWheels.count, 4, name)
            guard shortWheels.count == 4, longWheels.count == 4 else { continue }
            func middle(_ range: ClosedRange<Float>) -> Float { (range.lowerBound + range.upperBound) / 2 }
            for (a, b) in zip(shortWheels, longWheels) {
                XCTAssertEqual(a.upperBound - a.lowerBound, b.upperBound - b.lowerBound, accuracy: 0.002, "\(name): a wheel's length")
            }
            for bogie in [0, 2] {
                let base = middle(shortWheels[bogie + 1]) - middle(shortWheels[bogie])
                XCTAssertEqual(base, 2.125, accuracy: 0.005, "\(name): a bogie's wheelbase")
                XCTAssertEqual(base, middle(longWheels[bogie + 1]) - middle(longWheels[bogie]), accuracy: 0.002, name)
                let centre = (middle(shortWheels[bogie]) + middle(shortWheels[bogie + 1])) / 2
                let before = (middle(longWheels[bogie]) + middle(longWheels[bogie + 1])) / 2
                XCTAssertEqual(centre, along(before, cab: name.hasPrefix("cab")), accuracy: 0.005, "\(name): the bogie's place")
            }
            let feet = short.vertices.filter { $0.z < 0.30 }.map { abs($0.y) }
            XCTAssertEqual(feet.min() ?? 0, 0.630, accuracy: 0.002, name)
            XCTAssertEqual(feet.max() ?? 0, 0.805, accuracy: 0.002, name)
            XCTAssertEqual((feet.min() ?? 0) + (feet.max() ?? 0), 1.435, accuracy: 0.003, "\(name): the gauge")
        }
    }

    /// The cab's front is the 20 m car's, a metre back and not squashed:
    /// every point of it ahead of the front door's frame is there, so the
    /// nose keeps its length to its width. Behind it the doors stand where
    /// the shortening puts them, nearer the real car's than a car shortened
    /// as a whole (decision 986 §4: real door centres -5.40, 0.005 and
    /// 5.41 m, these -5.135, 0.226 and 5.892; the crew door, a metre back,
    /// at 8.413). A door is its frame's posts, at most 0.8 m apart.
    func testTheCabKeepsItsFrontAndShortensItsBody() throws {
        struct Point: Hashable { let x: Int, y: Int, z: Int }
        func key(_ x: Float, _ y: Float, _ z: Float) -> Point {
            Point(x: Int((x * 1000).rounded()), y: Int((y * 1000).rounded()), z: Int((z * 1000).rounded()))
        }
        for far in [false, true] {
            let short = try XCTUnwrap(Map3DKeikyuNew1000.cab(far: far))
            let long = try XCTUnwrap(Map3DRedCommuter.cab(far: far))
            let points = Set(short.vertices.map { key($0.x, $0.y, $0.z) })
            let front = long.vertices.filter { $0.x > 7.62 && $0.z > 1.06 }
            XCTAssertGreaterThan(front.count, 20)
            for v in front {
                XCTAssertTrue(points.contains(key(v.x - 1, v.y, v.z)), "far \(far): \(v.x), \(v.y), \(v.z) is not a metre back")
            }
        }
        let cab = try XCTUnwrap(Map3DKeikyuNew1000.cab())
        let frames = cab.vertices.filter { $0.y > 1.39 && $0.color == Map3DPalette.steel && $0.z > 1.1 && $0.z < 3.3 }.map(\.x).sorted()
        var doors: [ClosedRange<Float>] = []
        for x in frames {
            if let last = doors.last, x - last.upperBound < 0.8 { doors[doors.count - 1] = last.lowerBound...x } else { doors.append(x...x) }
        }
        XCTAssertEqual(doors.count, 4, "three doors and the crew door: \(doors)")
        guard doors.count == 4 else { return }
        for (door, centre) in zip(doors, [Float(-5.135), 0.226, 5.892, 8.413]) {
            XCTAssertEqual((door.lowerBound + door.upperBound) / 2, centre, accuracy: 0.01)
        }
    }

    /// The pair of windows between two doors is two windows on the near
    /// cars: the glass cut in two 75 mm apart and a pillar of the dark
    /// colour in the gap, in the glass's plane, two pairs a side; the far
    /// cars keep one pane (the studio's review of revision-5, decision 986
    /// §4).
    func testTheWindowPairsHaveTheirPillarsNear() throws {
        for far in [false, true] {
            for (name, car) in [("cab", try XCTUnwrap(Map3DKeikyuNew1000.cab(far: far))),
                                ("middle", try XCTUnwrap(Map3DKeikyuNew1000.middle(far: far)))] {
                let pillars = car.vertices.filter { abs($0.y) > 1.399 && $0.z > 2.1 && $0.z < 3.1 && $0.color == Map3DPalette.dark }
                // Two triangles a pillar, three vertices each.
                XCTAssertEqual(pillars.count, far ? 0 : 24, "\(name) far \(far)")
                for side: Float in [-1, 1] {
                    let xs = pillars.filter { $0.y * side > 0 }.map(\.x).sorted()
                    guard !far, xs.count == 12 else { continue }
                    XCTAssertEqual(xs[5] - xs[0], 0.075, accuracy: 0.002, "\(name)")
                    XCTAssertEqual(xs[11] - xs[6], 0.075, accuracy: 0.002, "\(name)")
                }
            }
        }
    }

    /// The lamps are the cab's own lenses at its face, the white band and
    /// the body where the 20 m car has them.
    func testTheLampsAndTheBandAreWhereTheyWere() throws {
        for far in [false, true] {
            let cab = try XCTUnwrap(Map3DKeikyuNew1000.cab(far: far))
            let lit = cab.vertices.filter(\.glows)
            XCTAssertTrue(lit.contains { $0.color == Map3DTrainStyle.headlamp })
            XCTAssertTrue(lit.contains { $0.color == Map3DPalette.lantern })
            XCTAssertGreaterThan(lit.map(\.x).min() ?? 0, 8.8)
            XCTAssertFalse(try XCTUnwrap(Map3DKeikyuNew1000.middle(far: far)).vertices.contains(where: \.glows))
        }
        let middle = try XCTUnwrap(Map3DKeikyuNew1000.middle())
        let side = middle.vertices.filter { abs($0.x) < 7 && $0.y > 1.39 }
        let white = side.filter { $0.color == Map3DPalette.acUnit }.map(\.z)
        XCTAssertEqual(white.min() ?? 0, 1.915, accuracy: 0.01)
        XCTAssertEqual(white.max() ?? 0, 3.24, accuracy: 0.01)
        XCTAssertTrue(side.contains { $0.color == Map3DTrainStyle.glass && $0.layer == Map3DVertex.trainGlass })
    }

    /// The type's train is this set, laid at its own 18 m a car with no
    /// gap, the cab turned round at the back, and a far set of its own.
    func testTheTypesTrainIsLaidAtEighteenMetresACar() throws {
        XCTAssertEqual(Map3DTrainSet.byType[TrainType.keikyuNew1000.rawValue], Map3DKeikyuNew1000.key)
        let set = try XCTUnwrap(Map3DTrainSet.byKey[Map3DKeikyuNew1000.key])
        XCTAssertTrue(set.ownLengths)
        XCTAssertEqual(set.far, Map3DKeikyuNew1000.key + "Far")
        XCTAssertNotNil(Map3DTrainSet.byKey[Map3DKeikyuNew1000.key + "Far"])
        let pack = Map3DModelPack.standard
        for count in [4, 6, 8, 12] {
            let layout = try XCTUnwrap(pack.layout(forType: TrainType.keikyuNew1000.rawValue, count: count), "\(count) cars")
            XCTAssertEqual(layout.count, count)
            for car in layout {
                XCTAssertEqual(car.length, 18.00, accuracy: 0.005)
                XCTAssertEqual(car.gap, 0, accuracy: 0.005)
            }
            XCTAssertEqual(pack.models[layout[0].model].name, "set-keikyuNew1000-head")
            XCTAssertEqual(pack.models[layout[count - 1].model].name, "set-keikyuNew1000-tail")
        }
        XCTAssertEqual(Map3DShowcase.entry(Map3DKeikyuNew1000.key)?.category, .japan)
        XCTAssertEqual(Map3DShowcase.entry(Map3DKeikyuNew1000.key)?.chinese, "京急新1000形")
    }

    /// The fit the change is for: the length the game gives a car of the
    /// type (its slot on the track and at a platform) is the length the
    /// car is drawn, so an eight-car train takes 144 m of both; and the
    /// car stands as the 20 m car does beside a platform and under the
    /// game's structures.
    func testTheDrawnCarFillsTheTypesSlotAndClearsThePlatform() throws {
        let slot = Float(TrainType.keikyuNew1000.carLength) / Float(WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(slot, Map3DKeikyuNew1000.carLength, accuracy: 0.001)
        let cab = try XCTUnwrap(Map3DKeikyuNew1000.cab())
        XCTAssertEqual(cab.length, slot, accuracy: 0.005)
        XCTAssertLessThan(cab.maximum.y, Map3DScene.Builder.platformEdge)
        XCTAssertEqual(Map3DScene.Builder.platformHeight - 1.00, 0.15, accuracy: 0.001)
        XCTAssertLessThan(cab.maximum.z, Map3DScene.Builder.contactHeight)
        XCTAssertLessThan(cab.maximum.z, Map3DScene.Builder.boreCrown)
    }

    /// The general train of four cars or more keeps its 20 m cars: this
    /// change does not move it.
    func testTheGeneralTrainKeepsItsTwentyMetreCars() throws {
        let pack = Map3DModelPack.standard
        let layout = try XCTUnwrap(pack.layout(forType: "", count: 4))
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 80.0, accuracy: 0.05)
        XCTAssertEqual(pack.models[layout[0].model].name, "set-redCommuter-head")
    }
}
