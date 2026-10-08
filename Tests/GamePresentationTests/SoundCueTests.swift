import Foundation
import GameCore
import GamePresentation
import XCTest

/// The sounds the session asks the app to play (``SoundCue``): the station
/// chime when a train in service arrives, a rail joint when track is built
/// and a whoosh when the player changes tool or goes into or out of a game.
/// The sounds never change the world.
final class SoundCueTests: XCTestCase {
    // One straight edge east along y = 3072, West's platform near its
    // start and East's near its end; Tram (two cars) stands at West's
    // berth going east, 5120 along it.
    private static let west = StationID(rawValue: 1)
    private static let east = StationID(rawValue: 2)
    private static let tram = TrainID(rawValue: 1)
    private static let edge = TrackEdgeID.edge(1)

    private func makeServiceWorld() throws -> GameWorld {
        var world = try makeWorld(width: 16_384, height: 6_144, balance: 1_000_000, speed: .normal)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 3_072))
        try world.buildTrackEdge(from: a, to: b)
        try world.buildStation(named: "West", at: PlanPoint(x: 2_560, y: 3_584))
        try world.buildStation(named: "East", at: PlanPoint(x: 12_800, y: 3_584))
        try world.addTrackPlatform(Self.west, on: Self.edge, from: 1_024, to: 5_120)
        try world.addTrackPlatform(Self.east, on: Self.edge, from: 9_216, to: 13_312)
        try world.purchaseTrain(named: "Tram")
        try world.setTrainCars(Self.tram, to: 2)
        try world.placeTrain(Self.tram, at: .onEdge(TrackTraversal(edge: Self.edge, direction: .forward), offset: 5_120))
        try world.setTrainContinuation(Self.tram, along: [], stoppingAt: 5_120)
        try world.setTrainMovementRate(Self.tram, to: 1_024)
        try world.setTrainTimetable(Self.tram, to: [
            ScheduledStop(station: Self.west, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 2)),
            ScheduledStop(station: Self.east, arrival: GameTime(minutes: 6), departure: GameTime(minutes: 8)),
        ])
        try world.startTrainService(Self.tram)
        return world
    }

    func testATrainInServiceChimesWhenItArrivesNotWhenItStartsOrLeaves() async throws {
        let world = try makeServiceWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            var heard: [(minute: Int64, cue: SoundCue)] = []
            session.playSound = { heard.append((session.world.clock.now.seconds / 60, $0)) }

            // A tick is a minute at 600×: the train leaves West at 00:02
            // and stops at East at 00:06, its last call.
            for _ in 0..<10 {
                session.advance(realElapsed: GameSession.tickInterval)
            }

            XCTAssertEqual(heard.map(\.cue), [.arrival(watched: false)], "nobody is looking at it")
            XCTAssertEqual(heard.first?.minute, 6)
            XCTAssertEqual(session.world.stationStopText(of: Self.tram, in: .english), "Stopped at East")
        }
    }

    /// A line sends its train out at a whole minute and the train leaves
    /// 42 s later, within the same 600× tick: that is no arrival. Only its
    /// arrivals at East and back at West ring, each while it stands there.
    func testALineTrainChimesOnlyWhenItArrivesNotWhenItIsSentOut() async throws {
        var world = try makeServiceWorld()
        try world.stopTrainService(Self.tram)
        try world.setTrainTimetable(Self.tram, to: [])
        let line = try world.createLine(named: "Shuttle", stops: [Self.west, Self.east]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(Self.tram, to: line)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            var heard: [(cue: SoundCue, stoppedAt: [StationID])] = []
            session.playSound = { heard.append(($0, session.world.stationsStoppedAt(by: Self.tram))) }
            // Counted apart from the sounds: each step that leaves the
            // train standing at a station it was not standing at before.
            var arrivals = 0
            for _ in 0..<40 {
                let before = session.world.stationsStoppedAt(by: Self.tram)
                session.advance(realElapsed: GameSession.tickInterval)
                let after = session.world.stationsStoppedAt(by: Self.tram)
                if !after.isEmpty && after != before { arrivals += 1 }
            }

            XCTAssertGreaterThan(arrivals, 10, "the line ran")
            XCTAssertEqual(heard.count, arrivals, "each arrival at East and at West, and nothing else")
            XCTAssertTrue(heard.allSatisfy { $0.cue == .arrival(watched: false) })
            XCTAssertTrue(heard.allSatisfy { !$0.stoppedAt.isEmpty }, "it rings only standing at a station")
        }
    }

    func testTheTrainThePlayerIsLookingAtChimesAsWatched() async throws {
        let world = try makeServiceWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            XCTAssertEqual(session.watchedTrainIDs, [], "selected, but the train tool is closed")
            session.followTrain(Self.tram)
            XCTAssertEqual(session.watchedTrainIDs, [Self.tram])
            var heard: [SoundCue] = []
            session.playSound = { heard.append($0) }
            for _ in 0..<10 {
                session.advance(realElapsed: GameSession.tickInterval)
            }
            XCTAssertEqual(heard, [.arrival(watched: true)])
        }
    }

    func testTheSoundsChangeNothingInTheWorld() async throws {
        let world = try makeServiceWorld()
        var expected = world
        try expected.advance(ticks: 10)
        await MainActor.run { [expected] in
            let quiet = GameSession(world: world)
            let heard = GameSession(world: world)
            heard.playSound = { _ in }
            for _ in 0..<10 {
                quiet.advance(realElapsed: GameSession.tickInterval)
                heard.advance(realElapsed: GameSession.tickInterval)
            }
            XCTAssertEqual(quiet.world, expected)
            XCTAssertEqual(heard.world, expected)
        }
    }

    func testAnotherToolWhooshesAndTheSameToolIsSilent() async throws {
        let world = try makeWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            var heard: [SoundCue] = []
            session.playSound = { heard.append($0) }

            session.selectTool(.select)
            XCTAssertEqual(heard, [], "already the select tool")
            session.selectTool(.network)
            session.selectTool(.train)
            XCTAssertEqual(heard, [.transition, .transition])
        }
    }

    func testBuildingTrackSoundsARailJointAndARefusalIsSilent() async throws {
        let world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTool(.network)
            var heard: [SoundCue] = []
            session.playSound = { heard.append($0) }

            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.kind, .failure, "no ends picked")
            XCTAssertEqual(heard, [])

            session.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: 512)
            session.tapNetwork(at: PlanPoint(x: 6_144, y: 2_048), reach: 512)
            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.kind, .success)
            XCTAssertEqual(session.world.network.edges.count, 1)
            XCTAssertEqual(heard, [.track])
        }
    }

    func testTheLauncherHandsItsPlayerToEachGameAndWhooshesInAndOut() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SoundCueTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        await MainActor.run {
            let launcher = GameLauncher(library: library, language: .english)
            var heard: [SoundCue] = []
            launcher.playSound = { heard.append($0) }

            launcher.startNewGame()
            XCTAssertEqual(heard, [.transition])
            launcher.session?.selectTool(.network)
            XCTAssertEqual(heard, [.transition, .transition], "the game plays through the launcher's player")
            launcher.returnToStart()
            XCTAssertEqual(heard, [.transition, .transition, .transition])
            launcher.returnToStart()
            XCTAssertEqual(heard.count, 3, "no game to leave")
        }
    }
}
