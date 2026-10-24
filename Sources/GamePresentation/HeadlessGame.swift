import Foundation
import GameCore

// Decision 260: a game with no screen, for tools. GameSim (Sources/GameSim)
// drives it from the command line, and tests and scripted play (the next
// tool) drive it in code: start or load a game, apply commands or a
// problem report's command log, let game time run, and read a summary as
// JSON. Each operation answers with a receipt. It goes through a
// `GameSession`, as the device does, so a command log replays through the
// same paths it was logged from (decision 193). Nothing here changes a
// rule; a session with no screen plays no sound and does not pause for
// events.
//
// Sources: godot-mcp's single dispatch script (an operation and its JSON
// in, JSON out), Unreal_mcp's receipt for every command and refusal of
// options it does not know (docs/research/GAME_AI_TOOLS_2026-10-15.md
// §3.1). Nothing copied; the code is this project's.

/// A game played with no screen (decision 260).
@MainActor
public final class HeadlessGame {
    public private(set) var session: GameSession
    /// The seed a new game's towns were drawn from (``newGame(seed:buysMap:rules:)``);
    /// `nil` for a game loaded.
    public private(set) var seed: UInt32?
    /// The towns a policy builds between (decision 261): a new game's;
    /// empty for a game loaded.
    public private(set) var towns: [PlanPoint] = []

    /// The world as it is now.
    public var world: GameWorld { session.world }

    public init(world: GameWorld) {
        session = Self.session(world)
    }

    private static func session(_ world: GameWorld) -> GameSession {
        let session = GameSession(world: world)
        // Game time runs on as asked: a goal met or a month closed does
        // not stop it.
        session.pausesForImportantEvents = false
        return session
    }

    // MARK: - Starting

    /// A new game as the app starts one on a blank map (``GameWorld/newGame(anchor:bounds:balance:eventSeed:land:water:steep:buysMap:rules:)``)
    /// with `seed`'s towns and events, under `rules` (decision 258: the
    /// app's new games are simple unless the player chooses realistic).
    public static func newGame(seed: UInt32, buysMap: Bool = false, rules: NewGameRules = .simple) -> HeadlessGame {
        let game = HeadlessGame(world: .newGame(eventSeed: seed, buysMap: buysMap, rules: rules))
        game.seed = seed
        game.towns = Land.townCentres(seed: seed, in: GameWorld.newGameBounds)
        return game
    }

    /// A new game on `map` under `rules` and then `preset` (decision 261:
    /// any policy, any rules, any map). A real place reads the app's data
    /// from `files`.
    public static func newGame(map: PolicyMap, rules: NewGameRules = .simple, preset: RulePreset? = nil, files: RealWorldFiles? = nil) throws -> HeadlessGame {
        var (world, towns) = try map.start(rules: rules, files: files)
        try preset?.apply(to: &world)
        let game = HeadlessGame(world: world)
        if case .blank(let seed) = map { game.seed = seed }
        game.towns = towns
        return game
    }

    /// The game in `data`: a save file the app wrote (``SaveLibrary``),
    /// migrated as the app migrates it, or a problem report's command log
    /// (``CommandLogReport``), from where its log starts.
    public static func load(_ data: Data) throws -> HeadlessGame {
        if let world = try? SaveLibrary.decode(data) {
            return HeadlessGame(world: world)
        }
        if let report = try? JSONDecoder().decode(CommandLogReport.self, from: data) {
            return HeadlessGame(world: report.start.world)
        }
        throw HeadlessGameError("neither a save file nor a command log report this build reads")
    }

    /// The game as a save file the app reads.
    public func saveFile(at date: Date = Date(timeIntervalSince1970: 0)) throws -> Data {
        try SaveLibrary.encode(session.worldToSave, at: date)
    }

    // MARK: - Commands

    /// What `apply` did.
    public struct Applied: Codable, Hashable, Sendable {
        /// How many entries or commands were applied.
        public var applied: Int
        /// How many of the commands the world refused (a log's refused
        /// entries, refused again, count too).
        public var refused: Int
        /// Why it stopped before the end, if it did: the index and reason.
        public var stoppedAt: Int?
        public var stopReason: String?
    }

    /// Applies `data`: a problem report (its log's entries), a list of
    /// log entries (``CommandLog/Entry``), replayed as the device made
    /// them, at the game times they came at; or a list of commands
    /// (``PlayerCommand``), made one after another now. `data` names the
    /// real-world data a log's land reading needs.
    public func apply(_ data: Data, realWorld: RealWorldFiles? = nil) throws -> Applied {
        let decoder = JSONDecoder()
        if let report = try? decoder.decode(CommandLogReport.self, from: data) {
            return replay(report.entries, realWorld: realWorld, startData: report.startData)
        }
        if let entries = try? decoder.decode([CommandLog.Entry].self, from: data) {
            return replay(entries, realWorld: realWorld)
        }
        if let commands = try? decoder.decode([PlayerCommand].self, from: data) {
            return perform(commands)
        }
        throw HeadlessGameError("not a command log report, a list of log entries or a list of commands this build reads")
    }

