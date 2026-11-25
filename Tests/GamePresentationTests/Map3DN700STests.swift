import XCTest
@testable import GamePresentation

/// Decision 979: the N700S, the owner's old cars cut into faces of the
/// palette's colours, in the N700S-G's place.
final class Map3DN700STests: XCTestCase {
    func testTheThreeUnitsDecodeAtTheRealSize() throws {
        for unit in Map3DN700S.Unit.allCases {
            let model = try XCTUnwrap(Map3DN700S.model(unit), unit.rawValue)
            XCTAssertEqual(model.length, Map3DN700S.length(unit), accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(model.maximum.y - model.minimum.y, 3.36, accuracy: 0.02, "\(unit.rawValue) is 3.36 m wide")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.03, unit.rawValue)
            XCTAssertTrue(Map3DN700S.registration.triangles.contains(model.triangleCount), unit.rawValue)
            // The roof 3.60 m up, where nothing stands on it: the middle
            // car's middle, the pantograph car's front half (its cover and
            // shields are at its back) and the cab car's back (its roof
            // comes down toward the nose, its aerial is at the very end).
            let plain: ClosedRange<Float> = unit == .cab ? -11 ... -7 : unit == .pantograph ? 2...8 : -2...2
            let roof = model.vertices.filter { plain.contains($0.x) && $0.color == Map3DTrainShapeRefresh.highSpeedBodyColor }.map(\.z).max()
            // (A cable duct 4 cm high runs along the pantograph car's roof.)
            XCTAssertEqual(try XCTUnwrap(roof), 3.60, accuracy: unit == .pantograph ? 0.05 : 0.01, unit.rawValue)
        }
        // The cab carries its aerial and the middle car its cable cover a
        // little over the roof; the pantograph car's shields stand a metre
        // over it, under the 5.2 m wire.
        XCTAssertEqual(try XCTUnwrap(Map3DN700S.model(.cab)).maximum.z, 3.89, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(Map3DN700S.model(.middle)).maximum.z, 3.80, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(Map3DN700S.model(.pantograph)).maximum.z, 4.61, accuracy: 0.02)
    }

    /// The wheels stand on standard-gauge rails: 1,435 mm between the
    /// rails' inner faces, the wheels' outer faces a little wider.
    func testTheWheelsStandOnStandardGauge() throws {
        for unit in Map3DN700S.Unit.allCases {
            let low = try XCTUnwrap(Map3DN700S.model(unit)).vertices.filter { $0.z < 0.05 }
            XCTAssertFalse(low.isEmpty, unit.rawValue)
            XCTAssertTrue(low.allSatisfy { $0.color == Map3DPalette.dark }, "\(unit.rawValue): only the wheels reach the rail")
            let widest = low.map { abs($0.y) }.max() ?? 0
            XCTAssertGreaterThan(widest, 1.435 / 2, unit.rawValue)
            XCTAssertLessThan(widest, 1.435 / 2 + 0.2, unit.rawValue)
        }
    }

    /// Each coupled end has its hood: the body's outline (its white over
    /// its skirt's grey, the full width and height) drawn out to 2 cm from
    /// the coupling, so two cars are 4 cm apart and not 0.6 m of open air
    /// beside a narrow gangway (the owner: the first car and the second
    /// were too far apart). The blue lines are not carried across it.
    func testTheHoodsCloseTheGapBetweenCars() throws {
        for unit in Map3DN700S.Unit.allCases {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            let half = Map3DN700S.length(unit) / 2
            for end: Float in unit.isCab ? [-1] : [-1, 1] {
                let rim = model.vertices.filter { abs($0.x * end - (half - Map3DN700S.hoodGap)) < 0.002 && $0.color != Map3DPalette.dark }
                let name = "\(unit.rawValue) \(end)"
                XCTAssertEqual(rim.map { abs($0.y) }.max() ?? 0, 1.68, accuracy: 0.01, "\(name): as wide as the body")
                XCTAssertEqual(rim.map(\.z).max() ?? 0, 3.60, accuracy: 0.01, "\(name): to the roof")
                XCTAssertEqual(rim.map(\.z).min() ?? 9, 0.20, accuracy: 0.02, "\(name): to the skirt's foot")
                XCTAssertTrue(rim.allSatisfy { $0.color == ($0.z > 0.95 ? Map3DTrainShapeRefresh.highSpeedBodyColor : $0.z < 0.94 ? Map3DPalette.steel : $0.color) }, name)
                // Nothing of the body's reaches past it but the gangway.
                XCTAssertTrue(model.vertices.allSatisfy { $0.x * end <= half - Map3DN700S.hoodGap + 0.002 || $0.color == Map3DPalette.dark }, name)
            }
        }
    }

