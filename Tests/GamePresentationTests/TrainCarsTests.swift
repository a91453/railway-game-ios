import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 205: a train's cars drawn 20 m long on the map,
/// only on the map.
final class TrainCarsTests: XCTestCase {
    private typealias Point = TrainMotion.Point
    private let car = TrainCars.drawnCarLength
    private let spacing = Double(Train.carLength)

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
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), count: 3)
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
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), lengths: [14.77 * m, 9 * m, 19.4 * m], gaps: [0, 0.6 * m, 0])
        XCTAssertEqual(cars.count, 3)
        XCTAssertEqual(cars[0].first!.x, car / 2, accuracy: 1e-6)
        XCTAssertEqual(cars[0].last!.x, car / 2 - 14.77 * m, accuracy: 1e-3)
        XCTAssertEqual(cars[1].first!.x, cars[0].last!.x, accuracy: 1e-3, "the tender against the locomotive")
        XCTAssertEqual(cars[2].first!.x, cars[1].last!.x - 0.6 * m, accuracy: 1e-3)
        // Past the body's 16 m, straight on.
        XCTAssertEqual(cars[2].last!.x, car / 2 - (14.77 + 9 + 0.6 + 19.4) * m, accuracy: 1e-3)
        XCTAssertTrue(TrainCars.cars(body: [], heading: Point(x: 1, y: 0), lengths: [m], gaps: []).isEmpty)
    }

    /// 88.1: a 12-car 700T or N700S-G at its real 25 m a car on a train
    /// whose cars stand 16 m apart ran some 120 m past its body, straight
    /// off the curving viaduct. Shrunk to the 240 m twelve cars are drawn
    /// at; at its real pitch, as it was.
    func testALongSetIsNoLongerThanItsTrain() {
        let m = Double(WorldCoordinate.unitsPerMetre)
        let lengths = [25.3 * m] + Array(repeating: 25 * m, count: 10) + [25.3 * m], gaps = Array(repeating: 0.0, count: 12)
        let short = TrainCars.cars(body: [Point(x: 0, y: 0), Point(x: -11 * spacing, y: 0)], heading: Point(x: 1, y: 0),
                                   lengths: lengths, gaps: gaps)
        XCTAssertEqual(short.count, 12)
        XCTAssertEqual(short[0].first!.x, car / 2, accuracy: 1e-6, "the nose where every train's is")
        XCTAssertEqual(short[11].last!.x, car / 2 - 12 * car, accuracy: 1e-3, "as long as twelve cars drawn 20 m a car")
        XCTAssertEqual(short[0].first!.x - short[0].last!.x, 25.3 / 300.6 * 12 * car, accuracy: 1e-3, "each its share")
        let pitch = Double(TrainType.highSpeed.carLength)
        let real = TrainCars.cars(body: [Point(x: 0, y: 0), Point(x: -11 * pitch, y: 0)], heading: Point(x: 1, y: 0),
                                  lengths: lengths, gaps: gaps)
        XCTAssertEqual(real[11].last!.x, car / 2 - 300.6 * m, accuracy: 1e-3, "its own lengths")
    }

    /// 88.1: past its tail a train goes on the way its body runs there,
    /// not the way its last step does, which can be a few world units
    /// between rounded points (here 2 along and 1 across, 27° off) and,
    /// laid on for a hundred metres, swung the last cars off the track.
    func testTheTailGoesOnTheWayTheBodyRuns() {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        var body = (0...40).map { Point(x: -Double($0) * metre, y: 0) }
        body.append(Point(x: body.last!.x - 2, y: 1))
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), count: 8)
        let back = cars[7].last!
        XCTAssertEqual(back.x, car / 2 - 8 * car, accuracy: metre)
        XCTAssertEqual(back.y, 0, accuracy: metre / 2, "on the track's line, not \(back.y / metre) m off it")
    }

    func testTheGapIsLeftBetweenCarsNotAtTheEnds() {
        let body = [Point(x: 0, y: 0), Point(x: -spacing, y: 0)]
        let gap = 100.0
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), count: 2, gap: gap)
        XCTAssertEqual(cars[0].first!.x, car / 2, accuracy: 1e-6)
        XCTAssertEqual(cars[1].last!.x, -car * 1.5, accuracy: 1e-6)
        XCTAssertEqual(cars[0].last!.x - cars[1].first!.x, gap, accuracy: 1e-6)
    }

    func testOneCarStandsAcrossItsHead() {
        let cars = TrainCars.cars(body: [Point(x: 10, y: 20)], heading: Point(x: 0, y: 2), count: 1)
        XCTAssertEqual(cars.count, 1)
        XCTAssertEqual(cars[0].first!.y, 20 + car / 2, accuracy: 1e-6)
        XCTAssertEqual(cars[0].last!.y, 20 - car / 2, accuracy: 1e-6)
        XCTAssertEqual(cars[0].first!.x, 10, accuracy: 1e-6)
    }

    func testCarsFollowACurvedBody() {
        // The body turns a right angle 16 m behind the head.
        let body = [Point(x: 0, y: 0), Point(x: -spacing, y: 0), Point(x: -spacing, y: -spacing * 4)]
        let cars = TrainCars.cars(body: body, heading: Point(x: 1, y: 0), count: 2)
        // The second car spans the corner.
        XCTAssertTrue(cars[1].contains(Point(x: -spacing, y: 0)))
        XCTAssertEqual(cars[1].last!.x, -spacing, accuracy: 1e-6)
    }

    func testNoBodyNoCars() {
        XCTAssertTrue(TrainCars.cars(body: [], heading: Point(x: 1, y: 0), count: 3).isEmpty)
    }
}
