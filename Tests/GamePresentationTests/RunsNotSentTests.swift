@testable import GameCore
@testable import GamePresentation
import XCTest

/// MISSRUN: a run timetabled past midnight belongs to the day before, and
/// is not missed when that midnight comes (``RunsNotSent``). The long
/// reports counted at the next midnight and called the real lines' last
/// runs missed: Ankeng's 24:14 and 24:37, Danhai's six from 24:14 to
/// 26:05, the High Speed Rail's 24:14 out of Taipei.
final class RunsNotSentTests: XCTestCase {
    private let track = TestLine(tiles: 9)
    private let alpha = StationID(rawValue: 1)
    private let gamma = StationID(rawValue: 2)
    private let main = LineID(rawValue: 1)
    private let day = GameTime.secondsPerDay

    /// Alpha and Gamma on a straight track, one train standing at Alpha at
    /// 23:00 on day 0; Main runs Alpha to Gamma at 24:14, and Gamma to
    /// Alpha at 23:10, which has no train to take it.
    private func world() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 10_240, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 23 * 60), speed: .normal)
        )
        try track.build(in: &world)
        try track.buildStation(named: "Alpha", beside: 3, at: 0, in: &world)
        try track.buildStation(named: "Gamma", beside: 7, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLinePerformance(main, to: TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: track.at(3, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1024)
        try world.assignTrain(train.id, to: main)
        let pastMidnight: Int64 = 24 * 3_600 + 14 * 60
        try world.setLineRuns(main, to: [
            LineRun(from: 0, to: 1, times: [
                LineRunTime(arrival: pastMidnight, departure: pastMidnight),
                LineRunTime(arrival: pastMidnight + 1_800, departure: pastMidnight + 1_800),
            ]),
            LineRun(from: 1, to: 0, times: [
                LineRunTime(arrival: 23 * 3_600 + 600, departure: 23 * 3_600 + 600),
                LineRunTime(arrival: 23 * 3_600 + 2_400, departure: 23 * 3_600 + 2_400),
            ]),
        ])
        return world
    }

    func testARunPastMidnightIsNotMissedAtMidnight() throws {
        var world = try world()
        try world.advance(ticks: 60)
        XCTAssertEqual(world.clock.now.seconds, day)
        var line = try XCTUnwrap(world.line(id: main))
        // Counted the old way, both runs look missed at midnight.
        XCTAssertEqual(line.runs.indices.count { (line.runDays[$0] ?? -1) < 0 }, 2)
        XCTAssertEqual(RunsNotSent.on(0, of: line, at: world.clock.now), [1], "only the run with no train")
        XCTAssertEqual(RunsNotSent.closed(day: 0, of: [line]), day + 14 * 60 + LineRun.latestDispatch + 1)

        try world.advance(ticks: 60)
        line = try XCTUnwrap(world.line(id: main))
        XCTAssertEqual(line.runDays[0], 0, "the 24:14 went, for day 0")
        XCTAssertEqual(RunsNotSent.on(0, of: line, at: world.clock.now), [1])
    }
}
