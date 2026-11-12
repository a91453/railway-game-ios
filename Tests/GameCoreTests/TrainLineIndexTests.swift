@testable import GameCore
import XCTest

/// Decision 703: the line of each train looked up (``GameWorld/TrainLineIndex``)
/// is the line ``GameWorld/assignedLine(of:)`` searches for, for every
/// train and after every command, with the same index kept throughout;
/// and so are the answers worked out from it.
final class TrainLineIndexTests: XCTestCase {
    /// Every train of `world`, and one it has not, asked of `known` and of
    /// the searches the index stands in for.
    private func check(_ world: GameWorld, _ known: inout GameWorld.TrainLineIndex, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        for id in world.trains.map(\.id) + [TrainID(rawValue: 9_999)] {
            let assigned = world.assignedLine(of: id)
            let searched = world.lines.firstIndex { assigned == $0.id }
            XCTAssertEqual(world.assignedLineIndex(of: id, known: &known), searched, "\(step), train \(id)", file: file, line: line)
            XCTAssertEqual(searched.map { world.lines[$0] }, assigned.flatMap { world.line(id: $0) }, "\(step), train \(id)", file: file, line: line)
            XCTAssertEqual(known.isOnRing(id, in: world.lines), world.lines.contains { $0.isRing && $0.trains.contains(id) }, "\(step), train \(id)", file: file, line: line)
            guard let train = world.train(id: id) else { continue }
            if case .waitingAtStop(let stop, let cycle)? = train.execution, let times = train.times {
                XCTAssertEqual(world.closingStart(of: train, stop: stop, cycle: cycle, times: times, known: &known),
                               world.closingStart(of: train, stop: stop, cycle: cycle, times: times), "\(step), train \(id)", file: file, line: line)
            }
            XCTAssertEqual(world.hasRoutePreferences(train, known: &known), world.hasRoutePreferences(train), "\(step), train \(id)", file: file, line: line)
        }
    }

    func testTheIndexAnswersAsTheSearchDoesAfterEveryCommand() throws {
        var (world, local, express, stations) = try LocalPassTests.running()
        let first = try XCTUnwrap(world.assignedLine(of: local))
        var known = GameWorld.TrainLineIndex()
        check(world, &known, "as built")
        XCTAssertNotNil(world.assignedLineIndex(of: express, known: &known), "a pattern's train is the line's")

        // A train on no line, then on a new line; the express taken off
        // its pattern and put on another line.
        let spare = try world.purchaseTrain(named: "Spare").id
        check(world, &known, "a train bought")
        XCTAssertNil(world.assignedLineIndex(of: spare, known: &known))
        let second = try world.createLine(named: "Second", stops: [stations[0], stations[1]]).id
        let empty = try world.createLine(named: "Empty", stops: [stations[0], stations[1]]).id
        let third = try world.createLine(named: "Third", stops: [stations[0], stations[1]]).id
        check(world, &known, "lines created")
        try world.assignTrain(spare, to: third)
        check(world, &known, "the spare assigned")
        XCTAssertEqual(world.assignedLineIndex(of: spare, known: &known), 3)
        try world.unassignTrain(express)
        check(world, &known, "the express unassigned")
        XCTAssertNil(world.assignedLineIndex(of: express, known: &known))
        try world.assignTrain(express, to: second)
        check(world, &known, "the express on the second line")
        XCTAssertEqual(world.assignedLineIndex(of: express, known: &known).map { world.lines[$0].id }, second)

        // The index kept through the trains running: departures change the
        // lines (when they last sent a train out), never whose a train is.
        for step in 0..<120 {
            try world.advance(ticks: 30)
            check(world, &known, "running, step \(step)")
        }
        XCTAssertEqual(world.assignedLine(of: local), first)

        // A line before the spare's removed: its line is one place earlier.
        try world.removeLine(empty)
        check(world, &known, "the empty line removed")
        XCTAssertEqual(world.assignedLineIndex(of: spare, known: &known), 2)
    }

