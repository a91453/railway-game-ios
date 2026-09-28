import Foundation
import GameCore

// The Swift reader and runner for the portable golden scenarios in
// GoldenScenarios/ at the repository root. The schema is documented in
// GoldenScenarios/README.md; this file is the reference implementation of it.
//
// Only the public GameCore API is used: the same commands and read-only state
// a GameSession has. Every fixture value (integers, speed and direction names,
// commands, results, observations) is spelled out here rather than borrowed
// from a GameCore type's Codable form, so changing the Swift save format can
// never change what a fixture means.

/// A checked-in scenario: a starting world, steps in order (commands with the
/// outcome each one must have, and read-only observations with the answer
/// each one must give), and the state the world must end in.
struct GoldenScenario: Decodable {
    static let schemaVersion = 2

    var description: String
    var initialState: InitialState
    var steps: [Step]
    var expectedFinalState: WorldSummary

    struct InitialState: Decodable {
        var mapWidth: Int
        var mapHeight: Int
        var balance: Int64
        var costs: Costs
        var gameMinutes: Int64
        var speed: SpeedName

        func makeWorld() throws(GameError) -> GameWorld {
            try GameWorld(
                width: mapWidth,
                height: mapHeight,
                economy: GameEconomy(balance: Money(balance), costs: costs.constructionCosts),
                clock: GameClock(now: GameTime(minutes: gameMinutes), speed: speed.speed)
            )
        }
    }

    struct Costs: Decodable {
        var track: Int64
        var station: Int64
        var train: Int64

        var constructionCosts: ConstructionCosts {
            ConstructionCosts(track: Money(track), station: Money(station), train: Money(train))
        }

        private enum CodingKeys: String, CodingKey {
            case track, station, train
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func cost(_ key: CodingKeys) throws -> Int64 {
                let cost = try container.decode(Int64.self, forKey: key)
                // GameCore treats spending a negative amount as a programming error.
                guard cost >= 0 else {
                    throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Costs must not be negative.")
                }
                return cost
            }
            track = try cost(.track)
            station = try cost(.station)
            train = try cost(.train)
        }
    }

    /// One step: a command and the outcome it must have, or a read-only
    /// observation of the world at that point and the answer it must give.
    enum Step: Equatable {
        case command(ScenarioCommand, expect: StepOutcome)
        case observe(ScenarioObservation, expect: ObservationAnswer)
    }

    enum FixtureError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
    }

    /// Decodes a fixture, rejecting schema versions this reader does not know
    /// before looking at anything else.
    static func decode(_ data: Data) throws -> GoldenScenario {
        struct Header: Decodable {
            var schemaVersion: Int
        }
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        guard version == schemaVersion else { throw FixtureError.unsupportedSchemaVersion(version) }
        return try JSONDecoder().decode(GoldenScenario.self, from: data)
    }

    /// Runs the scenario on a new world and describes every way the result
    /// differs from the committed expectations. Empty means the scenario passed.
    ///
    /// Only reads the fixture: expectations are never written back, so a
    /// behavior change has to be made to the fixture by hand and reviewed.
    func differences() -> [String] {
        var world: GameWorld
        do throws(GameError) {
            world = try initialState.makeWorld()
        } catch {
            return ["initialState was rejected: \(compactJSON(StepOutcome.rejected(error)))"]
        }

        var differences: [String] = []
        for (index, step) in steps.enumerated() {
            switch step {
            case .command(let command, let expect):
                let before = world
                let outcome = command.apply(to: &world)
                if outcome != expect {
                    differences.append("steps[\(index)]: expected \(compactJSON(expect)), got \(compactJSON(outcome))")
                }
                if case .rejected = outcome, world != before {
                    differences.append("steps[\(index)]: the rejected command changed the world")
                }
            case .observe(let observation, let expect):
                let answer = observation.answer(in: world)
                if answer != expect {
                    differences.append("steps[\(index)]: expected \(compactJSON(expect)), got \(compactJSON(answer))")
                }
            }
        }

        let finalState = WorldSummary(world)
        if finalState != expectedFinalState {
            differences.append("""
                expectedFinalState differs.
                expected: \(compactJSON(expectedFinalState))
                actual:   \(compactJSON(finalState))
                """)
        }
        return differences
    }
}

extension GoldenScenario.Step: Decodable {
    private enum CodingKeys: String, CodingKey {
        case command, observe, expect
    }

    private enum AnswerKeys: String, CodingKey {
        case neighbors, connected
    }

