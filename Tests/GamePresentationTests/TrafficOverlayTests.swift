import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Stage V4e (ARCHITECTURE decision 64): what the map draws of traffic
/// control, read from the world. On the W–M–E single track with a passing
/// loop at M (the same world as TrafficControlSessionTests): edge 1 runs
/// from (1024, 4096) to (9216, 4096), edge 2 on to (25600, 4096), edge 3 on
/// to (33792, 4096), all straight, so a chainage c along edge 1, 2 or 3 is
/// x = 1024 + c, 9216 + c or 25600 + c on y = 4096.
final class TrafficOverlayTests: XCTestCase {
    private let east = TrainID(rawValue: 1), west = TrainID(rawValue: 2)

    private func passingLoopWorld(speed: GameSpeed = .normal) throws -> GameWorld {
        var world = try makeWorld(width: 36_864, height: 12_288, balance: 100_000_000, speed: speed)
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

    /// Decision 210: the reason a wait's tag gives is the case its words
    /// (``GameCore/GameWorld/routeWaitText(of:in:)``) tell.
    private func assertReasonsMatchTheWords(_ overlay: TrafficOverlay, in world: GameWorld, file: StaticString = #filePath, line: UInt = #line) {
        for wait in overlay.waits {
            let text = world.routeWaitText(of: wait.train, in: .english) ?? ""
            let expected: TrafficOverlay.WaitReason? =
                text.hasPrefix("Deadlocked") ? .deadlock
                : text.hasPrefix("Standing aside") ? .standAside
                : text.hasPrefix("Following") ? .following
                : text.hasPrefix("Waiting for") ? .route
                : text.hasPrefix("Waiting at") ? .meet
                : nil
            XCTAssertEqual(wait.reason, expected, "\(wait.train): \(text)", file: file, line: line)
        }
    }

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
    /// Each faces along its 8192-long edge: east forward, west backward.
    func testADeadlockShowsWhereEachTrainWaitsForTheOther() throws {
        var world = try passingLoopWorld()
        try world.setTrafficControl(true)
        try world.advance(ticks: 1)
        let overlay = world.trafficOverlay()
        XCTAssertEqual(overlay.authorities, [])
        XCTAssertEqual(overlay.waits, [
            .init(train: east, holder: west, holderName: "Westbound", reason: .deadlock, isDeadlocked: true,
                  contested: .init(lines: [[point(29_696), point(32_768)]]), from: point(4_096), to: point(29_696), heading: PlanVector(dx: 8_192, dy: 0)),
            .init(train: west, holder: east, holderName: "Eastbound", reason: .deadlock, isDeadlocked: true,
                  contested: .init(lines: [[point(2_048), point(5_120)]]), from: point(30_720), to: point(5_120), heading: PlanVector(dx: -8_192, dy: 0)),
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
        // Decision 210: why, for its tag.
        XCTAssertEqual(wait.reason, .standAside)
        XCTAssertEqual(wait.reason.tag(holder: wait.holderName, in: .traditionalChinese), "待避 · Westbound")
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
        // Decision 210: a meet by plan, as the plan has it.
        XCTAssertEqual(world.scheduledTrafficWait(of: TrainID(rawValue: 1))?.kind, .meet)
        XCTAssertEqual(wait.reason, .meet)
    }

    // MARK: - Read once a tick (decision 64, later fix)

    /// The reading the game loop takes with each tick is what asking the
    /// world gives, at every tick from the deadlock to both trains on
    /// their way, with traffic control on and off, for every train
    /// (including one bought and not placed) in both languages.
    func testTheReadingIsWhatTheWorldSaysAtEveryTick() throws {
        var world = try passingLoopWorld(speed: .x10)
        let unplaced = try world.purchaseTrain(named: "Spare").id
        try world.setTrafficControl(true)
        var waited: Set<String> = []
        var reasons: Set<TrafficOverlay.WaitReason> = []
        var previous: TrafficReading?
        for tick in 0..<240 {
            if tick == 200 { try world.setTrafficControl(false) }
            try world.advance(ticks: 1)
            for language in [DisplayLanguage.english, .traditionalChinese] {
                var reading = TrafficReading(world: world, train: east, in: language, previous: language == .english ? previous : nil)
                if language == .english { previous = reading }
                XCTAssertEqual(reading.overlay, world.trafficOverlay(), "tick \(tick)")
                reasons.formUnion(reading.overlay.waits.map(\.reason))
                assertReasonsMatchTheWords(reading.overlay, in: world)
                for id in [east, west, unplaced, TrainID(rawValue: 99)] {
                    let text = world.routeWaitText(of: id, in: language)
                    XCTAssertEqual(reading.waitText(of: id, in: world, language: language), text, "tick \(tick), train \(id)")
                    if let text, language == .english { waited.insert(String(text.prefix(12))) }
                }
            }
        }
        // The deadlock, the dispatcher's standing aside and the following.
        XCTAssertTrue(waited.contains("Deadlocked w"), "\(waited)")
        XCTAssertTrue(waited.contains("Standing asi"), "\(waited)")
        XCTAssertTrue(reasons.isSuperset(of: [.deadlock, .standAside]), "\(reasons)")
    }

    /// The same for a scheduled meet (decision 59), over its next minutes.
    func testTheReadingOfAScheduledMeetIsWhatTheWorldSays() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: root.appendingPathComponent("SaveFixtures/v9-scheduled-meet.json"))).world
        var scheduled = 0
        var previous: TrafficReading?
        for _ in 0..<30 {
            // Decision 210: with the kinds the last reading kept, the same.
            var reading = TrafficReading(world: world, in: .english, previous: previous)
            previous = reading
            XCTAssertEqual(reading.overlay, world.trafficOverlay())
            assertReasonsMatchTheWords(reading.overlay, in: world)
            for train in world.trains {
                XCTAssertEqual(reading.waitText(of: train.id, in: world, language: .english), world.routeWaitText(of: train.id, in: .english))
                if world.scheduledTrafficWait(of: train.id) != nil { scheduled += 1 }
            }
            try world.advance(ticks: 1)
        }
        XCTAssertGreaterThan(scheduled, 0)
    }

