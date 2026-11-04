import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 205: a train's cars drawn 20 m long on the map,
/// only on the map.
final class TrainCarsTests: XCTestCase {
    private typealias Point = TrainMotion.Point
    private let car = TrainCars.drawnCarLength
    private let spacing = Double(Train.carLength)
    /// How far ahead of its head the nose of a train of 16 m cars is drawn
    /// (decision 565, ``TrainCars/noseLead(pitch:)``).
    private let half = TrainCars.drawnCarLength / 2

    func testTheCountComesFromTheBodyLength() {
        XCTAssertEqual(TrainCars.count(length: 0, carPitch: spacing), 1)
        XCTAssertEqual(TrainCars.count(length: spacing, carPitch: spacing), 2)
        XCTAssertEqual(TrainCars.count(length: spacing * 5, carPitch: spacing), 6)
        // Decision 227: a high-speed set of twelve 25 m cars.
        let real = Double(TrainType.highSpeed.carLength)
        XCTAssertEqual(TrainCars.count(length: real * 11, carPitch: real), 12)
    }

    func testAStraightTrainRunsFromHalfACarAheadBackOverItsBodyAndBeyond() {
        // Three cars facing +x: centres at 0, -16 m, -32 m.
        let body = [Point(x: 0, y: 0), Point(x: -spacing * 2, y: 0)]
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), count: 3, lead: half)
        XCTAssertEqual(cars.count, 3)
        XCTAssertEqual(cars[0].first!.x, car / 2, accuracy: 1e-6)
        XCTAssertEqual(cars[0].last!.x, -car / 2, accuracy: 1e-6)
        XCTAssertEqual(cars[1].last!.x, -car * 1.5, accuracy: 1e-6)
        // 60 m drawn where the body is 32 m: the tail goes on straight.
        XCTAssertEqual(cars[2].last!.x, -car * 2.5, accuracy: 1e-6)
        for polyline in cars {
            XCTAssertTrue(polyline.allSatisfy { $0.y == 0 })
        }
    }

    /// Decision 399: cars at their own lengths, each gap behind its car,
    /// the nose where every train's is.
    func testCarsAtTheirOwnLengths() {
        let body = [Point(x: 0, y: 0), Point(x: -spacing, y: 0)]
        let m = Double(WorldCoordinate.unitsPerMetre)
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), lengths: [14.77 * m, 9 * m, 19.4 * m], gaps: [0, 0.6 * m, 0], lead: half)
        XCTAssertEqual(cars.count, 3)
        XCTAssertEqual(cars[0].first!.x, car / 2, accuracy: 1e-6)
        XCTAssertEqual(cars[0].last!.x, car / 2 - 14.77 * m, accuracy: 1e-3)
        XCTAssertEqual(cars[1].first!.x, cars[0].last!.x, accuracy: 1e-3, "the tender against the locomotive")
        XCTAssertEqual(cars[2].first!.x, cars[1].last!.x - 0.6 * m, accuracy: 1e-3)
        // Past the body's 16 m, straight on.
        XCTAssertEqual(cars[2].last!.x, car / 2 - (14.77 + 9 + 0.6 + 19.4) * m, accuracy: 1e-3)
        XCTAssertTrue(TrainCars.cars(body: [], heading: Point(x: 1, y: 0), lengths: [m], gaps: [], lead: half).isEmpty)
    }

    /// 88.1: a 12-car 700T or N700S-G at its real 25 m a car on a train
    /// whose cars stand 16 m apart ran some 120 m past its body, straight
    /// off the curving viaduct. Shrunk to the 240 m twelve cars are drawn
    /// at; at its real pitch, as it was.
    func testALongSetIsNoLongerThanItsTrain() {
        let m = Double(WorldCoordinate.unitsPerMetre)
        let lengths = [25.3 * m] + Array(repeating: 25 * m, count: 10) + [25.3 * m], gaps = Array(repeating: 0.0, count: 12)
        let short = TrainCars.cars(body: [Point(x: 0, y: 0), Point(x: -11 * spacing, y: 0)], heading: Point(x: 1, y: 0),
                                   lengths: lengths, gaps: gaps, lead: half)
        XCTAssertEqual(short.count, 12)
        XCTAssertEqual(short[0].first!.x, car / 2, accuracy: 1e-6, "the nose where every train's is")
        XCTAssertEqual(short[11].last!.x, car / 2 - 12 * car, accuracy: 1e-3, "as long as twelve cars drawn 20 m a car")
        XCTAssertEqual(short[0].first!.x - short[0].last!.x, 25.3 / 300.6 * 12 * car, accuracy: 1e-3, "each its share")
        let pitch = Double(TrainType.highSpeed.carLength)
        let real = TrainCars.cars(body: [Point(x: 0, y: 0), Point(x: -11 * pitch, y: 0)], heading: Point(x: 1, y: 0),
                                  lengths: lengths, gaps: gaps, lead: half)
        XCTAssertEqual(real[11].last!.x, car / 2 - 300.6 * m, accuracy: 1e-3, "its own lengths")
    }

    /// A set up to half a car longer than its bound keeps its own lengths
    /// (a 12-car EMU3000, 245.7 m, on 16 m pitches whose bound is 240 m);
    /// past that it is shrunk to the bound as before.
    func testASetHalfACarOverItsBoundKeepsItsOwnLengths() {
        let m = Double(WorldCoordinate.unitsPerMetre)
        let body = [Point(x: 0, y: 0), Point(x: -11 * spacing, y: 0)], gaps = Array(repeating: 0.0, count: 12)
        let under = TrainCars.cars(body: body, heading: Point(x: 1, y: 0),
                                   lengths: Array(repeating: 249.9 / 12 * m, count: 12), gaps: gaps, lead: half)
        XCTAssertEqual(under[11].last!.x, car / 2 - 249.9 * m, accuracy: 1e-3, "9.9 m over: its own lengths")
        let over = TrainCars.cars(body: body, heading: Point(x: 1, y: 0),
                                  lengths: Array(repeating: 250.1 / 12 * m, count: 12), gaps: gaps, lead: half)
        XCTAssertEqual(over[11].last!.x, car / 2 - 12 * car, accuracy: 1e-3, "10.1 m over: shrunk to twelve 20 m cars")
    }

    /// 88.1: past its tail a train goes on the way its body runs there,
    /// not the way its last step does, which can be a few world units
    /// between rounded points (here 2 along and 1 across, 27° off) and,
    /// laid on for a hundred metres, swung the last cars off the track.
    func testTheTailGoesOnTheWayTheBodyRuns() {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        var body = (0...40).map { Point(x: -Double($0) * metre, y: 0) }
        body.append(Point(x: body.last!.x - 2, y: 1))
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), count: 8, lead: half)
        let back = cars[7].last!
        XCTAssertEqual(back.x, car / 2 - 8 * car, accuracy: metre)
        XCTAssertEqual(back.y, 0, accuracy: metre / 2, "on the track's line, not \(back.y / metre) m off it")
    }

    func testTheGapIsLeftBetweenCarsNotAtTheEnds() {
        let body = [Point(x: 0, y: 0), Point(x: -spacing, y: 0)]
        let gap = 100.0
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), count: 2, gap: gap, lead: half)
        XCTAssertEqual(cars[0].first!.x, car / 2, accuracy: 1e-6)
        XCTAssertEqual(cars[1].last!.x, -car * 1.5, accuracy: 1e-6)
        XCTAssertEqual(cars[0].last!.x - cars[1].first!.x, gap, accuracy: 1e-6)
    }

    func testOneCarStandsAcrossItsHead() {
        let cars = TrainCars.cars(body: [Point(x: 10, y: 20)], heading: Point(x: 0, y: 2), count: 1, lead: half)
        XCTAssertEqual(cars.count, 1)
        XCTAssertEqual(cars[0].first!.y, 20 + car / 2, accuracy: 1e-6)
        XCTAssertEqual(cars[0].last!.y, 20 - car / 2, accuracy: 1e-6)
        XCTAssertEqual(cars[0].first!.x, 10, accuracy: 1e-6)
    }

    func testCarsFollowACurvedBody() {
        // The body turns a right angle 16 m behind the head.
        let body = [Point(x: 0, y: 0), Point(x: -spacing, y: 0), Point(x: -spacing, y: -spacing * 4)]
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), count: 2, lead: half)
        // The second car spans the corner.
        XCTAssertTrue(cars[1].contains(Point(x: -spacing, y: 0)))
        XCTAssertEqual(cars[1].last!.x, -spacing, accuracy: 1e-6)
    }

    /// Decision 565 (PLATSTOP, 110.1): with real car lengths, the first
    /// car's nose at the head, where GameCore stops the train at the far
    /// end of its platform, and each car its own length, so a train that
    /// fits its platform is drawn inside it.
    func testWithRealCarLengthsTheNoseIsAtTheHeadAndEachCarItsOwnLength() {
        let pitch = Double(Train.realStandardCarLength)
        XCTAssertEqual(TrainCars.noseLead(pitch: pitch), 0)
        XCTAssertEqual(TrainCars.carLength(pitch: pitch), pitch)
        XCTAssertEqual(TrainCars.realLength(count: 4, pitch: pitch), 4 * pitch)
        // Without real car lengths, as before: half a 20 m car ahead.
        XCTAssertEqual(TrainCars.noseLead(pitch: spacing), half)
        XCTAssertEqual(TrainCars.carLength(pitch: spacing), car)
        XCTAssertNil(TrainCars.realLength(count: 4, pitch: spacing))
        // Four 20 m cars, centres 60 m apart: 80 m from the head back.
        let body = [Point(x: 0, y: 0), Point(x: -3 * pitch, y: 0)]
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), count: 4, length: TrainCars.carLength(pitch: pitch))
        XCTAssertEqual(cars[0].first!.x, 0, accuracy: 1e-6, "the nose at the head")
        XCTAssertEqual(cars[3].last!.x, -4 * pitch, accuracy: 1e-6, "the tail a car past the last car's centre")
        // A light-rail type of 12 m cars is drawn 12 m a car, not 20.
        let light = 12 * Double(WorldCoordinate.unitsPerMetre)
        let short = TrainCars.cars(body: [Point(x: 0, y: 0), Point(x: -light, y: 0)], heading: Point(x: 1, y: 0), count: 2,
                                   length: TrainCars.carLength(pitch: light))
        XCTAssertEqual(short[1].last!.x, -2 * light, accuracy: 1e-6)
    }

    /// Decision 565: with real car lengths a set's models are never laid
    /// longer than its cars' real lengths, shrunk to them when they are
    /// (a 12-car EMU3000's 245.7 m of models in the 243.6 m of its 20.3 m
    /// cars); shorter models keep their own lengths.
    func testWithRealCarLengthsASetIsNoLongerThanItsCars() {
        let m = Double(WorldCoordinate.unitsPerMetre)
        let pitch = 20.3 * m, gaps = Array(repeating: 0.0, count: 12)
        let body = [Point(x: 0, y: 0), Point(x: -11 * pitch, y: 0)]
        let real = TrainCars.realLength(count: 12, pitch: pitch)
        let long = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), lengths: Array(repeating: 245.7 / 12 * m, count: 12), gaps: gaps,
                                  real: real)
        XCTAssertEqual(long[0].first!.x, 0, accuracy: 1e-6)
        XCTAssertEqual(long[11].last!.x, -12 * pitch, accuracy: 1e-3)
        let short = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), lengths: Array(repeating: 20 * m, count: 12), gaps: gaps,
                                   real: real)
        XCTAssertEqual(short[11].last!.x, -240 * m, accuracy: 1e-3)
    }

    func testNoBodyNoCars() {
        XCTAssertTrue(TrainCars.cars(body: [], heading: Point(x: 1, y: 0), count: 3, lead: half).isEmpty)
    }
    /// Decision 538 (104.1, Zhuzhong): on a curve of 100 m radius, with the
    /// track ahead of the head and past the tail given, every car's two
    /// ends stand on the curve; laid straight on, as before, the last
    /// car's back end stood metres off it.
    func testTheEndCarsFollowTheTrackRoundACurve() {
        let radius = 100 * Double(WorldCoordinate.unitsPerMetre)
        // Anticlockwise round the origin, `along` world units from angle 0.
        func arc(_ from: Double, _ to: Double) -> [Point] {
            let steps = 200
            return (0...steps).map { step in
                let angle = (from + (to - from) * Double(step) / Double(steps)) / radius
                return Point(x: radius * cos(angle), y: radius * sin(angle))
            }
        }
        // The head at 80 m along, going anticlockwise; a body of 40 m back.
        let head = 80 * Double(WorldCoordinate.unitsPerMetre), body = 40 * Double(WorldCoordinate.unitsPerMetre)
        let angle = head / radius
        let heading = Point(x: -sin(angle), y: cos(angle))
        let laid = arc(head, head - body)
        let track = (ahead: arc(head, head + car), behind: arc(head, head - body - 2 * car))
        func off(_ cars: [[Point]]) -> Double {
            cars.flatMap { [$0.first!, $0.last!] }.map { abs(($0.x * $0.x + $0.y * $0.y).squareRoot() - radius) }.max()!
                / Double(WorldCoordinate.unitsPerMetre)
        }
        let metre = Double(WorldCoordinate.unitsPerMetre)
        for cars in [TrainCars.cars(body: laid, heading: heading, count: 3, gap: 0.6 * metre, track: track),
                     TrainCars.cars(body: laid, heading: heading, lengths: [21 * metre, 20 * metre, 21 * metre],
                                    gaps: [0.6 * metre, 0.6 * metre], track: track)] {
            XCTAssertEqual(cars.count, 3)
            // The chords' ends on the sampled arc: within its sag.
            XCTAssertLessThan(off(cars), 0.05)
        }
        XCTAssertGreaterThan(off(TrainCars.cars(body: laid, heading: heading, count: 3, gap: 0.6 * metre)), 1)
    }
}