    /// Reads `{"command", "expect"}` or `{"observe", "expect"}`. The shape of
    /// an observation's `expect` is fixed by the observation's type.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch (container.contains(.command), container.contains(.observe)) {
        case (true, false):
            self = try .command(
                container.decode(ScenarioCommand.self, forKey: .command),
                expect: container.decode(StepOutcome.self, forKey: .expect)
            )
        case (false, true):
            let observation = try container.decode(ScenarioObservation.self, forKey: .observe)
            let expect = try container.nestedContainer(keyedBy: AnswerKeys.self, forKey: .expect)
            switch observation {
            case .connectedNeighbors:
                guard !expect.contains(.connected) else {
                    throw DecodingError.dataCorruptedError(forKey: .connected, in: expect, debugDescription: "connectedNeighbors is answered by \"neighbors\" alone.")
                }
                let neighbors = try expect.decode([PositionSummary].self, forKey: .neighbors)
                self = .observe(observation, expect: .neighbors(neighbors.map(\.position)))
            case .isConnected:
                guard !expect.contains(.neighbors) else {
                    throw DecodingError.dataCorruptedError(forKey: .neighbors, in: expect, debugDescription: "isConnected is answered by \"connected\" alone.")
                }
                self = try .observe(observation, expect: .connected(expect.decode(Bool.self, forKey: .connected)))
            }
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A step needs exactly one of \"command\" and \"observe\"."
            ))
        }
    }
}

// MARK: - Commands

/// A `GameWorld` command as a scenario step, tagged by `"type"`.
enum ScenarioCommand: Equatable {
    case buildTrack(GridPosition, TrackConnections)
    case removeTrack(GridPosition)
    case buildStation(name: String, GridPosition)
    case purchaseTrain(name: String)
    case setSpeed(GameSpeed)
    case pause
    case resume
    case advance(ticks: Int)

    /// Applies the command through the matching `GameWorld` command.
    func apply(to world: inout GameWorld) -> StepOutcome {
        do throws(GameError) {
            switch self {
            case .buildTrack(let position, let connections):
                try world.buildTrack(at: position, connections: connections)
            case .removeTrack(let position):
                try world.removeTrack(at: position)
            case .buildStation(let name, let position):
                try world.buildStation(named: name, at: position)
            case .purchaseTrain(let name):
                try world.purchaseTrain(named: name)
            case .setSpeed(let speed):
                world.setSpeed(speed)
            case .pause:
                world.pause()
            case .resume:
                world.resume()
            case .advance(let ticks):
                world.advance(ticks: ticks)
            }
            return .ok
        } catch {
            return .rejected(error)
        }
    }
}

extension ScenarioCommand: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, x, y, connections, name, speed, ticks
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "buildTrack":
            let connections = try container.decode(Directions.self, forKey: .connections)
            self = try .buildTrack(container.decodePosition(x: .x, y: .y), connections.connections)
        case "removeTrack":
            self = try .removeTrack(container.decodePosition(x: .x, y: .y))
        case "buildStation":
            self = try .buildStation(name: container.decode(String.self, forKey: .name), container.decodePosition(x: .x, y: .y))
        case "purchaseTrain":
            self = try .purchaseTrain(name: container.decode(String.self, forKey: .name))
        case "setSpeed":
            self = try .setSpeed(container.decode(SpeedName.self, forKey: .speed).speed)
        case "pause":
            self = .pause
        case "resume":
            self = .resume
        case "advance":
            let ticks = try container.decode(Int.self, forKey: .ticks)
            // GameCore treats a negative tick count as a programming error.
            guard ticks >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .ticks, in: container, debugDescription: "Ticks must not be negative.")
            }
            self = .advance(ticks: ticks)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown command type \"\(type)\".")
        }
    }
}

// MARK: - Outcomes

/// What one command did: succeeded, or was rejected with a `GameError`.
/// Encoded as `{"result": "ok"}` or `{"result": "<error>", ...error data}`.
enum StepOutcome: Equatable {
    case ok
    case rejected(GameError)
}

