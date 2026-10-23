import Foundation
@testable import GameCore
import XCTest

/// Decision 366: on a line that runs at a headway, a stopping train stands
/// aside at a station with a passing loop for an express of the line behind
/// it (TestFlight 81.1's report).
///
/// The network, worked by hand: double track 13.4 km long, the north track
/// (nodes 1 to 6, e1 to e5) eastbound and the south track (nodes 7 to 10,
/// e6 to e8) westbound, as trains keep left (decision 202). Beyond West a
/// crossover (e9) takes a train from the south track to the north going
/// east, beyond East another (e10) from the north track to the south going
/// west. West, A, Middle, B and East stand about 3.3 km apart with a
/// platform on each track; Middle also has a loop north of the eastbound
/// track (e11 to e13, nodes 11 and 12), its platform on e12. The loop leaves
/// and joins the straight track along it, so keeping left takes a train
/// into the loop by default (it is within decision 202's 50 m margin).
final class LocalPassTests: XCTestCase {
    static func world(loopBetween: Bool = false) throws -> (world: GameWorld, line: LineID, stations: [StationID]) {
        let loop: Int64 = loopBetween ? 10_240 : 4_096
        var world = try GameWorld(bounds: WorldBounds(width: 870_400, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: ConstructionCosts(track: 0, station: 0, train: 0)), clock: GameClock(speed: .normal))
        for (x, y): (Int64, Int64) in [(1_024, 8_192), (30_720, 8_192), (400_384, 8_192), (440_320, 8_192), (811_008, 8_192), (860_160, 8_192),
                                       (1_024, 12_288), (26_624, 12_288), (806_912, 12_288), (860_160, 12_288),
                                       (408_576, loop), (432_128, loop)] {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        try world.buildTrackEdge(from: .node(1), to: .node(2)) // e1 West, north
        try world.buildTrackEdge(from: .node(2), to: .node(3)) // e2 A, north
        try world.buildTrackEdge(from: .node(3), to: .node(4)) // e3 Middle, north
        try world.buildTrackEdge(from: .node(4), to: .node(5)) // e4 B, north
        try world.buildTrackEdge(from: .node(5), to: .node(6)) // e5 East, north
        try world.buildTrackEdge(from: .node(7), to: .node(8)) // e6 West, south
        try world.buildTrackEdge(from: .node(8), to: .node(9)) // e7 A, Middle and B, south
        try world.buildTrackEdge(from: .node(9), to: .node(10)) // e8 East, south
        try world.buildTrackEdge(from: .node(8), to: .node(2), curve: .cubic(PlanPoint(x: 28_672, y: 12_288), PlanPoint(x: 28_672, y: 8_192))) // e9
        try world.buildTrackEdge(from: .node(5), to: .node(9), curve: .cubic(PlanPoint(x: 808_960, y: 8_192), PlanPoint(x: 808_960, y: 12_288))) // e10
        try world.buildTrackEdge(from: .node(3), to: .node(11), curve: .cubic(PlanPoint(x: 404_480, y: 8_192), PlanPoint(x: 404_480, y: loop))) // e11
        try world.buildTrackEdge(from: .node(11), to: .node(12)) // e12 Middle's loop
        try world.buildTrackEdge(from: .node(12), to: .node(4), curve: .cubic(PlanPoint(x: 436_224, y: loop), PlanPoint(x: 436_224, y: 8_192))) // e13
        var ids: [StationID] = []
        for (name, x) in zip(["West", "A", "Middle", "B", "East"], [10_240, 220_160, 420_352, 620_544, 835_584] as [Int64]) {
            ids.append(try world.buildStation(named: name, at: PlanPoint(x: x, y: 14_336)).id)
        }
        try world.addTrackPlatform(ids[0], on: .edge(1), from: 2_048, to: 14_336)
        try world.addTrackPlatform(ids[0], on: .edge(6), from: 2_048, to: 14_336)
        try world.addTrackPlatform(ids[1], on: .edge(2), from: 183_296, to: 195_584)
        try world.addTrackPlatform(ids[1], on: .edge(7), from: 187_392, to: 199_680)
        try world.addTrackPlatform(ids[2], on: .edge(3), from: 13_824, to: 26_112)
        try world.addTrackPlatform(ids[2], on: .edge(12), from: 5_632, to: 17_920)
        try world.addTrackPlatform(ids[2], on: .edge(7), from: 387_584, to: 399_872)
        try world.addTrackPlatform(ids[3], on: .edge(4), from: 174_080, to: 186_368)
        try world.addTrackPlatform(ids[3], on: .edge(7), from: 587_776, to: 600_064)
        try world.addTrackPlatform(ids[4], on: .edge(5), from: 30_720, to: 43_008)
        try world.addTrackPlatform(ids[4], on: .edge(8), from: 34_816, to: 47_104)
        world.setKeepLeft(true)
        world.setFlexDispatch(true)
        let line = try world.createLine(named: "Main", stops: ids).id
        return (world, line, ids)
    }

    /// The line runs all day: two stopping trains (one sent out from each
    /// end) and an express calling only at West and East, under traffic
    /// control and the simple rules' switches (no block sections). The
    /// express stands at West's westbound platform, so it is sent out 44
    /// seconds after the first stopping train, once its way is clear.
    static func running(loopBetween: Bool = false) throws -> (world: GameWorld, local: TrainID, express: TrainID, stations: [StationID]) {
        var (world, line, ids) = try Self.world(loopBetween: loopBetween)
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
            try world.assignTrain(id, to: line, pattern: i < 2 ? nil : express)
            trains.append(id)
        }
        try world.setTrafficControl(true)
        world.setSpeed(.x1)
        return (world, trains[0], trains[2], ids)
    }

