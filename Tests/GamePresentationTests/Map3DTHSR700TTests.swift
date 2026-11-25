import XCTest
@testable import GamePresentation

/// Decision 988: the 700T, the owner's old 700 series cars painted as the
/// real train, in the place of the recipe's 700T and its far set.
final class Map3DTHSR700TTests: XCTestCase {
    private let white = Map3DTrainShapeRefresh.highSpeedBodyColor
    private let orange = Map3DTrainShapeRefresh.highSpeedBandColor

    func testTheThreeUnitsDecodeAtTheRealSize() throws {
        for unit in Map3DTHSR700T.Unit.allCases {
            let model = try XCTUnwrap(Map3DTHSR700T.model(unit), unit.rawValue)
            XCTAssertEqual(model.length, Map3DTHSR700T.length(unit), accuracy: 0.01, unit.rawValue)
            XCTAssertEqual(model.maximum.y - model.minimum.y, 3.38, accuracy: 0.02, "\(unit.rawValue) is 3.38 m wide")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.03, unit.rawValue)
            XCTAssertTrue(Map3DTHSR700T.triangles.contains(model.triangleCount), unit.rawValue)
            // The roof 3.65 m up, where nothing stands on it: the middle
            // car's whole length, the pantograph car's front half (its
            // pantograph is over its back) and the cab car's back (its
            // roof comes down toward the nose). (The roof's faces run the
            // car's length, so its corners are at the car's ends.)
            let plain: ClosedRange<Float> = unit == .cab ? -13.5 ... -7 : unit == .pantograph ? 2...12.5 : -12.5...12.5
            let roof = model.vertices.filter { plain.contains($0.x) && $0.color == white }.map(\.z).max()
            XCTAssertEqual(try XCTUnwrap(roof), 3.65, accuracy: 0.01, unit.rawValue)
        }
        // The cab carries its aerial a little over the roof; the
        // pantograph's head is under the 5.2 m wire.
        XCTAssertEqual(try XCTUnwrap(Map3DTHSR700T.model(.cab)).maximum.z, 3.88, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(Map3DTHSR700T.model(.middle)).maximum.z, 3.65, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(Map3DTHSR700T.model(.pantograph)).maximum.z, 4.61, accuracy: 0.02)
    }

    /// The wheels stand on standard-gauge rails: 1,435 mm between the
    /// rails' inner faces, the wheels' outer faces a little wider.
    func testTheWheelsStandOnStandardGauge() throws {
        for unit in Map3DTHSR700T.Unit.allCases {
            let low = try XCTUnwrap(Map3DTHSR700T.model(unit)).vertices.filter { $0.z < 0.05 }
            XCTAssertFalse(low.isEmpty, unit.rawValue)
            XCTAssertTrue(low.allSatisfy { $0.color == Map3DPalette.dark }, "\(unit.rawValue): only the wheels reach the rail")
            let widest = low.map { abs($0.y) }.max() ?? 0
            XCTAssertGreaterThan(widest, 1.435 / 2, unit.rawValue)
            XCTAssertLessThan(widest, 1.435 / 2 + 0.2, unit.rawValue)
        }
    }

    /// The real livery: a white body, the black line over the orange band
    /// under the windows, a grey skirt, and no colour that is not the
    /// palette's. The band is the colour the teal paint swaps (decision
    /// 983).
    func testTheBodyIsWhiteWithTheBlackLineOverTheOrangeBand() throws {
        XCTAssertEqual(Map3DTHSR700T.meshPalette, [
            white, orange, Map3DPalette.dark, Map3DPalette.tankStand, Map3DTrainStyle.glass,
            Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern, Map3DPalette.steel,
        ])
        XCTAssertEqual(orange, Map3DPalette.highSpeedOrange)
        for unit in Map3DTHSR700T.Unit.allCases {
            let model = try XCTUnwrap(Map3DTHSR700T.model(unit))
            XCTAssertTrue(Set(model.vertices.map(\.color)).isSubset(of: Set(Map3DTHSR700T.meshPalette)), unit.rawValue)
            // The side wall behind the cab's nose (every car's back half),
            // between the doors.
            let side = model.vertices.filter { $0.x > -8 && $0.x < -1 && abs($0.y) > 1.68 }
            let band = side.filter { $0.color == orange }.map(\.z)
            XCTAssertEqual(try XCTUnwrap(band.min()), 1.58, accuracy: 0.01, "\(unit.rawValue): the band's foot")
            XCTAssertEqual(try XCTUnwrap(band.max()), 1.88, accuracy: 0.01, "\(unit.rawValue): the band's top")
            let line = side.filter { $0.color == Map3DPalette.dark && $0.z < 2.02 }.map(\.z)
            XCTAssertEqual(try XCTUnwrap(line.min()), 1.88, accuracy: 0.01, "\(unit.rawValue): the line on the band")
            XCTAssertEqual(try XCTUnwrap(line.max()), 1.99, accuracy: 0.01, "\(unit.rawValue): the line's top")
            let glass = side.filter { $0.color == Map3DTrainStyle.glass }.map(\.z)
            XCTAssertGreaterThan(try XCTUnwrap(glass.min()), 1.99, "\(unit.rawValue): the line under the windows")
            // White under the band, down to the skirt.
            XCTAssertTrue(side.contains { $0.color == white && $0.z < 1.2 }, unit.rawValue)
            XCTAssertFalse(model.vertices.filter { $0.color == Map3DPalette.tankStand && $0.z < 1 }.isEmpty, "\(unit.rawValue): the grey skirt")
        }
    }

    /// The cab car's nose: the band deep, from the skirt up, before the
    /// front door and on round the nose's tip; the black line starting two
    /// metres and more behind the front door; a black piece under the band
    /// behind the door; and no driver's door (the old car had one, the
    /// 700T has not).
    func testTheNoseWearsTheDeepBand() throws {
        let cab = try XCTUnwrap(Map3DTHSR700T.model(.cab))
        let door = try XCTUnwrap(Map3DTHSR700T.doors(.cab).first)
        let wall = cab.vertices.filter { abs($0.y) > 1.68 }
        XCTAssertTrue(wall.contains { $0.color == orange && $0.x > door.x.upperBound && $0.z < 1.2 }, "deep before the door")
        XCTAssertFalse(wall.contains { $0.color == orange && $0.x < door.x.lowerBound - 1.1 && $0.z < 1.57 }, "the band alone behind it")
        XCTAssertTrue(cab.vertices.contains { $0.color == orange && $0.x > 13 && abs($0.y) < 0.3 }, "round the tip")
        XCTAssertTrue(cab.vertices.contains { $0.color == white && $0.x > 10 && abs($0.y) < 0.3 && $0.z > 1.8 }, "the nose's top white")
        // The owner, 2026-11-25: the nose's top is white, as the real
        // train's, but the faces that look up round its tip and on its
        // shoulders are orange ("塗多一點比較像", the second of three
        // versions). From over the nose the white top starts 1.8 m behind
        // the tip, ±0.2 m wide, ±0.8 m at 3 m and the car's whole width at
        // 5.5 m (the tool's NOSE_TOP): no orange face looking up is in it.
        let tip = try XCTUnwrap(cab.vertices.map(\.x).max())
        func inWhiteTop(_ x: Float, _ y: Float) -> Bool {
            let behind = tip - x
            guard behind > 1.8 + 0.02 else { return false }
            let half: Float = behind < 3.0 ? 0.2 + (behind - 1.8) / 1.2 * 0.6
                : behind < 5.5 ? 0.8 + (behind - 3.0) / 2.5 * 1.2 : 2.0
            return abs(y) < half - 0.02
        }
        var shoulders = 0
        for start in stride(from: 0, to: cab.vertices.count, by: 3) where cab.vertices[start].color == orange && cab.vertices[start].x > 6 {
            let a = cab.vertices[start], b = cab.vertices[start + 1], c = cab.vertices[start + 2]
            let u = (b.x - a.x, b.y - a.y, b.z - a.z), v = (c.x - a.x, c.y - a.y, c.z - a.z)
            let n = (u.1 * v.2 - u.2 * v.1, u.2 * v.0 - u.0 * v.2, u.0 * v.1 - u.1 * v.0)
            let size = (n.0 * n.0 + n.1 * n.1 + n.2 * n.2).squareRoot()
            guard size > 0.002, abs(n.2) / size >= 0.7 else { continue }  // a sliver, or not looking up
            let x = (a.x + b.x + c.x) / 3, y = (a.y + b.y + c.y) / 3
            XCTAssertFalse(inWhiteTop(x, y), "an orange face looking up in the white top at \(x), \(y)")
            if tip - x > 2.5, tip - x < 5.5, abs(y) > 0.8 { shoulders += 1 }
        }
        XCTAssertGreaterThan(shoulders, 0, "the shoulders' orange")
        XCTAssertFalse(cab.vertices.contains { $0.color == orange && $0.z > 1.8 && abs($0.y) < 0.15 && $0.x > 6 && $0.x < tip - 1.9 },
                       "the centre line white behind the tip")
        let line = wall.filter { $0.color == Map3DPalette.dark && $0.z > 1.87 && $0.z < 2.0 }.map(\.x)
        XCTAssertEqual(try XCTUnwrap(line.max()), door.x.lowerBound - 2.3, accuracy: 0.05, "the line's point")
        let piece = wall.filter { $0.color == Map3DPalette.dark && $0.z < 1.57 && $0.z > 1.0 }.map(\.x)
        XCTAssertFalse(piece.isEmpty, "the black piece under the band")
        XCTAssertLessThan(try XCTUnwrap(piece.max()), door.x.lowerBound)
        XCTAssertGreaterThan(try XCTUnwrap(piece.min()), door.x.lowerBound - 4)
        // Before the front door the wall has only white and the band:
        // no frame, no glass.
        XCTAssertFalse(wall.contains { $0.x > door.x.upperBound + 0.01 && ($0.color == Map3DPalette.steel || $0.color == Map3DTrainStyle.glass) })
    }

    /// Each door has its frame: a thin grey line round the leaf, from the
    /// sill under the band to over the door's window.
    func testTheDoorsHaveTheirFrames() throws {
        for unit in Map3DTHSR700T.Unit.allCases {
            let model = try XCTUnwrap(Map3DTHSR700T.model(unit))
            let wall = model.vertices.filter { abs($0.y) > 1.68 }
            let frame = wall.filter { $0.color == Map3DPalette.steel }.map(\.z)
            let glass = wall.filter { $0.color == Map3DTrainStyle.glass }.map(\.z)
            let top = try XCTUnwrap(frame.max(), unit.rawValue), sill = try XCTUnwrap(frame.min(), unit.rawValue)
            XCTAssertGreaterThan(top, try XCTUnwrap(glass.max()), "\(unit.rawValue): the frame's top over the door's window")
            XCTAssertLessThan(top, 3.2, unit.rawValue)
            XCTAssertLessThan(sill, 1.45, "\(unit.rawValue): the sill under the band")
        }
    }

    /// Each door is a piece of its own: no triangle is partly a door's and
    /// partly the wall's, on either side, so a door can be moved apart
    /// from the wall (to open at a station) without the mesh cut again.
    func testEachDoorIsAPieceOfItsOwn() throws {
        XCTAssertEqual(Map3DTHSR700T.Unit.allCases.map { Map3DTHSR700T.doors($0).count }, [2, 2, 2])
        for unit in Map3DTHSR700T.Unit.allCases {
            let model = try XCTUnwrap(Map3DTHSR700T.model(unit))
            // The side walls' triangles.
            var walls: [(points: [Map3DPoint], color: UInt32)] = []
            for first in stride(from: 0, to: model.vertices.count, by: 3) {
                let points = model.vertices[first..<first + 3].map { Map3DPoint($0.x, $0.y, $0.z) }
                if points.allSatisfy({ abs($0.y) > 1.68 }) { walls.append((points, model.vertices[first].color)) }
            }
            for door in Map3DTHSR700T.doors(unit) {
                XCTAssertGreaterThan(door.x.upperBound - door.x.lowerBound, 0.7, unit.rawValue)
                XCTAssertGreaterThan(door.z.upperBound - door.z.lowerBound, 1.6, unit.rawValue)
                for side in [Float(1), -1] {
                    var own = 0, glass = 0, frame = 0, band = 0
                    for (triangle, color) in walls where triangle[0].y * side > 0 {
                        if triangle.allSatisfy({ door.contains($0) }) {
                            own += 1
                            if color == Map3DTrainStyle.glass { glass += 1 }
                            if color == Map3DPalette.steel { frame += 1 }
                            if color == orange { band += 1 }
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

    /// Each coupled end has its hood, as the real train's joints have:
    /// the body's outline (its white over its skirt's grey, the full width
    /// and height) drawn out to 2 cm from the coupling, so two cars are
    /// 4 cm apart and not 0.6 m of open air beside a narrow gangway. The
    /// band and the line are not carried across it.
    func testTheHoodsCloseTheGapBetweenCars() throws {
        for unit in Map3DTHSR700T.Unit.allCases {
            let model = try XCTUnwrap(Map3DTHSR700T.model(unit))
            let half = Map3DTHSR700T.length(unit) / 2
            for end: Float in unit.isCab ? [-1] : [-1, 1] {
                let rim = model.vertices.filter { abs($0.x * end - (half - Map3DTHSR700T.hoodGap)) < 0.002 && $0.color != Map3DPalette.dark }
                let name = "\(unit.rawValue) \(end)"
                XCTAssertEqual(rim.map { abs($0.y) }.max() ?? 0, 1.69, accuracy: 0.01, "\(name): as wide as the body")
                XCTAssertEqual(rim.map(\.z).max() ?? 0, 3.65, accuracy: 0.01, "\(name): to the roof")
                XCTAssertLessThan(rim.map(\.z).min() ?? 9, 0.8, "\(name): down the skirt")
                XCTAssertTrue(rim.allSatisfy { $0.color == white || $0.color == Map3DPalette.tankStand }, "\(name): no band on it")
                XCTAssertTrue(rim.contains { $0.color == white } && rim.contains { $0.color == Map3DPalette.tankStand }, name)
                // Nothing of the body's reaches past it but the gangway.
                XCTAssertTrue(model.vertices.allSatisfy { $0.x * end <= half - Map3DTHSR700T.hoodGap + 0.002 || $0.color == Map3DPalette.dark }, name)
            }
        }
    }

    /// The glass is marked as the windows; the cab's lamps are on its
    /// nose, a white one and a red one on each side of the centre line,
    /// and the other cars have none.
    func testTheGlassAndTheLampsAreMarked() throws {
        for unit in Map3DTHSR700T.Unit.allCases {
            let model = try XCTUnwrap(Map3DTHSR700T.model(unit))
            XCTAssertTrue(Map3DTrainMaterial.marksOwnGlass(model), unit.rawValue)
        }
        let cab = try XCTUnwrap(Map3DTHSR700T.model(.cab))
        for lens in [Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
            let lamps = cab.vertices.filter { $0.color == lens }
            XCTAssertFalse(lamps.isEmpty)
            XCTAssertGreaterThan(lamps.map(\.x).min() ?? 0, Map3DTHSR700T.pitch * 0.3, "the lamps on the nose")
            XCTAssertTrue(lamps.contains { $0.y > 0.1 } && lamps.contains { $0.y < -0.1 }, "a lamp on each side")
        }
        // The windscreen over the nose, on the car's centre line too.
        XCTAssertFalse(cab.vertices.filter { $0.color == Map3DTrainStyle.glass && $0.x > 5.5 && abs($0.y) < 0.3 }.isEmpty)
        for unit in [Map3DTHSR700T.Unit.middle, .pantograph] {
            let model = try XCTUnwrap(Map3DTHSR700T.model(unit))
            XCTAssertTrue(model.vertices.allSatisfy { $0.color != Map3DTrainStyle.headlamp && $0.color != Map3DPalette.lantern }, unit.rawValue)
        }
    }

    /// The owner, 2026-11-25 (「他是從車燈到上方」): the real 700T's
    /// windscreen and lamps are in one black mask, from the lamps up to the
    /// windscreen's top; the old car's were two patches with white between
    /// them. The mask reaches the lamps' front edge and the windscreen's
    /// back one, and no face between the lamps and the windscreen is left
    /// white.
    func testTheMaskRunsFromTheLampsToTheWindscreensTop() throws {
        let cab = try XCTUnwrap(Map3DTHSR700T.model(.cab))
        func onTheNose(_ v: Map3DVertex) -> Bool { v.x > 7 && v.z > 2 && abs(v.y) < 1.2 }
        let nose = cab.vertices.filter(onTheNose)
        let lamps = nose.filter { $0.color == Map3DTrainStyle.headlamp || $0.color == Map3DPalette.lantern }
        let glass = nose.filter { $0.color == Map3DTrainStyle.glass }
        let mask = nose.filter { $0.color == Map3DPalette.dark }
        let lampFront = try XCTUnwrap(lamps.map(\.x).max()), lampBack = try XCTUnwrap(lamps.map(\.x).min())
        let glassFront = try XCTUnwrap(glass.map(\.x).max()), glassBack = try XCTUnwrap(glass.map(\.x).min())
        XCTAssertLessThan(glassFront, lampBack, "the lamps before the windscreen")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(mask.map(\.x).max()), lampFront, "the mask to the lamps' front edge")
        XCTAssertLessThanOrEqual(try XCTUnwrap(mask.map(\.x).min()), glassBack + 0.2, "and to the windscreen's top")
        var between = 0
        for start in stride(from: 0, to: cab.vertices.count, by: 3) {
            let corners = cab.vertices[start ..< start + 3]
            let x = corners.map(\.x).reduce(0, +) / 3, y = corners.map(\.y).reduce(0, +) / 3, z = corners.map(\.z).reduce(0, +) / 3
            guard x > glassFront + 0.02, x < lampBack - 0.02, abs(y) < 0.35, z > 2.2 else { continue }
            between += 1
            XCTAssertEqual(corners[start].color, Map3DPalette.dark, "a face between the lamps and the windscreen at \(x), \(y)")
        }
        XCTAssertGreaterThan(between, 0)
    }

    /// The cab car is the real one's 27 m, 2 m longer than the recipe's
    /// was, and its nose is given no stretch of its own (the owner's
    /// rule): from its tip to its front door is the old car's 6.736 units
    /// times the factor the middle car's length has (12.5 / 10.501). The
    /// length it has over that is in its straight body, as windows: its
    /// windows and doors are the middle car's size and spacing, fourteen
    /// a side where the old car had twelve.
    func testTheCabCarIsLongerByWindowsNotByItsNose() throws {
        let cab = try XCTUnwrap(Map3DTHSR700T.model(.cab)), middle = try XCTUnwrap(Map3DTHSR700T.model(.middle))
        XCTAssertEqual(Map3DTHSR700T.cabLength, 27)
        XCTAssertEqual(cab.maximum.x, 13.5, accuracy: 0.01, "the tip at the car's front end")
        XCTAssertEqual(cab.maximum.x - Map3DTHSR700T.doors(.cab)[0].x.upperBound, 6.736 * 12.5 / 10.501, accuracy: 0.01)
        // A side's windows: the glass on the wall at the windows' height
        // (its triangles, joined where they touch: a wall's own edge
        // crossing a window cuts its glass in pieces), each window's two
        // edges. The doors' windows are taller and not counted.
        func windows(_ model: Map3DModelPack.Model) -> [Float] {
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
            return merged.flatMap { [$0.lowerBound, $0.upperBound] }
        }
        // (The doors' windows are higher and narrower: left out by their height.)
        func cabin(_ model: Map3DModelPack.Model) -> [Float] {
            let doors = Map3DTHSR700T.doors(model.name == Map3DTHSR700T.Unit.cab.rawValue ? .cab : .middle)
            return windows(model).filter { x in !doors.contains { $0.x.contains(x) } }
        }
        let cabEdges = cabin(cab), middleEdges = cabin(middle)
        XCTAssertEqual(cabEdges.count, 28, "fourteen windows a side")
        XCTAssertEqual(middleEdges.count, 40, "twenty windows a side")
        XCTAssertEqual(cabEdges[1] - cabEdges[0], middleEdges[1] - middleEdges[0], accuracy: 0.002, "a window's width")
        XCTAssertEqual(cabEdges[2] - cabEdges[0], middleEdges[2] - middleEdges[0], accuracy: 0.002, "the windows' spacing")
        let cabDoor = Map3DTHSR700T.doors(.cab)[1], middleDoor = Map3DTHSR700T.doors(.middle)[1]
        XCTAssertEqual(cabDoor.x.upperBound - cabDoor.x.lowerBound, middleDoor.x.upperBound - middleDoor.x.lowerBound, accuracy: 0.01, "a door's width")
    }

    /// Twelve cars as the 700T's were laid (decision 408): the cab at each
    /// end, the pantograph car fourth and ninth, the back half turned
    /// round, each car 25 m (the cab cars 27 m) with no gap; the head's
    /// white lamps and the tail's red lamps lit.
    func testTheTwelveCarsAreLaid() throws {
        let pack = Map3DModelPack.standard
        let key = Map3DTHSR700T.key
        XCTAssertEqual(key, "highSpeed")
        XCTAssertEqual(Map3DTHSR700T.cars, 12)
        let laid = try XCTUnwrap(pack.layout(forType: "HSR", count: 12))
        XCTAssertEqual(laid.map { pack.models[$0.model].name }, (["head", "car", "car", "panto", "car", "car", "carBack", "carBack",
                                                                    "pantoBack", "carBack", "carBack", "tail"]).map { "set-\(key)-\($0)" })
        XCTAssertTrue(laid.allSatisfy { $0.gap == 0 })
        XCTAssertEqual(laid.map(\.length).reduce(0, +), 10 * 25 + 2 * 27, accuracy: 0.1)
        // The two pantographs face each other: the fourth car's at its
        // back, the ninth's at its front.
        let roof = pack.models[laid[1].model].maximum.z
        func pantograph(_ car: Int) -> Float {
            let high = pack.models[laid[car].model].vertices.filter { $0.z > roof + 0.1 }.map(\.x)
            return high.reduce(0, +) / Float(max(high.count, 1))
        }
        XCTAssertLessThan(pantograph(3), -1)
        XCTAssertGreaterThan(pantograph(8), 1)
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
    }

    /// It has the recipe's 700T's place: the high-speed trains' set, the
    /// garage's high-speed row, the paints of decision 983; and the far
    /// set's key names it now, so nothing that kept it is left without a
    /// train.
    func testItHasTheRecipes700TsPlace() throws {
        let key = Map3DTHSR700T.key
        XCTAssertNil(Map3DTrainSet.byKey[Map3DTHSR700T.formerFarKey])
        XCTAssertEqual(Map3DTrainSet.named(Map3DTHSR700T.formerFarKey)?.key, key)
        XCTAssertNotNil(Map3DModelPack.standard.layout(forType: Map3DTHSR700T.formerFarKey, count: 12))
        XCTAssertEqual(Map3DTrainSet.named("HSR")?.key, key)
        XCTAssertEqual(Map3DTrainSet.variant(of: "HSR", number: 2), "HSR")
        // No far set: a car is under two thousand triangles, drawn as far
        // as any train's model.
        XCTAssertNil(try XCTUnwrap(Map3DTrainSet.byKey[key]).far)
        XCTAssertFalse(Map3DTrainSet.nearOnly.contains(key))
        XCTAssertEqual(Map3DTrainSet.reach(of: "HSR"), Map3DTrains.modelReach)
        let entry = try XCTUnwrap(Map3DShowcase.entry(key))
        XCTAssertEqual(entry.category, .highSpeed)
        XCTAssertEqual(entry.defaultCars, 12)
        XCTAssertEqual(entry.gauge, 1.435)
        // The teal paint swaps the band, on every car, and nothing else.
        let family = try XCTUnwrap(TrainPaintFamily.named(set: key))
        XCTAssertEqual(family.id, Map3DTrainShapeRefresh.highSpeedPaints.id)
        let teal = try XCTUnwrap(family.paints.first)
        for unit in Map3DTHSR700T.Unit.allCases {
            let model = try XCTUnwrap(Map3DTHSR700T.model(unit))
            let painted = teal.painted(model.vertices)
            XCTAssertFalse(painted.contains { $0.color == orange }, unit.rawValue)
            XCTAssertEqual(painted.filter { $0.color == Map3DTrainShapeRefresh.highSpeedGameBandColor }.count,
                           model.vertices.filter { $0.color == orange }.count, unit.rawValue)
            XCTAssertEqual(zip(painted, model.vertices).filter { $0.color != $1.color }.count,
                           model.vertices.filter { $0.color == orange }.count, unit.rawValue)
        }
    }
}