    /// The real livery: a white body, the two blue lines along its side
    /// under the windows (the upper one the wider), a grey skirt, and no
    /// colour that is not the palette's.
    func testTheBodyIsWhiteWithTheTwoBlueLines() throws {
        let blue = Map3DPalette.shinkansenBlue
        XCTAssertEqual(Map3DN700S.meshPalette, [
            Map3DTrainShapeRefresh.highSpeedBodyColor, blue, Map3DPalette.steel, Map3DTrainStyle.glass,
            Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern,
        ])
        for unit in Map3DN700S.Unit.allCases {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            XCTAssertTrue(Set(model.vertices.map(\.color)).isSubset(of: Set(Map3DN700S.meshPalette)), unit.rawValue)
            // The side wall behind the cab's nose (every car's back half).
            let side = model.vertices.filter { $0.x > -8 && $0.x < -1 && abs($0.y) > 1.67 }
            let lines = Set(side.filter { $0.color == blue }.map { ($0.z * 100).rounded() / 100 }).sorted()
            let low = try XCTUnwrap(lines.first), high = try XCTUnwrap(lines.last)
            XCTAssertEqual(low, 1.62, accuracy: 0.02, "\(unit.rawValue): the thin line's foot")
            XCTAssertEqual(high, 1.95, accuracy: 0.02, "\(unit.rawValue): the wide line's top")
            // White between the two lines.
            XCTAssertTrue(side.contains { $0.color == Map3DTrainShapeRefresh.highSpeedBodyColor && $0.z > 1.70 && $0.z < 1.76 }, unit.rawValue)
            let glass = side.filter { $0.color == Map3DTrainStyle.glass }.map(\.z)
            XCTAssertFalse(glass.isEmpty, unit.rawValue)
            XCTAssertLessThan(high, glass.min() ?? 0, "\(unit.rawValue): the lines under the windows")
            XCTAssertFalse(side.filter { $0.color == Map3DPalette.steel && $0.z < 1 }.isEmpty, "\(unit.rawValue): the grey skirt")
        }
    }

    /// Each door has its frame: a thin grey line round the leaf, from the
    /// sill under the blue lines to over the door's window (without it a
    /// door is only its small window on the wall; the owner's first look).
    func testTheDoorsHaveTheirFrames() throws {
        for unit in Map3DN700S.Unit.allCases {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            let wall = model.vertices.filter { abs($0.y) > 1.67 && $0.x < 4 }
            let frame = wall.filter { $0.color == Map3DPalette.steel && $0.z > 1.0 }.map(\.z)
            let glass = wall.filter { $0.color == Map3DTrainStyle.glass }.map(\.z)
            let top = try XCTUnwrap(frame.max(), unit.rawValue), sill = try XCTUnwrap(frame.min(), unit.rawValue)
            XCTAssertGreaterThan(top, try XCTUnwrap(glass.max()), "\(unit.rawValue): the frame's top over the door's window")
            XCTAssertLessThan(top, 3.3, unit.rawValue)
            XCTAssertLessThan(sill, 1.3, "\(unit.rawValue): the sill under the blue lines")
            // The frame leaves the blue lines whole.
            XCTAssertFalse(frame.contains { $0 > 1.63 && $0 < 1.94 }, unit.rawValue)
        }
    }