    /// The first stopping train leaves West at 0:42 and calls at A, the
    /// express follows 44 seconds later. Before decision 366 nothing was
    /// planned (decision 59 finds the express overtaking within the call at
    /// A, which has no siding): both took the loop at Middle, kept to it by
    /// keeping left, and the express ran behind the stopping train all the
    /// way, reaching East after it (at 19:58, the stopping train at 14:47).
    /// Now the stopping train waits at Middle on the other track, the
    /// express goes by along the loop, and reaches East first: at 11:41,
    /// the stopping train at 16:15, 88 seconds later than before.
    func testTheStoppingTrainStandsAsideAtMiddleForTheExpress() throws {
        try assertStandsAside(loopBetween: false, on: .edge(3), "aside from the express's way through the loop")
    }

    /// The loop between the two tracks instead (south of the eastbound
    /// one, at y 10240): keeping left takes trains straight through, so the
    /// stopping train turns into the loop and the express runs by on the
    /// straight track, as the report asks.
    func testWithTheLoopBetweenTheTracksTheStoppingTrainTakesIt() throws {
        try assertStandsAside(loopBetween: true, on: .edge(12), "in the loop, the straight track left to the express")
    }

    func assertStandsAside(loopBetween: Bool, on edge: TrackEdgeID, _ message: String, line: UInt = #line) throws {
        var (world, local, express, ids) = try Self.running(loopBetween: loopBetween)
        var arrived: [TrainID: Int] = [:]
        var waits: [ScheduledTrafficWait] = []
        var stoodAt: Set<TrackEdgeID> = []
        for second in 1...1_200 {
            try world.advance(ticks: 10)
            for wait in world.scheduledTrafficWaits() where !waits.contains(wait) { waits.append(wait) }
            for id in [local, express] where arrived[id] == nil && world.isStopped(world.train(id: id)!, at: ids[4]) { arrived[id] = second }
            if world.isStopped(world.train(id: local)!, at: ids[2]), case .onEdge(let standing, _)? = world.train(id: local)!.position { stoodAt.insert(standing.edge) }
        }
        let wait = try XCTUnwrap(waits.first { $0.train == local }, "a wait planned for the stopping train", line: line)
        XCTAssertEqual(wait.station, ids[2], "at Middle", line: line)
        XCTAssertEqual(wait.other, express, line: line)
        XCTAssertEqual(wait.kind, .overtake, line: line)
        XCTAssertEqual(stoodAt, [edge], message, line: line)
        let fast = try XCTUnwrap(arrived[express], line: line), stopping = try XCTUnwrap(arrived[local], line: line)
        XCTAssertLessThan(fast, stopping, "the express reached East first", line: line)
        print("[local-pass] loopBetween \(loopBetween): express \(fast) s, stopping \(stopping) s")
    }

    /// The stopping train never waits on the westbound track, which a
    /// train going the other way runs on: decision 60's siding.
    func testItNeverStandsAsideOnTheTrackTheOtherWay() throws {
        var (world, _, _, _) = try Self.running()
        for _ in 0..<3_600 {
            try world.advance(ticks: 10)
            for wait in world.scheduledTrafficWaits() {
                guard let train = world.train(id: wait.train), world.isStopped(train, at: wait.station),
                      case .onEdge(let standing, _)? = train.position else { continue }
                XCTAssertTrue(standing.direction == .forward && [3, 12].map(TrackEdgeID.edge).contains(standing.edge), "\(wait.train) stands at \(standing)")
            }
        }
        XCTAssertEqual(world.deadlockedTrains(), [])
    }

    /// Advancing half an hour at once ends where advancing it second by
    /// second does.
    func testABatchEndsWhereSecondsDo() throws {
        let start = try Self.running().world
        var single = start
        for _ in 0..<1_800 { try single.advance(ticks: 10) }
        var batched = start
        try batched.advance(ticks: 18_000)
        XCTAssertEqual(batched, single)
    }
}
