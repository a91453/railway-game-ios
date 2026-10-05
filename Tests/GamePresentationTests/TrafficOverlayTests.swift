import Foundation
import GameCore
import GamePresentation
import XCTest

/// Stage V4e (ARCHITECTURE decision 64): what the map draws of traffic
/// control, read from the world. On the W–M–E single track with a passing
/// loop at M (the same world as TrafficControlSessionTests): edge 1 runs
/// from (1024, 4096) to (9216, 4096), edge 2 on to (25600, 4096), edge 3 on
/// to (33792, 4096), all straight, so a chainage c along edge 1, 2 or 3 is
/// x = 1024 + c, 9216 + c or 25600 + c on y = 4096.
final class TrafficOverlayTests: XCTestCase {
    private let east = TrainID(rawValue: 1), west = TrainID(rawValue: 2)

    private func passingLoopWorld() throws -> GameWorld {
        var world = try makeWorld(width: 36_864, height: 12_288, balance: 100_000_000, speed: .normal)
        for (x, y) in [(1_024, 4_096), (9_216, 4_096), (25_600, 4_096), (33_792, 4_096), (13_312, 6_144), (21_504, 6_144)] as [(Int64, Int64)] {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        for edge in 1...3 { try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        try world.buildTrackEdge(from: .node(2), to: .node(5), curve: .cubic(PlanPoint(x: 11_264, y: 4_096), PlanPoint(x: 11_264, y: 6_144)))
        try world.buildTrackEdge(from: .node(5), to: .node(6))
        try world.buildTrackEdge(from: .node(6), to: .node(3), curve: .cubic(PlanPoint(x: 23_552, y: 6_144), PlanPoint(x: 23_552, y: 4_096)))
        var stations: [StationID] = []
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
            stations.append(try world.buildStation(named: name, at: PlanPoint(x: x, y: 8_192)).id)
        }
        for (station, edge, start) in [(0, 1, Int64(1_024)), (1, 2, 7_168), (1, 5, 3_072), (2, 3, 5_120)] {
            try world.addTrackPlatform(stations[station], on: .edge(edge), from: start, to: start + 2_048)
        }
        for (name, traversal, stops) in [
            ("Eastbound", TrackTraversal(edge: .edge(1), direction: .forward), [stations[0], stations[2]]),
            ("Westbound", TrackTraversal(edge: .edge(3), direction: .backward), [stations[2], stations[0]]),
        ] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(traversal, offset: 3_072))
            try world.setTrainContinuation(id, along: [], stoppingAt: 3_072)
            try world.setTrainMovementRate(id, to: 1_024)
            try world.setTrainTimetable(id, to: stops.enumerated().map {
                ScheduledStop(station: $0.element, arrival: GameTime(minutes: Int64($0.offset) * 4), departure: GameTime(minutes: Int64($0.offset) * 4))
            })
            try world.startTrainService(id)
        }
        return world
    }

    private func point(_ x: Int64) -> WorldCoordinate { WorldCoordinate(x: x, y: 4_096) }

    func testWithoutTrafficControlNothingIsDrawn() throws {
        var world = try passingLoopWorld()
        try world.advance(ticks: 1)
        let overlay = world.trafficOverlay()
        XCTAssertTrue(overlay.isEmpty)
        XCTAssertNil(overlay.summary(in: .english))
        XCTAssertNil(overlay.summary(in: .traditionalChinese))
    }

    /// 0:42: each due train waits for the other, which stands on the track
    /// it needs: Eastbound (head at chainage 3072 of edge 1) on Westbound's
    /// 4096–7168 of edge 3, Westbound (head at 8192 − 3072 = 5120 of edge 3)
    /// on Eastbound's 1024–4096 of edge 1, each drawn to the end nearest it.
    func testADeadlockShowsWhereEachTrainWaitsForTheOther() throws {
        var world = try passingLoopWorld()
        try world.setTrafficControl(true)
        try world.advance(ticks: 1)
        let overlay = world.trafficOverlay()
        XCTAssertEqual(overlay.authorities, [])
        XCTAssertEqual(overlay.waits, [
            .init(train: east, holder: west, isDeadlocked: true,
                  contested: .init(lines: [[point(29_696), point(32_768)]]), from: point(4_096), to: point(29_696)),
            .init(train: west, holder: east, isDeadlocked: true,
                  contested: .init(lines: [[point(2_048), point(5_120)]]), from: point(30_720), to: point(5_120)),
        ])
        // The other train holds exactly what each waits for.
        XCTAssertEqual(world.contestedResources(of: east), world.heldResources(of: west))
        XCTAssertEqual(world.contestedResources(of: west), world.heldResources(of: east))
        XCTAssertEqual(overlay.summary(in: .english), "2 deadlocked")
        XCTAssertEqual(overlay.summary(in: .traditionalChinese), "2 列死結")
        // The words stay.
        XCTAssertEqual(world.routeWaitText(of: east, in: .english), "Deadlocked with Westbound")
    }

    /// 1:00: the dispatcher has sent Eastbound to stand aside at M's main
    /// platform (head at chainage 9216 of edge 2), and Westbound has taken
    /// its route round the loop to W: its authority ends with the whole of
    /// edge 1. Eastbound waits for the track by the junction at E's end of
    /// M (from 14336 of edge 2), the nearest of which is x = 23552.
    func testAStandingAsideTrainWaitsWhileTheOtherHoldsItsAuthority() throws {
        var world = try passingLoopWorld()
        try world.setTrafficControl(true)
        try world.advance(ticks: 2)
        let overlay = world.trafficOverlay()
        XCTAssertEqual(overlay.authorities.map(\.train), [west])
        XCTAssertEqual(overlay.authorities.first?.track.lines.first, [point(1_024), point(9_216)])
        XCTAssertEqual(overlay.waits.count, 1)
        let wait = try XCTUnwrap(overlay.waits.first)
        XCTAssertEqual(wait.train, east)
        XCTAssertEqual(wait.holder, west)
        XCTAssertFalse(wait.isDeadlocked)
        XCTAssertEqual(wait.from, point(18_432))
        XCTAssertEqual(wait.to, point(23_552))
        XCTAssertEqual(wait.contested.nodes, [point(25_600)])
        XCTAssertTrue(wait.contested.lines.contains([point(23_552), point(25_600)]))
        XCTAssertEqual(overlay.summary(in: .english), "Movement authority for 1 train · 1 waiting")
        XCTAssertEqual(overlay.summary(in: .traditionalChinese), "1 列車有行車授權 · 1 列等候")
        XCTAssertEqual(world.routeWaitText(of: east, in: .english), "Standing aside at M until Westbound clears the route")
        // Both on their way: two authorities, no waits.
        try world.advance(ticks: 1)
        XCTAssertEqual(world.trafficOverlay().authorities.map(\.train), [east, west])
        XCTAssertEqual(world.trafficOverlay().waits, [])
        XCTAssertEqual(world.trafficOverlay().summary(in: .english), "Movement authority for 2 trains")
    }

    /// A scheduled meet (decision 59) keeps the train for the other by plan,
    /// not for its track: nothing contested, drawn to the other's head.
    func testAScheduledWaitIsDrawnToTheOtherTrain() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: root.appendingPathComponent("SaveFixtures/v9-scheduled-meet.json"))).world
        let wait = try XCTUnwrap(world.trafficOverlay().waits.first { $0.train == TrainID(rawValue: 1) })
        let other = try XCTUnwrap(world.train(id: wait.holder)?.position.flatMap { world.location(of: $0) })
        XCTAssertEqual(wait.holder, world.scheduledTrafficWait(of: TrainID(rawValue: 1))?.other)
        XCTAssertTrue(wait.contested.isEmpty)
        XCTAssertFalse(wait.isDeadlocked)
        XCTAssertEqual(wait.to, other.position)
    }
}
