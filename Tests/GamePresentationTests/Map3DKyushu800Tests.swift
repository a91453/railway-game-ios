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
        // The real cars: the middle car 25 m, the cab car 27.35 m.
        XCTAssertEqual(Map3DKyushu800.Unit.middle.pitch, 25)
        XCTAssertEqual(Map3DKyushu800.Unit.cab.pitch, 27.35)
    }

    /// The windows of a car's row on one wall, between its doors: each is
    /// the glass triangles that touch along the car, from its back to its
    /// front.
    private func windows(_ unit: Map3DKyushu800.Unit) throws -> [ClosedRange<Float>] {
        let doors = Map3DKyushu800.doors(unit)
        let vertices = try XCTUnwrap(Map3DKyushu800.model(unit)).vertices
        var panes: [ClosedRange<Float>] = []
        for first in stride(from: 0, to: vertices.count, by: 3) where vertices[first].color == Map3DTrainStyle.glass {
            let corners = vertices[first..<first + 3]
            let xs = corners.map(\.x)
            guard corners.allSatisfy({ $0.y > 1.6 }), let low = xs.min(), let high = xs.max(),
                  !doors.contains(where: { $0.x.lowerBound - 0.1 < low && high < $0.x.upperBound + 0.1 }) else { continue }
            panes.append(low...high)
        }
        var runs: [ClosedRange<Float>] = []
        for pane in panes.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = runs.last, pane.lowerBound <= last.upperBound + 0.01 {
                runs[runs.count - 1] = last.lowerBound...max(last.upperBound, pane.upperBound)
            } else {
                runs.append(pane)
            }
        }
        return runs
    }

    /// A window to each row of seats, about a metre apart, as on the real
    /// train: fourteen on the cab car, as the real one, and sixteen on the middle car (the
    /// old middle car has fourteen, 1.13 to 1.22 m apart at this size),
    /// and the two cars' windows as wide and as far apart as each other's.
    /// The middle car's door behind the row stands nearer the car's end
    /// than the old one (6.76 to 7.92 m from the middle) to make room.
    func testTheWindowsAreAboutAMetreApartOnBothCars() throws {
        var widths: [Map3DKyushu800.Unit: ClosedRange<Float>] = [:]
        for (unit, count) in [(Map3DKyushu800.Unit.cab, 14), (.middle, 16)] {
            let row = try windows(unit)
            XCTAssertEqual(row.count, count, unit.rawValue)
            let apart = zip(row.dropFirst(), row).map { ($0.lowerBound + $0.upperBound - $1.lowerBound - $1.upperBound) / 2 }
            XCTAssertTrue(apart.allSatisfy { $0 > 1.0 && $0 < 1.11 }, "\(unit.rawValue): \(apart)")
            let wide = row.map { $0.upperBound - $0.lowerBound }
            widths[unit] = try XCTUnwrap(wide.min())...(try XCTUnwrap(wide.max()))
            // As wide as the real train's, measured on photographs: 0.71 m,
            // about as wide as they are high.
            XCTAssertTrue(wide.allSatisfy { $0 > 0.67 && $0 < 0.74 }, "\(unit.rawValue): \(wide)")
        }
        // The middle car's row stays between its two doors.
        let doors = Map3DKyushu800.doors(.middle)
        let row = try windows(.middle)
        XCTAssertGreaterThan(try XCTUnwrap(row.first).lowerBound, doors[1].x.upperBound + 0.3)
        XCTAssertLessThan(try XCTUnwrap(row.last).upperBound, doors[0].x.lowerBound - 0.3)
        XCTAssertEqual(doors[1].x.upperBound, -6.761 - 0.515, accuracy: 0.01)
        XCTAssertEqual(doors[1].x.upperBound - doors[1].x.lowerBound, 1.163, accuracy: 0.01, "the door itself as wide as it was")
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
            // The roof's flat top is red from side to side, as far as the
            // hood at the car's end.
            let roof = all.filter { $0.x < 0 && $0.x > 0.35 - unit.pitch / 2 && $0.z > 3.6 && abs($0.y) < 1.3 }
            XCTAssertFalse(roof.isEmpty, unit.rawValue)
            XCTAssertTrue(roof.allSatisfy { $0.colour == Map3DPalette.trainRed }, "\(unit.rawValue): the red roof")
            XCTAssertFalse(all.filter { $0.colour == Map3DPalette.steel && $0.z < 1 }.isEmpty, "\(unit.rawValue): the grey skirt")
            // Each door has its frame (the old texture's thin line around the
            // panel), up the wall above the red line.
            XCTAssertFalse(all.filter { $0.colour == Map3DPalette.steel && $0.z > 1.6 && $0.z < 3.3 }.isEmpty, "\(unit.rawValue): the door frames")
        }
    }

    /// The cab car has the real one's proportions, measured on photographs
    /// of it with the windows as the rule (1.04 m apart): from the joint to
    /// the first window's middle some 2.8 to 3.1 m, fourteen windows, and
    /// the crew door's middle some 19.5 m from the joint, 7.85 m from the
    /// nose's tip. The old car made longer as a whole had the door 8.9 m
    /// from the tip and thirteen windows.
    func testTheCabCarHasTheRealCarsProportions() throws {
        let model = try XCTUnwrap(Map3DKyushu800.model(.cab))
        let doors = Map3DKyushu800.doors(.cab)
        let crew = try XCTUnwrap(doors.first { $0.crew })
        XCTAssertEqual(model.maximum.x - (crew.x.lowerBound + crew.x.upperBound) / 2, 7.85, accuracy: 0.1, "the nose")
        let row = try windows(.cab)
        let first = try XCTUnwrap(row.first), last = try XCTUnwrap(row.last)
        XCTAssertEqual((first.lowerBound + first.upperBound) / 2 - model.minimum.x, 2.95, accuracy: 0.25, "the first window")
        XCTAssertEqual((last.lowerBound + last.upperBound) / 2 - model.minimum.x, 16.5, accuracy: 0.25, "the last window")
        // The row stands between the two doors.
        let passenger = try XCTUnwrap(doors.first { !$0.crew })
        XCTAssertGreaterThan(first.lowerBound, passenger.x.upperBound + 0.3)
        XCTAssertLessThan(last.upperBound, crew.x.lowerBound - 0.3)
    }

    /// Between two cars the real train has a dark hood all the way round,
    /// flush with the body from the roof to the skirt. The old cars had a
    /// narrow gangway alone, and 0.6 m of daylight around it; here each
    /// coupled end's outline runs on to 2 cm short of the joint, so two
    /// cars' hoods stand 4 cm apart.
    func testADarkHoodClosesTheGapBetweenTwoCars() throws {
        for unit in Map3DKyushu800.Unit.allCases {
            let model = try XCTUnwrap(Map3DKyushu800.model(unit))
            let half = unit.pitch / 2
            // The cab car couples at its back alone.
            for end in unit == .cab ? [Float(-1)] : [-1, 1] {
                let past = faces(model).filter { $0.x * end > half - 0.29 }
                XCTAssertTrue(past.allSatisfy { $0.colour == Map3DPalette.dark }, "\(unit.rawValue): dark past the body's end")
                XCTAssertFalse(past.filter { $0.z > 3.6 }.isEmpty, "\(unit.rawValue): over the roof")
                XCTAssertFalse(past.filter { $0.y > 1.68 }.isEmpty, "\(unit.rawValue): down one wall")
                XCTAssertFalse(past.filter { $0.y < -1.68 }.isEmpty, "\(unit.rawValue): down the other")
                XCTAssertFalse(past.filter { $0.z < 0.7 && abs($0.y) > 1.4 }.isEmpty, "\(unit.rawValue): as far down as the skirt")
                // Its mouth is closed, 2 cm short of the joint.
                let mouth = past.filter { abs($0.x * end - (half - 0.02)) < 0.001 }
                XCTAssertFalse(mouth.isEmpty, "\(unit.rawValue): the mouth")
                let wide = model.vertices.filter { abs($0.y) > 1 && $0.x * end > half - 0.29 }.map { $0.x * end }
                XCTAssertEqual(wide.max() ?? 0, half - 0.02, accuracy: 0.001, "\(unit.rawValue): short of the joint")
            }
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