    /// Makes `commands` now, one after another, going on past a refused one.
    public func perform(_ commands: [PlayerCommand]) -> Applied {
        var refused = 0
        for command in commands where session.perform(command, message: { _, _, _ in "" }) == nil {
            refused += 1
        }
        return Applied(applied: commands.count, refused: refused)
    }

    /// Replays `entries` as ``CommandLogReplay`` does (decision 193): each
    /// at the game time it came at, refused where the device's was; stops
    /// at the first that parts from the device's game.
    public func replay(_ entries: [CommandLog.Entry], realWorld: RealWorldFiles? = nil, startData: RealWorldDataSet = RealWorldDataSet()) -> Applied {
        var result = Applied(applied: 0, refused: 0)
        // The device's session paused for events and logged it: replay as
        // it ran.
        session.pausesForImportantEvents = true
        defer { session.pausesForImportantEvents = false }
        do {
            try install(startData, from: realWorld)
        } catch {
            result.stoppedAt = 0
            result.stopReason = "\(error)"
            return result
        }
        for (index, entry) in entries.enumerated() {
            let reason: String?
            do {
                reason = try step(entry, realWorld: realWorld)
            } catch {
                reason = "\(error)"
            }
            if let reason {
                result.stoppedAt = index
                result.stopReason = reason
                return result
            }
            if entry.refused { result.refused += 1 }
            result.applied += 1
        }
        return result
    }

    /// Replays `entry`; why it cannot, if it cannot.
    public func step(_ entry: CommandLog.Entry, realWorld: RealWorldFiles?) throws -> String? {
        guard session.world.clock.now.seconds == entry.time else {
            return "the game time is \(session.world.clock.now.seconds) s, the device's was \(entry.time) s"
        }
        switch entry.action {
        case .command(let command):
            let outcome = session.perform(command) { _, _, _ in "" }
            if (outcome == nil) != entry.refused {
                return "\(command.name) was \(entry.refused ? "refused" : "made") on the device, not here: \(session.message?.text ?? "")"
            }
        case .advance(let ticks):
            session.advance(ticks: ticks)
        case .setSpeed(let speed):
            session.setSpeed(speed)
        case .pause:
            // A pause the device's session made by itself for an event
            // (decision 175), the replay's has made at the same tick.
            if session.world.clock.isPaused, session.isPausedForEvent { break }
            guard !session.world.clock.isPaused else { return "already paused" }
            session.togglePause()
        case .resume:
            guard session.world.clock.isPaused else { return "not paused" }
            session.togglePause()
        case .undo:
            guard session.canUndo else { return "nothing to undo" }
            session.undo()
        case .redo:
            guard session.canRedo else { return "nothing to redo" }
            session.redo()
        case .readLandRoundStations(let data):
            try install(data, from: realWorld)
            session.readLandRoundStations()
        case .readLand(let reach, let point):
            session.readLand(within: reach, of: point)
        case .transfers(let points):
            session.applyTransfers(points)
        case .unrecorded(let caller):
            return "\(caller) changed the world with no recorded command"
        }
        return nil
    }

    /// Gives the session the real-world data `data` says the device's had.
    public func install(_ data: RealWorldDataSet, from files: RealWorldFiles?) throws {
        guard data != RealWorldDataSet() else { return }
        guard let files else { throw HeadlessGameError("the log reads the app's real-world data: give its folder") }
        try files.install(data, in: session)
    }

    // MARK: - Time

    /// What `advance` did.
    public struct Advanced: Codable, Hashable, Sendable {
        /// Game seconds that passed.
        public var seconds: Int64
        public var day: Int64
        /// The balance's change, in dollars.
        public var balanceChange: Int64
    }

    /// Lets `seconds` of game time pass at the world's running speed (a
    /// paused game is resumed first), a day at a time, as whole ticks: at
    /// least `seconds`, less than a tick more.
    public func advance(seconds: Int64) -> Advanced {
        let start = world.clock.now.seconds, balance = world.economy.balance
        if world.clock.isPaused { session.togglePause() }
        let tenths = world.clock.speed.tenthsPerTick
        var left = seconds
        while left > 0 {
            let chunk = min(left, GameTime.secondsPerDay)
            let ticks = Int((chunk * 10 + tenths - 1) / tenths)
            let before = world.clock.now.seconds
            session.advance(ticks: ticks)
            let ran = world.clock.now.seconds - before
            // Game time at its limit: GameCore refused the step.
            guard ran > 0 else { break }
            left -= ran
        }
        return Advanced(
            seconds: world.clock.now.seconds - start, day: world.clock.now.seconds / GameTime.secondsPerDay,
            balanceChange: (world.economy.balance - balance).amount / 100
        )
    }

