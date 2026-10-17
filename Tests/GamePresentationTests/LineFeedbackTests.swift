import GameCore
@testable import GamePresentation
import XCTest

/// Decision 274: feedback, second batch. A line's trains' fit from
/// yesterday's fullest train, the people waiting at its ends against what
/// a train takes, and a train's seats as full as it is.
@MainActor
final class LineFeedbackTests: XCTestCase {
    func testTheFitOfALinesTrains() {
        XCTAssertEqual(TrainFit(peakLoad: 0), .tooBig)
        XCTAssertEqual(TrainFit(peakLoad: 349), .tooBig)
        XCTAssertEqual(TrainFit(peakLoad: 350), .justRight)
        XCTAssertEqual(TrainFit(peakLoad: 999), .justRight)
        XCTAssertEqual(TrainFit(peakLoad: 1_000), .tooSmall)
        XCTAssertEqual(TrainFit(peakLoad: 1_100), .tooSmall)
        XCTAssertEqual(TrainFit.tooSmall.title(in: .traditionalChinese), "列車不夠")
        XCTAssertTrue(TrainFit.tooBig.advice(peakPercent: 20, in: .english).contains("20% full"))
        XCTAssertTrue(TrainFit.tooSmall.advice(peakPercent: 104, in: .traditionalChinese).contains("104%"))
    }

    /// One, two or three people: under half a train, under a train, a
    /// train or more.
    func testTheDemandAtALinesEnds() {
        XCTAssertEqual(EndDemand(waiting: 0, capacity: 400), .calm)
        XCTAssertEqual(EndDemand(waiting: 199, capacity: 400), .calm)
        XCTAssertEqual(EndDemand(waiting: 200, capacity: 400), .busy)
        XCTAssertEqual(EndDemand(waiting: 399, capacity: 400), .busy)
        XCTAssertEqual(EndDemand(waiting: 400, capacity: 400), .crowded)
        XCTAssertEqual(EndDemand(waiting: 5, capacity: 0), .crowded, "no room at all")
        XCTAssertEqual(EndDemand.crowded.rawValue, 3, "three people")
        XCTAssertLessThan(EndDemand.calm, EndDemand.busy)
    }

    /// Two rows of four seats a car, filled from the first car; standing
    /// over the rated capacity.
    func testTheSeatMap() {
        let half = SeatMap(load: TrainLoadInfo(passengerCount: 50, capacity: 100), cars: 4)
        XCTAssertEqual(half.filled, 16)
        XCTAssertFalse(half.standing)
        XCTAssertTrue(half.isFilled(car: 1, seat: 7))
        XCTAssertFalse(half.isFilled(car: 2, seat: 0))
        let over = SeatMap(load: TrainLoadInfo(passengerCount: 120, capacity: 100), cars: 2)
        XCTAssertEqual(over.filled, 16, "every seat")
        XCTAssertTrue(over.standing)
        let empty = SeatMap(load: TrainLoadInfo(passengerCount: 0, capacity: 0), cars: 0)
        XCTAssertEqual(empty.cars, 1)
        XCTAssertEqual(empty.filled, 0)
    }

    /// Lesson 2's game begins with lesson 1's line and its train: its ends
    /// at once, its fit once it has run a day.
    func testALinesFeedback() throws {
        var world = GameWorld.newGame(lesson: Lesson.all[1])
        let line = try XCTUnwrap(world.lines.first)
        let feedback = try XCTUnwrap(world.lineFeedback(line.id))
        XCTAssertNil(feedback.fit, "not a day run yet")
        XCTAssertEqual(feedback.ends.map(\.station), [line.stops.first, line.stops.last].compactMap { $0 })
        XCTAssertTrue(feedback.endsText(in: .english).contains("waiting"))
        try world.advance(ticks: 1 + 1_440)
        let after = try XCTUnwrap(world.lineFeedback(line.id))
        let peak = try XCTUnwrap(world.lineYesterday(line.id)?.peakLoad)
        XCTAssertEqual(after.fit, TrainFit(peakLoad: peak))
        XCTAssertEqual(after.peakPercent, (peak + 5) / 10)
        XCTAssertNil(GameWorld.newGame(lesson: Lesson.all[0]).lines.first.flatMap { world.lineFeedback($0.id) }, "no line, nothing")
    }

    /// A line's end counts the people waiting for that line only: at a
    /// station two lines start from, the other line's riders are not
    /// "more than a train takes" on this one.
    func testAnEndCountsOnlyThoseWaitingForTheLine() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let alpha = try world.buildStation(named: "Alpha", at: TestLine.centre(1, 0)).id
        let beta = try world.buildStation(named: "Beta", at: TestLine.centre(3, 0)).id
        let gamma = try world.buildStation(named: "Gamma", at: TestLine.centre(3, 2)).id
        let main = try world.createLine(named: "Main", stops: [alpha, beta]).id
        let branch = try world.createLine(named: "Branch", stops: [alpha, gamma]).id
        for line in [main, branch] {
            let train = try world.purchaseTrain(named: "T\(line.rawValue)")
            try world.assignTrain(train.id, to: line, pattern: nil)
        }
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 20_000))
        try world.setStationDemand(beta, to: StationDemand(kind: .office, dailyTrips: 1_000))
        try world.setStationDemand(gamma, to: StationDemand(kind: .office, dailyTrips: 1_000))
        world.setSpeed(.normal)
        try world.advance(ticks: 240)
        func waiting(for line: LineID) -> Int64 {
            world.waitingPassengers(at: alpha).filter { $0.line == line }.reduce(0) { $0 + $1.count }
        }
        XCTAssertGreaterThan(waiting(for: main), 0, "the test needs riders for each line")
        XCTAssertGreaterThan(waiting(for: branch), 0, "the test needs riders for each line")
        XCTAssertEqual(world.lineFeedback(main)?.ends.first?.waiting, waiting(for: main))
        XCTAssertEqual(world.lineFeedback(branch)?.ends.first?.waiting, waiting(for: branch))
    }

    /// A long train's seat map wraps, at most ``SeatMap/carsPerRow`` cars a
    /// row, so it fits the train card on a phone (300 points at most).
    func testALongTrainsSeatMapWraps() {
        let load = TrainLoadInfo(passengerCount: 50, capacity: 100)
        XCTAssertEqual(SeatMap(load: load, cars: 4).rows, [0..<4])
        XCTAssertEqual(SeatMap(load: load, cars: 6).rows, [0..<6])
        XCTAssertEqual(SeatMap(load: load, cars: 12).rows, [0..<6, 6..<12])
        XCTAssertEqual(SeatMap(load: load, cars: 16).rows, [0..<6, 6..<12, 12..<16])
    }
}