    /// Each door is a piece of its own: no triangle is partly a door's and
    /// partly the wall's, on either side, so a door can be moved apart
    /// from the wall (to open at a station) without the mesh cut again.
    func testEachDoorIsAPieceOfItsOwn() throws {
        XCTAssertEqual(Map3DN700S.Unit.allCases.map { Map3DN700S.doors($0).count }, [3, 2, 2])
        XCTAssertEqual(Map3DN700S.doors(.cab).map(\.crew), [true, false, false])
        for unit in Map3DN700S.Unit.allCases {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            // The side walls' triangles.
            var walls: [(points: [Map3DPoint], color: UInt32)] = []
            for first in stride(from: 0, to: model.vertices.count, by: 3) {
                let points = model.vertices[first..<first + 3].map { Map3DPoint($0.x, $0.y, $0.z) }
                if points.allSatisfy({ abs($0.y) > 1.5 }) { walls.append((points, model.vertices[first].color)) }
            }
            for door in Map3DN700S.doors(unit) {
                XCTAssertGreaterThan(door.x.upperBound - door.x.lowerBound, 0.45, unit.rawValue)
                XCTAssertGreaterThan(door.z.upperBound - door.z.lowerBound, 1.4, unit.rawValue)
                for side in [Float(1), -1] {
                    var own = 0, glass = 0, frame = 0
                    for (triangle, color) in walls where triangle[0].y * side > 0 {
                        if triangle.allSatisfy({ door.contains($0) }) {
                            own += 1
                            if color == Map3DTrainStyle.glass { glass += 1 }
                            if color == Map3DPalette.steel { frame += 1 }
                        } else if !door.crew {
                            // (The driver's door is on the nose's taper,
                            // where its outline is not square to the car:
                            // the tool's node is its piece, this box only
                            // its place.)
                            XCTAssertFalse(triangle.contains { door.contains($0, margin: -0.01) },
                                           "\(unit.rawValue): a triangle crosses the door at x \(door.x)")
                        }
                    }
                    XCTAssertGreaterThan(own, 40, "\(unit.rawValue): the door at x \(door.x), side \(side)")
                    XCTAssertGreaterThan(glass, 0, unit.rawValue)
                    XCTAssertGreaterThan(frame, 5, unit.rawValue)
                }
            }
        }
    }