    // MARK: - Scripted play

    /// What `play` did (decision 261): each day's numbers and what went
    /// wrong.
    public struct Played: Codable, Hashable, Sendable {
        public struct Day: Codable, Hashable, Sendable {
            public var day: Int64
            /// Whole dollars at the end of the day.
            public var balance: Int64
            /// Passengers who paid a fare that day.
            public var trips: Int64
            public var deadlocked: Int
        }

        /// The trains held for a route others hold, each minute, added up,
        /// and how many times a train began to be held.
        public var heldTrainMinutes: Int
        public var holdEpisodes: Int

        public var policy: String
        public var days: [Day]
        /// Each kind of anomaly the first day it was seen.
        public var anomalies: [PlayAnomaly]
        /// How many days each kind was seen on.
        public var anomalyDays: [String: Int]
        /// Actions never run: waiting for money at the end.
        public var unbuilt: Int
    }

    /// Plays `policy` for `days` days on the world (decision 261), its
    /// actions due from the day the play starts, a minute at a time as the
    /// device plays; the session goes on from the world it ends with (its
    /// command log starts there).
    public func play(_ policy: Policy, days: Int64) throws -> Played {
        var player = PolicyPlayer(world: world, policy: policy, byMinute: true)
        var rows: [Played.Day] = []
        for _ in 0..<days {
            try player.playDay()
            let world = player.world
            rows.append(Played.Day(
                day: player.day, balance: world.economy.balance.amount / 100, trips: world.lastDayTrips(),
                deadlocked: world.deadlockedTrains().count
            ))
        }
        session = Self.session(player.world)
        return Played(
            heldTrainMinutes: player.heldTrainMinutes, holdEpisodes: player.holdEpisodes, policy: policy.name, days: rows, anomalies: player.anomalies,
            anomalyDays: Dictionary(uniqueKeysWithValues: player.anomalyDays.map { ($0.key.rawValue, $0.value) }),
            unbuilt: player.pending.count
        )
    }

    // MARK: - Reading

    /// The world summed up (``HeadlessSummary``), with only `sections`.
    public func summary(_ sections: Set<HeadlessSummary.Section> = Set(HeadlessSummary.Section.allCases)) -> HeadlessSummary {
        HeadlessSummary(world: world, sections: sections)
    }
}

/// Why a headless game could not do what it was asked.
public struct HeadlessGameError: Error, CustomStringConvertible, Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Where the app's bundled real-world data is read from (decision 260):
/// a folder with the app's files (`RailwayGameApp/Resources/RealWorld`),
/// each read once, when first needed.
@MainActor
public final class RealWorldFiles {
    public let folder: URL
    private var population: PopulationGrid?
    private var places: PlaceGrid?
    private var water: WaterGrid?
    private var heights: HeightGrid?
    private var coverage: CoverageGrid?

    public init(folder: URL) {
        self.folder = folder
    }

    /// The bytes of the bundled file `name`.
    public func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appendingPathComponent(name))
    }

    /// The bundled places, with the land no one lives on when the folder
    /// has it (decision 385 (續), as the app reads them).
    private func bundledPlaces() throws -> PlaceGrid {
        var places = try PlaceGrid(data: data("taiwan_places.json"))
        places.noBuild = try? RealNoBuildLand(data: data("taiwan_no_build.json"))
        return places
    }

    /// The bundled people and places of Taiwan, read once.
    func peopleAndPlaces() throws -> (PopulationGrid, PlaceGrid) {
        population = try population ?? PopulationGrid(data: data("taiwan_population.json"))
        places = try places ?? bundledPlaces()
        return (population!, places!)
    }

    /// Gives `session` the data `set` names that it does not have yet.
    func install(_ set: RealWorldDataSet, in session: GameSession) throws {
        if set.population, session.population == nil {
            population = try population ?? PopulationGrid(data: data("taiwan_population.json"))
            session.population = population
        }
        if set.places, session.places == nil {
            places = try places ?? bundledPlaces()
            session.places = places
        }
        if set.water, session.water == nil {
            water = try water ?? WaterGrid(data: data("taiwan_water.json"))
            session.water = water
        }
        if set.heights, session.heights == nil {
            heights = try heights ?? HeightGrid(data: data("taiwan_heights.dat"))
            session.heights = heights
        }
        if set.coverage, session.coverage == nil {
            coverage = try coverage ?? CoverageGrid(data: data("taiwan_coverage.dat"))
            session.coverage = coverage
        }
    }
}

