import GameCore
@testable import GamePresentation
import XCTest

/// Decision 276: each trip's result stamped where it ends, full or plenty
/// of seats, from the fullest its train was.
@MainActor
final class TripStampTests: XCTestCase {
    /// Decision 274's fit: under 35% plenty of seats, 100% and over full,
    /// in between no stamp.
    func testTheStampOfATripsPeakLoad() {
        XCTAssertEqual(TripStampKind(peakLoad: 0), .roomy)
        XCTAssertEqual(TripStampKind(peakLoad: 349), .roomy)
        XCTAssertNil(TripStampKind(peakLoad: 350))
        XCTAssertNil(TripStampKind(peakLoad: 999))
        XCTAssertEqual(TripStampKind(peakLoad: 1_000), .full)
        XCTAssertEqual(TripStampKind.full.title(in: .traditionalChinese), "客滿")
        XCTAssertEqual(TripStampKind.roomy.title(in: .english), "Plenty of seats")
    }

    /// One a station, the newer in its place; at most six; gone after
    /// their lifetime; at 600× only the followed train's and those near
    /// the middle.
    func testTheBoard() {
        func stamp(_ station: Int, train: Int = 1, kind: TripStampKind = .full) -> TripStamp {
            TripStamp(station: StationID(rawValue: station), location: PlanPoint(x: Int64(station), y: 0), train: TrainID(rawValue: train), kind: kind)
        }
        var board = TripStampBoard()
        board.add([stamp(1), stamp(2)], at: 0)
        board.add([stamp(1, kind: .roomy)], at: 0.5)
        XCTAssertEqual(board.stamps.map(\.station.rawValue), [2, 1])
        XCTAssertEqual(board.stamps.last?.kind, .roomy)
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
    /// first trips of the day leave its four-car train mostly empty; its
    /// morning riders fill a one-car train. Each stamp is at a stop of the
    /// line.
    func testALinesTripsAreStampedWhereTheyEnd() throws {
        func stamps(cars: Int, until done: ([TripStamp]) -> Bool) throws -> (stamps: [TripStamp], stops: [StationID]) {
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
                if done(stamped) { break }
            }
            return (stamped, line.stops)
        }
        let long = try stamps(cars: 4) { $0.count >= 4 }
        XCTAssertFalse(long.stamps.isEmpty, "a long train's trips end with plenty of seats")
        XCTAssertTrue(long.stamps.allSatisfy { $0.kind == .roomy }, "\(long.stamps.map(\.kind))")
        XCTAssertTrue(long.stamps.allSatisfy { long.stops.contains($0.station) })

        // At night a one-car train has seats; in the morning it is full.
        let short = try stamps(cars: Train.minimumCars) { $0.contains { $0.kind == .full } }
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