extension StepOutcome: Codable {
    private enum CodingKeys: String, CodingKey {
        case result, x, y, width, height, required, available
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let result = try container.decode(String.self, forKey: .result)
        switch result {
        case "ok":
            self = .ok
        case "invalidMapSize":
            let width = try container.decode(Int.self, forKey: .width)
            self = try .rejected(.invalidMapSize(width: width, height: container.decode(Int.self, forKey: .height)))
        case "outOfBounds":
            self = try .rejected(.outOfBounds(container.decodePosition(x: .x, y: .y)))
        case "tileOccupied":
            self = try .rejected(.tileOccupied(container.decodePosition(x: .x, y: .y)))
        case "invalidTrackConnections":
            self = .rejected(.invalidTrackConnections)
        case "invalidName":
            self = .rejected(.invalidName)
        case "insufficientFunds":
            let required = try Money(container.decode(Int64.self, forKey: .required))
            self = try .rejected(.insufficientFunds(required: required, available: Money(container.decode(Int64.self, forKey: .available))))
        case "noTrackToRemove":
            self = try .rejected(.noTrackToRemove(container.decodePosition(x: .x, y: .y)))
        default:
            throw DecodingError.dataCorruptedError(forKey: .result, in: container, debugDescription: "Unknown result \"\(result)\".")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        func encode(_ position: GridPosition) throws {
            try container.encode(position.x, forKey: .x)
            try container.encode(position.y, forKey: .y)
        }
        // Exhaustive on purpose: a new GameError case must be given a
        // portable name here before the tests compile again.
        switch self {
        case .ok:
            try container.encode("ok", forKey: .result)
        case .rejected(.invalidMapSize(let width, let height)):
            try container.encode("invalidMapSize", forKey: .result)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
        case .rejected(.outOfBounds(let position)):
            try container.encode("outOfBounds", forKey: .result)
            try encode(position)
        case .rejected(.tileOccupied(let position)):
            try container.encode("tileOccupied", forKey: .result)
            try encode(position)
        case .rejected(.invalidTrackConnections):
            try container.encode("invalidTrackConnections", forKey: .result)
        case .rejected(.invalidName):
            try container.encode("invalidName", forKey: .result)
        case .rejected(.insufficientFunds(let required, let available)):
            try container.encode("insufficientFunds", forKey: .result)
            try container.encode(required.amount, forKey: .required)
            try container.encode(available.amount, forKey: .available)
        case .rejected(.noTrackToRemove(let position)):
            try container.encode("noTrackToRemove", forKey: .result)
            try encode(position)
        }
    }
}

// MARK: - Observations

/// A read-only track topology query as a scenario step, tagged by `"type"`.
/// Observations are not commands: they ask the world through its public
/// queries and never change it.
enum ScenarioObservation: Equatable {
    case connectedNeighbors(GridPosition)
    case isConnected(GridPosition, to: GridPosition)

    func answer(in world: GameWorld) -> ObservationAnswer {
        switch self {
        case .connectedNeighbors(let position):
            .neighbors(world.connectedNeighbors(of: position))
        case .isConnected(let position, let other):
            .connected(world.isConnected(position, to: other))
        }
    }
}

extension ScenarioObservation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, x, y, from, to
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "connectedNeighbors":
            self = try .connectedNeighbors(container.decodePosition(x: .x, y: .y))
        case "isConnected":
            let from = try container.decode(PositionSummary.self, forKey: .from)
            self = try .isConnected(from.position, to: container.decode(PositionSummary.self, forKey: .to).position)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown observation type \"\(type)\".")
        }
    }
}

/// What an observation answered. Encoded as `{"neighbors": [{"x", "y"}, ...]}`
/// in the order the query returned them, or `{"connected": true|false}`.
enum ObservationAnswer: Equatable {
    case neighbors([GridPosition])
    case connected(Bool)
}

extension ObservationAnswer: Encodable {
    private enum CodingKeys: String, CodingKey {
        case neighbors, connected
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .neighbors(let positions):
            try container.encode(positions.map(PositionSummary.init), forKey: .neighbors)
        case .connected(let connected):
            try container.encode(connected, forKey: .connected)
        }
    }
}

/// A grid position as `{"x": ..., "y": ...}`.
struct PositionSummary: Codable, Equatable {
    var x: Int
    var y: Int

    init(_ position: GridPosition) {
        x = position.x
        y = position.y
    }

    var position: GridPosition {
        GridPosition(x: x, y: y)
    }
}

// MARK: - Final state

/// The externally meaningful state of a world: time, money and what has been
/// built or bought. Lists are in the contract's canonical order (stations and
/// trains by ascending ID, tracks row by row from the north-west corner),
/// sorted here rather than inherited from how GameCore stores them.
struct WorldSummary: Codable, Equatable {
    var gameMinutes: Int64
    var speed: SpeedName
    var balance: Int64
    var stations: [StationSummary]
    var tracks: [TrackSummary]
    var trains: [TrainSummary]

    struct StationSummary: Codable, Equatable {
        var id: Int
        var name: String
        var x: Int
        var y: Int
    }

    struct TrackSummary: Codable, Equatable {
        var x: Int
        var y: Int
        var connections: Directions
    }

    struct TrainSummary: Codable, Equatable {
        var id: Int
        var name: String
    }

