import Foundation
import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 101: trains for a line in one step. The player
/// picks how often a train comes; the line gets the trains its round trip
/// needs for that, bought, placed where its trips start, assigned and set
/// to that headway, as one edit; and the line sends them all out.
@MainActor
final class LineStaffingTests: XCTestCase {
    private static let line = TestLine(tiles: 9, row: 1)
    private static let main = LineID(rawValue: 1)

    /// Alpha, Beta, Gamma and Delta along one straight track, and a line
    /// calling at all four, running all day.
    private func lineWorld(balance: Money = 1_000_000) throws -> GameWorld {
        var world = try makeWorld(width: 9_216, height: 4_096, balance: balance, speed: .normal)
        try Self.line.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            stops.append(try Self.line.buildStation(named: name, beside: x, at: 0, in: &world))
        }
        try world.createLine(named: "Main", stops: stops)
        try world.setLineServiceWindow(Self.main, to: .allDay)
        return world
    }

    func testThePlanIsOneTrainForEachHeadwayOfTheRoundTrip() throws {
        let world = try lineWorld()
        let roundTrip = try XCTUnwrap(world.lineJourney(Self.main)).roundTripMinutes
        let most = try XCTUnwrap(world.lineMaximumTrains(Self.main))
        for headway in GameWorld.staffingHeadways {
            let plan = try XCTUnwrap(world.lineStaffingPlan(Self.main, headway: headway))
            let wanted = Int((roundTrip + headway - 1) / headway)
            XCTAssertEqual(plan.trains, min(max(1, wanted), most), "every \(headway) min")
            XCTAssertEqual(plan.roundTripMinutes, roundTrip)
            XCTAssertEqual(plan.cost, Money(world.economy.costs.train.amount * Int64(plan.trains)))
            XCTAssertLessThanOrEqual(plan.actualHeadway * Int64(plan.trains), roundTrip + Int64(plan.trains) - 1)
        }
        XCTAssertNil(world.lineStaffingPlan(Self.main, headway: 1), "under the 2-minute minimum")
        XCTAssertNil(world.lineStaffingPlan(LineID(rawValue: 9), headway: 5))
    }

    func testNoPlanForALineWithoutTrackOrARing() throws {
        var world = try makeWorld(balance: 1_000_000)
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 1_024, y: 1_024)).id
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 5_120, y: 1_024)).id
        try world.createLine(named: "Paper", stops: [a, b])
        XCTAssertNil(world.lineStaffingPlan(Self.main, headway: 5), "no track joins them")

        let session = GameSession(world: world)
        session.staffSelectedLine(headway: 5)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, world)

        var ring = try lineWorld()
        try ring.setLineRing(Self.main, to: true)
        XCTAssertNil(ring.lineStaffingPlan(Self.main, headway: 5))
    }

    func testStaffingBuysPlacesAssignsAndSetsTheHeadwayInOneEdit() throws {
        let start = try lineWorld()
        let session = GameSession(world: start)
        let plan = try XCTUnwrap(start.lineStaffingPlan(Self.main, headway: 5))
        let journey = try XCTUnwrap(start.lineJourney(Self.main))
        XCTAssertGreaterThan(plan.trains, 1, "the test needs several trains")

        session.staffSelectedLine(headway: 5)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let world = session.world
        XCTAssertEqual(world.trains.count, plan.trains)
        XCTAssertEqual(world.economy.balance, start.economy.balance - plan.cost)
        let line = try XCTUnwrap(world.line(id: Self.main))
        XCTAssertEqual(line.trains, world.trains.map(\.id))
        XCTAssertEqual(line.targetHeadways, TargetHeadways(peak: 5, offPeak: 5, low: 5))
        for train in world.trains {
            XCTAssertEqual(train.position, journey.start, "\(train.name) waits where the line's trips start")
        }
        XCTAssertEqual(session.undoCount, 1, "one edit")

        session.undo()
        XCTAssertEqual(session.world, start)
    }

    func testStaffingIsRefusedWholeWhenTheMoneyDoesNotReach() throws {
        let rich = try lineWorld()
        let plan = try XCTUnwrap(rich.lineStaffingPlan(Self.main, headway: 3))
        let start = try lineWorld(balance: plan.cost - Money(1))
        let session = GameSession(world: start)
        session.staffSelectedLine(headway: 3)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, start, "no train bought")
    }

    func testTheLineSendsEveryStaffedTrainOutAHeadwayApart() throws {
        let session = GameSession(world: try lineWorld())
        session.staffSelectedLine(headway: 5)
        var world = session.world
        let ids = world.trains.map(\.id)
        var firstLeft: [TrainID: Int64] = [:]
        for _ in 0..<(12 * 60) where firstLeft.count < ids.count {
            try world.advance(ticks: 1)
            for id in ids where firstLeft[id] == nil && world.train(id: id)?.execution != nil {
                firstLeft[id] = world.clock.now.seconds
            }
        }
        XCTAssertEqual(Set(firstLeft.keys), Set(ids), "every train was sent out")
        let times = firstLeft.values.sorted()
        for (earlier, later) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, 5 * GameTime.secondsPerMinute, "one headway apart")
        }
    }
}
