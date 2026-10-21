import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The sounds the session asks the app to play (``SoundCue``): the station
/// chime when a train in service arrives (decision 219: the station's own,
/// or its motif at high speed), a rail joint when track is built
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

    /// A loop step can advance up to five ticks (``GameSession/maximumStepDuration``).
    /// A step in which the train arrives at its last call and leaves it,
    /// completing its service (GameCore then clears its service times),
    /// still rings, as it does a tick at a time.
    func testAnArrivalAtTheLastCallRingsWhenTheServiceEndsInTheSameStep() async throws {
        let world = try makeServiceWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            var heard: [SoundCue] = []
            session.playSound = { heard.append($0) }

            // Five ticks a step: minutes 0–5, then 5–10, in which the train
            // arrives at East at 00:06 and leaves it at 00:08, its last call.
            session.advance(realElapsed: GameSession.maximumStepDuration)
            session.advance(realElapsed: GameSession.maximumStepDuration)

            XCTAssertEqual(session.world.clock.now, GameTime(minutes: 10))
            XCTAssertNil(session.world.trains.first?.times, "the service is complete")
            XCTAssertEqual(heard, [.arrival(watched: false)])
        }
    }

    /// A train that arrives at its last call early in a minute leaves it
    /// (the terminal's 42 s) within the same 600× tick, completing its
    /// service: that arrival still rings, a tick at a time.
    func testAnArrivalAtTheLastCallRingsWhenTheServiceEndsInTheSameTick() async throws {
        var world = try makeServiceWorld()
        try world.stopTrainService(Self.tram)
        try world.setTrainTimetable(Self.tram, to: [
            ScheduledStop(station: Self.west, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 2)),
            ScheduledStop(station: Self.east, arrival: GameTime(seconds: 365), departure: GameTime(seconds: 365)),
        ])
        try world.startTrainService(Self.tram)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            var heard: [(minute: Int64, cue: SoundCue)] = []
            session.playSound = { heard.append((session.world.clock.now.seconds / 60, $0)) }
            for _ in 0..<6 {
                session.advance(realElapsed: GameSession.tickInterval)
            }
            XCTAssertEqual(session.world.trains.first?.times?.departure, GameTime(minutes: 2), "on its way to East")
            // It arrives at 00:06:05 and its service is complete before
            // 00:07, so its times are gone when that tick ends.
            for _ in 0..<4 {
                session.advance(realElapsed: GameSession.tickInterval)
            }
            XCTAssertNil(session.world.trains.first?.times)
            XCTAssertEqual(heard.map(\.cue), [.arrival(watched: false)])
            XCTAssertEqual(heard.first?.minute, 7)
        }
    }

    /// A line's train that arrives back at its last call, completes and is
    /// sent out again within one step rings for that arrival.
    func testALineTrainThatArrivesCompletesAndIsSentOutInOneStepRings() async throws {
        var world = try makeServiceWorld()
        try world.stopTrainService(Self.tram)
        try world.setTrainTimetable(Self.tram, to: [])
        let line = try world.createLine(named: "Shuttle", stops: [Self.west, Self.east]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(Self.tram, to: line)
        // A tick at a time, counted apart from the sounds as the test
        // above does: which five-tick steps leave the train standing at a
        // station it was not standing at the tick before.
        var single = world
        var stepsWithArrivals = 0
        for _ in 0..<8 {
            var arrived = false
            for _ in 0..<5 {
                let before = single.stationsStoppedAt(by: Self.tram)
                try single.advance(ticks: 1)
                let after = single.stationsStoppedAt(by: Self.tram)
                if !after.isEmpty && after != before { arrived = true }
            }
            if arrived { stepsWithArrivals += 1 }
        }
        await MainActor.run { [world, stepsWithArrivals] in
            let session = GameSession(world: world)
            var heard = 0
            session.playSound = { _ in heard += 1 }
            for _ in 0..<8 {
                session.advance(realElapsed: GameSession.maximumStepDuration)
            }
            XCTAssertEqual(session.world.clock.now, GameTime(minutes: 40))
            XCTAssertGreaterThan(stepsWithArrivals, 5, "the line ran")
            // One sound a step, however many arrivals it holds.
            XCTAssertEqual(heard, stepsWithArrivals)
        }
    }

    /// Decision 143: the game loop's ticks, worked out off the main actor,
    /// ring as ticks on the main actor do.
    @MainActor
    func testTheLoopsTicksRingAsTicksOnTheMainActorDo() async throws {
        let world = try makeServiceWorld()
        let stepped = GameSession(world: world)
        var heardStepped: [SoundCue] = []
        stepped.playSound = { heardStepped.append($0) }
        let looped = GameSession(world: world)
        var heardLooped: [SoundCue] = []
        looped.playSound = { heardLooped.append($0) }

        for _ in 0..<10 {
            stepped.advance(realElapsed: GameSession.tickInterval)
            let tick = try XCTUnwrap(looped.beginLoopTick())
            looped.finish(tick, with: await tick.work())
        }

        XCTAssertEqual(looped.world, stepped.world)
        XCTAssertEqual(heardStepped, [.arrival(watched: false)])
        XCTAssertEqual(heardLooped, heardStepped)
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
            // Decision 219: at 600× a watched train plays the motif.
            XCTAssertEqual(heard, [.arrival(watched: true, chime: .local, motif: true)])
        }
    }

    // MARK: - Decision 219: each station's chime

    /// An attraction 703 m east of East, inside its 800 m catchment
    /// (51,200 units) and 863 m from West, outside West's. The service
    /// world is only 256 m wide, so it lies past the map's east edge,
    /// which the chime's distance does not mind.
    private static let sight = Attraction(id: AttractionID(rawValue: 1), name: "海岸", englishName: "Shore",
                                          point: PlanPoint(x: 12_800 + 45_000, y: 3_584), kind: .coast, baseStars: 300)

    /// Tourist before metro before local: an attraction in the catchment
    /// makes a tourist station, two passenger lines or a high speed line
    /// a metro one, anything else a local one.
    func testAStationsChimeIsTouristBeforeMetroBeforeLocal() throws {
        var world = try makeServiceWorld()
        XCTAssertEqual(StationChime.of(Self.west, in: world), .local, "no line calls")
        let first = try world.createLine(named: "One", stops: [Self.west, Self.east]).id
        XCTAssertEqual(StationChime.of(Self.west, in: world), .local, "one line")
        try world.createLine(named: "Two", stops: [Self.west, Self.east])
        XCTAssertEqual(StationChime.of(Self.west, in: world), .metro, "two lines")
        XCTAssertEqual(StationChime.of(StationID(rawValue: 99), in: world), .local, "no such station")

        var fast = try makeServiceWorld()
        let line = try fast.createLine(named: "HSR", stops: [Self.west, Self.east]).id
        XCTAssertEqual(StationChime.of(Self.west, in: fast), .local)
        try fast.setLinePerformance(line, to: .highSpeed)
        XCTAssertEqual(StationChime.of(Self.west, in: fast), .metro, "a high speed line calls")

        world.setTourism([Self.sight])
        XCTAssertEqual(StationChime.of(Self.east, in: world), .tourist, "the attraction beats the two lines")
        XCTAssertEqual(StationChime.of(Self.west, in: world), .metro, "the attraction is out of West's catchment")
        try world.removeLine(first)
        XCTAssertEqual(StationChime.of(Self.west, in: world), .local)
    }

    /// The chime is the station's the watched train arrived at: a line's
    /// train rings East's tourist motif there and West's local one back
    /// there (600×), also in steps of several ticks, where it arrives and
    /// leaves within one step, or completes its trip at West (one sound a
    /// step: the step's first arrival). Not watched, it rings the local
    /// chime everywhere.
    func testAWatchedTrainRingsTheChimeOfTheStationItArrivedAt() async throws {
        var world = try makeServiceWorld()
        try world.stopTrainService(Self.tram)
        try world.setTrainTimetable(Self.tram, to: [])
        world.setTourism([Self.sight])
        let line = try world.createLine(named: "Shuttle", stops: [Self.west, Self.east]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        try world.assignTrain(Self.tram, to: line)
        await MainActor.run { [world] in
            for step in [GameSession.tickInterval, GameSession.maximumStepDuration] {
                let session = GameSession(world: world)
                session.followTrain(Self.tram)
                var heard: [(cue: SoundCue, at: [StationID])] = []
                session.playSound = { heard.append(($0, session.world.stationsStoppedAt(by: Self.tram))) }
                for _ in 0..<(step == GameSession.tickInterval ? 40 : 8) {
                    session.advance(realElapsed: step)
                }
                let chimes = heard.map(\.cue)
                XCTAssertTrue(chimes.contains(.arrival(watched: true, chime: .tourist, motif: true)), "\(step): East")
                XCTAssertTrue(chimes.contains(.arrival(watched: true, chime: .local, motif: true)), "\(step): West")
                // A tick at a time the train still stands where it rang;
                // a longer step may take it on to the next station.
                for (cue, at) in heard where step == GameSession.tickInterval && !at.isEmpty {
                    let expected: StationChime = at == [Self.east] ? .tourist : .local
                    XCTAssertEqual(cue, .arrival(watched: true, chime: expected, motif: true), "\(step): standing at \(at)")
                }

                let unwatched = GameSession(world: world)
                var others: [SoundCue] = []
                unwatched.playSound = { others.append($0) }
                for _ in 0..<(step == GameSession.tickInterval ? 40 : 8) {
                    unwatched.advance(realElapsed: step)
                }
                XCTAssertFalse(others.isEmpty)
                XCTAssertTrue(others.allSatisfy { $0 == .arrival(watched: false) }, "\(step): the local chime, quieter")
            }
        }
    }

    /// The research note's §6: a watched train rings its station's whole
    /// chime at 60× and slower and its motif at 600× and faster; the
    /// others ring the local chime at every speed.
    func testTheSpeedDecidesBetweenTheChimeAndItsMotif() throws {
        var world = try makeServiceWorld()
        world.setTourism([Self.sight])
        let east = SoundCue.ArrivedTrain(train: Self.tram, station: Self.east)
        let other = SoundCue.ArrivedTrain(train: TrainID(rawValue: 7), station: Self.west)
        func cue(_ arrived: [SoundCue.ArrivedTrain], watched: Set<TrainID>, _ speed: GameSpeed) -> SoundCue? {
            SoundCue.arrivalCue(for: arrived, watched: watched, speed: speed, in: world)
        }
        for speed in [GameSpeed.x1, .x10, .x60, .normal, .double, .fast] {
            let motif = speed.tenthsPerTick >= GameSpeed.normal.tenthsPerTick
            XCTAssertEqual(cue([other, east], watched: [Self.tram], speed), .arrival(watched: true, chime: .tourist, motif: motif), "\(speed)")
            XCTAssertEqual(cue([east, other], watched: [], speed), .arrival(watched: false), "\(speed): the others ring the local chime")
        }
        XCTAssertNil(cue([], watched: [Self.tram], .x1))
        XCTAssertEqual(cue([SoundCue.ArrivedTrain(train: Self.tram, station: nil)], watched: [Self.tram], .x1),
                       .arrival(watched: true), "a station not known rings the local chime")
    }

    /// Every chime and motif the cues name is a file the app bundles and
    /// the audio manifest lists (`tools/audio/manifest.json`).
    func testEveryChimeIsABundledFileInTheManifest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("tools/audio/manifest.json"))) as? [String: Any]
        let listed = Set((manifest?["files"] as? [[String: Any]] ?? []).compactMap { $0["file"] as? String })
        var cues: [SoundCue] = [.track, .transition, .built, .income, .refused, .warning, .goalMet, .lineAcquired]
        for chime in StationChime.allCases {
            for watched in [false, true] {
                cues.append(.arrival(watched: watched, chime: chime, motif: false))
                cues.append(.arrival(watched: watched, chime: chime, motif: true))
            }
        }
        var files: Set<String> = []
        for cue in cues {
            let file = "\(cue.resource.name).\(cue.resource.extension)"
            files.insert(file)
            XCTAssertTrue(listed.contains(file), "\(file) is in the manifest")
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RailwayGameApp/Resources/Audio/\(file)").path), "\(file) is bundled")
        }
        XCTAssertEqual(SoundCue.arrival(watched: false, chime: .local).resource.name, "station-chime", "the local chime is decision 79's")
        XCTAssertEqual(files.count, 14, "three chimes, three motifs, eight sounds")
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

    /// Since decision 184 a refusal has a sound of its own, not the rail
    /// joint's.
    func testBuildingTrackSoundsARailJointAndARefusalSoundsRefused() async throws {
        let world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000)
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTool(.network)
            var heard: [SoundCue] = []
            session.playSound = { heard.append($0) }

            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.kind, .failure, "no ends picked")
            XCTAssertEqual(heard, [.refused])
            heard.removeAll()

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
    // MARK: - Decision 219, stage 2: the music steps aside at an interchange

    /// From 800 m out the music goes down evenly in decibels, in half
    /// decibel steps, to 6 dB down at 300 m and nearer.
    func testTheMusicGoesDownSixDecibelsFrom800To300Metres() {
        XCTAssertEqual(MusicDuck.gain(metresToStation: 1_500), 1)
        XCTAssertEqual(MusicDuck.gain(metresToStation: 800), 1)
        XCTAssertEqual(MusicDuck.gain(metresToStation: 550), pow(10, -3.0 / 20), accuracy: 1e-9)
        XCTAssertEqual(MusicDuck.gain(metresToStation: 300), pow(10, -6.0 / 20), accuracy: 1e-9)
        XCTAssertEqual(MusicDuck.gain(metresToStation: 0), pow(10, -6.0 / 20), accuracy: 1e-9)
        var last = 1.0
        for metres in stride(from: 900.0, through: 0, by: -10) {
            let gain = MusicDuck.gain(metresToStation: metres)
            XCTAssertLessThanOrEqual(gain, last, "\(metres) m")
            last = gain
        }
        // In steps: about a dozen levels on the way in.
        let levels = Set(stride(from: 900.0, through: 0, by: -1).map { MusicDuck.gain(metresToStation: $0) })
        XCTAssertEqual(levels.count, 13)
    }

    /// Two lines call at West and East, so both ring the interchange
    /// chime. Followed at 60×, the tram (already within 300 m of East)
    /// takes the music down while it runs there and stands there, and it
    /// comes back when following stops; at 600× it never goes down.
    func testFollowingATrainIntoAnInterchangeAtSixtyTimesTakesTheMusicDown() async throws {
        var world = try makeServiceWorld()
        try world.createLine(named: "One", stops: [Self.west, Self.east])
        try world.createLine(named: "Two", stops: [Self.west, Self.east])
        world.setSpeed(.x60)
        let interchange = world
        await MainActor.run {
            let session = GameSession(world: interchange)
            var told: [Double] = []
            session.duckMusic = { told.append($0) }
            session.followTrain(Self.tram)
            XCTAssertEqual(told.count, 1, "standing at West, an interchange")
            XCTAssertEqual(told.last ?? 1, pow(10, -6.0 / 20), accuracy: 1e-9)
            for _ in 0..<80 {
                session.advance(realElapsed: GameSession.tickInterval)
            }
            XCTAssertEqual(told.count, 1, "the level is told only when it changes")
            session.stopFollowingTrain()
            XCTAssertEqual(told.last, 1)

            session.setSpeed(.normal)
            session.followTrain(Self.tram)
            session.advance(realElapsed: GameSession.tickInterval)
            XCTAssertEqual(told.last, 1, "not at 600×")
            XCTAssertEqual(told.count, 2)
        }
    }

    /// An edit between steps (paused, or before the next tick) that takes
    /// the followed train out of service brings the music back at once,
    /// not at the next step.
    func testStoppingTheFollowedTrainBringsTheMusicBackAtOnce() async throws {
        var world = try makeServiceWorld()
        try world.createLine(named: "One", stops: [Self.west, Self.east])
        try world.createLine(named: "Two", stops: [Self.west, Self.east])
        world.setSpeed(.x60)
        let interchange = world
        await MainActor.run {
            let session = GameSession(world: interchange)
            var told: [Double] = []
            session.duckMusic = { told.append($0) }
            session.followTrain(Self.tram)
            XCTAssertEqual(told.last ?? 1, pow(10, -6.0 / 20), accuracy: 1e-9)
            session.selectTrain(Self.tram)
            session.stopSelectedTrainService()
            XCTAssertEqual(told.last, 1, "out of service, no station ahead")
        }
    }

    /// A local station leaves the music alone, and so does a train nobody
    /// follows.
    func testALocalStationOrNoFollowedTrainLeavesTheMusicAlone() async throws {
        var world = try makeServiceWorld()
        world.setSpeed(.x60)
        let local = world
        await MainActor.run {
            let session = GameSession(world: local)
            var told: [Double] = []
            session.duckMusic = { told.append($0) }
            for _ in 0..<40 {
                session.advance(realElapsed: GameSession.tickInterval)
            }
            session.followTrain(Self.tram)
            for _ in 0..<40 {
                session.advance(realElapsed: GameSession.tickInterval)
            }
            XCTAssertEqual(told, [])
        }
    }

    func testTheLauncherHandsItsMusicToEachGameAndRestoresItOnLeaving() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SoundCueTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        await MainActor.run {
            let launcher = GameLauncher(library: library, language: .english)
            var told: [Double] = []
            launcher.duckMusic = { told.append($0) }
            launcher.startNewGame()
            XCTAssertEqual(told, [1])
            XCTAssertNotNil(launcher.session?.duckMusic)
            launcher.returnToStart()
            XCTAssertEqual(told, [1, 1])
        }
    }
}