    /// The game loop reads traffic control with its tick, off the main
    /// actor: the session shows that reading for the world the tick made,
    /// with the selected train's wait in words, and reads again, once,
    /// after a command.
    @MainActor
    func testTheGameLoopReadsTrafficControlWithItsTick() async throws {
        var world = try passingLoopWorld()
        try world.setTrafficControl(true)
        let session = GameSession(world: world)
        session.selectTrain(east)
        let tick = try XCTUnwrap(session.beginLoopTick())
        let outcome = await tick.work()
        XCTAssertTrue(session.finish(tick, with: outcome))
        let memo = try XCTUnwrap(session.trafficMemo)
        XCTAssertEqual(memo.revision, session.worldRevision, "the tick's reading is of the world it made")
        XCTAssertEqual(memo.reading.texts[east], .some("Deadlocked with Westbound"), "read with the tick")
        XCTAssertEqual(session.trafficOverlay, session.world.trafficOverlay())
        XCTAssertEqual(session.trafficOverlay.waits.filter(\.isDeadlocked).count, 2)
        XCTAssertEqual(session.routeWaitText(of: east), session.world.routeWaitText(of: east, in: session.language))
        XCTAssertEqual(session.routeWaitText(of: west), session.world.routeWaitText(of: west, in: session.language))
        XCTAssertEqual(session.trafficMemo?.revision, session.worldRevision)

        session.setTrafficControl(false)
        XCTAssertNotEqual(session.trafficMemo?.revision, session.worldRevision)
        XCTAssertEqual(session.trafficOverlay, TrafficOverlay())
        XCTAssertNil(session.routeWaitText(of: east))
    }

    // MARK: - Marks side by side (the site's blockSideShift)