/// A world summed up for a tool (decision 260): money, trips, trains,
/// lines, stations, deadlocks and the challenge, as plain values a JSON
/// encoder writes. Money is in whole dollars, rounded down.
public struct HeadlessSummary: Codable, Hashable, Sendable {
    public enum Section: String, CaseIterable, Codable, Sendable {
        case economy, trains, lines, stations, deadlock, goals
    }

    public struct Clock: Codable, Hashable, Sendable {
        public var seconds: Int64
        public var day: Int64
        public var speed: String
    }

    public struct Economy: Codable, Hashable, Sendable {
        public var balance: Int64
        public var loan: Int64
        /// The last day closed: its index and totals; `nil` before any.
        public var lastDay: Day?
    }

    public struct Day: Codable, Hashable, Sendable {
        public var day: Int64
        public var fares: Int64
        public var costs: Int64
        public var operatingResult: Int64
        /// Passengers who paid a fare that day.
        public var trips: Int64
    }

    public struct Train: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var line: Int?
        public var cars: Int
        /// `unplaced`, `idle` (placed, no service), `atStop` or `running`.
        public var state: String
        /// The station it stands at or last left, in service.
        public var station: Int?
        public var deadlocked: Bool
    }

    public struct Line: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var stops: [Int]
        public var trains: Int
    }

    public struct Station: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var dailyTrips: Int64
        public var waiting: Int64
    }

    public struct Goals: Codable, Hashable, Sendable {
        public var scenario: String
        /// Each goal's title and the day it was met, if it was.
        public var goals: [Goal]
        /// `completed`, `failed`, or `nil` while it runs.
        public var outcome: String?
    }

    public struct Goal: Codable, Hashable, Sendable {
        public var title: String
        public var metOnDay: Int64?
    }

    public var clock: Clock
    public var economy: Economy?
    public var trains: [Train]?
    public var lines: [Line]?
    public var stations: [Station]?
    /// The trains only waiting for each other (traffic control, decision 58).
    public var deadlocked: [Int]?
    public var goals: Goals?

    public init(world: GameWorld, sections: Set<Section> = Set(Section.allCases)) {
        let dollars = { (money: Money) in money.amount / 100 }
        clock = Clock(seconds: world.clock.now.seconds, day: world.clock.now.seconds / GameTime.secondsPerDay, speed: world.clock.speed.rawValue)
        let deadlocked = Set(world.deadlockedTrains())
        if sections.contains(.economy) {
            let last = world.accounts.days.last
            economy = Economy(
                balance: dollars(world.economy.balance), loan: dollars(world.accounts.loan),
                lastDay: last.map { day in
                    Day(
                        day: day.day, fares: dollars(day.fareRevenue), costs: dollars(day.totalCost),
                        operatingResult: dollars(StationMasterAdvice.operatingResult(on: day)), trips: day.fareTrips
                    )
                }
            )
        }
        if sections.contains(.trains) {
            trains = world.trains.map { train in
                let state: String
                var station: StationID?
                switch train.execution {
                case .waitingAtStop(let stop, _)?:
                    state = "atStop"
                    station = train.timetable.indices.contains(stop) ? train.timetable[stop].station : nil
                case .travellingToStop(let stop, _)?:
                    state = "running"
                    let left = stop > 0 ? stop - 1 : train.timetable.count - 1
                    station = train.timetable.indices.contains(left) ? train.timetable[left].station : nil
                case nil:
                    state = train.position == nil ? "unplaced" : "idle"
                }
                return Train(
                    id: train.id.rawValue, name: train.name, line: world.assignedLine(of: train.id)?.rawValue, cars: train.cars,
                    state: state, station: station?.rawValue, deadlocked: deadlocked.contains(train.id)
                )
            }
        }
        if sections.contains(.lines) {
            lines = world.lines.map { line in
                Line(
                    id: line.id.rawValue, name: line.name, stops: line.stops.map(\.rawValue),
                    trains: world.trains.count { world.assignedLine(of: $0.id) == line.id }
                )
            }
        }
        if sections.contains(.stations) {
            stations = world.stations.map { station in
                let record = world.passengers.first { $0.station == station.id }
                return Station(
                    id: station.id.rawValue, name: station.name, dailyTrips: world.stationDemand(of: station.id)?.dailyTrips ?? 0,
                    waiting: record?.waitingCount ?? 0
                )
            }
        }
        if sections.contains(.deadlock) {
            self.deadlocked = deadlocked.map(\.rawValue).sorted()
        }
        if sections.contains(.goals), let state = world.scenario {
            let progress = world.goalProgress(in: .english)
            let outcome: String? = switch state.outcome {
            case .completed?: "completed"
            case .failed?: "failed"
            case nil: nil
            }
            goals = Goals(
                scenario: state.scenario.id,
                goals: progress.map { Goal(title: $0.title, metOnDay: $0.metOnDay) },
                outcome: outcome
            )
        }
    }
}
