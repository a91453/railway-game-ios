import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 343: the sound of the followed train running (``RunningSound``),
/// which the session tells the app when it changes. Never part of the world.
final class RunningSoundTests: XCTestCase {
    // One straight edge 6 km east, West's 200 m platform at its start and
    // East's at its end; Tram leaves West at 00:02 and stops at East at
    // 00:06, near 100 km/h on the way.
    private static let west = StationID(rawValue: 1)
    private static let east = StationID(rawValue: 2)
    private static let tram = TrainID(rawValue: 1)
    private static let edge = TrackEdgeID.edge(1)

    private func makeServiceWorld(performance: TrainPerformance = .standard) throws -> GameWorld {
        var world = try makeWorld(width: 393_216, height: 6_144, balance: 100_000_000, speed: .x60)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 385_024, y: 3_072))
        try world.buildTrackEdge(from: a, to: b)
        try world.buildStation(named: "West", at: PlanPoint(x: 7_424, y: 3_584))
        try world.buildStation(named: "East", at: PlanPoint(x: 377_600, y: 3_584))
        try world.addTrackPlatform(Self.west, on: Self.edge, from: 0, to: 12_800)
        try world.addTrackPlatform(Self.east, on: Self.edge, from: 371_200, to: 384_000)
        try world.purchaseTrain(named: "Tram")
        try world.setTrainCars(Self.tram, to: 2)
        try world.setTrainPerformance(Self.tram, to: performance)
        try world.placeTrain(Self.tram, at: .onEdge(TrackTraversal(edge: Self.edge, direction: .forward), offset: 12_800))
        try world.setTrainContinuation(Self.tram, along: [], stoppingAt: 12_800)
        try world.setTrainMovementRate(Self.tram, to: 1_024)
        try world.setTrainTimetable(Self.tram, to: [
            ScheduledStop(station: Self.west, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 2)),
            ScheduledStop(station: Self.east, arrival: GameTime(minutes: 6), departure: GameTime(minutes: 8)),
        ])
        try world.startTrainService(Self.tram)
        return world
    }

    /// The faster, the louder and higher, in steps: 12 dB down just above
    /// 5 km/h, full at the loop's full speed and beyond; nothing below.
    func testTheSoundRisesWithSpeedInSteps() throws {
        XCTAssertNil(RunningSound.of(.electric, atKMH: 0))
        XCTAssertNil(RunningSound.of(.electric, atKMH: 4.9))
        let slow = try XCTUnwrap(RunningSound.of(.electric, atKMH: 5))
        XCTAssertEqual(slow.volume, pow(10, -12.0 / 20), accuracy: 0.03)
        XCTAssertEqual(slow.rate, 0.8, accuracy: 0.021)
        let half = try XCTUnwrap(RunningSound.of(.electric, atKMH: 60))
        XCTAssertEqual(half.volume, pow(10, -6.0 / 20), accuracy: 1e-9)
        XCTAssertEqual(half.rate, 1.0, accuracy: 1e-9)
        for kmh in [120.0, 160] {
            let full = try XCTUnwrap(RunningSound.of(.electric, atKMH: kmh))
            XCTAssertEqual(full.volume, 1)
            XCTAssertEqual(full.rate, 1.2, accuracy: 1e-9)
        }
        // The high-speed loop is full only at 300 km/h.
        XCTAssertEqual(RunningSound.of(.highSpeed, atKMH: 150)?.rate ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(RunningSound.of(.highSpeed, atKMH: 300)?.volume, 1)

        var last = 0.0
        var levels = Set<RunningSound>()
        for kmh in stride(from: 5.0, through: 130, by: 0.5) {
            let sound = try XCTUnwrap(RunningSound.of(.electric, atKMH: kmh))
            XCTAssertGreaterThanOrEqual(sound.volume, last, "\(kmh) km/h")
            last = sound.volume
            levels.insert(sound)
        }
        // So the app is told a few dozen times from a start to full speed.
        XCTAssertLessThanOrEqual(levels.count, 40)
    }

    /// Followed at 60×, the train is silent standing at West, runs with
    /// the electric loop to East and falls silent there; it is told only
    /// when the sound changes.
    func testAFollowedTrainSoundsWhileItRunsAndFallsSilentAtTheStation() async throws {
        let world = try makeServiceWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            var told: [RunningSound?] = []
            session.runningSound = { told.append($0) }
            session.followTrain(Self.tram)
            XCTAssertEqual(told.count, 0, "standing: silent, as it was")
            // A tick is six seconds at 60×: past 00:07, after East.
            for _ in 0..<75 {
                session.advance(realElapsed: GameSession.tickInterval)
            }
            let heard = told.compactMap { $0 }
            XCTAssertFalse(heard.isEmpty, "it ran")
            XCTAssertTrue(heard.allSatisfy { $0.loop == .electric })
            XCTAssertNil(told.last ?? nil, "stopped at East")
            for (earlier, later) in zip(told, told.dropFirst()) {
                XCTAssertNotEqual(earlier, later, "told only on a change")
            }
        }
    }

    /// A high-speed train plays the high-speed loop.
    func testAHighSpeedTrainPlaysTheHighSpeedLoop() async throws {
        let world = try makeServiceWorld(performance: .highSpeed)
        await MainActor.run {
            let session = GameSession(world: world)
            var told: [RunningSound?] = []
            session.runningSound = { told.append($0) }
            session.followTrain(Self.tram)
            for _ in 0..<30 {
                session.advance(realElapsed: GameSession.tickInterval)
            }
            let heard = told.compactMap { $0 }
            XCTAssertFalse(heard.isEmpty)
            XCTAssertTrue(heard.allSatisfy { $0.loop == .highSpeed })
        }
    }

    /// Pausing, going faster than 60× or no longer following silences it
    /// at once, not at the next step; resuming brings it back.
    func testPausingSpeedingUpOrLettingGoSilencesItAtOnce() async throws {
        let world = try makeServiceWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            var told: [RunningSound?] = []
            session.runningSound = { told.append($0) }
            session.followTrain(Self.tram)
            // Running out of West.
            for _ in 0..<25 {
                session.advance(realElapsed: GameSession.tickInterval)
            }
            XCTAssertNotNil(told.last ?? nil)

            session.togglePause()
            XCTAssertNil(told.last ?? nil, "paused")
            session.togglePause()
            XCTAssertNotNil(told.last ?? nil, "running again")

            session.setSpeed(.normal)
            XCTAssertNil(told.last ?? nil, "600×")
            session.setSpeed(.x60)
            XCTAssertNotNil(told.last ?? nil)

            session.stopFollowingTrain()
            XCTAssertNil(told.last ?? nil, "not followed")
        }
    }

    /// Both loops are made by the audio tool, listed in its manifest as
    /// running loops and bundled with the app.
    func testEveryLoopIsABundledFileInTheManifest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("tools/audio/manifest.json"))) as? [String: Any]
        let entries = manifest?["files"] as? [[String: Any]] ?? []
        for loop in RunningSound.Loop.allCases {
            let file = "\(loop.resource.name).\(loop.resource.extension)"
            let entry = try XCTUnwrap(entries.first { $0["file"] as? String == file }, file)
            XCTAssertEqual(entry["kind"] as? String, "running", file)
            XCTAssertNotNil(entry["loopSeam"], file)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RailwayGameApp/Resources/Audio/\(file)").path), "\(file) is bundled")
        }
    }

    func testTheLauncherHandsItsPlayerToEachGameAndSilencesItOnLeaving() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RunningSoundTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        await MainActor.run {
            let launcher = GameLauncher(library: library, language: .english)
            var told: [RunningSound?] = []
            launcher.runningSound = { told.append($0) }
            launcher.startNewGame()
            XCTAssertEqual(told, [nil])
            XCTAssertNotNil(launcher.session?.runningSound)
            launcher.returnToStart()
            XCTAssertEqual(told, [nil, nil])
        }
    }
}