    func testRoutePreferencesFoundFromTheIndexAreThoseSearchedFor() throws {
        for patterns in [false, true] {
            var (world, _, line, train) = try LineRoutePreferenceTests.setup(patterns: patterns)
            var known = GameWorld.TrainLineIndex()
            check(world, &known, "no route, patterns \(patterns)")
            try world.setLineRoutePreferences(line, to: [LineRoutePreferenceTests.loop(world, pattern: patterns)], pattern: patterns ? 0 : nil)
            for step in 0..<60 {
                try world.advance(ticks: 30)
                check(world, &known, "a route, patterns \(patterns), step \(step)")
            }
            XCTAssertTrue(try world.hasRoutePreferences(XCTUnwrap(world.train(id: train)), known: &known), "patterns \(patterns)")
            try world.setLineRoutePreferences(line, to: [], pattern: patterns ? 0 : nil)
            check(world, &known, "the route taken away, patterns \(patterns)")
            XCTAssertFalse(try world.hasRoutePreferences(XCTUnwrap(world.train(id: train)), known: &known), "patterns \(patterns)")
        }
    }

    /// A ring's train dwells at its first stop as at any other (decision
    /// 49): found from the index as from the search, the line made a ring
    /// and a line again.
    func testARingsTrainsAreThoseSearchedFor() throws {
        var (world, _, line, train) = try LineRoutePreferenceTests.setup()
        var known = GameWorld.TrainLineIndex()
        check(world, &known, "a line")
        XCTAssertFalse(known.isOnRing(train, in: world.lines))
        var closings = 0
        for step in 0..<600 {
            try world.advance(ticks: 5)
            check(world, &known, "a line, step \(step)")
            XCTAssertEqual(world.nextServiceEvent(after: world.clock.now, known: &known), world.nextServiceEvent(after: world.clock.now), "step \(step)")
            // The train standing with its doors open: the same world with
            // the line a ring, asked of the same index.
            guard let standing = world.train(id: train), case .waitingAtStop(let stop, let cycle)? = standing.execution,
                  let times = standing.times, times.exchangeEnd != nil else { continue }
            closings += 1
            var ring = world
            try ring.setLineRing(line, to: true)
            XCTAssertTrue(known.isOnRing(train, in: ring.lines), "step \(step)")
            XCTAssertEqual(ring.closingStart(of: standing, stop: stop, cycle: cycle, times: times, known: &known),
                           ring.closingStart(of: standing, stop: stop, cycle: cycle, times: times), "step \(step)")
            check(ring, &known, "a ring, step \(step)")
            XCTAssertFalse(known.isOnRing(train, in: world.lines), "a line again, step \(step)")
        }
        XCTAssertGreaterThan(closings, 0, "the train stood at a stop with its doors open")
    }

    /// A plan worked out with the index kept from before a command is the
    /// plan worked out with nothing kept.
    func testAPlanAfterACommandIsThePlanWorkedOutAfresh() throws {
        var (world, _, express, _) = try LocalPassTests.running()
        var parts = GameWorld.TrafficParts(), paths = GameWorld.PathMemo()
        func compare(_ step: String) {
            let kept = world.trafficPlan(parts: &parts, paths: &paths)
            var freshParts = GameWorld.TrafficParts(), freshPaths = GameWorld.PathMemo()
            let fresh = world.trafficPlan(parts: &freshParts, paths: &freshPaths)
            XCTAssertEqual(kept.waits, fresh.waits, step)
            XCTAssertEqual(kept.services.map(\.points), fresh.services.map(\.points), step)
        }
        for step in 0..<200 {
            try world.advance(ticks: 10)
            compare("before, step \(step)")
        }
        try world.unassignTrain(express)
        // What a command changes the parts are not kept through; the index
        // is, and answers for the lines as they now are.
        var afterCommand = GameWorld.TrafficParts()
        afterCommand.trainLines = parts.trainLines
        parts = afterCommand
        paths = GameWorld.PathMemo()
        for step in 0..<200 {
            try world.advance(ticks: 10)
            compare("after, step \(step)")
        }
    }
}
