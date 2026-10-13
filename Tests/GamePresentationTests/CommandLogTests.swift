import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The command log (ARCHITECTURE decision 193): every change of the world
/// a session makes is logged in order, with its game time, refused
/// commands too; it keeps at most ``CommandLog/limit`` entries; and a
/// problem report made from it replays, through a session with the
/// app's data, to the same world.
@MainActor
final class CommandLogTests: XCTestCase {
    private static let reach: Int64 = 512

    /// A blank map, paused, with money to build.
    private func blankWorld() throws -> GameWorld {
        try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000, speed: .paused)
    }

    /// Track from (2048, 2048) to (6144, 2048) and on to (10240, 4096), and
    /// a station with a platform on the first stretch, all from the tools.
    private func build(in session: GameSession) {
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 2_048), reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: 6_144, y: 2_048), reach: Self.reach)
        session.buildNetworkTrack()
        session.tapNetwork(at: PlanPoint(x: 10_240, y: 4_096), reach: Self.reach)
        session.buildNetworkTrack()
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: 4_096, y: 2_100), reach: Self.reach)
        session.addNetworkPlatform()
    }

    /// A report of the session's log, through its file and back.
    private func report(of session: GameSession) throws -> CommandLogReport {
        let report = session.commandLogReport(version: "0.5.0", build: "56.1", data: [:])
        return try JSONDecoder().decode(CommandLogReport.self, from: report.encoded())
    }

    // MARK: - What is logged

    func testEveryChangeIsLoggedInOrderWithItsTime() throws {
        let session = GameSession(world: try blankWorld())
        build(in: session)
        // The same platform again overlaps it: refused, and logged.
        session.tapNetwork(at: PlanPoint(x: 4_096, y: 2_100), reach: Self.reach)
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .failure)
        session.undo()
        session.redo()
        session.setSpeed(.normal)
        session.advance(ticks: 3)
        session.advance(ticks: 2)
        session.togglePause()
        let platform = try XCTUnwrap(session.world.trackPlatforms(of: StationID(rawValue: 1)).first)
        session.removeNetworkPlatform(platform)
        session.setNetworkMode(.remove)
        session.tapNetwork(at: PlanPoint(x: 8_192, y: 3_000), reach: Self.reach)
        session.removeNetworkEdge()

        let log = session.commandLog
        XCTAssertEqual(log.start, try blankWorld())
        XCTAssertEqual(log.entries.map(\.action.name), [
            "command", "command", "command", "command", "undo", "redo", "setSpeed", "advance", "pause", "command", "command",
        ])
        XCTAssertEqual(log.entries.map(\.refused), [false, false, false, true, false, false, false, false, false, false, false])
        XCTAssertEqual(log.entries[7].action, .advance(ticks: 5), "game time running on is one entry")
        XCTAssertEqual(log.entries[7].time, 0, "the time it came at")
        XCTAssertEqual(log.entries[8].time, 300, "five ticks of a minute later")
        guard case .command(.addPlatform(let addition)) = log.entries[2].action else { return XCTFail("\(log.entries[2])") }
        XCTAssertEqual(addition.station, .new(name: "Station 1", at: PlanPoint(x: 4_096, y: 2_048), demand: .cityDefault))
        XCTAssertEqual(log.entries[10].action, .command(.removeTrack(.edge(2))))
    }

    /// An edit with no value yet is logged by the function that made it,
    /// and any other change by the world's observer: none goes unseen.
    func testAChangeWithNoCommandIsLoggedAsNotRecorded() throws {
        var world = try blankWorld()
        _ = try world.buildStation(named: "West", at: PlanPoint(x: 2_048, y: 2_048))
        let session = GameSession(world: world)
        session.selectStation(StationID(rawValue: 1))
        session.renameSelectedStation(to: "East")
        XCTAssertEqual(session.world.stations.first?.name, "East")
        XCTAssertEqual(session.commandLog.entries.map(\.action), [.unrecorded("renameSelectedStation(to:)")])
        // A refused or empty edit with no value changes nothing: not logged.
        session.renameSelectedStation(to: "East")
        XCTAssertEqual(session.commandLog.entries.count, 1)
    }

    /// A tick worked out off the main actor and dropped because a command
    /// came first (decision 143) is not game time put in place.
    func testADroppedTickIsNotLogged() throws {
        let session = GameSession(world: try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000, speed: .normal))
        let dropped = try XCTUnwrap(session.beginLoopTick())
        session.setSpeed(.fast)
        XCTAssertFalse(session.finish(dropped, with: .success(try GameSession.advanced(dropped.world, by: 1, listening: false))))
        let taken = try XCTUnwrap(session.beginLoopTick())
        XCTAssertTrue(session.finish(taken, with: .success(try GameSession.advanced(taken.world, by: 1, listening: false))))
        XCTAssertEqual(session.commandLog.entries.map(\.action), [.setSpeed(.fast), .advance(ticks: 1)])
    }

    /// The log keeps at most its limit: reaching it, the world after the
    /// oldest half becomes the start. Game time running on does not join
    /// the entry the next start was taken after. A report replays from the
    /// new start to the same world.
    func testTheLogKeepsAtMostItsLimit() throws {
        let session = GameSession(world: try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000, speed: .paused))
        let half = CommandLog.limit / 2
        for _ in 0..<(half - 1) { session.togglePause() }
        XCTAssertFalse(session.world.clock.isPaused)
        session.advance(ticks: 1)
        session.advance(ticks: 1)
        XCTAssertEqual(session.commandLog.entries.count, half + 1, "not into the halfway entry")
        let halfway = session.commandLog.entries[half - 1]
        XCTAssertEqual(halfway.action, .advance(ticks: 1))
        while session.commandLog.entries.count < CommandLog.limit - 1 { session.togglePause() }
        XCTAssertEqual(session.commandLog.start, try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000, speed: .paused))
        session.togglePause()
        XCTAssertEqual(session.commandLog.entries.count, CommandLog.limit - half)
        XCTAssertEqual(session.commandLog.start.clock.now.seconds, 60, "after the halfway tick, not the next")
        XCTAssertEqual(session.commandLog.entries.first?.action, .advance(ticks: 1))
        let replay = try CommandLogReplay(report(of: session))
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world, session.world)
    }

    // MARK: - Commands and the closures they replace

    /// Each command does what its tool's closure did before decision 193:
    /// the same world, or the same error.
    func testEachCommandMakesWhatItsClosureMade() throws {
        var line = try blankWorld()
        let west = try line.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let east = try line.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
        let edge = try line.buildTrackEdge(from: west, to: east)
        var managed = GameWorld.newGame()
        let managedWest = try managed.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let managedEast = try managed.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
        let managedEdge = try managed.buildTrackEdge(from: managedWest, to: managedEast)
        var withPlatform = line
        let station = try withPlatform.buildStation(named: "West", at: PlanPoint(x: 3_000, y: 2_048))
        try withPlatform.addTrackPlatform(station.id, on: edge, from: 512, to: 2_560)
        let platform = TrackPlatform(station: station.id, edge: edge, start: 512, end: 2_560)
        let demand = StationDemand(kind: .office, dailyTrips: 4_000)

        func stretch(_ start: NetworkAnchor, _ end: NetworkAnchor, from: WorldCoordinate, to: WorldCoordinate) -> PlayerCommand.TrackStretch {
            PlayerCommand.TrackStretch(
                start: start, end: end, from: from, to: to, curve: .straight, profile: .uniform, structure: .automatic,
                ground: [from.plan, to.plan]
            )
        }
        struct Case {
            let name: String
            let world: GameWorld
            let command: PlayerCommand
            let closure: (inout GameWorld) throws(GameError) -> Void
            init(_ name: String, _ world: GameWorld, _ command: PlayerCommand, _ closure: @escaping (inout GameWorld) throws(GameError) -> Void) {
                self.name = name
                self.world = world
                self.command = command
                self.closure = closure
            }
        }
        let cases: [Case] = [
            Case("new track", line, .buildTrack(stretch(.point(PlanPoint(x: 6_144, y: 6_144)), .node(east), from: WorldCoordinate(x: 6_144, y: 6_144), to: WorldCoordinate(x: 6_144, y: 2_048)))) { world throws(GameError) in
                let first = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 6_144))
                try world.buildTrackEdge(from: first, to: east, curve: .straight, profile: .uniform, structure: .automatic)
            },
            Case("a turnout", line, .buildTrack(stretch(.track(NetworkEdgePoint(edge: edge, distance: 2_048)), .point(PlanPoint(x: 4_096, y: 6_144)), from: WorldCoordinate(x: 4_096, y: 2_048), to: WorldCoordinate(x: 4_096, y: 6_144)))) { world throws(GameError) in
                let first = try world.splitTrackEdge(edge, at: 2_048)
                let last = try world.buildTrackNode(at: WorldCoordinate(x: 4_096, y: 6_144))
                try world.buildTrackEdge(from: first, to: last, curve: .straight, profile: .uniform, structure: .automatic)
            },
            Case("track off the map", line, .buildTrack(stretch(.node(east), .point(PlanPoint(x: 99_999, y: 2_048)), from: WorldCoordinate(x: 6_144, y: 2_048), to: WorldCoordinate(x: 99_999, y: 2_048)))) { world throws(GameError) in
                let last = try world.buildTrackNode(at: WorldCoordinate(x: 99_999, y: 2_048))
                try world.buildTrackEdge(from: east, to: last, curve: .straight, profile: .uniform, structure: .automatic)
            },
            Case("a new station", managed, .addPlatform(.init(edge: managedEdge, start: 512, end: 2_560, station: .new(name: "Middle", at: PlanPoint(x: 3_584, y: 2_048), demand: demand)))) { world throws(GameError) in
                let station = try world.buildStation(named: "Middle", at: PlanPoint(x: 3_584, y: 2_048))
                if world.accounts.mode == .management, !world.landDemand { try world.setStationDemand(station.id, to: demand) }
                try world.addTrackPlatform(station.id, on: managedEdge, from: 512, to: 2_560)
            },
            Case("a new station, free", line, .addPlatform(.init(edge: edge, start: 512, end: 2_560, station: .new(name: "Middle", at: PlanPoint(x: 3_584, y: 2_048), demand: demand)))) { world throws(GameError) in
                let station = try world.buildStation(named: "Middle", at: PlanPoint(x: 3_584, y: 2_048))
                if world.accounts.mode == .management, !world.landDemand { try world.setStationDemand(station.id, to: demand) }
                try world.addTrackPlatform(station.id, on: edge, from: 512, to: 2_560)
            },
            Case("a second platform", withPlatform, .addPlatform(.init(edge: edge, start: 2_560, end: 3_584, station: .existing(station.id)))) { world throws(GameError) in
                try world.addTrackPlatform(station.id, on: edge, from: 2_560, to: 3_584)
            },
            Case("an overlapping platform", withPlatform, .addPlatform(.init(edge: edge, start: 1_024, end: 3_072, station: .existing(station.id)))) { world throws(GameError) in
                try world.addTrackPlatform(station.id, on: edge, from: 1_024, to: 3_072)
            },
            Case("removing a platform", withPlatform, .removePlatform(platform)) { world throws(GameError) in
                try world.removeTrackPlatform(platform.station, on: platform.edge, from: platform.start)
            },
            Case("removing a platform not there", line, .removePlatform(platform)) { world throws(GameError) in
                try world.removeTrackPlatform(platform.station, on: platform.edge, from: platform.start)
            },
            Case("removing track", line, .removeTrack(edge)) { world throws(GameError) in
                try world.removeTrackEdge(edge)
                try world.removeTrackNode(west)
                try world.removeTrackNode(east)
            },
            Case("removing track with a platform", withPlatform, .removeTrack(edge)) { world throws(GameError) in
                try world.removeTrackEdge(edge)
            },
        ]
        for item in cases {
            let (name, world, command, closure) = (item.name, item.world, item.command, item.closure)
            let session = GameSession(world: world)
            var byCommand = world
            var byClosure = world
            let commandError = Result { () throws(GameError) in _ = try session.apply(command, to: &byCommand) }.failure
            let closureError = Result { () throws(GameError) in try closure(&byClosure) }.failure
            XCTAssertEqual(commandError, closureError, name)
            if commandError == nil {
                XCTAssertEqual(byCommand, byClosure, name)
                XCTAssertNotEqual(byCommand, world, "\(name) changes the world")
            }
            // Through the session: all or nothing, and logged.
            session.perform(command) { _, _, _ in "" }
            XCTAssertEqual(session.world, commandError == nil ? byClosure : world, name)
            XCTAssertEqual(session.commandLog.entries, [CommandLog.Entry(time: 0, action: .command(command), refused: commandError != nil)], name)
        }
    }

    func testEveryEntryKeepsItsFormThroughItsFile() throws {
        let entries: [CommandLog.Entry] = [
            .init(time: 0, action: .command(.buildTrack(.init(
                start: .track(NetworkEdgePoint(edge: .edge(3), distance: 77)), end: .point(PlanPoint(x: 5, y: -6)),
                from: WorldCoordinate(x: 1, y: 2, z: 3), to: WorldCoordinate(x: 5, y: -6, z: 0),
                curve: .cubic(PlanPoint(x: 1, y: 1), PlanPoint(x: 2, y: 2)), profile: TrackProfile(startTransition: 64, endTransition: 128),
                structure: .elevated, ground: [PlanPoint(x: 1, y: 2), PlanPoint(x: 5, y: -6)]
            )))),
            .init(time: 1, action: .command(.buildTrack(.init(
                start: .node(.node(1)), end: .node(.node(2)), from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 9, y: 0),
                curve: .straight, profile: .uniform, structure: .automatic, ground: []
            ))), refused: true),
            .init(time: 2, action: .command(.addPlatform(.init(edge: .edge(1), start: 0, end: 9, station: .existing(StationID(rawValue: 4)))))),
            .init(time: 3, action: .command(.addPlatform(.init(
                edge: .edge(1), start: 0, end: 9, station: .new(name: "北門", at: PlanPoint(x: 4, y: 0), demand: StationDemand(kind: .civic, dailyTrips: 7, hinterland: 2))
            )))),
            .init(time: 4, action: .command(.removePlatform(TrackPlatform(station: StationID(rawValue: 2), edge: .edge(5), start: 1, end: 8)))),
            .init(time: 5, action: .command(.removeTrack(.edge(9)))),
            .init(time: 6, action: .advance(ticks: 40)),
            .init(time: 7, action: .setSpeed(.x10)),
            .init(time: 8, action: .pause),
            .init(time: 9, action: .resume),
            .init(time: 10, action: .undo),
            .init(time: 11, action: .redo),
            .init(time: 12, action: .readLandRoundStations(RealWorldDataSet(population: true, heights: true))),
            .init(time: 13, action: .readLand(reach: 800, at: PlanPoint(x: 3, y: 4))),
            .init(time: 14, action: .unrecorded("buyMapTile(_:)")),
        ]
        let data = try JSONEncoder().encode(entries)
        XCTAssertEqual(try JSONDecoder().decode([CommandLog.Entry].self, from: data), entries)
        XCTAssertThrowsError(try JSONDecoder().decode(CommandLog.Entry.self, from: Data(#"{"time":0,"action":"jump"}"#.utf8)))
    }

    // MARK: - Reports

    /// A report says what the player may have typed, for them to see
    /// before they send it, and nothing about the device.
    func testAReportNamesWhatThePlayerTyped() throws {
        var world = try blankWorld()
        _ = try world.buildStation(named: "Home", at: PlanPoint(x: 9_000, y: 6_000))
        let session = GameSession(world: world)
        session.stationName = "Grandma's"
        build(in: session)
        let report = try report(of: session)
        XCTAssertEqual(report.typedNames, ["Home", "Grandma's"])
        XCTAssertEqual(report.version, "0.5.0")
        XCTAssertEqual(report.build, "56.1")
        let file = try XCTUnwrap(String(data: report.encoded(), encoding: .utf8))
        for key in ["\"schemaVersion\"", "\"version\"", "\"build\"", "\"data\"", "\"start\"", "\"startData\"", "\"entries\"", "\"end\""] {
            XCTAssertTrue(file.contains(key), key)
        }
        XCTAssertEqual(
            report.attachmentText(in: .english),
            "Attached: command-log.json, with the save this game started from, the 3 things done since (commands, game time, Undo and Redo) and the version 0.5.0 (56.1). Nothing about you or your device. Names in it: Home, Grandma's."
        )
        XCTAssertEqual(
            report.attachmentText(in: .traditionalChinese, shown: 1),
            "會附上 command-log.json：這局開始時的存檔、之後做的 3 件事（指令、遊戲時間、復原與重做），以及版本 0.5.0 (56.1)。不含你或裝置的任何資料。裡面的名稱：Home 等 2 個。"
        )
        XCTAssertEqual(CommandLogReport.digest(of: Data()), "cbf29ce484222325", "FNV-1a's offset")
        XCTAssertEqual(CommandLogReport.digest(of: Data("a".utf8)), "af63dc4c8601ec8c")
    }

    /// The report replays, through a session with no screen, to the world
    /// the game came to: Undo and Redo, refused commands, speed and time
    /// included.
    func testABlankMapsReportReplaysToTheSameWorld() throws {
        let session = GameSession(world: try blankWorld())
        build(in: session)
        session.tapNetwork(at: PlanPoint(x: 4_096, y: 2_100), reach: Self.reach)
        session.addNetworkPlatform()
        session.undo()
        session.setSpeed(.normal)
        // As the game loop puts them in place, a tick at a time; the log
        // keeps them as one entry, which the replay puts in place at once.
        for _ in 0..<7 {
            let tick = try XCTUnwrap(session.beginLoopTick())
            XCTAssertTrue(session.finish(tick, with: .success(try GameSession.advanced(tick.world, by: 1, listening: true))))
        }
        XCTAssertEqual(session.commandLog.entries.last?.action, .advance(ticks: 7))
        session.undo()
        session.togglePause()
        session.redo()
        session.togglePause()
        session.advance(ticks: 4)
        let report = try report(of: session)
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.replayed, report.entries.count)
        XCTAssertEqual(replay.session.world, session.world)
        XCTAssertEqual(CommandLogReport.Summary(replay.session.world), report.end)
        XCTAssertEqual(replay.session.commandLog.entries, report.entries, "the replay logs what it replays")
    }

    /// Game time on a line with a train running: ticks the game loop put
    /// in place one at a time replay as the log's one entry to the same
    /// world, the train where it was, the fares and the accounts too.
    func testATrainsRunReplaysTickForTick() throws {
        var world = try newGameLine(through: [PlanPoint(x: 20_000, y: 20_000), PlanPoint(x: 60_000, y: 20_000)])
        world.setSpeed(.normal)
        let session = GameSession(world: world)
        func loop(_ ticks: Int) throws {
            for _ in 0..<ticks {
                let tick = try XCTUnwrap(session.beginLoopTick())
                XCTAssertTrue(session.finish(tick, with: .success(try GameSession.advanced(tick.world, by: 1, listening: false))))
            }
        }
        try loop(90)
        session.togglePause()
        session.togglePause()
        try loop(150)
        XCTAssertEqual(session.commandLog.entries.map(\.action), [.advance(ticks: 90), .pause, .resume, .advance(ticks: 150)])
        let replay = try CommandLogReplay(report(of: session))
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertNotEqual(replay.session.world.trains.first?.position, world.trains.first?.position, "the train ran")
        XCTAssertEqual(replay.session.world, session.world)
    }

    /// A replay stops before what it cannot replay, and says what.
    func testAReplayStopsBeforeAChangeWithNoCommand() throws {
        let session = GameSession(world: try blankWorld())
        build(in: session)
        session.selectStation(StationID(rawValue: 1))
        session.renameSelectedStation(to: "Renamed")
        let report = try report(of: session)
        let replay = try CommandLogReplay(report)
        XCTAssertEqual(replay.stopped?.index, 3)
        XCTAssertEqual(replay.stopped?.reason, "renameSelectedStation(to:) changed the world with no recorded command")
        XCTAssertEqual(replay.replayed, 3)
    }

    /// On the real map the land round a new station is read in from the
    /// app's data (decision 88), and the ground under new track (decision
    /// 124): the replay reads the same files, arriving when the device's
    /// did, and comes to the same world.
    func testARealMapsReportReplaysWithTheBundledData() throws {
        let session = GameSession(world: GameWorld.newWholeTaiwanGame())
        session.population = try CommandLogReplay.population.get()
        session.places = try CommandLogReplay.places.get()
        session.water = try CommandLogReplay.water.get()
        session.heights = try CommandLogReplay.heights.get()
        session.coverage = try CommandLogReplay.coverage.get()
        session.readLandRoundStations()
        // Changhua, on the plain.
        let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
        let changhua = frame.worldPosition(latitude: 24.0818, longitude: 120.5385)
        let west = PlanPoint(x: Int64(changhua.x.rounded()), y: Int64(changhua.y.rounded()))
        session.selectTool(.network)
        session.tapNetwork(at: west, reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: west.x + 30_000, y: west.y), reach: Self.reach)
        session.buildNetworkTrack()
        XCTAssertEqual(session.world.network.edges.count, 1, "\(String(describing: session.message))")
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: west.x + 15_000, y: west.y), reach: Self.reach)
        session.addNetworkPlatform()
        XCTAssertEqual(session.world.stations.count, 1, "\(String(describing: session.message))")
        XCTAssertFalse(session.world.land.isEmpty, "the land round it is read in")
        XCTAssertEqual(session.commandLog.entries.first?.action, .readLandRoundStations(RealWorldDataSet(
            population: true, places: true, water: true, heights: true, coverage: true
        )))

        let report = try JSONDecoder().decode(CommandLogReport.self, from: session.commandLogReport(
            version: "0.5.0", build: "56.1",
            data: CommandLogReport.digests(reading: CommandLogReplay.bundled)
        ).encoded())
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(report.data.count, CommandLogReport.dataFiles.count)
        XCTAssertEqual(replay.warnings, [])
        XCTAssertEqual(replay.session.world, session.world)

        // Data of another build: a warning.
        var other = report.data
        other["taiwan_water.json"] = "0000000000000000"
        let warned = try CommandLogReplay(CommandLogReport(
            log: session.commandLog, world: session.world, version: report.version, build: report.build, data: other
        ))
        XCTAssertEqual(warned.warnings.count, 1)
        XCTAssertEqual(warned.session.world, session.world, "still replayed")
    }

    // MARK: - The example report

    /// The example report in `ReplayFixtures/Reports/`, from which the
    /// GameCore fixture `problem-report-blank-map.json` is converted
    /// (`ProblemReportFixtureTests`): a blank map, track, stations and
    /// platforms from the network tool, a refused platform, the speed and
    /// game time between them.
    private func exampleSession() throws -> GameSession {
        let session = GameSession(world: try blankWorld())
        session.networkStructure = .surface
        build(in: session)
        session.setSpeed(.normal)
        session.advance(ticks: 2)
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: 4_096, y: 2_100), reach: Self.reach)
        session.addNetworkPlatform()
        session.advance(ticks: 1)
        session.tapNetwork(at: PlanPoint(x: 8_192, y: 3_100), reach: Self.reach)
        session.addNetworkPlatform()
        session.advance(ticks: 3)
        session.setNetworkMode(.build)
        session.tapNetwork(at: PlanPoint(x: 10_240, y: 4_096), reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: 14_336, y: 4_096), reach: Self.reach)
        session.buildNetworkTrack()
        session.advance(ticks: 1)
        session.tapNetwork(at: PlanPoint(x: 14_336, y: 7_000), reach: Self.reach)
        session.buildNetworkTrack()
        session.togglePause()
        session.togglePause()
        session.advance(ticks: 5)
        let platform = try XCTUnwrap(session.world.trackPlatforms(of: StationID(rawValue: 1)).first)
        session.removeNetworkPlatform(platform)
        session.advance(ticks: 2)
        session.setNetworkMode(.remove)
        session.tapNetwork(at: PlanPoint(x: 14_400, y: 5_500), reach: Self.reach)
        session.removeNetworkEdge()
        session.setSpeed(.fast)
        session.advance(ticks: 4)
        session.setNetworkMode(.platform)
        session.tapNetwork(at: PlanPoint(x: 12_288, y: 4_150), reach: Self.reach)
        session.addNetworkPlatform()
        session.advance(ticks: 6)
        return session
    }

    /// The committed example replays to where the game it was made from came.
    func testTheExampleReportReplays() throws {
        let url = CommandLogReplay.root.appendingPathComponent("ReplayFixtures/Reports/blank-map.json")
        let report = try JSONDecoder().decode(CommandLogReport.self, from: Data(contentsOf: url))
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(CommandLogReport.Summary(replay.session.world), report.end)
        XCTAssertEqual(replay.session.world, try exampleSession().world, "made by the example's session")
        XCTAssertEqual(report.entries.filter(\.refused).count, 1)
    }

    /// Writes the example report, only on request: `COMMAND_LOG_RECORD=<directory>`.
    func testRecordingTheExampleReport() throws {
        guard let directory = ProcessInfo.processInfo.environment["COMMAND_LOG_RECORD"] else {
            throw XCTSkip("set COMMAND_LOG_RECORD=<directory> to record the example report")
        }
        let report = try exampleSession().commandLogReport(version: "example", build: "0", data: [:])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: URL(fileURLWithPath: directory).appendingPathComponent("blank-map.json"))
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