    private func mark(_ train: Int, _ x: Double, _ y: Double, along: (Double, Double) = (1, 0)) -> WaitMarkSides.Mark {
        WaitMarkSides.Mark(train: TrainID(rawValue: train), center: ScreenPoint(x: x, y: y), along: ScreenPoint(x: along.0, y: along.1))
    }

    /// Two 20-point marks on one spot of an east–west track move apart
    /// across it, the first (in train order) to its left (the screen's
    /// y grows down, so the normal of (1, 0) is (0, 1)), by 20/2 + 2/2 =
    /// 11 points each: 22 points apart, 2 more than their size.
    func testTwoMarksOnOneSpotMoveApartAcrossTheirTrack() {
        let offsets = WaitMarkSides.offsets([mark(2, 100, 50), mark(1, 100, 50)], size: 20)
        XCTAssertEqual(offsets, [
            TrainID(rawValue: 1): ScreenPoint(x: 0, y: 11),
            TrainID(rawValue: 2): ScreenPoint(x: 0, y: -11),
        ])
    }

    /// On a diagonal track the normal is (−√½, √½): the move is
    /// (√½·20 + √½·20) / 2 + 1 = 10√2 + 1 along it.
    func testMarksOnADiagonalTrackMoveAlongItsNormal() throws {
        let offsets = WaitMarkSides.offsets([mark(1, 0, 0, along: (3, 3)), mark(2, 5, 5, along: (3, 3))], size: 20)
        let amount = 10 * 2.0.squareRoot() + 1
        let first = try XCTUnwrap(offsets[TrainID(rawValue: 1)])
        XCTAssertEqual(first.x, -amount * 0.5.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(first.y, amount * 0.5.squareRoot(), accuracy: 1e-9)
        let second = try XCTUnwrap(offsets[TrainID(rawValue: 2)])
        XCTAssertEqual(second.x, -first.x, accuracy: 1e-9)
        XCTAssertEqual(second.y, -first.y, accuracy: 1e-9)
    }

    /// Marks a size or more apart, a lone mark, and a mark with no way
    /// along its track stay where they are; a third mark joined to a
    /// group by its neighbour takes the next side in turn.
    func testMarksApartStayAndAGroupAlternates() {
        XCTAssertEqual(WaitMarkSides.offsets([mark(1, 0, 0), mark(2, 20, 0)], size: 20), [:])
        XCTAssertEqual(WaitMarkSides.offsets([mark(1, 0, 0)], size: 20), [:])
        XCTAssertEqual(WaitMarkSides.offsets([mark(1, 0, 0, along: (0, 0)), mark(2, 0, 0)], size: 20), [TrainID(rawValue: 2): ScreenPoint(x: 0, y: -11)])
        let chain = WaitMarkSides.offsets([mark(1, 0, 0), mark(2, 15, 0), mark(3, 30, 0)], size: 20)
        XCTAssertEqual(chain.mapValues(\.y), [TrainID(rawValue: 1): 11, TrainID(rawValue: 2): -11, TrainID(rawValue: 3): 11])
    }

    /// A deadlocked train's mark beats between full and 0.35 every 1.2 s,
    /// and stays at full when the player reduces motion.
    func testADeadlockBeatsUnlessMotionIsReduced() {
        XCTAssertEqual(TrafficOverlay.deadlockStrength(at: 0, reduceMotion: false), 1, accuracy: 1e-12)
        XCTAssertEqual(TrafficOverlay.deadlockStrength(at: 0.6, reduceMotion: false), 0.35, accuracy: 1e-12)
        XCTAssertEqual(TrafficOverlay.deadlockStrength(at: 1.2, reduceMotion: false), 1, accuracy: 1e-12)
        XCTAssertEqual(TrafficOverlay.deadlockStrength(at: 0.3, reduceMotion: false), 0.675, accuracy: 1e-12)
        for time in stride(from: 0.0, to: 3, by: 0.1) {
            XCTAssertEqual(TrafficOverlay.deadlockStrength(at: time, reduceMotion: true), 1)
        }
    }
}