    init(_ world: GameWorld) {
        gameMinutes = world.clock.now.minutes
        speed = SpeedName(world.clock.speed)
        balance = world.economy.balance.amount
        stations = world.stations
            .map { StationSummary(id: $0.id.rawValue, name: $0.name, x: $0.position.x, y: $0.position.y) }
            .sorted { $0.id < $1.id }
        tracks = world.tracks
            .map { TrackSummary(x: $0.position.x, y: $0.position.y, connections: Directions($0.connections)) }
            .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        trains = world.trains
            .map { TrainSummary(id: $0.id.rawValue, name: $0.name) }
            .sorted { $0.id < $1.id }
    }
}

// MARK: - Names

/// A game speed as its fixture name: `"paused"`, `"normal"` or `"double"`.
struct SpeedName: Codable, Equatable {
    var speed: GameSpeed

    init(_ speed: GameSpeed) {
        self.speed = speed
    }

    private static func name(of speed: GameSpeed) -> String {
        switch speed {
        case .paused: "paused"
        case .normal: "normal"
        case .double: "double"
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let speed = GameSpeed.allCases.first(where: { Self.name(of: $0) == name }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown speed \"\(name)\".")
        }
        self.speed = speed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.name(of: speed))
    }
}

/// Track connections as a JSON array of direction names. Order does not
/// matter when reading; writing uses north, east, south, west.
struct Directions: Codable, Equatable {
    var connections: TrackConnections

    init(_ connections: TrackConnections) {
        self.connections = connections
    }

    private static func name(of direction: TrackDirection) -> String {
        switch direction {
        case .north: "north"
        case .east: "east"
        case .south: "south"
        case .west: "west"
        }
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var connections: TrackConnections = []
        while !container.isAtEnd {
            let name = try container.decode(String.self)
            guard let direction = TrackDirection.allCases.first(where: { Self.name(of: $0) == name }) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown direction \"\(name)\".")
            }
            guard connections.insert(TrackConnections(direction)).inserted else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Direction \"\(name)\" is listed twice.")
            }
        }
        self.connections = connections
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for direction in connections.directions {
            try container.encode(Self.name(of: direction))
        }
    }
}

extension KeyedDecodingContainer {
    /// A grid position stored as two flat integer fields.
    fileprivate func decodePosition(x: Key, y: Key) throws -> GridPosition {
        try GridPosition(x: decode(Int.self, forKey: x), y: decode(Int.self, forKey: y))
    }
}

// MARK: - Fixture files

enum GoldenScenarioFixtures {
    /// `GoldenScenarios/` at the repository root, found from this source file.
    /// The fixtures are deliberately not a SwiftPM resource: they belong to no
    /// Swift target, so any language's test runner can read them in place.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // GameCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("GoldenScenarios", isDirectory: true)

    /// Every fixture file, sorted by name.
    static func urls() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The largest integer magnitude every JSON reader represents exactly,
    /// including ones that read all numbers as doubles (2^53 − 1).
    static let largestPortableInteger: Int64 = 9_007_199_254_740_991

    /// Every number in the JSON `text` that is not a plain integer within
    /// ±``largestPortableInteger``. Swift's `JSONDecoder` accepts `1.0`, `1e2`
    /// and larger integers; other languages' readers may reject them or round
    /// them, so fixtures avoid them.
    static func nonPortableNumbers(in text: String) -> [String] {
        let digits: ClosedRange<Unicode.Scalar> = "0"..."9"
        var found: [String] = []
        var number = String.UnicodeScalarView()
        var inString = false
        var escaped = false
        func finishNumber() {
            if !number.isEmpty, !isPortableInteger(String(number)) {
                found.append(String(number))
            }
            number = String.UnicodeScalarView()
        }
        // Scalars rather than Characters: a quote followed by a combining mark
        // is a single Character but still opens or closes a string.
        for scalar in text.unicodeScalars {
            if inString {
                if escaped {
                    escaped = false
                } else if scalar == "\\" {
                    escaped = true
                } else if scalar == "\"" {
                    inString = false
                }
                continue
            }
            // A JSON number starts with "-" or a digit and may continue with
            // digits, ".", "e", "E", "+" and "-".
            if digits.contains(scalar) || scalar == "-" || (!number.isEmpty && "+.eE".unicodeScalars.contains(scalar)) {
                number.append(scalar)
            } else {
                finishNumber()
                inString = scalar == "\""
            }
        }
        finishNumber()
        return found
    }

    private static func isPortableInteger(_ number: String) -> Bool {
        let digits = number.hasPrefix("-") ? number.dropFirst() : Substring(number)
        guard !digits.isEmpty,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              digits == "0" || !digits.hasPrefix("0"),
              let value = Int64(number)
        else { return false }
        return value.magnitude <= largestPortableInteger.magnitude
    }
}

/// Compact JSON with sorted keys, for failure messages that can be compared
/// against (and, after review, copied into) a fixture.
private func compactJSON(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value) else { return "\(value)" }
    return String(decoding: data, as: UTF8.self)
}
