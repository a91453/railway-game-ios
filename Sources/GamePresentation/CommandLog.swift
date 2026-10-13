import GameCore

/// The commands that reached the world since the game was loaded or begun
/// (ARCHITECTURE decision 193): where it started, and every change since,
/// in order, with the game time it came at. A problem report can carry it
/// (``CommandLogReport``), and a test on Linux replays it through a
/// session as the device ran it, so a bug met on the iPhone becomes a
/// regression test.
///
/// ``GameSession`` keeps it, and writes to it only where the world
/// changes: a command (``GameSession/perform(_:caller:message:)``), an edit
/// still made as a closure (logged as ``Action/unrecorded(_:)``), game time
/// put in place, the speed, Undo and Redo, and land read in. Its
/// ``GameSession/world`` observer logs any other change as not recorded,
/// so the log never leaves one out unseen.
///
/// It holds at most ``limit`` entries: on reaching it, the world as it was
/// after the oldest half becomes the start, and that half goes. So it keeps
/// between half the limit and the limit, and two worlds besides the one
/// played (the start and the next start), whose unchanged parts they share.
///
/// The reference keeps the same (`docs/debugging_desyncs.md`): a save when
/// the game begins and `commands-out.log`, every command with its date.
public struct CommandLog: Sendable {
    /// 5,000 entries; game time running on is one entry until something
    /// else happens.
    public static let limit = 5_000

    /// What the log starts from.
    public private(set) var start: GameWorld
    /// The real-world data the session had then.
    public private(set) var startData: RealWorldDataSet
    public private(set) var entries: [Entry] = []
    /// The world after the first ``limit``/2 entries, the data then, and
    /// their count: the next ``start``.
    private var halfway: (world: GameWorld, data: RealWorldDataSet, count: Int)?

    public init(start: GameWorld, data: RealWorldDataSet = RealWorldDataSet()) {
        self.start = start
        self.startData = data
    }

    /// One change of the world, or a command it refused.
    public struct Entry: Hashable, Sendable {
        /// The game time it came at, in seconds.
        public var time: Int64
        public var action: Action
        /// Whether the world refused it: it changed nothing, but is logged
        /// in its place.
        public var refused: Bool

        public init(time: Int64, action: Action, refused: Bool = false) {
            self.time = time
            self.action = action
            self.refused = refused
        }
    }

    public enum Action: Hashable, Sendable {
        case command(PlayerCommand)
        /// Ticks of game time put in place (not those worked out and
        /// dropped because a command came first, decision 143).
        case advance(ticks: Int)
        case setSpeed(GameSpeed)
        case pause
        case resume
        case undo
        case redo
        /// ``GameSession/readLandRoundStations()``, with the data the
        /// session had then: a game's data arrives when the app has read it,
        /// at the start or later (``GameLauncher``).
        case readLandRoundStations(RealWorldDataSet)
        /// The land under a building's site (decision 95).
        case readLand(reach: Int64, at: PlanPoint)
        /// A change with no value yet: the function that made it. A replay
        /// stops before it.
        case unrecorded(String)
    }

    /// The real-world data the session had when it last read land round
    /// its stations, or at the start.
    var lastData: RealWorldDataSet {
        for entry in entries.reversed() {
            if case .readLandRoundStations(let data) = entry.action { return data }
        }
        return startData
    }

    /// Adds `entry`, made in `world` as it is after it, with `data`; game
    /// time running on joins the entry before it if that was game time too.
    mutating func append(_ entry: Entry, now world: GameWorld, data: RealWorldDataSet) {
        // Not into the entry the next start was taken after.
        if case .advance(let ticks) = entry.action, entries.count > halfway?.count ?? 0,
           let last = entries.last, case .advance(let before) = last.action, !last.refused {
            entries[entries.count - 1].action = .advance(ticks: before + ticks)
        } else {
            entries.append(entry)
        }
        if entries.count == Self.limit / 2, halfway == nil {
            halfway = (world, data, entries.count)
        } else if entries.count >= Self.limit, let halfway {
            start = halfway.world
            startData = halfway.data
            entries.removeFirst(halfway.count)
            self.halfway = (world, data, entries.count)
        }
    }
}

/// Which of the app's real-world data a session had (``GameSession/population``
/// and the others).
public struct RealWorldDataSet: Hashable, Sendable, Codable {
    public var population = false
    public var places = false
    public var water = false
    public var heights = false
    public var coverage = false

    public init(population: Bool = false, places: Bool = false, water: Bool = false, heights: Bool = false, coverage: Bool = false) {
        self.population = population
        self.places = places
        self.water = water
        self.heights = heights
        self.coverage = coverage
    }
}

// MARK: - Plain values

extension CommandLog.Entry: Codable {
    private enum CodingKeys: String, CodingKey {
        case time, action, refused, command, ticks, speed, data, reach, point, caller
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(Int64.self, forKey: .time)
        refused = try container.decodeIfPresent(Bool.self, forKey: .refused) ?? false
        let kind = try container.decode(String.self, forKey: .action)
        switch kind {
        case "command":
            // GameCore's own coding refuses values a world cannot hold, as a
            // refused command's may be: the replay stops there instead.
            if let command = try? container.decode(PlayerCommand.self, forKey: .command) {
                action = .command(command)
            } else {
                action = .unrecorded("a command this build cannot read")
            }
        case "advance": action = .advance(ticks: try container.decode(Int.self, forKey: .ticks))
        case "setSpeed": action = .setSpeed(try container.decode(GameSpeed.self, forKey: .speed))
        case "pause": action = .pause
        case "resume": action = .resume
        case "undo": action = .undo
        case "redo": action = .redo
        case "readLandRoundStations": action = .readLandRoundStations(try container.decode(RealWorldDataSet.self, forKey: .data))
        case "readLand":
            let point = try container.decode([Int64].self, forKey: .point)
            guard point.count == 2 else {
                throw DecodingError.dataCorruptedError(forKey: .point, in: container, debugDescription: "A plan point is x and y.")
            }
            action = .readLand(reach: try container.decode(Int64.self, forKey: .reach), at: PlanPoint(x: point[0], y: point[1]))
        case "unrecorded": action = .unrecorded(try container.decode(String.self, forKey: .caller))
        default:
            throw DecodingError.dataCorruptedError(forKey: .action, in: container, debugDescription: "Unknown action \(kind).")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time, forKey: .time)
        if refused { try container.encode(true, forKey: .refused) }
        try container.encode(action.name, forKey: .action)
        switch action {
        case .command(let command): try container.encode(command, forKey: .command)
        case .advance(let ticks): try container.encode(ticks, forKey: .ticks)
        case .setSpeed(let speed): try container.encode(speed, forKey: .speed)
        case .pause, .resume, .undo, .redo: break
        case .readLandRoundStations(let data): try container.encode(data, forKey: .data)
        case .readLand(let reach, let point):
            try container.encode(reach, forKey: .reach)
            try container.encode([point.x, point.y], forKey: .point)
        case .unrecorded(let caller): try container.encode(caller, forKey: .caller)
        }
    }
}

extension CommandLog.Action {
    /// How the log writes its kind.
    public var name: String {
        switch self {
        case .command: "command"
        case .advance: "advance"
        case .setSpeed: "setSpeed"
        case .pause: "pause"
        case .resume: "resume"
        case .undo: "undo"
        case .redo: "redo"
        case .readLandRoundStations: "readLandRoundStations"
        case .readLand: "readLand"
        case .unrecorded: "unrecorded"
        }
    }
}