    /// cab's lamps are on its nose and the other cars have none.
    func testTheGlassAndTheLampsAreMarked() throws {
        for unit in Map3DN700S.Unit.allCases {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            XCTAssertTrue(Map3DTrainMaterial.marksOwnGlass(model), unit.rawValue)
        }
        let cab = try XCTUnwrap(Map3DN700S.model(.cab))
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let lamps = cab.vertices.filter { $0.color == lens }
            XCTAssertFalse(lamps.isEmpty)
            XCTAssertGreaterThan(lamps.map(\.x).min() ?? 0, Map3DN700S.pitch * 0.3, "the lamps on the nose")
            XCTAssertTrue(lamps.contains { $0.y > 0.5 } && lamps.contains { $0.y < -0.5 }, "a lamp on each shoulder")
        }
        // The windscreen over the nose, on the car's centre line too.
        XCTAssertFalse(cab.vertices.filter { $0.color == Map3DTrainStyle.glass && $0.x > 5.5 && abs($0.y) < 0.3 }.isEmpty)
        for unit in [Map3DN700S.Unit.middle, .pantograph] {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            XCTAssertTrue(model.vertices.allSatisfy { $0.color != Map3DTrainStyle.headlamp && $0.color != Map3DPalette.lantern }, unit.rawValue)
        }
    }

    /// The cab car is the real one's 27.35 m, made longer as a whole car:
    /// its nose is given no stretch of its own (the owner's rule). The old
    /// car's nose, 7.41 units from where its full-width side wall ends to
    /// its tip, times the one factor the whole car's length has
    /// (13.675 / 10.501); and its windows as many as the old car's.
    func testTheNoseHasNoStretchOfItsOwn() throws {
        let cab = try XCTUnwrap(Map3DN700S.model(.cab))
        XCTAssertEqual(Map3DN700S.cabLength, 27.35)
        XCTAssertEqual(cab.maximum.x, 13.675, accuracy: 0.01, "the tip at the car's front end")
        // (Full width: 1.68 m from the centre line. A cut's new vertex a
        // little way into the nose's taper is not the wall's end.)
        let wall = cab.vertices.filter { abs($0.y) > 1.675 && $0.z > 2.5 }.map(\.x).max() ?? 0
        XCTAssertEqual(cab.maximum.x - wall, 7.41 * 13.675 / 10.501, accuracy: 0.03)
    }

    /// Twelve cars as the N700S-G's were laid (decision 408): the cab at
    /// each end, the pantograph car fourth and ninth, the back half turned
    /// round, each car 25 m (the cab cars 27.35 m) with no gap; the head's white lamps and the
    /// tail's red lamps lit.
    func testTheTwelveCarsAreLaidAsTheN700SGsWere() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DN700S.key
        XCTAssertEqual(Map3DN700S.cars, 12)
        let laid = try XCTUnwrap(pack.layout(forType: key, count: 12))
        XCTAssertEqual(laid.map { pack.models[$0.model].name }, (["head", "car", "car", "panto", "car", "car", "carBack", "carBack",
                                                                    "pantoBack", "carBack", "carBack", "tail"]).map { "set-\(key)-\($0)" })
        XCTAssertTrue(laid.allSatisfy { $0.gap == 0 })
        XCTAssertEqual(laid.map(\.length).reduce(0, +), 10 * 25 + 2 * 27.35, accuracy: 0.1)
        // The two pantograph covers face each other: the fourth car's at
        // its back, the ninth's at its front.
        let roof = pack.models[laid[1].model].maximum.z
        func cover(_ car: Int) -> Float {
            let high = pack.models[laid[car].model].vertices.filter { $0.z > roof + 0.1 }.map(\.x)
            return high.reduce(0, +) / Float(max(high.count, 1))
        }
        XCTAssertLessThan(cover(3), -1)
        XCTAssertGreaterThan(cover(8), 1)
        for (front, back) in [(1, 10), (3, 8), (0, 11)] {
            let a = pack.models[laid[front].model], b = pack.models[laid[back].model]
            XCTAssertEqual(b.triangleCount, a.triangleCount)
            XCTAssertEqual(b.minimum.x, -a.maximum.x, accuracy: 1e-3, "car \(back + 1) is car \(front + 1) turned")
        }
        for count in 1...16 {
            for car in 0..<count { XCTAssertNotNil(pack.modelIndex(forType: key, carIndex: car, count: count), "\(count) cars, car \(car)") }
        }
        // Decision 449: the pack lights a running car's lamps only at its
        // train's ends, the head's white and the tail's red.
        let set = try XCTUnwrap(Map3DTrainSet.byKey[key])
        let head = try XCTUnwrap(pack.lights[try XCTUnwrap(pack.index(of: set.headName))]).lamps(atFront: true)
        XCTAssertFalse(head.head.isEmpty)
        XCTAssertTrue(head.head.allSatisfy { $0.color == Map3DTrainStyle.headlamp && $0.x > 5 })
        let tail = try XCTUnwrap(pack.lights[try XCTUnwrap(pack.index(of: set.tailName))]).lamps(atFront: false)
        XCTAssertFalse(tail.tail.isEmpty)
        XCTAssertTrue(tail.tail.allSatisfy { $0.color == Map3DPalette.lantern && $0.x < -5 })
        // The nose has both lamps side by side: only the white ones glow
        // on the first car and only the red ones on the last, as the real
        // train's do.
        // (The set's own models: the pack keeps a running car's lamps apart.)
        let cars = set.build()
        let first = cars.head.vertices.filter { $0.layer == Map3DVertex.glowing }
        let last = try XCTUnwrap(cars.tail).vertices.filter { $0.layer == Map3DVertex.glowing }
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(first.allSatisfy { $0.color == Map3DTrainStyle.headlamp })
        XCTAssertFalse(last.isEmpty)
        XCTAssertTrue(last.allSatisfy { $0.color == Map3DPalette.lantern })
    }

    /// It has the N700S-G's place: the train pack's set, the odd-numbered
    /// high-speed trains once the pack is unlocked, the garage's
    /// high-speed row; and the N700S-G's keys name it now, so nothing that
    /// kept one is left without a train.
    func testItHasTheN700SGsPlace() throws {
        XCTAssertNil(Map3DTrainSet.byKey["n700sG"])
        XCTAssertNil(Map3DTrainSet.byKey["n700sGFar"])
        for former in Map3DN700S.formerKeys {
            XCTAssertEqual(Map3DTrainSet.named(former)?.key, Map3DN700S.key, former)
            XCTAssertNotNil(Map3DModelPack.standard.layout(forType: former, count: 12), former)
        }
        XCTAssertTrue(TrainPack.sets.contains(Map3DN700S.key))
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1), Map3DN700S.key)
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1, locked: TrainPack.locked(unlocked: false)), "HSR")
        // No far set: a car is two to three thousand triangles, drawn as
        // far as any train's model.
        XCTAssertNil(try XCTUnwrap(Map3DTrainSet.byKey[Map3DN700S.key]).far)
        XCTAssertFalse(Map3DTrainSet.nearOnly.contains(Map3DN700S.key))
        XCTAssertEqual(Map3DTrainSet.reach(of: Map3DN700S.key), Map3DTrains.modelReach)
        let entry = try XCTUnwrap(Map3DShowcase.entry(Map3DN700S.key))
        XCTAssertEqual(entry.category, .highSpeed)
        XCTAssertEqual(entry.defaultCars, 12)
        XCTAssertEqual(entry.gauge, 1.435)
        XCTAssertNil(Map3DShowcase.entry("n700sG"))
    }
}
