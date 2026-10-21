import GameCore
@testable import GamePresentation
import XCTest

/// Decision 276: each trip's result stamped where it ends, from the
/// fullest its train was; since decision 310, full only.
@MainActor
final class TripStampTests: XCTestCase {
    /// Decision 274's fit: 100% and over full; under it no stamp, plenty
    /// of seats included (decision 310). The train's "滿載", not the
    /// station's "客滿".
    func testTheStampOfATripsPeakLoad() {
        XCTAssertNil(TripStampKind(peakLoad: 0))
        XCTAssertNil(TripStampKind(peakLoad: 349))
        XCTAssertNil(TripStampKind(peakLoad: 999))
        XCTAssertEqual(TripStampKind(peakLoad: 1_000), .full)
        XCTAssertEqual(TripStampKind.full.title(in: .traditionalChinese), "滿載")
        XCTAssertEqual(TripStampKind.full.title(in: .english), "Train full")
    }

    /// One a station, the newer in its place; at most six; gone after
    /// their lifetime; at 600× only the followed train's and those near
    /// the middle.
    func testTheBoard() {
        func stamp(_ station: Int, train: Int = 1) -> TripStamp {
            TripStamp(station: StationID(rawValue: station), location: PlanPoint(x: Int64(station), y: 0), train: TrainID(rawValue: train), kind: .full)
        }
        var board = TripStampBoard()
        board.add([stamp(1), stamp(2)], at: 0)
        board.add([stamp(1, train: 2)], at: 0.5)
        XCTAssertEqual(board.stamps.map(\.station.rawValue), [2, 1])
        XCTAssertEqual(board.stamps.last?.train.rawValue, 2)
        board.add((3...9).map { stamp($0) }, at: 1)
        XCTAssertEqual(board.stamps.count, TripStampBoard.maximum)
        XCTAssertEqual(board.stamps.map(\.station.rawValue), [4, 5, 6, 7, 8, 9])
        board.expire(at: 1 + TripStampBoard.lifetime)
        XCTAssertEqual(board.stamps, [])

        board.add([stamp(1, train: 7), stamp(10), stamp(20), stamp(30), stamp(40)], at: 5)
        let shown = board.shown(fast: true, followed: TrainID(rawValue: 7)) { Double($0.x) }
        XCTAssertEqual(Set(shown.map(\.station.rawValue)), [1, 10, 20])
        XCTAssertEqual(board.shown(fast: false, followed: nil) { _ in 0 }.count, 5)
        XCTAssertGreaterThan(TripStampBoard.hold, 0)
    }

    /// Lesson 2's game begins with lesson 1's line and its train. Its
    /// four-car train's first trips of the day run mostly empty and are not
    /// stamped (decision 310); its morning riders fill a one-car train,
    /// stamped full. Each stamp is at a stop of the line.
    func testALinesTripsAreStampedWhereTheyEnd() throws {
        func stamps(cars: Int, until done: ([TripStamp], Int) -> Bool) throws -> (stamps: [TripStamp], stops: [StationID]) {
            let session = GameSession(world: GameWorld.newGame(lesson: Lesson.all[1]))
            let line = try XCTUnwrap(session.world.lines.first)
            // Re-formed as the line panel does (decision 180).
            session.selectLine(line.id)
            session.reformSelectedLine(type: nil, cars: cars)
            var world = session.world
            XCTAssertEqual(world.line(id: line.id)?.assignedTrains.compactMap { world.train(id: $0)?.cars }.first, cars,
                           session.message?.text ?? "")
            var loads = TripLoads()
            var stamped: [TripStamp] = []
            for _ in 0..<(3 * 1_440) {
                let before = world
                try world.advance(ticks: 1)
                stamped += loads.step(from: before, to: world)
                let ended = world.tripLog.filter { $0.line == line.id && $0.arrival != nil && !$0.isDeadhead }.count
                if done(stamped, ended) { break }
            }
            return (stamped, line.stops)
        }
        // Its first four trips end, none of them full.
        var ended = 0
        let long = try stamps(cars: 4) { ended = $1; return $1 >= 4 }
        XCTAssertGreaterThanOrEqual(ended, 4, "the long train's first trips ended")
        XCTAssertEqual(long.stamps, [], "trips with seats to spare are not stamped")

        // In the morning a one-car train is full.
        let short = try stamps(cars: Train.minimumCars) { stamped, _ in stamped.contains { $0.kind == .full } }
        XCTAssertTrue(short.stamps.contains { $0.kind == .full }, "a one-car train's morning trips end full: \(short.stamps.map(\.kind))")
        XCTAssertTrue(short.stamps.allSatisfy { short.stops.contains($0.station) })
    }

    /// A trip that ended before the step, or one never read running, is
    /// not stamped.
    func testOnlyATripReadRunningIsStamped() throws {
        var world = GameWorld.newGame(lesson: Lesson.all[1])
        var loads = TripLoads()
        // Not read while it ran: a day passes in one step.
        let before = world
        try world.advance(ticks: 1_440)
        XCTAssertEqual(loads.step(from: before, to: world), [])
        // The same world again: nothing ended since.
        XCTAssertEqual(loads.step(from: world, to: world), [])
    }
}
