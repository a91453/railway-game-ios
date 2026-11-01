import Foundation
@testable import GameCore
import XCTest

/// Decision 542: overtakes worked out from where the trains actually are,
/// on lines with runs (decision 133) too, and with a stopping train that has
/// already set off for the station where it is to stand aside (decision
/// 526's gaps). The network is ``LocalPassTests``': double track 13.4 km
/// long, West, A, Middle, B and East about 3.3 km apart, Middle with a loop
/// beside the eastbound track (its platform on e12).
final class LiveOvertakeTests: XCTestCase {
    /// The line at a headway, two stopping trains, and an express train
    /// standing at West, not yet on the line.
    static func lateExpress() throws -> (world: GameWorld, local: TrainID, express: TrainID, stations: [StationID], line: LineID, pattern: Int) {
        var (world, line, ids) = try LocalPassTests.world()
        let express = try world.addLinePattern(line, calling: [0, 4])
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1), pattern: express)
        let berths = [TrainPosition.onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 14_336),
                      .onEdge(TrackTraversal(edge: .edge(8), direction: .backward), offset: 18_432),
                      .onEdge(TrackTraversal(edge: .edge(6), direction: .forward), offset: 14_336)]
        var trains: [TrainID] = []
        for (i, position) in berths.enumerated() {
            let id = try world.purchaseTrain(named: "T\(i + 1)").id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: position)
            if case .onEdge(_, let offset) = position { try world.setTrainContinuation(id, along: [], stoppingAt: offset) }
            try world.setTrainMovementRate(id, to: 1_024)
            if i < 2 { try world.assignTrain(id, to: line) }
            trains.append(id)
        }
        try world.setTrafficControl(true)
        world.setSpeed(.x1)
        return (world, trains[0], trains[2], ids, line, express)
    }

    /// The express is put on the line at 5:00, when the first stopping
    /// train has left A for Middle (at 4:30). On `main` before decision 542
    /// the stopping train could stand aside only beyond Middle, the call it
    /// had set off for: the plan had it wait at B, which has no loop, so it
    /// stood on the straight track there and the express ran behind it all
    /// the way to East (the stopping train arrived at 14:48, the express at
    /// 19:59). Now the stopping train turns into Middle's loop on its way
    /// and the express goes by on the straight track.
    func testAStoppingTrainOnItsWayTurnsIntoTheLoopForAnExpressPutOnBehindIt() throws {
        var (world, local, express, ids, line, pattern) = try Self.lateExpress()
        var arrived: [TrainID: Int] = [:]
        var waits: [ScheduledTrafficWait] = []
        var stoodAt: Set<TrackEdgeID> = []
        for second in 1...1_500 {
            if second == 300 {
                guard case .travellingToStop(2, _)? = world.train(id: local)!.execution else { return XCTFail("on its way to Middle") }
                try world.assignTrain(express, to: line, pattern: pattern)
            }
            try world.advance(ticks: 10)
            for wait in world.scheduledTrafficWaits() where !waits.contains(wait) { waits.append(wait) }
            for id in [local, express] where arrived[id] == nil && world.isStopped(world.train(id: id)!, at: ids[4]) { arrived[id] = second }
            if arrived[local] == nil, world.isStopped(world.train(id: local)!, at: ids[2]), case .onEdge(let standing, _)? = world.train(id: local)!.position { stoodAt.insert(standing.edge) }
        }
        let wait = try XCTUnwrap(waits.first { $0.train == local }, "a wait planned for the stopping train")
        XCTAssertEqual(wait.station, ids[2], "at Middle")
        XCTAssertEqual(wait.other, express)
        XCTAssertEqual(stoodAt, [.edge(12)], "in the loop, the straight track left to the express")
        let fast = try XCTUnwrap(arrived[express]), stopping = try XCTUnwrap(arrived[local])
        XCTAssertLessThan(fast, stopping, "the express reached East first")
        print("[live-overtake] on its way: express \(fast) s, stopping \(stopping) s")
    }

    /// Lines with runs (decision 133): the stopping line all five stations,
    /// leaving West at 10:00 and reaching East at 25:00; an express line
    /// from West at 16:00 to East at 26:00, back from East at 27:00 (it
    /// stands at East's one eastbound platform until then). On time the express never
    /// catches the stopping train. The stopping train stands at West, not
    /// yet on its line.
    static func runs() throws -> (world: GameWorld, local: TrainID, express: TrainID, stations: [StationID], line: LineID) {
        var (world, line, ids) = try LocalPassTests.world()
        func at(_ seconds: Int64, _ dwell: Int64 = 0) -> LineRunTime { LineRunTime(arrival: seconds, departure: seconds + dwell) }
        try world.setLineRuns(line, to: [LineRun(from: 0, to: 4, times: [at(600), at(780, 60), at(1_020, 60), at(1_260, 60), at(1_500)])])
        let fastLine = try world.createLine(named: "Express", stops: [ids[0], ids[4]]).id
        try world.setLineRuns(fastLine, to: [LineRun(from: 0, to: 1, times: [at(960), at(1_560)]), LineRun(from: 1, to: 0, times: [at(1_620), at(2_220)])])
        var trains: [TrainID] = []
        for (i, position) in [TrainPosition.onEdge(TrackTraversal(edge: .edge(1), direction: .forward), offset: 14_336),
                              .onEdge(TrackTraversal(edge: .edge(6), direction: .forward), offset: 14_336)].enumerated() {
            let id = try world.purchaseTrain(named: "T\(i + 1)").id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: position)
            if case .onEdge(_, let offset) = position { try world.setTrainContinuation(id, along: [], stoppingAt: offset) }
            try world.setTrainMovementRate(id, to: 1_024)
            if i == 1 { try world.assignTrain(id, to: fastLine) }
            trains.append(id)
        }
        try world.setTrafficControl(true)
        world.setSpeed(.x1)
        return (world, trains[0], trains[1], ids, line)
    }

    /// The stopping train is put on its line at 15:00 and sets off from
    /// West about five and a half minutes late. Before
    /// decision 542 only the runs' own timetables were planned by (decisions
    /// 59 and 294), which have no overtake, so the express caught it up and
    /// ran behind it to East. Now the plan reads how late it is: it stands
    /// aside in Middle's loop and the express goes by.
    func testALateStoppingTrainOfARunStandsAsideForTheExpress() throws {
        var (world, local, express, ids, line) = try Self.runs()
        var arrived: [TrainID: Int] = [:]
        var waits: [ScheduledTrafficWait] = []
        var stoodAt: Set<TrackEdgeID> = []
        for second in 1...2_400 {
            if second == 900 { try world.assignTrain(local, to: line) }
            try world.advance(ticks: 10)
            for wait in world.scheduledTrafficWaits() where !waits.contains(wait) { waits.append(wait) }
            for id in [local, express] where arrived[id] == nil && world.isStopped(world.train(id: id)!, at: ids[4]) { arrived[id] = second }
            if arrived[local] == nil, world.isStopped(world.train(id: local)!, at: ids[2]), case .onEdge(let standing, _)? = world.train(id: local)!.position { stoodAt.insert(standing.edge) }
        }
        print("[live-overtake] runs: express \(arrived[express] ?? -1) s, stopping \(arrived[local] ?? -1) s, waits \(waits.map { "\($0.train)@\($0.station)" })")
        let wait = try XCTUnwrap(waits.first { $0.train == local }, "a wait planned for the stopping train")
        XCTAssertEqual(wait.station, ids[2], "at Middle")
        XCTAssertEqual(wait.other, express)
        XCTAssertEqual(stoodAt, [.edge(12)], "in the loop, the straight track left to the express")
        let fast = try XCTUnwrap(arrived[express]), stopping = try XCTUnwrap(arrived[local])
        XCTAssertLessThan(fast, stopping, "the express reached East first")
    }

    /// Advancing at once ends where advancing second by second does, with
    /// trains turning aside on their way (the commands given at the same
    /// seconds).
    func testABatchEndsWhereSecondsDo() throws {
        var (headway, _, express, _, line, pattern) = try Self.lateExpress()
        try headway.advance(ticks: 3_000)
        try headway.assignTrain(express, to: line, pattern: pattern)
        var (runs, local, _, _, runLine) = try Self.runs()
        try runs.advance(ticks: 9_000)
        try runs.assignTrain(local, to: runLine)
        for start in [headway, runs] {
            var single = start
            for _ in 0..<1_500 { try single.advance(ticks: 10) }
            var batched = start
            try batched.advance(ticks: 15_000)
            XCTAssertEqual(batched, single)
        }
    }
}
