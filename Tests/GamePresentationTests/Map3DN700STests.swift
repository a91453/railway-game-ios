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
    /// the coupling on the centre line, so two cars are 4 cm apart and not
    /// 0.6 m of open air beside a narrow gangway (the owner: the first car
    /// and the second were too far apart). The blue lines are not carried
    /// across it. Seen from above its mouth is a shallow V, closed in the
    /// dark grey; only the coupler's dark wedge reaches the coupling.
    func testTheHoodsCloseTheGapBetweenCars() throws {
        let gap = Map3DN700S.hoodGap, taper = Map3DN700S.hoodTaper
        for unit in Map3DN700S.Unit.allCases {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            let half = Map3DN700S.length(unit) / 2
            for end: Float in unit.isCab ? [-1] : [-1, 1] {
                let name = "\(unit.rawValue) \(end)"
                func mouth(_ vertex: Map3DVertex) -> Float { half - gap - abs(vertex.y) * taper }
                // Its outside: the white and the grey past the end wall.
                let hood = model.vertices.filter { $0.x * end > half - 0.29 && $0.color != Map3DPalette.dark }
                let rim = hood.filter { abs($0.x * end - mouth($0)) < 0.002 }
                XCTAssertEqual(hood.map { $0.x * end }.max() ?? 0, half - gap, accuracy: 0.002, "\(name): 2 cm short in the middle")
                XCTAssertTrue(hood.allSatisfy { $0.x * end <= mouth($0) + 0.002 }, "\(name): the V")
                XCTAssertEqual(rim.map { abs($0.y) }.max() ?? 0, 1.68, accuracy: 0.01, "\(name): as wide as the body")
                XCTAssertEqual(rim.map(\.z).max() ?? 0, 3.60, accuracy: 0.01, "\(name): to the roof")
                XCTAssertEqual(rim.map(\.z).min() ?? 9, 0.20, accuracy: 0.02, "\(name): to the skirt's foot")
                XCTAssertTrue(rim.allSatisfy { $0.color == ($0.z > 0.95 ? Map3DTrainShapeRefresh.highSpeedBodyColor : $0.z < 0.94 ? Map3DPalette.steel : $0.color) }, name)
                // Past the mouth only the dark coupler, its edge at the
                // coupling on the centre line.
                let past = model.vertices.filter { $0.x * end > mouth($0) + 0.002 }
                XCTAssertTrue(past.allSatisfy { $0.color == Map3DPalette.dark && abs($0.y) <= 0.05 && $0.z > 0.9 && $0.z < 1.1 }, name)
                XCTAssertEqual(model.vertices.map { $0.x * end }.max() ?? 0, half, accuracy: 0.001, "\(name): the coupler")
            }
        }
    }

    /// Two cars turned 3 degrees to each other on a curve, each half that
    /// about their joint, keep their hoods 3 cm apart (a straight mouth's
    /// would cross 5 cm into each other: the studio's first review); only
    /// the couplers' tips, on the centre line at the joint, touch.
    func testTheHoodsKeepApartOnACurve() throws {
        let turn = Float(1.5) * .pi / 180
        for unit in Map3DN700S.Unit.allCases {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            let half = Map3DN700S.length(unit) / 2
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
            let wall = model.vertices.filter { abs($0.y) > 1.67 && $0.x < 4.9 }
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

    /// Each door is a piece of its own: its triangles, on each side, are
    /// the model's run the tool wrote as the door's node, all of them
    /// inside its box, and no triangle of the wall's is on the door
    /// (without the door the wall has its opening, as whole as the door
    /// was: the studio's first review found wall faces 161 to 343 mm²
    /// over the doors), so a door can be moved apart from the wall (to
    /// open at a station) without the mesh cut again.
    func testEachDoorIsAPieceOfItsOwn() throws {
        XCTAssertEqual(Map3DN700S.Unit.allCases.map { Map3DN700S.doors($0).count }, [3, 2, 2])
        XCTAssertEqual(Map3DN700S.doors(.cab).map(\.crew), [true, false, false])
        func corners(_ model: Map3DModelPack.Model, _ triangle: Int) -> [Map3DPoint] {
            model.vertices[3 * triangle..<3 * triangle + 3].map { Map3DPoint($0.x, $0.y, $0.z) }
        }
        // Whether (x, z) is inside `points`, seen from the side.
        func inside(_ x: Float, _ z: Float, _ points: [Map3DPoint]) -> Bool {
            func cross(_ a: Map3DPoint, _ b: Map3DPoint) -> Float { (b.x - a.x) * (z - a.z) - (b.z - a.z) * (x - a.x) }
            let turns = [cross(points[0], points[1]), cross(points[1], points[2]), cross(points[2], points[0])]
            return turns.allSatisfy { $0 > 1e-7 } || turns.allSatisfy { $0 < -1e-7 }
        }
        // The area a triangle covers seen from the side.
        func side(_ points: [Map3DPoint]) -> Float {
            abs((points[1].x - points[0].x) * (points[2].z - points[0].z) - (points[2].x - points[0].x) * (points[1].z - points[0].z)) / 2
        }
        for unit in Map3DN700S.Unit.allCases {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            let doors = Map3DN700S.doors(unit)
            // The doors' nodes follow the body's, one after the other, to
            // the model's last triangle.
            let runs = doors.flatMap { [$0.left, $0.right] }.sorted { $0.lowerBound < $1.lowerBound }
            XCTAssertEqual(runs.last?.upperBound, model.triangleCount, unit.rawValue)
            for (run, next) in zip(runs, runs.dropFirst()) { XCTAssertEqual(run.upperBound, next.lowerBound, unit.rawValue) }
            let wall = Set(0..<model.triangleCount).subtracting(runs.flatMap { Array($0) })
            for door in doors {
                XCTAssertGreaterThan(door.x.upperBound - door.x.lowerBound, 0.45, unit.rawValue)
                XCTAssertGreaterThan(door.z.upperBound - door.z.lowerBound, 1.4, unit.rawValue)
                for sign in [Float(1), -1] {
                    let name = "\(unit.rawValue): the door at x \(door.x), side \(sign)"
                    let own = door.triangles(side: sign)
                    XCTAssertGreaterThan(own.count, 40, name)
                    var glass = 0, frame = 0, covered: Float = 0
                    for triangle in own {
                        let points = corners(model, triangle)
                        XCTAssertTrue(points.allSatisfy { door.contains($0) && $0.y * sign > 1.5 }, name)
                        covered += side(points)
                        if model.vertices[3 * triangle].color == Map3DTrainStyle.glass { glass += 1 }
                        if model.vertices[3 * triangle].color == Map3DPalette.steel { frame += 1 }
                    }
                    XCTAssertGreaterThan(glass, 0, name)
                    XCTAssertGreaterThan(frame, 5, name)
                    // Nothing of the wall's is on the door: no wall face's
                    // middle inside one of the door's faces, seen from the
                    // side. (Its outline is near its box, a little off square
                    // where the texture was: a passenger door covers its box
                    // within 1%.)
                    let leaf = own.map { corners(model, $0) }
                    for triangle in wall {
                        let points = corners(model, triangle)
                        guard points.allSatisfy({ $0.y * sign > 1.5 }) else { continue }
                        let x = (points[0].x + points[1].x + points[2].x) / 3, z = (points[0].z + points[1].z + points[2].z) / 3
                        guard door.contains(Map3DPoint(x, points[0].y, z), margin: 0.01) else { continue }
                        XCTAssertFalse(leaf.contains { inside(x, z, $0) }, "\(name): the wall's triangle \(triangle) on it")
                    }
                    guard !door.crew else { continue }
                    let box = (door.x.upperBound - door.x.lowerBound) * (door.z.upperBound - door.z.lowerBound)
                    XCTAssertEqual(covered, box, accuracy: box * 0.01, name)
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
        for (lens, faces) in [(Map3DTrainStyle.headlamp, 11), (Map3DPalette.lantern, 9)] {
            let lamps = cab.vertices.filter { $0.color == lens }
            XCTAssertGreaterThan(lamps.map(\.x).min() ?? 0, Map3DN700S.pitch * 0.3, "the lamps on the nose")
            // The same lamp on each shoulder: as many faces, each where the
            // other's mirror image is to 5 mm (the old car's two sides are
            // a few millimetres apart).
            for sign in [Float(1), -1] {
                XCTAssertEqual(lamps.filter { $0.y * sign > 0.5 }.count, 3 * faces, "\(lens) on the \(sign) shoulder")
            }
            // The lamp's middle, its faces weighed by their areas.
            func middle(_ side: [Map3DVertex]) -> Map3DPoint {
                var sum = Map3DPoint(0, 0, 0), total: Float = 0
                for first in stride(from: 0, to: side.count, by: 3) {
                    let a = side[first], b = side[first + 1], c = side[first + 2]
                    let p = Map3DPoint(a.x, abs(a.y), a.z), q = Map3DPoint(b.x, abs(b.y), b.z), r = Map3DPoint(c.x, abs(c.y), c.z)
                    let area = (q - p).cross(r - p).length / 2
                    sum = sum + (p + q + r) * (area / 3)
                    total += area
                }
                return sum * (1 / total)
            }
            let left = middle(lamps.filter { $0.y > 0 }), right = middle(lamps.filter { $0.y < 0 })
            XCTAssertEqual(left.x, right.x, accuracy: 0.005, "\(lens)")
            XCTAssertEqual(left.y, right.y, accuracy: 0.005, "\(lens)")
            XCTAssertEqual(left.z, right.z, accuracy: 0.005, "\(lens)")
        }
        // The windscreen over the nose, on the car's centre line too.
        XCTAssertFalse(cab.vertices.filter { $0.color == Map3DTrainStyle.glass && $0.x > 5.5 && abs($0.y) < 0.3 }.isEmpty)
        for unit in [Map3DN700S.Unit.middle, .pantograph] {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            XCTAssertTrue(model.vertices.allSatisfy { $0.color != Map3DTrainStyle.headlamp && $0.color != Map3DPalette.lantern }, unit.rawValue)
        }
    }

    /// The cab car is the real one's 27.35 m, and its nose has no stretch
    /// of its own (the owner's rule): the tip is at the car's front end,
    /// and the side walls reach their full width as far behind it as the
    /// old car's did, times the factor the middle cars' length has.
    func testTheNoseHasNoStretchOfItsOwn() throws {
        let cab = try XCTUnwrap(Map3DN700S.model(.cab))
        XCTAssertEqual(Map3DN700S.cabLength, 27.35)
        XCTAssertEqual(cab.maximum.x, 13.675, accuracy: 0.01, "the tip at the car's front end")
        // (Full width: 1.68 m from the centre line. A cut's new vertex a
        // little way into the nose's taper is not the wall's end.)
        let wall = cab.vertices.filter { abs($0.y) > 1.675 && $0.z > 2.5 }.map(\.x).max() ?? 0
        XCTAssertEqual(Map3DN700S.noseLength, 8.82, accuracy: 0.005)
        XCTAssertEqual(cab.maximum.x - wall, Map3DN700S.noseLength, accuracy: 0.03)
    }

    /// The cab car's saloon is the real first car's: thirteen windows on
    /// each side, 1.023 m from one to the next (the cab cars' seat pitch),
    /// each as wide as a middle car's (0.52 m), and passenger doors as
    /// wide as a middle car's (0.74 m); the driver's door 8.4 m behind
    /// the tip (the real car's some 8.0 to 8.3 m, by photographs).
    func testTheCabCarHasTheRealCarsProportions() throws {
        func windows(_ unit: Map3DN700S.Unit, side: Float) throws -> [ClosedRange<Float>] {
            let model = try XCTUnwrap(Map3DN700S.model(unit))
            let doors = Map3DN700S.doors(unit)
            var spans: [ClosedRange<Float>] = []
            for first in stride(from: 0, to: model.vertices.count, by: 3) where model.vertices[first].color == Map3DTrainStyle.glass {
                let points = model.vertices[first..<first + 3]
                guard points.allSatisfy({ $0.y * side > 1.5 }),
                      !doors.contains(where: { $0.triangles(side: side).contains(first / 3) }) else { continue }
                let xs = points.map(\.x)
                let low = try XCTUnwrap(xs.min()), high = try XCTUnwrap(xs.max())
                spans.append(low...high)
            }
            var merged: [ClosedRange<Float>] = []
            for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if let last = merged.last, span.lowerBound <= last.upperBound + 0.002 {
                    merged[merged.count - 1] = last.lowerBound...max(last.upperBound, span.upperBound)
                } else {
                    merged.append(span)
                }
            }
            return merged
        }
        let cab = try XCTUnwrap(Map3DN700S.model(.cab))
        let doors = Map3DN700S.doors(.cab)
        for side in [Float(1), -1] {
            // (Behind the front passenger door: the windscreen and the
            // cab's side windows are ahead of it.)
            let saloon = try windows(.cab, side: side).filter { $0.upperBound < doors[1].x.lowerBound }
            XCTAssertEqual(saloon.count, Map3DN700S.cabWindows)
            let middle = try windows(.middle, side: side).filter { $0.upperBound - $0.lowerBound > 0.4 }
            let width = try XCTUnwrap(middle.first.map { $0.upperBound - $0.lowerBound })
            XCTAssertEqual(width, 0.52, accuracy: 0.005, "a middle car's window")
            for window in saloon {
                XCTAssertEqual(window.upperBound - window.lowerBound, width, accuracy: 0.005)
            }
            for (window, next) in zip(saloon, saloon.dropFirst()) {
                XCTAssertEqual(next.lowerBound - window.lowerBound, Map3DN700S.cabWindowPitch, accuracy: 0.003)
            }
        }
        let middleDoor = try XCTUnwrap(Map3DN700S.doors(.middle).first)
        for door in doors where !door.crew {
            XCTAssertEqual(door.x.upperBound - door.x.lowerBound, middleDoor.x.upperBound - middleDoor.x.lowerBound, accuracy: 0.01)
        }
        let crew = try XCTUnwrap(doors.first { $0.crew })
        XCTAssertEqual(cab.maximum.x - (crew.x.lowerBound + crew.x.upperBound) / 2, 8.43, accuracy: 0.02)
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
        // Every face of the lamps' lit, eleven white ones a shoulder at the
        // head and nine red ones at the tail, and nothing else.
        let first = cars.head.vertices.filter { $0.layer == Map3DVertex.glowing }
        let last = try XCTUnwrap(cars.tail).vertices.filter { $0.layer == Map3DVertex.glowing }
        XCTAssertTrue(first.allSatisfy { $0.color == Map3DTrainStyle.headlamp })
        XCTAssertTrue(last.allSatisfy { $0.color == Map3DPalette.lantern })
        for sign in [Float(1), -1] {
            XCTAssertEqual(first.filter { $0.y * sign > 0.5 }.count, 3 * 11, "the head's white lamp on the \(sign) shoulder")
            XCTAssertEqual(last.filter { $0.y * sign > 0.5 }.count, 3 * 9, "the tail's red lamp on the \(sign) shoulder")
        }
        XCTAssertEqual(first.count, 3 * 22)
        XCTAssertEqual(last.count, 3 * 18)
        for car in [try XCTUnwrap(cars.middle), try XCTUnwrap(cars.pantograph)] {
            XCTAssertFalse(car.vertices.contains { $0.layer == Map3DVertex.glowing })
        }
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
        // N700ST-PAINT: the high-speed type's odd-numbered trains wear the
        // N700ST's paint on these cars (`Map3DN700STTests`).
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 1), Map3DN700ST.key)
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
