import Foundation
@testable import GameCore
import XCTest

/// The deadlock search's cost (BH9, docs/research/BUGHUNT_HANG_2026-10-30.md):
/// asking whether each train is a line's spare (``GameWorld/isSpare(_:)``)
/// worked its line's capacity layout and journeys out again for every
/// train, so on a long single track in deadlock the search grew with the
/// trains times the stations' berths and paths: 120 stations and 40 trains
/// took 0.97 s a search and 1.8 s a tick at 6000× (Linux release), and the
/// app runs the search on the main actor after every command. One look at
/// the world now keeps one ``GameWorld/DispatchMemo`` for every train it
/// asks about; the answers are the same.
final class DeadlockSearchCostTests: XCTestCase {
    /// A single track of `count` stations, one platform each and no passing
    /// loop, a line calling at all of them with `trains` trains placed
    /// along it, alternately facing east and west, under traffic control.
    /// `inService` (all of them when `nil`) of them run at a time; the
    /// rest are the line's spares.
    static func singleTrack(stations count: Int, trains: Int, inService: Int? = nil, window: ServiceWindow = .allDay) throws -> GameWorld {
        let span: Int64 = 8_192
        var world = try GameWorld(
            bounds: WorldBounds(width: span * Int64(count + 2), height: 12_288),
            economy: GameEconomy(balance: 1_000_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal)
        )
        for index in 0...count { _ = try world.buildTrackNode(at: WorldCoordinate(x: 1_024 + span * Int64(index), y: 4_096)) }
        for edge in 1...count { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        var stations: [StationID] = []
        for index in 0..<count {
            let station = try world.buildStation(named: "S\(index)", at: PlanPoint(x: 1_024 + span * Int64(index) + 4_096, y: 8_192))
            try world.addTrackPlatform(station.id, on: .edge(index + 1), from: 3_072, to: 5_120)
            stations.append(station.id)
        }
        let line = try world.createLine(named: "L", stops: stations).id
        for index in 0..<trains {
            let edge = 1 + index * count / trains
            let traversal = index % 2 == 0 ? SingleTrackMeet.forward(edge) : SingleTrackMeet.backward(edge)
            let id = try SingleTrackMeet.stand(&world, edge: traversal, offset: index % 2 == 0 ? 5_120 : 3_072)
            try world.assignTrain(id, to: line)
        }
        let running = inService ?? trains
        try world.setLineServiceWindow(line, to: window)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: running, offPeak: running, low: running))
        try world.setTrafficControl(true)
        return world
    }

    /// The single track W–M–E with its passing loop (`SingleTrackMeet`), a
    /// line over all three with `trains` trains, `inService` of them run.
    static func passingLoop(trains: Int, inService: Int) throws -> GameWorld {
        var world = try SingleTrackMeet.world()
        let line = try world.createLine(named: "L", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east]).id
        let places = [(SingleTrackMeet.forward(1), Int64(3_072)), (SingleTrackMeet.backward(3), 3_072), (SingleTrackMeet.forward(5), 5_120)]
        for (traversal, offset) in places.prefix(trains) {
            try world.assignTrain(try SingleTrackMeet.stand(&world, edge: traversal, offset: offset), to: line)
        }
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: inService, offPeak: inService, low: inService))
        try world.setTrafficControl(true)
        return world
    }

    /// Differential: at every minute of generated games, whether each train
    /// is a spare, asked with one memo kept across all the trains in turn
    /// (as the deadlock search and a spare standing aside now ask), is
    /// what asking each with a fresh memo (as they asked before) says. The
    /// deadlock and the spare that stands aside follow from those answers
    /// alone, so they are the same too.
    func testASharedMemoAnswersAsAFreshOneForEveryTrain() throws {
        var spares = 0, deadlocks = 0, asked = 0
        let ran = try runCampaign("deadlock.spare-memo", cases: 6) { testCase in
            var world: GameWorld
            if testCase.index % 3 == 2 {
                let trains = 2 + testCase.random.below(2)
                world = try Self.passingLoop(trains: trains, inService: 1 + testCase.random.below(trains))
                testCase.note("passing loop, \(trains) trains")
            } else {
                let count = 4 + testCase.random.below(10)
                let trains = 2 + testCase.random.below(min(count, 8) - 1)
                let inService = 1 + testCase.random.below(trains)
                let window: ServiceWindow = testCase.random.chance(1, in: 2) ? .allDay : .standard
                world = try Self.singleTrack(stations: count, trains: trains, inService: inService, window: window)
                testCase.note("single track, \(count) stations, \(trains) trains, \(inService) in service, \(window)")
            }
            for _ in 0..<(3 * 60) {
                try world.advance(ticks: 1)
                var memo = GameWorld.DispatchMemo()
                for train in world.trains {
                    let fresh = world.isSpare(train)
                    let shared = world.isSpare(train, memo: &memo)
                    asked += 1
                    if fresh { spares += 1 }
                    guard fresh == shared else {
                        testCase.fail("at \(world.clock.now.seconds) s, train \(train.id): fresh \(fresh), shared \(shared)")
                        return
                    }
                }
                if !world.deadlockedTrains().isEmpty { deadlocks += 1 }
            }
        }
        XCTAssertGreaterThan(ran, 0)
        // Not vacuous: the games had spares and deadlocks to ask about.
        XCTAssertGreaterThan(spares, 0, "asked \(asked)")
        XCTAssertGreaterThan(deadlocks, 0)
    }

    /// The search works each line's capacity layout out once, not once a
    /// spare: on 40 stations with 16 trains in deadlock, most of them the
    /// line's spares, it costs a few layouts (before, one a spare and more:
    /// some 17 times one layout, Linux debug). Timed against one layout on
    /// the same machine, so a slow runner slows both.
    func testTheSearchDoesNotWorkTheLineOutAgainForEverySpare() throws {
        var world = try Self.singleTrack(stations: 40, trains: 16)
        try world.advance(ticks: 30)
        XCTAssertFalse(world.deadlockedTrains().isEmpty, "a deadlock to search")
        let spares = world.trains.filter { world.isSpare($0) }.count
        XCTAssertGreaterThanOrEqual(spares, 8, "spares to ask about")
        let line = try XCTUnwrap(world.lines.first)
        let clock = ContinuousClock()
        func fastest(_ body: () -> Void) -> Double {
            (0..<3).map { _ in
                let spent = clock.measure(body)
                return Double(spent.components.seconds) * 1_000 + Double(spent.components.attoseconds) / 1e15
            }.min() ?? 0
        }
        let layout = fastest { _ = world.capacityLayout(of: line) }
        let search = fastest { _ = world.deadlockedTrains() }
        XCTAssertLessThan(search, layout * 5, String(format: "%d spares: one layout %.1f ms, the search %.1f ms", spares, layout, search))
    }

    /// On request, what the search and a tick at 6000× cost on long single
    /// tracks in deadlock (the numbers in the bug hunt's report):
    ///
    ///     DEADLOCK_COST_REPORT=40x16,120x40 swift test -c release \
    ///       -Xswiftc -enable-testing --filter DeadlockSearchCostTests
    func testWhatTheSearchCostsOnLongSingleTracks() throws {
        guard let value = ProcessInfo.processInfo.environment["DEADLOCK_COST_REPORT"] else {
            throw XCTSkip("set DEADLOCK_COST_REPORT=<stations>x<trains>,… to time the deadlock search")
        }
        func ms(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        }
        let clock = ContinuousClock()
        var rows = ["| Stations | Trains | Mean tick ms | Longest tick ms | Ticks in deadlock | deadlockedTrains() ms |", "| ---: | ---: | ---: | ---: | ---: | ---: |"]
        for pair in value.split(separator: ",").map({ $0.split(separator: "x").compactMap { Int($0) } }) where pair.count == 2 {
            var world = try Self.singleTrack(stations: pair[0], trains: pair[1])
            world.setSpeed(.fast)
            var ticks: [Double] = []
            var inDeadlock = 0
            for _ in 0..<144 {
                ticks.append(ms(try clock.measure { try world.advance(ticks: 1) }))
                if !world.deadlockedTrains().isEmpty { inDeadlock += 1 }
            }
            let search = ms(clock.measure { _ = world.deadlockedTrains() })
            rows.append(String(
                format: "| %d | %d | %.1f | %.1f | %d/144 | %.1f |",
                pair[0], pair[1], ticks.reduce(0, +) / Double(ticks.count), ticks.max() ?? 0, inDeadlock, search
            ))
        }
        print(rows.joined(separator: "\n"))
    }
}
