import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 853: the departure melody (``DepartureMelody``), played when
/// the doors of a train the player is looking at start closing, at 60×
/// and slower; each line plays one of three, always the same one.
final class DepartureMelodyTests: XCTestCase {
    // As `SoundCueTests`: one straight edge east, West's platform near its
    // start and East's near its end; Tram stands at West going east and
    // leaves at 00:02 for East, its last call, at 00:06.
    private static let west = StationID(rawValue: 1)
    private static let east = StationID(rawValue: 2)
    private static let tram = TrainID(rawValue: 1)
    private static let edge = TrackEdgeID.edge(1)

    private func makeServiceWorld(speed: GameSpeed) throws -> GameWorld {
        var world = try makeWorld(width: 16_384, height: 6_144, balance: 1_000_000, speed: speed)
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

    /// The cues heard while the session runs `ticks` ticks, following the
    /// tram when `follow`, with when each was heard (game seconds).
    @MainActor
    private static func heard(_ world: GameWorld, ticks: Int, follow: Bool) -> [(second: Int64, cue: SoundCue)] {
        let session = GameSession(world: world)
        if follow { session.followTrain(Self.tram) }
        var heard: [(second: Int64, cue: SoundCue)] = []
        session.playSound = { heard.append((session.world.clock.now.seconds, $0)) }
        for _ in 0..<ticks {
            session.advance(realElapsed: GameSession.tickInterval)
        }
        return heard
    }

    private static func departures(_ heard: [(second: Int64, cue: SoundCue)]) -> [(second: Int64, cue: SoundCue)] {
        heard.filter { if case .departure = $0.cue { true } else { false } }
    }

    /// At 10× (a tick is a game second) the doors close over 9 ticks: the
    /// melody plays once, as they start to, before 00:02; never at East,
    /// where the service ends. A train on no line plays the first melody.
    func testAFollowedTrainPlaysTheMelodyOnceAsItsDoorsStartClosing() async throws {
        let world = try makeServiceWorld(speed: .x10)
        await MainActor.run {
            let all = Self.heard(world, ticks: 600, follow: true)
            let played = Self.departures(all)
            XCTAssertEqual(played.map(\.cue), [.departure(.a)])
            if let second = played.first?.second {
                XCTAssertGreaterThanOrEqual(second, 120 - ServiceDwell.doorClosing)
                XCTAssertLessThan(second, 120, "before it leaves West at 00:02")
            }
            XCTAssertTrue(all.contains { $0.cue == .arrival(watched: true, chime: .local, motif: false) }, "it reached East")
        }
    }

    /// Decision 866: a station set to a melody plays it, whatever the
    /// line's; set back to each line's own, the line's again.
    func testAStationSetToAMelodyPlaysIt() async throws {
        var world = try makeServiceWorld(speed: .x10)
        try world.setStationDepartureMelody(Self.west, to: .c)
        XCTAssertEqual(DepartureMelody.of(Self.tram, at: Self.west, in: world), .c)
        XCTAssertEqual(DepartureMelody.of(Self.tram, at: Self.east, in: world), .a, "East is not set: the train's own")
        XCTAssertEqual(DepartureMelody.of(Self.tram, at: nil, in: world), .a)
        let set = world
        await MainActor.run {
            XCTAssertEqual(Self.departures(Self.heard(set, ticks: 600, follow: true)).map(\.cue), [.departure(.c)])
        }
        try world.setStationDepartureMelody(Self.west, to: nil)
        XCTAssertEqual(DepartureMelody.of(Self.tram, at: Self.west, in: world), .a)
    }

    /// At 60× (six game seconds a tick) the doors close within a tick or
    /// two; the melody still plays once.
    func testAtSixtyTimesItStillPlaysOnce() async throws {
        let world = try makeServiceWorld(speed: .x60)
        await MainActor.run {
            XCTAssertEqual(Self.departures(Self.heard(world, ticks: 100, follow: true)).map(\.cue), [.departure(.a)])
        }
    }

    /// At 600× a train stands a second or less: no melody. Nor for a train
    /// nobody is looking at.
    func testNotAtSixHundredTimesNorForATrainNobodyWatches() async throws {
        let fast = try makeServiceWorld(speed: .normal)
        let slow = try makeServiceWorld(speed: .x10)
        await MainActor.run {
            XCTAssertTrue(Self.departures(Self.heard(fast, ticks: 10, follow: true)).isEmpty)
            XCTAssertTrue(Self.departures(Self.heard(slow, ticks: 600, follow: false)).isEmpty)
        }
    }

    /// The doors of the tram closing at West, seen between two worlds a
    /// step apart: while they close, and, when a step jumped over their
    /// closing, once it has left with them open before.
    func testAClosingIsSeenWhileTheDoorsCloseOrOnceTheTrainHasLeft() throws {
        var world = try makeServiceWorld(speed: .x10)
        var open: GameWorld?
        var closing: GameWorld?
        var gone: GameWorld?
        for _ in 0..<200 {
            let times = world.train(id: Self.tram)?.times
            if open == nil, times?.exchangeEnd != nil, times?.closing == nil { open = world }
            if closing == nil, times?.closing != nil { closing = world }
            if gone == nil, case .travellingToStop? = world.train(id: Self.tram)?.execution { gone = world }
            try world.advance(ticks: 1)
        }
        let before = try XCTUnwrap(open), during = try XCTUnwrap(closing), after = try XCTUnwrap(gone)
        let atWest = try XCTUnwrap(before.train(id: Self.tram)?.times?.arrival)
        let expected = [DepartureMelody.Closing(train: Self.tram, arrival: atWest, station: Self.west)]
        XCTAssertEqual(DepartureMelody.closings(from: before, to: during, watched: [Self.tram]), expected)
        XCTAssertEqual(DepartureMelody.closings(from: before, to: after, watched: [Self.tram]), expected, "a step that jumped over the closing")
        XCTAssertEqual(DepartureMelody.closings(from: before, to: before, watched: [Self.tram]), [], "the doors still open")
        XCTAssertEqual(DepartureMelody.closings(from: during, to: after, watched: [Self.tram]), [], "already seen closing")
        XCTAssertEqual(DepartureMelody.closings(from: before, to: during, watched: []), [], "nobody watching")
    }

    /// A line's melody comes from its name, the same every time, and the
    /// names spread over the first of all three pairs (the melodies lines
    /// had before decision 868); a line's train plays its line's.
    func testEachLinePlaysItsOwnMelodyAlways() throws {
        let names = ["Shuttle", "淡水信義線", "板南線", "文湖線", "East Rail Line", "Tuen Ma Line", "臺鐵西部幹線", "Rovaniemi–Kemijärvi"]
        XCTAssertEqual(names.map(DepartureMelody.of(lineNamed:)), names.map(DepartureMelody.of(lineNamed:)))
        XCTAssertEqual(Set(names.map(DepartureMelody.of(lineNamed:))), [.a, .b, .c], "every pair has a line")
        XCTAssertEqual(DepartureMelody.of(lineNamed: ""), .b, "FNV-1a of no bytes is its offset basis, 2,166,136,261, which leaves 1 over 3")

        var world = try makeServiceWorld(speed: .x10)
        XCTAssertEqual(DepartureMelody.of(Self.tram, in: world), .a, "on no line")
        try world.stopTrainService(Self.tram)
        try world.setTrainTimetable(Self.tram, to: [])
        let line = try world.createLine(named: "Shuttle", stops: [Self.west, Self.east]).id
        try world.assignTrain(Self.tram, to: line)
        XCTAssertEqual(DepartureMelody.of(Self.tram, in: world), DepartureMelody.of(lineNamed: "Shuttle"))
    }

    /// Decision 868: six melodies in three pairs; a line's stations play
    /// its melody or that melody's companion, each station always the
    /// same one, and a station the player set plays what it was set to.
    func testALinesStationsPlayOneOfItsPairEachItsOwn() throws {
        XCTAssertEqual(DepartureMelody.allCases, [.a, .b, .c, .d, .e, .f])
        XCTAssertEqual(DepartureMelody.allCases.map(\.companion), [.d, .e, .f, .a, .b, .c])
        let stations = ["West", "East", "台北車站", "中山", "Admiralty", "Rovaniemi", "博多", "天神"]
        for line in ["Shuttle", "板南線", "East Rail Line"] {
            let melody = DepartureMelody.of(lineNamed: line)
            let heard = stations.map { DepartureMelody.of(lineNamed: line, atStationNamed: $0) }
            XCTAssertEqual(Set(heard), [melody, melody.companion], "\(line): both of its pair, and no other")
            XCTAssertEqual(heard, stations.map { DepartureMelody.of(lineNamed: line, atStationNamed: $0) })
        }
        XCTAssertEqual(DepartureMelody.of(lineNamed: "Shuttle", atStationNamed: ""), DepartureMelody.of(lineNamed: "Shuttle").companion,
                       "FNV-1a of no bytes, 2,166,136,261, is odd")

        var world = try makeServiceWorld(speed: .x10)
        XCTAssertEqual(DepartureMelody.of(Self.tram, at: Self.west, in: world), .a, "on no line")
        try world.stopTrainService(Self.tram)
        try world.setTrainTimetable(Self.tram, to: [])
        let line = try world.createLine(named: "Shuttle", stops: [Self.west, Self.east]).id
        try world.assignTrain(Self.tram, to: line)
        XCTAssertEqual(DepartureMelody.of(Self.tram, at: Self.west, in: world), DepartureMelody.of(lineNamed: "Shuttle", atStationNamed: "West"))
        XCTAssertEqual(DepartureMelody.of(Self.tram, at: Self.east, in: world), DepartureMelody.of(lineNamed: "Shuttle", atStationNamed: "East"))
        XCTAssertEqual(DepartureMelody.of(Self.tram, at: nil, in: world), DepartureMelody.of(lineNamed: "Shuttle"))
        try world.setStationDepartureMelody(Self.west, to: .f)
        XCTAssertEqual(DepartureMelody.of(Self.tram, at: Self.west, in: world), .f)
    }

    /// Each melody is a file the app bundles and the audio manifest lists,
    /// a departure melody of at most 8 s (the research note's §3), in the
    /// station chimes' volume.
    func testEveryMelodyIsABundledDepartureOfAtMostEightSeconds() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("tools/audio/manifest.json"))) as? [String: Any]
        let files = (manifest?["files"] as? [[String: Any]] ?? [])
        for melody in DepartureMelody.allCases {
            let cue = SoundCue.departure(melody)
            let file = "\(cue.resource.name).\(cue.resource.extension)"
            let entry = try XCTUnwrap(files.first { $0["file"] as? String == file }, "\(file) is in the manifest")
            XCTAssertEqual(entry["kind"] as? String, "departure")
            XCTAssertLessThanOrEqual(try XCTUnwrap(entry["seconds"] as? Double), 8)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RailwayGameApp/Resources/Audio/\(file)").path), "\(file) is bundled")
            XCTAssertEqual(cue.category, .chimes)
        }
    }
}
