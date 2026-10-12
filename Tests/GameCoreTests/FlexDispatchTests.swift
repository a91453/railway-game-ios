import Foundation
@testable import GameCore
import XCTest

/// Flexible dispatch (ARCHITECTURE decision 172): a line sends a train out
/// from either end, on a ring from any stop, and a train that stands
/// anywhere else runs empty to the nearer end first. Edits that move a
/// line's first stop no longer leave the line standing still.
///
/// The line of `LineDispatchTests`: nodes b, d and f carry Alpha, Beta and
/// Gamma, two links (2048 units) apart, with Delta's platform just past
/// Gamma's. The lines plan with a crawl, so a link takes a minute.
final class FlexDispatchTests: XCTestCase {
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let delta = StationID(rawValue: 4)
    private let main = LineID(rawValue: 1)
    private let one = TrainID(rawValue: 1)
    private let crawl = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1)

    private func makeWorld(stops: [StationID], trains count: Int = 1, at start: TrainPosition? = nil) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 0), speed: .normal)
        )
        world.setFlexDispatch(true)
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let delta = try world.buildStation(named: "Delta", at: TestLine.centre(5, 2)).id
        try world.addTrackPlatform(delta, on: line.edge(6), from: 512, to: 1_024)
        try world.createLine(named: "Main", stops: stops)
        try world.setLinePerformance(main, to: crawl)
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: count, offPeak: count, low: count))
        for index in 1...count {
            let train = try world.purchaseTrain(named: "T\(index)")
            try world.placeTrain(train.id, at: line.at(1, facingEast: true))
            try world.setTrainMovementRate(train.id, to: 1024)
            try world.assignTrain(train.id, to: main)
        }
        if let start {
            try move(&world, one, to: start)
        }
        return world
    }

    /// Stands `train` at `position`, still on its line, with its rate.
    private func move(_ world: inout GameWorld, _ train: TrainID, to position: TrainPosition) throws {
        try world.unplaceTrain(train)
        try world.placeTrain(train, at: position)
        try world.setTrainMovementRate(train, to: 1024)
    }

    private func stations(of train: TrainID, in world: GameWorld) -> [StationID] {
        world.train(id: train)?.timetable.map(\.station) ?? []
    }

    /// Off, as in every world before decision 172, nothing changes: a train
    /// at the last stop or off the line's stops is not sent out, and the
    /// notice and the outlook say nothing.
    func testWithoutFlexibleDispatchTheLineStaysAsItWas() throws {
        var world = try makeWorld(stops: [alpha, gamma], at: line.at(5, facingEast: false))
        world.setFlexDispatch(false)
        let before = world
        try world.advance(ticks: 30)
        XCTAssertNil(world.train(id: one)?.execution)
        XCTAssertEqual(world.train(id: one)?.timetable, [])
        XCTAssertNil(world.line(id: main)?.lastDispatch)
        XCTAssertEqual(world.lineDispatchOutlook(main), [])
        XCTAssertEqual(world.clock.now, GameTime(minutes: 30))
        XCTAssertFalse(before.flexDispatch)
        XCTAssertThrowsError(try world.reverseLineStops(main)) { XCTAssertEqual($0 as? GameError, .trainOnLine(one)) }
    }

    // MARK: - From the last stop

    /// A train that stands at the line's last stop is sent out from there,
    /// the round trip of the calls in reverse: back to the first stop, out
    /// to the last again. Alpha to Gamma is four links, 240 s at a crawl;
    /// the train leaves 42 s after it is sent out (the least dwell), stays
    /// 2 minutes at the far end and is back 240 s after that.
    func testATrainAtTheLastStopIsSentOutFromThereAndBack() throws {
        var world = try makeWorld(stops: [alpha, gamma], at: line.at(5, facingEast: false))
        try world.advance(ticks: 1)
        let train = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(train.timetable, [
            ScheduledStop(station: gamma, arrival: GameTime(seconds: 0), departure: GameTime(seconds: 42)),
            ScheduledStop(station: alpha, arrival: GameTime(seconds: 282), departure: GameTime(seconds: 402), reverses: true),
            ScheduledStop(station: gamma, arrival: GameTime(seconds: 642), departure: GameTime(seconds: 642), reverses: true),
        ])
        XCTAssertEqual(train.execution, .travellingToStop(1))
        XCTAssertFalse(train.isDeadheading)
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 0), "it takes the line's headway slot")
        XCTAssertEqual(world.lineDeadheadDistance(main), 0)
        XCTAssertEqual(world.lineDispatchOutlook(main), [TrainDispatchOutlook(train: one, isRunning: true, plan: .fromLastStop)], "the trip ends where it began")
    }

    /// Facing away from the way it can go, it is turned round as it
    /// leaves, as at the first stop.
    func testATrainFacingAwayAtTheLastStopTurnsRoundAsItLeaves() throws {
        var world = try makeWorld(stops: [alpha, gamma], at: line.at(5, facingEast: true))
        try world.advance(ticks: 1)
        let train = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(stations(of: one, in: world), [gamma, alpha, gamma])
        XCTAssertTrue(train.timetable[0].reverses)
        XCTAssertEqual(train.execution, .travellingToStop(1))
    }

    /// The trip ends at the last stop, where the train is ready again: the
    /// line goes on, a round trip after a round trip, from the same end.
    func testTheLineKeepsRunningFromTheLastStop() throws {
        var world = try makeWorld(stops: [alpha, gamma], at: line.at(5, facingEast: false))
        try world.advance(ticks: 12)
        XCTAssertNil(world.train(id: one)?.execution, "back at Gamma and ended")
        try world.advance(ticks: 1)
        let train = try XCTUnwrap(world.train(id: one))
        XCTAssertNotNil(train.execution, "sent out again")
        XCTAssertEqual(train.timetable.first?.station, gamma)
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 12))
    }

    // MARK: - The edits that used to stop a line

    /// Decision 134's case: a two-stop line whose first stop is moved back
    /// is a reversed line. The train that stands at what is now the last
    /// stop goes on from there; the line is never left without a dispatch.
    func testReversingALineWithATrainKeepsItRunning() throws {
        var world = try makeWorld(stops: [alpha, gamma])
        try world.advance(ticks: 12)
        XCTAssertNil(world.train(id: one)?.execution)
        let before = try XCTUnwrap(world.train(id: one)?.timetable)

        try world.reverseLineStops(main)
        XCTAssertEqual(world.line(id: main)?.stops, [gamma, alpha])
        try world.advance(ticks: 1)
        let train = try XCTUnwrap(world.train(id: one))
        XCTAssertNotNil(train.execution)
        XCTAssertEqual(stations(of: one, in: world), [alpha, gamma, alpha], "from the new last stop, Alpha")
        XCTAssertNotEqual(train.timetable, before)
    }

    /// A trip being run when the line is reversed is finished as it was
    /// planned (its own timetable); the next one follows the new order.
    func testAnEditedLineFinishesTheTripAlreadyRunning() throws {
        var world = try makeWorld(stops: [alpha, gamma])
        try world.advance(ticks: 2)
        let running = try XCTUnwrap(world.train(id: one)?.timetable)
        try world.reverseLineStops(main)
        try world.advance(ticks: 5)
        XCTAssertEqual(world.train(id: one)?.timetable, running)
        XCTAssertNotNil(world.train(id: one)?.execution)
    }

    /// Taking the first stop out of a line: a train that stands at the old
    /// first stop is on no stop of the line, and runs empty to the nearer
    /// end (Beta, two links; Gamma is four), without a fare, then goes out.
    func testATrainAtARemovedFirstStopRunsEmptyToTheNearerEnd() throws {
        var world = try makeWorld(stops: [alpha, beta, gamma])
        try world.setLineStops(main, to: [beta, gamma])
        XCTAssertEqual(world.lineDispatchOutlook(main), [TrainDispatchOutlook(train: one, isRunning: false, plan: .runsEmpty(to: beta))])

        try world.advance(ticks: 1)
        var train = try XCTUnwrap(world.train(id: one))
        XCTAssertTrue(train.isDeadheading)
        XCTAssertEqual(train.timetable.map(\.station), [alpha, beta])
        XCTAssertNil(world.line(id: main)?.lastDispatch, "an empty run takes no headway slot")
        XCTAssertEqual(world.lineDeadheadDistance(main), 2_048, "two links")
        XCTAssertEqual(world.riders(of: one), [])

        // 42 s at the stop, two links of 60 s each at a crawl.
        try world.advance(ticks: 3)
        train = try XCTUnwrap(world.train(id: one))
        XCTAssertFalse(train.isDeadheading, "the empty run is over")
        XCTAssertTrue(train.execution == nil || stations(of: one, in: world).first == beta, "sent out from Beta")
        try world.advance(ticks: 1)
        train = try XCTUnwrap(world.train(id: one))
        XCTAssertEqual(train.timetable.first?.station, beta)
        XCTAssertFalse(train.isDeadheading)
        XCTAssertNotNil(world.line(id: main)?.lastDispatch)
        XCTAssertEqual(world.lineDeadheadDistance(main), 2_048, "only the run to the end")
    }

    /// A station put in before the first stop: the train at the old first
    /// stop is now mid-line, and runs to an end (the first among equals).
    func testATrainAtAStopInsertedBeforeItRunsToAnEnd() throws {
        var world = try makeWorld(stops: [beta, gamma], at: line.at(3, facingEast: true))
        try world.setLineStops(main, to: [alpha, beta, gamma])
        let outlook = world.lineDispatchOutlook(main)
        XCTAssertEqual(outlook.count, 1)
        XCTAssertEqual(outlook.first?.plan, .runsEmpty(to: alpha), "two links either way; the first end among equals")
        try world.advance(ticks: 1)
        XCTAssertTrue(try XCTUnwrap(world.train(id: one)).isDeadheading)
        XCTAssertTrue(try XCTUnwrap(world.train(id: one)).timetable[0].reverses, "turned round to go west")
    }

    /// A first stop extended past the old one: the train stands mid-line,
    /// and a nearer end that is beyond is chosen by time, not by order.
    func testTheNearerEndIsTheOneItReachesSooner() throws {
        var world = try makeWorld(stops: [alpha, gamma], at: line.at(5, facingEast: true))
        try world.setLineStops(main, to: [alpha, gamma, delta])
        // At Gamma facing east; Delta's platform is just ahead, Alpha four
        // links behind.
        XCTAssertEqual(world.lineDispatchOutlook(main).first?.plan, .runsEmpty(to: delta))
        try world.advance(ticks: 1)
        let train = try XCTUnwrap(world.train(id: one))
        XCTAssertTrue(train.isDeadheading)
        XCTAssertEqual(train.timetable.map(\.station), [gamma, delta])
        XCTAssertFalse(train.timetable[0].reverses)
    }

    /// A line whose only trains cannot reach an end is not sent anything:
    /// the outlook says so, and nothing runs.
    func testATrainThatCannotReachAnEndIsStranded() throws {
        var world = try makeWorld(stops: [alpha, gamma])
        // Alpha is cut off from the rest of the track.
        try world.removeTrackPlatform(beta, on: line.edge(3), from: 512)
        try world.removeTrackEdge(line.edge(3))
        try world.setLineStops(main, to: [beta, gamma])
        let train = try XCTUnwrap(world.train(id: one))
        let standing = world
        try world.advance(ticks: 30)
        XCTAssertEqual(world.train(id: one)?.timetable, train.timetable)
        XCTAssertNil(world.train(id: one)?.execution)
        XCTAssertEqual(standing.lineDispatchOutlook(main).first?.plan, .stranded)
    }

    // MARK: - Cost, saving

    /// Decision 178, later: the key of the passenger load layer leaves out
    /// when a line last sent a train out, as the plan's key does.
    func testALineWithoutDispatchTimesDoesNotChangeAtADeparture() throws {
        var world = try makeWorld(stops: [alpha, beta, gamma])
        let before = try XCTUnwrap(world.line(id: main))
        try world.advance(ticks: 3)
        let after = try XCTUnwrap(world.line(id: main))
        XCTAssertNotEqual(before.lastDispatch, after.lastDispatch, "a train went out")
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(before.withoutDispatchTimes, after.withoutDispatchTimes)
        XCTAssertNil(after.withoutDispatchTimes.lastDispatch)
    }

    /// Decision 178's key leaves out the empty runs' distance too: it grows
    /// with every empty run and no plan reads it, so the passenger plan was
    /// worked out again after each.
    func testALineKeyDoesNotChangeWithAnEmptyRun() throws {
        var world = try makeWorld(stops: [beta, gamma], at: line.at(3, facingEast: true))
        try world.setLineStops(main, to: [alpha, beta, gamma])
        let before = try XCTUnwrap(world.line(id: main))
        try world.advance(ticks: 2)
        let after = try XCTUnwrap(world.line(id: main))
        XCTAssertGreaterThan(after.deadheadDistance, 0, "the train ran empty to an end")
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(before.withoutDispatchTimes, after.withoutDispatchTimes)
    }

    func testAnEmptyRunIsCountedForItsLine() throws {
        var world = try makeWorld(stops: [alpha, beta, gamma])
        try world.setLineStops(main, to: [beta, gamma])
        XCTAssertEqual(world.lineDeadheadDistance(main), 0)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.lineDeadheadDistance(main), 2_048)
        XCTAssertNil(world.lineDeadheadDistance(LineID(rawValue: 9)))
    }

    /// A save in the middle of an empty run loads the same world.
    func testAnEmptyRunSurvivesASave() throws {
        var world = try makeWorld(stops: [alpha, beta, gamma])
        try world.setLineStops(main, to: [beta, gamma])
        try world.advance(ticks: 2)
        XCTAssertTrue(try XCTUnwrap(world.train(id: one)).isDeadheading)
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.lineDeadheadDistance(main), 2_048)
        // An empty-run mark on a train with no service is damage.
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"deadhead\":true"))
        let idle = try makeWorld(stops: [alpha, gamma])
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(SavedGame(world: idle))) as? [String: Any])
        var worldObject = try XCTUnwrap(object["world"] as? [String: Any])
        var trains = try XCTUnwrap(worldObject["trains"] as? [[String: Any]])
        trains[0]["deadhead"] = true
        worldObject["trains"] = trains
        object["world"] = worldObject
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    /// Batches and single ticks agree with the new dispatch.
    func testLongBatchesMatchSingleTicksWithAnEmptyRun() throws {
        var batch = try makeWorld(stops: [alpha, beta, gamma])
        try batch.setLineStops(main, to: [beta, gamma])
        var single = batch
        try batch.advance(ticks: 90)
        for _ in 0..<90 { try single.advance(ticks: 1) }
        XCTAssertEqual(batch, single)
    }

    /// Version 45 (decision 172): a line Main calling at Beta and Gamma
    /// whose train stood at Alpha, the stop taken out; sent out empty to
    /// Beta, two links, and saved on its way (the `"deadhead"` train and
    /// the line's `"deadheadDistance"`). It saves byte for byte and is the
    /// world this build makes.
    func testVersionFortyFiveKeepsAnEmptyRun() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v45-flex-dispatch.json")
        var made = try makeWorld(stops: [alpha, beta, gamma])
        try made.setLineStops(main, to: [beta, gamma])
        try made.advance(ticks: 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["FLEX_DISPATCH_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 45)
        XCTAssertEqual((object["world"] as? [String: Any])?["flexDispatch"] as? Bool, true)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertTrue(try XCTUnwrap(world.train(id: one)).isDeadheading)
        XCTAssertEqual(world.lineDeadheadDistance(main), 2_048)
        // It goes on to Beta and is sent out from there, empty-handed no more.
        var carried = world
        try carried.advance(ticks: 5)
        XCTAssertFalse(try XCTUnwrap(carried.train(id: one)).isDeadheading)
        XCTAssertEqual(carried.train(id: one)?.timetable.first?.station, beta)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 45,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
