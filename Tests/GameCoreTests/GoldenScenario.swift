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
    static let schemaVersion = 17

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

    fileprivate enum AnswerKeys: String, CodingKey, CaseIterable {
        case neighbors, connected, position, movement, found, route, platforms, stations, timetable, execution
        case level, journey, trains, minutes, loads, exits, resources, conflicts, sections, tracks, platformTracks
        case edge, location, transitions, path, points
        case pose, alignment, nodes, trackPlatforms, levels
    }

    /// Reads `{"command", "expect"}` or `{"observe", "expect"}`. The shape of
    /// an observation's `expect` is fixed by the observation's type; an
    /// answer field that belongs to another type is rejected.
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
            func requireOnly(_ keys: [AnswerKeys], answering type: String) throws {
                for key in AnswerKeys.allCases where !keys.contains(key) && expect.contains(key) {
                    throw DecodingError.dataCorruptedError(forKey: key, in: expect, debugDescription: "\(type) is not answered by \"\(key.stringValue)\".")
                }
            }
            switch observation {
            case .connectedNeighbors:
                try requireOnly([.neighbors], answering: "connectedNeighbors")
                let neighbors = try expect.decode([PositionSummary].self, forKey: .neighbors)
                self = .observe(observation, expect: .neighbors(neighbors.map(\.position)))
            case .isConnected:
                try requireOnly([.connected], answering: "isConnected")
                self = try .observe(observation, expect: .connected(expect.decode(Bool.self, forKey: .connected)))
            case .train:
                try requireOnly([.position, .movement], answering: "train")
                let state = try TrainState(
                    position: expect.decode(TrainPositionSummary.self, forKey: .position),
                    movement: expect.decode(TrainMovementSummary.self, forKey: .movement)
                )
                self = .observe(observation, expect: .train(state))
            case .route, .routeToStation:
                try requireOnly([.found, .route], answering: "a route")
                // "route" is required when a route is found and absent when not.
                if try expect.decode(Bool.self, forKey: .found) {
                    let nodes = try expect.decode([PositionSummary].self, forKey: .route)
                    self = .observe(observation, expect: .route(nodes.map(\.position)))
                } else {
                    guard !expect.contains(.route) else {
                        throw DecodingError.dataCorruptedError(forKey: .route, in: expect, debugDescription: "A route that is not found has no \"route\".")
                    }
                    self = .observe(observation, expect: .route(nil))
                }
            case .platforms:
                try requireOnly([.platforms], answering: "platforms")
                let platforms = try expect.decode([PositionSummary].self, forKey: .platforms)
                self = .observe(observation, expect: .platforms(platforms.map(\.position)))
            case .stationStops, .wholeTrainStops:
                try requireOnly([.stations], answering: "a train's stops")
                let stations = try expect.decode([Int].self, forKey: .stations)
                self = .observe(observation, expect: .stations(stations.map(StationID.init(rawValue:))))
            case .timetable:
                try requireOnly([.timetable], answering: "timetable")
                let stops = try expect.decode([StopSummary].self, forKey: .timetable)
                self = .observe(observation, expect: .timetable(stops.map(\.stop)))
            case .execution:
                try requireOnly([.execution], answering: "execution")
                self = try .observe(observation, expect: .execution(expect.decode(ExecutionSummary.self, forKey: .execution)))
            case .serviceLevel:
                try requireOnly([.level], answering: "serviceLevel")
                let name = try expect.decode(String.self, forKey: .level)
                guard name == "closed" || ServiceLevel(rawValue: name) != nil else {
                    throw DecodingError.dataCorruptedError(forKey: .level, in: expect, debugDescription: "Unknown service level \"\(name)\".")
                }
                self = .observe(observation, expect: .level(ServiceLevel(rawValue: name)))
            case .lineJourney:
                try requireOnly([.found, .journey], answering: "lineJourney")
                self = try .observe(observation, expect: .journey(Self.found(expect, .journey, JourneySummary.self)))
            case .lineMaximumTrains, .lineTrainsInService:
                try requireOnly([.found, .trains], answering: "a line's trains")
                self = try .observe(observation, expect: .trains(Self.found(expect, .trains, Int.self)))
            case .lineHeadway:
                try requireOnly([.found, .minutes], answering: "lineHeadway")
                self = try .observe(observation, expect: .minutes(Self.found(expect, .minutes, Int64.self)))
            case .lineSegmentLoads:
                try requireOnly([.found, .loads], answering: "lineSegmentLoads")
                self = try .observe(observation, expect: .loads(Self.found(expect, .loads, [Int].self)))
            case .exits:
                try requireOnly([.exits], answering: "exits")
                self = try .observe(observation, expect: .exits(expect.decode([PositionSummary].self, forKey: .exits).map(\.position)))
            case .occupancy:
                try requireOnly([.resources], answering: "occupancy")
                self = try .observe(observation, expect: .resources(expect.decode([ResourceSummary].self, forKey: .resources).map(\.resource)))
            case .conflicts:
                try requireOnly([.conflicts], answering: "conflicts")
                self = try .observe(observation, expect: .conflicts(expect.decode([ConflictSummary].self, forKey: .conflicts).map(\.conflict)))
            case .trackSections:
                try requireOnly([.sections], answering: "trackSections")
                self = try .observe(observation, expect: .sections(expect.decode([SectionSummary].self, forKey: .sections).map(\.section)))
            case .parallelTracks:
                try requireOnly([.tracks], answering: "parallelTracks")
                self = try .observe(observation, expect: .tracks(expect.decode(Int.self, forKey: .tracks)))
            case .platformTracks:
                try requireOnly([.platformTracks], answering: "platformTracks")
                let tracks = try expect.decode([[PositionSummary]].self, forKey: .platformTracks)
                self = .observe(observation, expect: .platformTracks(tracks.map { $0.map(\.position) }))
            case .trackEdge:
                try requireOnly([.found, .edge], answering: "trackEdge")
                self = try .observe(observation, expect: .edge(Self.found(expect, .edge, EdgeInfoSummary.self)))
            case .edgeLocation:
                try requireOnly([.found, .location], answering: "edgeLocation")
                self = try .observe(observation, expect: .location(Self.found(expect, .location, LocationSummary.self)))
            case .transitions:
                try requireOnly([.transitions], answering: "transitions")
                self = try .observe(observation, expect: .transitions(expect.decode([TraversalSummary].self, forKey: .transitions).map(\.traversal)))
            case .pathToNode:
                try requireOnly([.found, .path], answering: "pathToNode")
                self = try .observe(observation, expect: .path(Self.found(expect, .path, [TraversalSummary].self)?.map(\.traversal)))
            case .bodyPath:
                try requireOnly([.points], answering: "bodyPath")
                self = try .observe(observation, expect: .points(expect.decode([PointSummary].self, forKey: .points).map(\.point)))
            case .edgePose:
                try requireOnly([.found, .pose], answering: "edgePose")
                self = try .observe(observation, expect: .pose(Self.found(expect, .pose, PoseSummary.self)))
            case .edgeAlignment:
                try requireOnly([.found, .alignment], answering: "edgeAlignment")
                self = try .observe(observation, expect: .alignment(Self.found(expect, .alignment, AlignmentSummary.self)))
            case .tunnelPortals:
                try requireOnly([.nodes], answering: "tunnelPortals")
                self = try .observe(observation, expect: .nodes(expect.decode([Int].self, forKey: .nodes)))
            case .trackPlatformsAlongTrain:
                try requireOnly([.trackPlatforms], answering: "trackPlatformsAlongTrain")
                self = try .observe(observation, expect: .trackPlatforms(expect.decode([PlatformSummary].self, forKey: .trackPlatforms)))
            case .platformLevels:
                try requireOnly([.levels], answering: "platformLevels")
                self = try .observe(observation, expect: .levels(expect.decode([PlatformLevelSummary].self, forKey: .levels)))
            }
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "A step needs exactly one of \"command\" and \"observe\"."
            ))
        }
    }
}

extension GoldenScenario.Step {
    /// A `{"found": true, key: value}` / `{"found": false}` answer: the value
    /// is required when found and absent when not.
    private static func found<T: Decodable>(
        _ expect: KeyedDecodingContainer<AnswerKeys>,
        _ key: AnswerKeys,
        _ type: T.Type
    ) throws -> T? {
        if try expect.decode(Bool.self, forKey: .found) {
            return try expect.decode(T.self, forKey: key)
        }
        guard !expect.contains(key) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: expect, debugDescription: "An answer that is not found has no \"\(key.stringValue)\".")
        }
        return nil
    }
}

// MARK: - Commands

/// A `GameWorld` command as a scenario step, tagged by `"type"`.
enum ScenarioCommand: Equatable {
    case buildTrack(GridPosition, TrackConnections)
    case buildTurnout(GridPosition, TrackConnections, stem: TrackDirection)
    case buildCrossing(GridPosition)
    case removeTrack(GridPosition)
    case buildStation(name: String, GridPosition)
    case extendStation(StationID, GridPosition)
    case purchaseTrain(name: String)
    case setTrainCars(TrainID, Int)
    case placeTrain(TrainID, TrainPosition)
    case unplaceTrain(TrainID)
    case reverseTrain(TrainID)
    case setTrainMovementRate(TrainID, Int64)
    case setTrainContinuation(TrainID, [GridPosition])
    case setTrainTimetable(TrainID, [ScheduledStop], period: Int64?)
    case startTrainService(TrainID)
    case stopTrainService(TrainID)
    case createLine(name: String, stops: [StationID])
    case removeLine(LineID)
    case setLineStops(LineID, [StationID])
    case setLineRate(LineID, Int64)
    case setLineServiceWindow(LineID, ServiceWindow)
    case setLineTrainsInService(LineID, TrainsInService, pattern: Int?)
    case setServiceDay(ServiceDay)
    case setLineTargetHeadways(LineID, TargetHeadways, pattern: Int?)
    case assignTrain(TrainID, LineID, pattern: Int?)
    case unassignTrain(TrainID)
    case addLinePattern(LineID, calls: [Int])
    case removeLinePattern(LineID, pattern: Int)
    case setSpeed(GameSpeed)
    case pause
    case resume
    case advance(ticks: Int)
    case buildTrackNode(WorldCoordinate)
    case buildTrackEdge(TrackNodeID, TrackNodeID, TrackCurve, TrackProfile, TrackStructure)
    case removeTrackEdge(TrackEdgeID)
    case removeTrackNode(TrackNodeID)
    case setTrainPath(TrainID, [TrackTraversal])
    case addTrackPlatform(StationID, TrackEdgeID, start: Int64, end: Int64)
    case removeTrackPlatform(StationID, TrackEdgeID, start: Int64)

    /// Applies the command through the matching `GameWorld` command.
    func apply(to world: inout GameWorld) -> StepOutcome {
        do throws(GameError) {
            switch self {
            case .buildTrack(let position, let connections):
                try world.buildTrack(at: position, connections: connections)
            case .buildTurnout(let position, let connections, let stem):
                try world.buildTurnout(at: position, connections: connections, stem: stem)
            case .buildCrossing(let position):
                try world.buildCrossing(at: position)
            case .removeTrack(let position):
                try world.removeTrack(at: position)
            case .buildStation(let name, let position):
                try world.buildStation(named: name, at: position)
            case .extendStation(let id, let position):
                try world.extendStation(id, to: position)
            case .purchaseTrain(let name):
                try world.purchaseTrain(named: name)
            case .setTrainCars(let id, let cars):
                try world.setTrainCars(id, to: cars)
            case .placeTrain(let id, let position):
                try world.placeTrain(id, at: position)
            case .unplaceTrain(let id):
                try world.unplaceTrain(id)
            case .reverseTrain(let id):
                try world.reverseTrain(id)
            case .setTrainMovementRate(let id, let rate):
                try world.setTrainMovementRate(id, to: rate)
            case .setTrainContinuation(let id, let nodes):
                try world.setTrainContinuation(id, to: nodes)
            case .setTrainTimetable(let id, let stops, let period):
                try world.setTrainTimetable(id, to: stops, repeatingEvery: period)
            case .startTrainService(let id):
                try world.startTrainService(id)
            case .stopTrainService(let id):
                try world.stopTrainService(id)
            case .createLine(let name, let stops):
                try world.createLine(named: name, stops: stops)
            case .removeLine(let id):
                try world.removeLine(id)
            case .setLineStops(let id, let stops):
                try world.setLineStops(id, to: stops)
            case .setLineRate(let id, let rate):
                try world.setLineRate(id, to: rate)
            case .setLineServiceWindow(let id, let window):
                try world.setLineServiceWindow(id, to: window)
            case .setLineTrainsInService(let id, let trains, let pattern):
                try world.setLineTrainsInService(id, to: trains, pattern: pattern)
            case .setServiceDay(let day):
                try world.setServiceDay(day)
            case .setLineTargetHeadways(let id, let headways, let pattern):
                try world.setLineTargetHeadways(id, to: headways, pattern: pattern)
            case .assignTrain(let id, let line, let pattern):
                try world.assignTrain(id, to: line, pattern: pattern)
            case .unassignTrain(let id):
                try world.unassignTrain(id)
            case .addLinePattern(let id, let calls):
                try world.addLinePattern(id, calling: calls)
            case .removeLinePattern(let id, let pattern):
                try world.removeLinePattern(id, at: pattern)
            case .setSpeed(let speed):
                world.setSpeed(speed)
            case .pause:
                world.pause()
            case .resume:
                world.resume()
            case .advance(let ticks):
                try world.advance(ticks: ticks)
            case .buildTrackNode(let position):
                try world.buildTrackNode(at: position)
            case .buildTrackEdge(let from, let to, let curve, let profile, let structure):
                try world.buildTrackEdge(from: from, to: to, curve: curve, profile: profile, structure: structure)
            case .removeTrackEdge(let edge):
                try world.removeTrackEdge(edge)
            case .removeTrackNode(let node):
                try world.removeTrackNode(node)
            case .setTrainPath(let id, let path):
                try world.setTrainContinuation(id, along: path)
            case .addTrackPlatform(let station, let edge, let start, let end):
                try world.addTrackPlatform(station, on: edge, from: start, to: end)
            case .removeTrackPlatform(let station, let edge, let start):
                try world.removeTrackPlatform(station, on: edge, from: start)
            }
            return .ok
        } catch {
            return .rejected(error)
        }
    }
}

extension ScenarioCommand: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, x, y, connections, name, train, position, rate, continuation, timetable, `repeat`, speed, ticks
        case line, stops, window, trains, bands, targetHeadways, pattern, calls, stem, station, cars
        case z, from, to, curve, edge, node, path
        case profile, structure, start, end
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "buildTrack":
            let connections = try container.decode(Directions.self, forKey: .connections)
            self = try .buildTrack(container.decodePosition(x: .x, y: .y), connections.connections)
        case "buildTurnout":
            // Read as written: whether the exits make a turnout is GameCore's decision.
            let connections = try container.decode(Directions.self, forKey: .connections)
            let stem = try container.decode(DirectionName.self, forKey: .stem).direction
            self = try .buildTurnout(container.decodePosition(x: .x, y: .y), connections.connections, stem: stem)
        case "buildCrossing":
            self = try .buildCrossing(container.decodePosition(x: .x, y: .y))
        case "removeTrack":
            self = try .removeTrack(container.decodePosition(x: .x, y: .y))
        case "buildStation":
            self = try .buildStation(name: container.decode(String.self, forKey: .name), container.decodePosition(x: .x, y: .y))
        case "extendStation":
            self = try .extendStation(container.decodeStation(forKey: .station), container.decodePosition(x: .x, y: .y))
        case "purchaseTrain":
            self = try .purchaseTrain(name: container.decode(String.self, forKey: .name))
        case "setTrainCars":
            // Read as written: rejecting a count outside 0...16 is GameCore's decision.
            self = try .setTrainCars(container.decodeTrain(forKey: .train), container.decode(Int.self, forKey: .cars))
        case "placeTrain":
            let train = try container.decodeTrain(forKey: .train)
            // A placement names where to put the train; taking it off the
            // track is the separate unplaceTrain command.
            guard let position = try container.decode(TrainPositionSummary.self, forKey: .position).position else {
                throw DecodingError.dataCorruptedError(forKey: .position, in: container, debugDescription: "placeTrain needs a \"node\" or \"link\" position.")
            }
            self = .placeTrain(train, position)
        case "unplaceTrain":
            self = try .unplaceTrain(container.decodeTrain(forKey: .train))
        case "reverseTrain":
            self = try .reverseTrain(container.decodeTrain(forKey: .train))
        case "setTrainMovementRate":
            // Read as written: rejecting a negative rate is GameCore's decision.
            self = try .setTrainMovementRate(container.decodeTrain(forKey: .train), container.decode(Int64.self, forKey: .rate))
        case "setTrainContinuation":
            let nodes = try container.decode([PositionSummary].self, forKey: .continuation)
            self = try .setTrainContinuation(container.decodeTrain(forKey: .train), nodes.map(\.position))
        case "setTrainTimetable":
            // Read as written: rejecting negative or backward times, a period
            // that does not fit and unknown stations is GameCore's decision.
            let stops = try container.decode([StopSummary].self, forKey: .timetable)
            let period = try container.decode(RepeatSummary.self, forKey: .repeat).period
            self = try .setTrainTimetable(container.decodeTrain(forKey: .train), stops.map(\.stop), period: period)
        case "startTrainService":
            self = try .startTrainService(container.decodeTrain(forKey: .train))
        case "stopTrainService":
            self = try .stopTrainService(container.decodeTrain(forKey: .train))
        // Line commands are read as written: rejecting too few stops, a rate
        // below 1, a window, counts or a day that do not fit is GameCore's
        // decision.
        case "createLine":
            let stops = try container.decode([Int].self, forKey: .stops).map(StationID.init(rawValue:))
            self = try .createLine(name: container.decode(String.self, forKey: .name), stops: stops)
        case "removeLine":
            self = try .removeLine(container.decodeLine(forKey: .line))
        case "setLineStops":
            let stops = try container.decode([Int].self, forKey: .stops).map(StationID.init(rawValue:))
            self = try .setLineStops(container.decodeLine(forKey: .line), stops)
        case "setLineRate":
            self = try .setLineRate(container.decodeLine(forKey: .line), container.decode(Int64.self, forKey: .rate))
        case "setLineServiceWindow":
            self = try .setLineServiceWindow(container.decodeLine(forKey: .line), container.decode(WindowSummary.self, forKey: .window).window)
        case "setLineTrainsInService":
            let trains = try container.decode(TrainsSummary.self, forKey: .trains).trains
            self = try .setLineTrainsInService(container.decodeLine(forKey: .line), trains, pattern: container.decodePattern(forKey: .pattern))
        case "setServiceDay":
            let bands = try container.decode([BandSummary].self, forKey: .bands)
            self = .setServiceDay(ServiceDay(bands: bands.map(\.band)))
        case "setLineTargetHeadways":
            let headways = try container.decode(TargetHeadwaysSummary.self, forKey: .targetHeadways).headways
            self = try .setLineTargetHeadways(container.decodeLine(forKey: .line), headways, pattern: container.decodePattern(forKey: .pattern))
        case "assignTrain":
            let line = try container.decodeLine(forKey: .line)
            self = try .assignTrain(container.decodeTrain(forKey: .train), line, pattern: container.decodePattern(forKey: .pattern))
        case "unassignTrain":
            self = try .unassignTrain(container.decodeTrain(forKey: .train))
        case "addLinePattern":
            // Read as written: whether the calls fit the line is GameCore's decision.
            self = try .addLinePattern(container.decodeLine(forKey: .line), calls: container.decode([Int].self, forKey: .calls))
        case "removeLinePattern":
            self = try .removeLinePattern(container.decodeLine(forKey: .line), pattern: container.decode(Int.self, forKey: .pattern))
        case "setSpeed":
            self = try .setSpeed(container.decode(SpeedName.self, forKey: .speed).speed)
        case "pause":
            self = .pause
        case "resume":
            self = .resume
        // Track network commands are read as written: whether a point lies
        // on the map, a curve makes an edge or a path can be taken is
        // GameCore's decision.
        case "buildTrackNode":
            self = try .buildTrackNode(WorldCoordinate(
                x: container.decode(Int64.self, forKey: .x), y: container.decode(Int64.self, forKey: .y), z: container.decode(Int64.self, forKey: .z)
            ))
        case "buildTrackEdge":
            // Schema 17: "profile" and "structure" are absent for a uniform
            // grade on the surface.
            let profile = try container.contains(.profile) ? container.decode(ProfileSummary.self, forKey: .profile).profile : .uniform
            let structure = try container.contains(.structure) ? container.decode(StructureName.self, forKey: .structure).structure : .surface
            self = try .buildTrackEdge(
                .node(container.decode(Int.self, forKey: .from)), .node(container.decode(Int.self, forKey: .to)),
                container.decode(CurveSummary.self, forKey: .curve).curve, profile, structure
            )
        case "addTrackPlatform":
            self = try .addTrackPlatform(
                container.decodeStation(forKey: .station), .edge(container.decode(Int.self, forKey: .edge)),
                start: container.decode(Int64.self, forKey: .start), end: container.decode(Int64.self, forKey: .end)
            )
        case "removeTrackPlatform":
            self = try .removeTrackPlatform(
                container.decodeStation(forKey: .station), .edge(container.decode(Int.self, forKey: .edge)),
                start: container.decode(Int64.self, forKey: .start)
            )
        case "removeTrackEdge":
            self = try .removeTrackEdge(.edge(container.decode(Int.self, forKey: .edge)))
        case "removeTrackNode":
            self = try .removeTrackNode(.node(container.decode(Int.self, forKey: .node)))
        case "setTrainPath":
            let path = try container.decode([TraversalSummary].self, forKey: .path).map(\.traversal)
            self = try .setTrainPath(container.decodeTrain(forKey: .train), path)
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
        case result, x, y, width, height, required, available, train, station, line, pattern, node, edge
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
        case "trackInUse":
            self = try .rejected(.trackInUse(container.decodePosition(x: .x, y: .y)))
        case "unknownTrain":
            self = try .rejected(.unknownTrain(container.decodeTrain(forKey: .train)))
        case "trainAlreadyPlaced":
            self = try .rejected(.trainAlreadyPlaced(container.decodeTrain(forKey: .train)))
        case "trainNotPlaced":
            self = try .rejected(.trainNotPlaced(container.decodeTrain(forKey: .train)))
        case "invalidTrainPosition":
            self = .rejected(.invalidTrainPosition)
        case "invalidMovementRate":
            self = .rejected(.invalidMovementRate)
        case "invalidContinuation":
            self = .rejected(.invalidContinuation)
        case "clockOverflow":
            self = .rejected(.clockOverflow)
        case "idsExhausted":
            self = .rejected(.idsExhausted)
        case "invalidTimetable":
            self = .rejected(.invalidTimetable)
        case "unknownStation":
            self = try .rejected(.unknownStation(container.decodeStation(forKey: .station)))
        case "trainServiceActive":
            self = try .rejected(.trainServiceActive(container.decodeTrain(forKey: .train)))
        case "trainServiceNotActive":
            self = try .rejected(.trainServiceNotActive(container.decodeTrain(forKey: .train)))
        case "noTimetable":
            self = try .rejected(.noTimetable(container.decodeTrain(forKey: .train)))
        case "trainNotAtFirstStop":
            self = try .rejected(.trainNotAtFirstStop(container.decodeTrain(forKey: .train)))
        case "unknownLine":
            self = try .rejected(.unknownLine(container.decodeLine(forKey: .line)))
        case "invalidLineStops":
            self = .rejected(.invalidLineStops)
        case "invalidLineRate":
            self = .rejected(.invalidLineRate)
        case "invalidServiceWindow":
            self = .rejected(.invalidServiceWindow)
        case "invalidTrainsInService":
            self = .rejected(.invalidTrainsInService)
        case "invalidServiceDay":
            self = .rejected(.invalidServiceDay)
        case "invalidHeadway":
            self = .rejected(.invalidHeadway)
        case "trainOnLine":
            self = try .rejected(.trainOnLine(container.decodeTrain(forKey: .train)))
        case "trainNotOnLine":
            self = try .rejected(.trainNotOnLine(container.decodeTrain(forKey: .train)))
        case "invalidLinePattern":
            self = .rejected(.invalidLinePattern)
        case "unknownLinePattern":
            self = try .rejected(.unknownLinePattern(container.decode(Int.self, forKey: .pattern)))
        case "invalidStationTile":
            self = try .rejected(.invalidStationTile(container.decodePosition(x: .x, y: .y)))
        case "invalidTrainLength":
            self = .rejected(.invalidTrainLength)
        case "unknownTrackNode":
            self = try .rejected(.unknownTrackNode(.node(container.decode(Int.self, forKey: .node))))
        case "unknownTrackEdge":
            self = try .rejected(.unknownTrackEdge(.edge(container.decode(Int.self, forKey: .edge))))
        case "invalidTrackGeometry":
            self = .rejected(.invalidTrackGeometry)
        case "trackNodeInUse":
            self = try .rejected(.trackNodeInUse(.node(container.decode(Int.self, forKey: .node))))
        case "trackEdgeInUse":
            self = try .rejected(.trackEdgeInUse(.edge(container.decode(Int.self, forKey: .edge))))
        case "trackTooSteep":
            self = .rejected(.trackTooSteep)
        case "invalidTrackStructure":
            self = .rejected(.invalidTrackStructure)
        case "trackConflict":
            self = try .rejected(.trackConflict(.edge(container.decode(Int.self, forKey: .edge))))
        case "trackEdgeHasPlatform":
            self = try .rejected(.trackEdgeHasPlatform(.edge(container.decode(Int.self, forKey: .edge))))
        case "invalidPlatform":
            self = .rejected(.invalidPlatform)
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
        case .rejected(.trackInUse(let position)):
            try container.encode("trackInUse", forKey: .result)
            try encode(position)
        case .rejected(.unknownTrain(let id)):
            try container.encode("unknownTrain", forKey: .result)
            try container.encode(id.rawValue, forKey: .train)
        case .rejected(.trainAlreadyPlaced(let id)):
            try container.encode("trainAlreadyPlaced", forKey: .result)
            try container.encode(id.rawValue, forKey: .train)
        case .rejected(.trainNotPlaced(let id)):
            try container.encode("trainNotPlaced", forKey: .result)
            try container.encode(id.rawValue, forKey: .train)
        case .rejected(.invalidTrainPosition):
            try container.encode("invalidTrainPosition", forKey: .result)
        case .rejected(.invalidMovementRate):
            try container.encode("invalidMovementRate", forKey: .result)
        case .rejected(.invalidContinuation):
            try container.encode("invalidContinuation", forKey: .result)
        case .rejected(.clockOverflow):
            try container.encode("clockOverflow", forKey: .result)
        case .rejected(.idsExhausted):
            try container.encode("idsExhausted", forKey: .result)
        case .rejected(.invalidTimetable):
            try container.encode("invalidTimetable", forKey: .result)
        case .rejected(.unknownStation(let id)):
            try container.encode("unknownStation", forKey: .result)
            try container.encode(id.rawValue, forKey: .station)
        case .rejected(.trainServiceActive(let id)):
            try container.encode("trainServiceActive", forKey: .result)
            try container.encode(id.rawValue, forKey: .train)
        case .rejected(.trainServiceNotActive(let id)):
            try container.encode("trainServiceNotActive", forKey: .result)
            try container.encode(id.rawValue, forKey: .train)
        case .rejected(.noTimetable(let id)):
            try container.encode("noTimetable", forKey: .result)
            try container.encode(id.rawValue, forKey: .train)
        case .rejected(.trainNotAtFirstStop(let id)):
            try container.encode("trainNotAtFirstStop", forKey: .result)
            try container.encode(id.rawValue, forKey: .train)
        case .rejected(.unknownLine(let id)):
            try container.encode("unknownLine", forKey: .result)
            try container.encode(id.rawValue, forKey: .line)
        case .rejected(.invalidLineStops):
            try container.encode("invalidLineStops", forKey: .result)
        case .rejected(.invalidLineRate):
            try container.encode("invalidLineRate", forKey: .result)
        case .rejected(.invalidServiceWindow):
            try container.encode("invalidServiceWindow", forKey: .result)
        case .rejected(.invalidTrainsInService):
            try container.encode("invalidTrainsInService", forKey: .result)
        case .rejected(.invalidServiceDay):
            try container.encode("invalidServiceDay", forKey: .result)
        case .rejected(.invalidHeadway):
            try container.encode("invalidHeadway", forKey: .result)
        case .rejected(.trainOnLine(let id)):
            try container.encode("trainOnLine", forKey: .result)
            try container.encode(id.rawValue, forKey: .train)
        case .rejected(.trainNotOnLine(let id)):
            try container.encode("trainNotOnLine", forKey: .result)
            try container.encode(id.rawValue, forKey: .train)
        case .rejected(.invalidLinePattern):
            try container.encode("invalidLinePattern", forKey: .result)
        case .rejected(.unknownLinePattern(let pattern)):
            try container.encode("unknownLinePattern", forKey: .result)
            try container.encode(pattern, forKey: .pattern)
        case .rejected(.invalidStationTile(let position)):
            try container.encode("invalidStationTile", forKey: .result)
            try encode(position)
        case .rejected(.invalidTrainLength):
            try container.encode("invalidTrainLength", forKey: .result)
        case .rejected(.unknownTrackNode(let node)):
            try container.encode("unknownTrackNode", forKey: .result)
            try encodeNode(node)
        case .rejected(.unknownTrackEdge(let edge)):
            try container.encode("unknownTrackEdge", forKey: .result)
            try encodeEdge(edge)
        case .rejected(.invalidTrackGeometry):
            try container.encode("invalidTrackGeometry", forKey: .result)
        case .rejected(.trackNodeInUse(let node)):
            try container.encode("trackNodeInUse", forKey: .result)
            try encodeNode(node)
        case .rejected(.trackEdgeInUse(let edge)):
            try container.encode("trackEdgeInUse", forKey: .result)
            try encodeEdge(edge)
        case .rejected(.trackTooSteep):
            try container.encode("trackTooSteep", forKey: .result)
        case .rejected(.invalidTrackStructure):
            try container.encode("invalidTrackStructure", forKey: .result)
        case .rejected(.trackConflict(let edge)):
            try container.encode("trackConflict", forKey: .result)
            try encodeEdge(edge)
        case .rejected(.trackEdgeHasPlatform(let edge)):
            try container.encode("trackEdgeHasPlatform", forKey: .result)
            try encodeEdge(edge)
        case .rejected(.invalidPlatform):
            try container.encode("invalidPlatform", forKey: .result)
        }
        // Fixtures name network nodes and edges by number; a grid tile or
        // link cannot reach these results through a fixture's commands, but
        // is written as positions so that a failure report never traps.
        func encodeNode(_ node: TrackNodeID) throws {
            switch node {
            case .node(let number): try container.encode(number, forKey: .node)
            case .tile(let tile): try encode(tile)
            }
        }
        func encodeEdge(_ edge: TrackEdgeID) throws {
            switch edge {
            case .edge(let number): try container.encode(number, forKey: .edge)
            case .link(let a, _): try encode(a)
            }
        }
    }
}

// MARK: - Observations

/// A read-only query as a scenario step, tagged by `"type"`: track topology,
/// one train's position and movement, a route to a tile or a station, a
/// station's platforms, the stations a train is stopped at, one train's
/// timetable, how far its timetable service has got, or what is derived
/// for a service line (its level at a time, its journey, how many trains it
/// can and does run, and its headway). Observations are not commands: they
/// ask the world through its public queries and never change it.
enum ScenarioObservation: Equatable {
    case connectedNeighbors(GridPosition)
    case isConnected(GridPosition, to: GridPosition)
    case train(TrainID)
    case route(from: TrainPosition, to: GridPosition)
    case platforms(StationID)
    case routeToStation(from: TrainPosition, station: StationID, cars: Int)
    case stationStops(TrainID)
    case wholeTrainStops(TrainID)
    case platformTracks(StationID)
    case timetable(TrainID)
    case execution(TrainID)
    case serviceLevel(LineID, at: GameTime)
    case lineJourney(LineID, pattern: Int?)
    case lineMaximumTrains(LineID, pattern: Int?)
    case lineTrainsInService(LineID, ServiceLevel, pattern: Int?)
    case lineHeadway(LineID, ServiceLevel, pattern: Int?)
    case lineSegmentLoads(LineID, ServiceLevel)
    case exits(GridPosition, facing: TrackDirection)
    case occupancy(TrainID)
    case conflicts
    case trackSections
    case parallelTracks(StationID, StationID)
    case trackEdge(TrackEdgeID)
    case edgeLocation(TrackTraversal, distance: Int64)
    case transitions(TrackTraversal)
    case pathToNode(from: TrainPosition, node: TrackNodeID)
    case bodyPath(TrainID)
    case edgePose(TrackTraversal, distance: Int64)
    case edgeAlignment(TrackEdgeID)
    case tunnelPortals
    case trackPlatformsAlongTrain(TrainID)
    case platformLevels(StationID)

    func answer(in world: GameWorld) -> ObservationAnswer {
        switch self {
        case .connectedNeighbors(let position):
            .neighbors(world.connectedNeighbors(of: position))
        case .isConnected(let position, let other):
            .connected(world.isConnected(position, to: other))
        case .train(let id):
            .train(world.train(id: id).map(TrainState.init))
        case .route(let start, let destination):
            .route(world.route(from: start, to: destination))
        case .platforms(let station):
            .platforms(world.platforms(of: station))
        case .routeToStation(let start, let station, let cars):
            .route(world.route(from: start, toStation: station, length: Int64(cars - 1) * Train.carLength))
        case .stationStops(let train):
            .stations(world.stationsStoppedAt(by: train))
        case .wholeTrainStops(let train):
            .stations(world.stationsBesideWholeTrain(train))
        case .platformTracks(let station):
            .platformTracks(world.platformTracks(of: station))
        case .timetable(let id):
            .timetable(world.train(id: id)?.timetable)
        case .execution(let id):
            .execution(world.train(id: id).map { ExecutionSummary($0.execution) })
        case .serviceLevel(let id, let time):
            .level(world.serviceLevel(of: id, at: time))
        case .lineJourney(let id, let pattern):
            .journey(world.lineJourney(id, pattern: pattern).map(JourneySummary.init))
        case .lineMaximumTrains(let id, let pattern):
            .trains(world.lineMaximumTrains(id, pattern: pattern))
        case .lineTrainsInService(let id, let level, let pattern):
            .trains(world.lineTrainsInService(id, at: level, pattern: pattern))
        case .lineHeadway(let id, let level, let pattern):
            .minutes(world.lineHeadway(id, at: level, pattern: pattern))
        case .lineSegmentLoads(let id, let level):
            .loads(world.lineSegmentLoads(id, at: level))
        case .exits(let position, let heading):
            .exits(world.exits(from: position, facing: heading))
        case .occupancy(let id):
            .resources(world.occupiedResources(of: id))
        case .conflicts:
            .conflicts(world.occupancyConflicts())
        case .trackSections:
            .sections(world.trackSections())
        case .parallelTracks(let a, let b):
            .tracks(world.parallelTracks(between: a, and: b))
        case .trackEdge(let id):
            .edge(world.trackEdge(id).map(EdgeInfoSummary.init))
        case .edgeLocation(let traversal, let distance):
            .location(world.trackGeometry(of: traversal.edge).flatMap { geometry in
                (0...geometry.length).contains(distance) ? LocationSummary(geometry.location(at: distance, going: traversal.direction)) : nil
            })
        case .transitions(let traversal):
            .transitions(world.transitions(after: traversal))
        case .pathToNode(let start, let node):
            .path(world.route(from: start, to: node))
        case .bodyPath(let id):
            .points(world.bodyPath(of: id))
        case .edgePose(let traversal, let distance):
            .pose(world.trackGeometry(of: traversal.edge).flatMap { geometry in
                (0...geometry.length).contains(distance) ? PoseSummary(geometry.location(at: distance, going: traversal.direction)) : nil
            })
        case .edgeAlignment(let id):
            .alignment(world.trackAlignment(of: id).map(AlignmentSummary.init))
        case .tunnelPortals:
            .nodes(world.network.nodes.map(\.id).filter(world.isTunnelPortal).map(\.number))
        case .trackPlatformsAlongTrain(let id):
            .trackPlatforms(world.trackPlatformsAlongWholeTrain(id).map(PlatformSummary.init))
        case .platformLevels(let id):
            .levels(world.railwaySnapshot().platforms.filter { $0.platform.station == id }.map(PlatformLevelSummary.init))
        }
    }
}

extension ScenarioObservation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, x, y, from, to, train, station, line, gameMinutes, level, pattern, heading, cars
        case edge, direction, distance, node
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
        case "train":
            self = try .train(container.decodeTrain(forKey: .train))
        case "route":
            // Read as written: whether the start is valid is GameCore's
            // decision, answered by "found": false.
            guard let start = try container.decode(TrainPositionSummary.self, forKey: .from).position else {
                throw DecodingError.dataCorruptedError(forKey: .from, in: container, debugDescription: "A route starts from a \"node\" or \"link\" position.")
            }
            self = try .route(from: start, to: container.decode(PositionSummary.self, forKey: .to).position)
        case "platforms":
            self = try .platforms(container.decodeStation(forKey: .station))
        case "routeToStation":
            // Read as written, like "route": whether the start and the
            // station are valid is GameCore's decision.
            guard let start = try container.decode(TrainPositionSummary.self, forKey: .from).position else {
                throw DecodingError.dataCorruptedError(forKey: .from, in: container, debugDescription: "A route starts from a \"node\" or \"link\" position.")
            }
            // "cars" is absent for a train of one car.
            let cars = try container.contains(.cars) ? container.decode(Int.self, forKey: .cars) : 1
            guard (Train.minimumCars...Train.maximumCars).contains(cars) else {
                throw DecodingError.dataCorruptedError(forKey: .cars, in: container, debugDescription: "A route is for 1 to \(Train.maximumCars) cars.")
            }
            self = try .routeToStation(from: start, station: container.decodeStation(forKey: .station), cars: cars)
        case "stationStops":
            self = try .stationStops(container.decodeTrain(forKey: .train))
        case "wholeTrainStops":
            self = try .wholeTrainStops(container.decodeTrain(forKey: .train))
        case "platformTracks":
            self = try .platformTracks(container.decodeStation(forKey: .station))
        case "timetable":
            self = try .timetable(container.decodeTrain(forKey: .train))
        case "execution":
            self = try .execution(container.decodeTrain(forKey: .train))
        case "serviceLevel":
            let time = try GameTime(minutes: container.decode(Int64.self, forKey: .gameMinutes))
            self = try .serviceLevel(container.decodeLine(forKey: .line), at: time)
        case "lineJourney":
            self = try .lineJourney(container.decodeLine(forKey: .line), pattern: container.decodePattern(forKey: .pattern))
        case "lineMaximumTrains":
            self = try .lineMaximumTrains(container.decodeLine(forKey: .line), pattern: container.decodePattern(forKey: .pattern))
        case "lineTrainsInService":
            let level = try container.decode(ServiceLevel.self, forKey: .level)
            self = try .lineTrainsInService(container.decodeLine(forKey: .line), level, pattern: container.decodePattern(forKey: .pattern))
        case "lineHeadway":
            let level = try container.decode(ServiceLevel.self, forKey: .level)
            self = try .lineHeadway(container.decodeLine(forKey: .line), level, pattern: container.decodePattern(forKey: .pattern))
        case "lineSegmentLoads":
            self = try .lineSegmentLoads(container.decodeLine(forKey: .line), container.decode(ServiceLevel.self, forKey: .level))
        case "exits":
            let heading = try container.decode(DirectionName.self, forKey: .heading).direction
            self = try .exits(container.decodePosition(x: .x, y: .y), facing: heading)
        case "occupancy":
            self = try .occupancy(container.decodeTrain(forKey: .train))
        case "conflicts":
            self = .conflicts
        case "trackSections":
            self = .trackSections
        case "parallelTracks":
            self = try .parallelTracks(
                StationID(rawValue: container.decode(Int.self, forKey: .from)), StationID(rawValue: container.decode(Int.self, forKey: .to))
            )
        case "trackEdge":
            self = try .trackEdge(.edge(container.decode(Int.self, forKey: .edge)))
        case "edgeLocation":
            let traversal = try TraversalSummary(edge: container.decode(Int.self, forKey: .edge), direction: container.decode(String.self, forKey: .direction))
            self = try .edgeLocation(traversal.traversal, distance: container.decode(Int64.self, forKey: .distance))
        case "transitions":
            let traversal = try TraversalSummary(edge: container.decode(Int.self, forKey: .edge), direction: container.decode(String.self, forKey: .direction))
            self = .transitions(traversal.traversal)
        case "pathToNode":
            guard let start = try container.decode(TrainPositionSummary.self, forKey: .from).position else {
                throw DecodingError.dataCorruptedError(forKey: .from, in: container, debugDescription: "A path starts from a train position.")
            }
            self = try .pathToNode(from: start, node: .node(container.decode(Int.self, forKey: .node)))
        case "bodyPath":
            self = try .bodyPath(container.decodeTrain(forKey: .train))
        case "edgePose":
            let traversal = try TraversalSummary(edge: container.decode(Int.self, forKey: .edge), direction: container.decode(String.self, forKey: .direction))
            self = try .edgePose(traversal.traversal, distance: container.decode(Int64.self, forKey: .distance))
        case "edgeAlignment":
            self = try .edgeAlignment(.edge(container.decode(Int.self, forKey: .edge)))
        case "tunnelPortals":
            self = .tunnelPortals
        case "trackPlatformsAlongTrain":
            self = try .trackPlatformsAlongTrain(container.decodeTrain(forKey: .train))
        case "platformLevels":
            self = try .platformLevels(container.decodeStation(forKey: .station))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown observation type \"\(type)\".")
        }
    }
}

/// What an observation answered. Encoded as `{"neighbors": [{"x", "y"}, ...]}`
/// in the order the query returned them, `{"connected": true|false}`,
/// `{"position", "movement"}` for a train, `{"found": true, "route":
/// [{"x", "y"}, ...]}` / `{"found": false}` for a route to a tile or a
/// station, `{"platforms": [{"x", "y"}, ...]}` in the order the query
/// returned them, `{"stations": [id, ...]}` for the stations a train is
/// stopped at, `{"timetable": [{"station", "arrival", "departure"}, ...]}`
/// for a train's timetable in its order, `{"execution": {"type", ...}}`
/// for its service, `{"level": "peak" | "offPeak" | "low" | "closed"}` for
/// a line's service level, `{"found": true, "journey": {...}}` /
/// `{"found": false}` for its journey, `{"found": true, "trains": n}` /
/// `{"found": false}` for how many trains it can or does run, and
/// `{"found": true, "minutes": n}` / `{"found": false}` for its headway, and
/// `{"found": true, "loads": [n, ...]}` / `{"found": false}` for the load on
/// each of its segments; and for track resources `{"exits": [{"x", "y"},
/// ...]}`, `{"resources": [...]}` for what a train occupies, `{"conflicts":
/// [{"resource", "trains"}, ...]}`, `{"sections": [{"nodes", "loop"}, ...]}`
/// and `{"tracks": n}` for the parallel tracks between two stations; for
/// station facilities `{"stations": [id, ...]}` for the stations a train
/// stands beside with its whole length, and `{"platformTracks": [[{"x",
/// "y"}, ...], ...]}` for a station's platform tracks. A
/// train the world does not have answers `{}` to `train`, `timetable` and
/// `execution`, which no fixture can expect.
enum ObservationAnswer: Equatable {
    case neighbors([GridPosition])
    case connected(Bool)
    case train(TrainState?)
    case route([GridPosition]?)
    case platforms([GridPosition])
    case stations([StationID])
    case timetable([ScheduledStop]?)
    case execution(ExecutionSummary?)
    case level(ServiceLevel?)
    case journey(JourneySummary?)
    case trains(Int?)
    case minutes(Int64?)
    case loads([Int]?)
    case exits([GridPosition])
    case resources([TrackResource])
    case conflicts([TrackConflict])
    case sections([TrackSection])
    case tracks(Int)
    case platformTracks([[GridPosition]])
    case edge(EdgeInfoSummary?)
    case location(LocationSummary?)
    case transitions([TrackTraversal])
    case path([TrackTraversal]?)
    case points([WorldCoordinate])
    case pose(PoseSummary?)
    case alignment(AlignmentSummary?)
    case nodes([Int])
    case trackPlatforms([PlatformSummary])
    case levels([PlatformLevelSummary])
}

extension ObservationAnswer: Encodable {
    private enum CodingKeys: String, CodingKey {
        case neighbors, connected, position, movement, found, route, platforms, stations, timetable, execution
        case level, journey, trains, minutes, loads, exits, resources, conflicts, sections, tracks, platformTracks
        case edge, location, transitions, path, points
        case pose, alignment, nodes, trackPlatforms, levels
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .neighbors(let positions):
            try container.encode(positions.map(PositionSummary.init), forKey: .neighbors)
        case .connected(let connected):
            try container.encode(connected, forKey: .connected)
        case .train(let state?):
            try container.encode(state.position, forKey: .position)
            try container.encode(state.movement, forKey: .movement)
        case .train(nil):
            break
        case .route(let nodes?):
            try container.encode(true, forKey: .found)
            try container.encode(nodes.map(PositionSummary.init), forKey: .route)
        case .route(nil):
            try container.encode(false, forKey: .found)
        case .platforms(let positions):
            try container.encode(positions.map(PositionSummary.init), forKey: .platforms)
        case .stations(let ids):
            try container.encode(ids.map(\.rawValue), forKey: .stations)
        case .timetable(let stops?):
            try container.encode(stops.map(StopSummary.init), forKey: .timetable)
        case .timetable(nil):
            break
        case .execution(let execution?):
            try container.encode(execution, forKey: .execution)
        case .execution(nil):
            break
        case .level(let level):
            try container.encode(level?.rawValue ?? "closed", forKey: .level)
        case .journey(let journey?):
            try container.encode(true, forKey: .found)
            try container.encode(journey, forKey: .journey)
        case .trains(let trains?):
            try container.encode(true, forKey: .found)
            try container.encode(trains, forKey: .trains)
        case .minutes(let minutes?):
            try container.encode(true, forKey: .found)
            try container.encode(minutes, forKey: .minutes)
        case .loads(let loads?):
            try container.encode(true, forKey: .found)
            try container.encode(loads, forKey: .loads)
        case .edge(let edge?):
            try container.encode(true, forKey: .found)
            try container.encode(edge, forKey: .edge)
        case .location(let location?):
            try container.encode(true, forKey: .found)
            try container.encode(location, forKey: .location)
        case .path(let path?):
            try container.encode(true, forKey: .found)
            try container.encode(path.map(TraversalSummary.init), forKey: .path)
        case .pose(let pose?):
            try container.encode(true, forKey: .found)
            try container.encode(pose, forKey: .pose)
        case .alignment(let alignment?):
            try container.encode(true, forKey: .found)
            try container.encode(alignment, forKey: .alignment)
        case .journey(nil), .trains(nil), .minutes(nil), .loads(nil), .edge(nil), .location(nil), .path(nil), .pose(nil), .alignment(nil):
            try container.encode(false, forKey: .found)
        case .nodes(let nodes):
            try container.encode(nodes, forKey: .nodes)
        case .trackPlatforms(let platforms):
            try container.encode(platforms, forKey: .trackPlatforms)
        case .levels(let levels):
            try container.encode(levels, forKey: .levels)
        case .transitions(let traversals):
            try container.encode(traversals.map(TraversalSummary.init), forKey: .transitions)
        case .points(let points):
            try container.encode(points.map(PointSummary.init), forKey: .points)
        case .exits(let positions):
            try container.encode(positions.map(PositionSummary.init), forKey: .exits)
        case .resources(let resources):
            try container.encode(resources.map(ResourceSummary.init), forKey: .resources)
        case .conflicts(let conflicts):
            try container.encode(conflicts.map(ConflictSummary.init), forKey: .conflicts)
        case .sections(let sections):
            try container.encode(sections.map(SectionSummary.init), forKey: .sections)
        case .tracks(let count):
            try container.encode(count, forKey: .tracks)
        case .platformTracks(let tracks):
            try container.encode(tracks.map { $0.map(PositionSummary.init) }, forKey: .platformTracks)
        }
    }
}

/// A train's position and movement, as observed or summarised.
struct TrainState: Equatable {
    var position: TrainPositionSummary
    var movement: TrainMovementSummary

    init(position: TrainPositionSummary, movement: TrainMovementSummary) {
        self.position = position
        self.movement = movement
    }

    init(_ train: Train) {
        position = TrainPositionSummary(train.position)
        movement = TrainMovementSummary(train.movement)
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

/// The externally meaningful state of a world: time, money, what has been
/// built or bought (each station with the tiles it grew onto), where each
/// train is and how it moves, each train's timetable, how it repeats, and
/// service, its cars and its body, the service lines and the service day.
/// Lists are in
/// the contract's canonical order (stations and trains by ascending ID,
/// tracks row by row from the north-west corner), sorted here rather than
/// inherited from how GameCore stores them.
struct WorldSummary: Codable, Equatable {
    var gameMinutes: Int64
    var speed: SpeedName
    var balance: Int64
    var stations: [StationSummary]
    var tracks: [TrackSummary]
    var trains: [TrainSummary]
    var lines: [LineSummary]
    var serviceDay: [BandSummary]
    var network: NetworkSummary

    struct StationSummary: Codable, Equatable {
        var id: Int
        var name: String
        var x: Int
        var y: Int
        /// The tiles it grew onto, in order; `[]` for one tile.
        var annexes: [PositionSummary]
    }

    struct TrackSummary: Codable, Equatable {
        var x: Int
        var y: Int
        var connections: Directions
        var layout: LayoutSummary
    }

    struct TrainSummary: Codable, Equatable {
        var id: Int
        var name: String
        var position: TrainPositionSummary
        var movement: TrainMovementSummary
        var timetable: [StopSummary]
        var `repeat`: RepeatSummary
        var execution: ExecutionSummary
        /// Its cars, and the nodes its body lies over, nearest first; `1`
        /// and `[]` for a train of one car.
        var cars: Int
        var trail: [PositionSummary]
        /// On the track network (schema 16): the edges its body lies over
        /// behind its head's edge, nearest first, by number.
        var trailEdges: [Int]
    }

    /// The track network (schema 16): nodes and edges in ID order.
    struct NetworkSummary: Codable, Equatable {
        var nodes: [NodeSummary]
        var edges: [EdgeSummary]
        /// The stations' platforms, in order along the track (schema 17).
        var platforms: [PlatformSummary]

        struct NodeSummary: Codable, Equatable {
            var id: Int
            var x: Int64
            var y: Int64
            var z: Int64
        }

        /// An edge with its length, which GameCore works out from its end
        /// nodes and curve: the fixture pins that number. Since schema 17
        /// also its profile and structure.
        struct EdgeSummary: Codable, Equatable {
            var id: Int
            var from: Int
            var to: Int
            var curve: CurveSummary
            var length: Int64
            var profile: ProfileSummary
            var structure: StructureName
        }

        init(_ network: RailwayNetwork) {
            nodes = network.nodes.map { NodeSummary(id: $0.id.number, x: $0.position.x, y: $0.position.y, z: $0.position.z) }
            edges = network.edges.map {
                EdgeSummary(
                    id: $0.id.number, from: $0.from.number, to: $0.to.number, curve: CurveSummary($0.curve), length: $0.length,
                    profile: ProfileSummary($0.profile), structure: StructureName($0.structure)
                )
            }
            platforms = network.platforms.map(PlatformSummary.init)
        }

        init(nodes: [NodeSummary], edges: [EdgeSummary], platforms: [PlatformSummary]) {
            self.nodes = nodes
            self.edges = edges
            self.platforms = platforms
        }
    }

    init(_ world: GameWorld) {
        gameMinutes = world.clock.now.minutes
        speed = SpeedName(world.clock.speed)
        balance = world.economy.balance.amount
        stations = world.stations
            .map {
                StationSummary(
                    id: $0.id.rawValue, name: $0.name, x: $0.position.x, y: $0.position.y, annexes: $0.annexes.map(PositionSummary.init)
                )
            }
            .sorted { $0.id < $1.id }
        tracks = world.tracks
            .map { TrackSummary(x: $0.position.x, y: $0.position.y, connections: Directions($0.connections), layout: LayoutSummary($0.layout)) }
            .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        trains = world.trains
            .map {
                TrainSummary(
                    id: $0.id.rawValue, name: $0.name, position: TrainPositionSummary($0.position),
                    movement: TrainMovementSummary($0.movement), timetable: $0.timetable.map(StopSummary.init),
                    repeat: RepeatSummary($0.timetablePeriod), execution: ExecutionSummary($0.execution),
                    cars: $0.cars, trail: $0.trail.map(PositionSummary.init), trailEdges: $0.trailEdges.map(\.number)
                )
            }
            .sorted { $0.id < $1.id }
        lines = world.lines.map(LineSummary.init).sorted { $0.id < $1.id }
        serviceDay = world.serviceDay.bands.map(BandSummary.init)
        network = NetworkSummary(world.network)
    }
}

// MARK: - Service lines

/// A service line as a fixture value: `{"id", "name", "stops", "rate",
/// "window", "trainsInService", "targetHeadways", "trains",
/// "lastDispatch", "patterns"}` (see `ServiceLine`). Every field is
/// required; `lastDispatch` is `null` for a line that never sent a train
/// out, and `patterns` is `[]` for a line without any.
struct LineSummary: Codable, Equatable {
    var id: Int
    var name: String
    var stops: [Int]
    var rate: Int64
    var window: WindowSummary
    var trainsInService: TrainsSummary
    var targetHeadways: TargetHeadwaysSummary
    var trains: [Int]
    var lastDispatch: Int64?
    var patterns: [PatternSummary]

    init(
        id: Int, name: String, stops: [Int], rate: Int64, window: WindowSummary, trainsInService: TrainsSummary,
        targetHeadways: TargetHeadwaysSummary, trains: [Int], lastDispatch: Int64?, patterns: [PatternSummary] = []
    ) {
        self.id = id
        self.name = name
        self.stops = stops
        self.rate = rate
        self.window = window
        self.trainsInService = trainsInService
        self.targetHeadways = targetHeadways
        self.trains = trains
        self.lastDispatch = lastDispatch
        self.patterns = patterns
    }

    init(_ line: ServiceLine) {
        id = line.id.rawValue
        name = line.name
        stops = line.stops.map(\.rawValue)
        rate = line.rate
        window = WindowSummary(line.window)
        trainsInService = TrainsSummary(line.trainsInService)
        targetHeadways = TargetHeadwaysSummary(line.targetHeadways)
        trains = line.trains.map(\.rawValue)
        lastDispatch = line.lastDispatch?.minutes
        patterns = line.patterns.map(PatternSummary.init)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, stops, rate, window, trainsInService, targetHeadways, trains, lastDispatch, patterns
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        stops = try container.decode([Int].self, forKey: .stops)
        rate = try container.decode(Int64.self, forKey: .rate)
        window = try container.decode(WindowSummary.self, forKey: .window)
        trainsInService = try container.decode(TrainsSummary.self, forKey: .trainsInService)
        targetHeadways = try container.decode(TargetHeadwaysSummary.self, forKey: .targetHeadways)
        trains = try container.decode([Int].self, forKey: .trains)
        // Required: a missing key is an error, not a line that never
        // dispatched.
        lastDispatch = try container.decodeNil(forKey: .lastDispatch) ? nil : container.decode(Int64.self, forKey: .lastDispatch)
        patterns = try container.decode([PatternSummary].self, forKey: .patterns)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(stops, forKey: .stops)
        try container.encode(rate, forKey: .rate)
        try container.encode(window, forKey: .window)
        try container.encode(trainsInService, forKey: .trainsInService)
        try container.encode(targetHeadways, forKey: .targetHeadways)
        try container.encode(trains, forKey: .trains)
        if let lastDispatch {
            try container.encode(lastDispatch, forKey: .lastDispatch)
        } else {
            try container.encodeNil(forKey: .lastDispatch)
        }
        try container.encode(patterns, forKey: .patterns)
    }
}

/// A line's pattern as a fixture value: `{"calls", "trainsInService",
/// "targetHeadways", "trains", "lastDispatch"}` (see `LinePattern`), every
/// field required as on a line; `lastDispatch` is `null` for a pattern
/// that never sent a train out.
struct PatternSummary: Codable, Equatable {
    var calls: [Int]
    var trainsInService: TrainsSummary
    var targetHeadways: TargetHeadwaysSummary
    var trains: [Int]
    var lastDispatch: Int64?

    init(calls: [Int], trainsInService: TrainsSummary, targetHeadways: TargetHeadwaysSummary, trains: [Int], lastDispatch: Int64?) {
        self.calls = calls
        self.trainsInService = trainsInService
        self.targetHeadways = targetHeadways
        self.trains = trains
        self.lastDispatch = lastDispatch
    }

    init(_ pattern: LinePattern) {
        calls = pattern.calls
        trainsInService = TrainsSummary(pattern.trainsInService)
        targetHeadways = TargetHeadwaysSummary(pattern.targetHeadways)
        trains = pattern.trains.map(\.rawValue)
        lastDispatch = pattern.lastDispatch?.minutes
    }

    private enum CodingKeys: String, CodingKey {
        case calls, trainsInService, targetHeadways, trains, lastDispatch
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calls = try container.decode([Int].self, forKey: .calls)
        trainsInService = try container.decode(TrainsSummary.self, forKey: .trainsInService)
        targetHeadways = try container.decode(TargetHeadwaysSummary.self, forKey: .targetHeadways)
        trains = try container.decode([Int].self, forKey: .trains)
        lastDispatch = try container.decodeNil(forKey: .lastDispatch) ? nil : container.decode(Int64.self, forKey: .lastDispatch)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(calls, forKey: .calls)
        try container.encode(trainsInService, forKey: .trainsInService)
        try container.encode(targetHeadways, forKey: .targetHeadways)
        try container.encode(trains, forKey: .trains)
        if let lastDispatch {
            try container.encode(lastDispatch, forKey: .lastDispatch)
        } else {
            try container.encodeNil(forKey: .lastDispatch)
        }
    }
}

/// Target headways as a fixture value: `{"peak", "offPeak", "low"}`, each
/// minutes or `null` at a level without a target (see `TargetHeadways`).
/// All three keys are required. Read as written: whether a target fits is
/// GameCore's decision.
struct TargetHeadwaysSummary: Codable, Equatable {
    var headways: TargetHeadways

    init(_ headways: TargetHeadways) {
        self.headways = headways
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case peak, offPeak, low
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func target(_ key: CodingKeys) throws -> Int64? {
            try container.decodeNil(forKey: key) ? nil : container.decode(Int64.self, forKey: key)
        }
        headways = try TargetHeadways(peak: target(.peak), offPeak: target(.offPeak), low: target(.low))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        for (key, target) in zip(CodingKeys.allCases, [headways.peak, headways.offPeak, headways.low]) {
            if let target {
                try container.encode(target, forKey: key)
            } else {
                try container.encodeNil(forKey: key)
            }
        }
    }
}

/// A service window as a fixture value, tagged by `"type"`: `{"type":
/// "allDay"}` or `{"type": "hours", "open", "close"}`, minutes of the day
/// (see `ServiceWindow`). Read as written: whether a window fits is
/// GameCore's decision. A field that belongs to another type is rejected.
struct WindowSummary: Codable, Equatable {
    var window: ServiceWindow

    init(_ window: ServiceWindow) {
        self.window = window
    }

    private enum CodingKeys: String, CodingKey {
        case type, open, close
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "allDay":
            for key in [CodingKeys.open, .close] where container.contains(key) {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "An \"allDay\" window has no \"\(key.stringValue)\".")
            }
            window = .allDay
        case "hours":
            window = try .hours(open: container.decode(Int.self, forKey: .open), close: container.decode(Int.self, forKey: .close))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown window type \"\(type)\".")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch window {
        case .allDay:
            try container.encode("allDay", forKey: .type)
        case .hours(let open, let close):
            try container.encode("hours", forKey: .type)
            try container.encode(open, forKey: .open)
            try container.encode(close, forKey: .close)
        }
    }
}

/// Trains in service as a fixture value: `{"peak", "offPeak", "low"}`.
/// Read as written: rejecting a negative count is GameCore's decision.
struct TrainsSummary: Codable, Equatable {
    var peak: Int
    var offPeak: Int
    var low: Int

    init(_ trains: TrainsInService) {
        peak = trains.peak
        offPeak = trains.offPeak
        low = trains.low
    }

    var trains: TrainsInService {
        TrainsInService(peak: peak, offPeak: offPeak, low: low)
    }
}

/// A band of the service day as a fixture value: `{"start", "level"}`, a
/// minute of the day and `"peak"`, `"offPeak"` or `"low"`.
struct BandSummary: Codable, Equatable {
    var start: Int
    var level: ServiceLevel

    init(_ band: ServiceDay.Band) {
        start = band.start
        level = band.level
    }

    var band: ServiceDay.Band {
        ServiceDay.Band(start: start, level: level)
    }
}

/// A line's journey as a fixture value: `{"start", "legs": [{"from", "to",
/// "route", "minutes"}, ...], "roundTripMinutes"}` (see `LineJourney`).
struct JourneySummary: Codable, Equatable {
    struct Leg: Codable, Equatable {
        var from: Int
        var to: Int
        var route: [PositionSummary]
        var minutes: Int64
    }

    var start: TrainPositionSummary
    var legs: [Leg]
    var roundTripMinutes: Int64

    init(_ journey: LineJourney) {
        start = TrainPositionSummary(journey.start)
        legs = journey.legs.map { Leg(from: $0.from, to: $0.to, route: $0.route.map(PositionSummary.init), minutes: $0.minutes) }
        roundTripMinutes = journey.roundTripMinutes
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

/// A direction as its fixture name: `"north"`, `"east"`, `"south"` or `"west"`.
struct DirectionName: Codable, Equatable {
    var direction: TrackDirection

    init(_ direction: TrackDirection) {
        self.direction = direction
    }

    static func name(of direction: TrackDirection) -> String {
        switch direction {
        case .north: "north"
        case .east: "east"
        case .south: "south"
        case .west: "west"
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let direction = TrackDirection.allCases.first(where: { Self.name(of: $0) == name }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown direction \"\(name)\".")
        }
        self.direction = direction
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.name(of: direction))
    }
}

/// Track connections as a JSON array of direction names. Order does not
/// matter when reading; writing uses north, east, south, west.
struct Directions: Codable, Equatable {
    var connections: TrackConnections

    init(_ connections: TrackConnections) {
        self.connections = connections
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var connections: TrackConnections = []
        while !container.isAtEnd {
            let direction = try container.decode(DirectionName.self).direction
            guard connections.insert(TrackConnections(direction)).inserted else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Direction \"\(DirectionName.name(of: direction))\" is listed twice.")
            }
        }
        self.connections = connections
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for direction in connections.directions {
            try container.encode(DirectionName(direction))
        }
    }
}

/// A train position as a fixture value, tagged by `"type"`:
/// `{"type": "unplaced"}`, `{"type": "node", "x", "y", "heading"}`, or
/// `{"type": "link", "from": {"x", "y"}, "to": {"x", "y"}, "offset"}`.
///
/// Values are read as written, not checked or normalised: whether a position
/// is valid is GameCore's decision, so a fixture can expect a placement at
/// offset 0 to be rejected. Fields that belong to another type are rejected
/// rather than ignored.
struct TrainPositionSummary: Codable, Equatable {
    /// `nil` for an unplaced train.
    var position: TrainPosition?

    init(_ position: TrainPosition?) {
        self.position = position
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, x, y, heading, from, to, offset, edge, direction
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let fields: [CodingKeys]
        switch type {
        case "unplaced":
            fields = []
            position = nil
        case "node":
            fields = [.x, .y, .heading]
            position = try .atNode(
                container.decodePosition(x: .x, y: .y),
                heading: container.decode(DirectionName.self, forKey: .heading).direction
            )
        case "link":
            fields = [.from, .to, .offset]
            position = try .onLink(
                from: container.decode(PositionSummary.self, forKey: .from).position,
                to: container.decode(PositionSummary.self, forKey: .to).position,
                offset: container.decode(Int64.self, forKey: .offset)
            )
        case "edge":
            fields = [.edge, .direction, .offset]
            let direction: TrackEdgeDirection
            switch try container.decode(String.self, forKey: .direction) {
            case "forward": direction = .forward
            case "backward": direction = .backward
            case let name: throw DecodingError.dataCorruptedError(forKey: .direction, in: container, debugDescription: "Unknown edge direction \"\(name)\".")
            }
            position = try .onEdge(
                TrackTraversal(edge: .edge(container.decode(Int.self, forKey: .edge)), direction: direction),
                offset: container.decode(Int64.self, forKey: .offset)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown position type \"\(type)\".")
        }
        for key in CodingKeys.allCases where key != .type && !fields.contains(key) && container.contains(key) {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "A \"\(type)\" position has no \"\(key.stringValue)\".")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch position {
        case nil:
            try container.encode("unplaced", forKey: .type)
        case .atNode(let tile, let heading)?:
            try container.encode("node", forKey: .type)
            try container.encode(tile.x, forKey: .x)
            try container.encode(tile.y, forKey: .y)
            try container.encode(DirectionName(heading), forKey: .heading)
        case .onLink(let from, let to, let offset)?:
            try container.encode("link", forKey: .type)
            try container.encode(PositionSummary(from), forKey: .from)
            try container.encode(PositionSummary(to), forKey: .to)
            try container.encode(offset, forKey: .offset)
        case .onEdge(let traversal, let offset)?:
            try container.encode("edge", forKey: .type)
            try container.encode(traversal.edge.networkNumberForFixture, forKey: .edge)
            try container.encode(traversal.direction == .forward ? "forward" : "backward", forKey: .direction)
            try container.encode(offset, forKey: .offset)
        }
    }
}

/// A train's movement as a fixture value:
/// `{"rate", "continuation": [{"x", "y"}, ...], "cursor"}`, in GameCore's
/// terms (see `TrainMovement`): `rate` units per basic step, the whole
/// continuation in order, and how many of its entries have been entered.
/// A spent continuation is `[]` with cursor 0; an idle train is
/// `{"rate": 0, "continuation": [], "cursor": 0}`.
struct TrainMovementSummary: Codable, Equatable {
    var rate: Int64
    var continuation: [PositionSummary]
    var cursor: Int
    /// On the track network (schema 16): the edges the train enters, by
    /// number; `[]` on the grid.
    var edges: [Int]

    init(rate: Int64, continuation: [GridPosition], cursor: Int, edges: [Int] = []) {
        self.rate = rate
        self.continuation = continuation.map(PositionSummary.init)
        self.cursor = cursor
        self.edges = edges
    }

    init(_ movement: TrainMovement) {
        self.init(rate: movement.rate, continuation: movement.continuation, cursor: movement.cursor, edges: movement.edges.map(\.number))
    }
}

/// A timetable stop as a fixture value: `{"station", "arrival", "departure",
/// "reverse"}`, a station ID, two game minutes and whether the train turns
/// round as it leaves (see `ScheduledStop`). Read as written, not checked:
/// whether a timetable is valid is GameCore's decision, so a fixture can
/// expect a negative time to be rejected.
struct StopSummary: Codable, Equatable {
    var station: Int
    var arrival: Int64
    var departure: Int64
    var reverse: Bool

    init(_ stop: ScheduledStop) {
        station = stop.station.rawValue
        arrival = stop.arrival.minutes
        departure = stop.departure.minutes
        reverse = stop.reverses
    }

    var stop: ScheduledStop {
        ScheduledStop(
            station: StationID(rawValue: station), arrival: GameTime(minutes: arrival), departure: GameTime(minutes: departure),
            reverses: reverse
        )
    }
}

/// How a timetable repeats, as a fixture value tagged by `"type"`:
/// `{"type": "once"}` for a timetable that runs once, or `{"type": "every",
/// "minutes"}` for one that repeats every `minutes` (see
/// `Train.timetablePeriod`). Read as written: whether a period fits is
/// GameCore's decision, so a fixture can expect 0 to be rejected. A field
/// that belongs to another type is rejected.
struct RepeatSummary: Codable, Equatable {
    /// `nil` for a timetable that runs once.
    var period: Int64?

    init(_ period: Int64?) {
        self.period = period
    }

    private enum CodingKeys: String, CodingKey {
        case type, minutes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "once":
            guard !container.contains(.minutes) else {
                throw DecodingError.dataCorruptedError(forKey: .minutes, in: container, debugDescription: "A \"once\" timetable has no \"minutes\".")
            }
            period = nil
        case "every":
            period = try container.decode(Int64.self, forKey: .minutes)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown repeat type \"\(type)\".")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let period {
            try container.encode("every", forKey: .type)
            try container.encode(period, forKey: .minutes)
        } else {
            try container.encode("once", forKey: .type)
        }
    }
}

/// A train's timetable service as a fixture value, tagged by `"type"`:
/// `{"type": "inactive"}` without a service, `{"type": "waiting", "stop",
/// "cycle"}` while it waits at timetable entry `stop`, or `{"type":
/// "travelling", "stop", "cycle"}` on its way to that entry (see
/// `TimetableExecution`). `stop` is a 0-based index into the timetable, not
/// a station ID; `cycle` counts the times a repeating timetable has started
/// again, 0 for one that runs once. Values are read as written; a field that
/// belongs to another type is rejected.
struct ExecutionSummary: Codable, Equatable {
    /// `nil` without an active service.
    var execution: TimetableExecution?

    init(_ execution: TimetableExecution?) {
        self.execution = execution
    }

    private enum CodingKeys: String, CodingKey {
        case type, stop, cycle
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "inactive":
            for key in [CodingKeys.stop, .cycle] where container.contains(key) {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "An \"inactive\" service has no \"\(key.stringValue)\".")
            }
            execution = nil
        case "waiting":
            execution = try .waitingAtStop(container.decode(Int.self, forKey: .stop), cycle: container.decode(Int64.self, forKey: .cycle))
        case "travelling":
            execution = try .travellingToStop(container.decode(Int.self, forKey: .stop), cycle: container.decode(Int64.self, forKey: .cycle))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown service type \"\(type)\".")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch execution {
        case nil:
            try container.encode("inactive", forKey: .type)
        case .waitingAtStop(let stop, let cycle)?:
            try container.encode("waiting", forKey: .type)
            try container.encode(stop, forKey: .stop)
            try container.encode(cycle, forKey: .cycle)
        case .travellingToStop(let stop, let cycle)?:
            try container.encode("travelling", forKey: .type)
            try container.encode(stop, forKey: .stop)
            try container.encode(cycle, forKey: .cycle)
        }
    }
}

extension KeyedDecodingContainer {
    /// A grid position stored as two flat integer fields.
    fileprivate func decodePosition(x: Key, y: Key) throws -> GridPosition {
        try GridPosition(x: decode(Int.self, forKey: x), y: decode(Int.self, forKey: y))
    }

    /// A train ID stored as a plain integer.
    fileprivate func decodeTrain(forKey key: Key) throws -> TrainID {
        try TrainID(rawValue: decode(Int.self, forKey: key))
    }

    /// A station ID stored as a plain integer.
    fileprivate func decodeStation(forKey key: Key) throws -> StationID {
        try StationID(rawValue: decode(Int.self, forKey: key))
    }

    /// A line ID stored as a plain integer.
    fileprivate func decodeLine(forKey key: Key) throws -> LineID {
        try LineID(rawValue: decode(Int.self, forKey: key))
    }

    /// A line's pattern index where the step names one, or `nil` for the
    /// line's own service when the key is absent. Read as written: whether
    /// the line has that pattern is GameCore's decision. An explicit `null`
    /// is rejected.
    fileprivate func decodePattern(forKey key: Key) throws -> Int? {
        contains(key) ? try decode(Int.self, forKey: key) : nil
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

// MARK: - Track resources (schema 14)

/// A track piece's layout as a fixture value, tagged by `"type"`:
/// `{"type": "open"}`, `{"type": "turnout", "stem"}` or `{"type":
/// "crossing"}` (see `TrackLayout`). A field that belongs to another type is
/// rejected.
struct LayoutSummary: Codable, Equatable {
    var layout: TrackLayout

    init(_ layout: TrackLayout) {
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey {
        case type, stem
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "open", "crossing":
            guard !container.contains(.stem) else {
                throw DecodingError.dataCorruptedError(forKey: .stem, in: container, debugDescription: "Only a turnout has a stem.")
            }
            layout = type == "open" ? .open : .crossing
        case "turnout":
            layout = .turnout(stem: try container.decode(DirectionName.self, forKey: .stem).direction)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown track layout \"\(type)\".")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch layout {
        case .open:
            try container.encode("open", forKey: .type)
        case .turnout(let stem):
            try container.encode("turnout", forKey: .type)
            try container.encode(DirectionName(stem), forKey: .stem)
        case .crossing:
            try container.encode("crossing", forKey: .type)
        }
    }
}

/// A track resource as a fixture value: `{"type": "node", "x", "y"}` or
/// `{"type": "link", "from": {"x", "y"}, "to": {"x", "y"}}` (a grid link's
/// one span), `from` first in row-major order; on the network (schema 16)
/// `{"type": "networkNode", "node"}` or `{"type": "networkSpan", "edge",
/// "start", "end"}` (see `TrackResource` and `TrackSpan`).
struct ResourceSummary: Codable, Equatable {
    var resource: TrackResource

    init(_ resource: TrackResource) {
        self.resource = resource
    }

    private enum CodingKeys: String, CodingKey {
        case type, x, y, from, to, node, edge, start, end
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "node":
            resource = .tile(try GridPosition(x: container.decode(Int.self, forKey: .x), y: container.decode(Int.self, forKey: .y)))
        case "link":
            // A grid link is one span, the whole link (schema 16).
            resource = .wholeLink(.link(
                try container.decode(PositionSummary.self, forKey: .from).position, try container.decode(PositionSummary.self, forKey: .to).position
            ))
        case "networkNode":
            resource = .node(.node(try container.decode(Int.self, forKey: .node)))
        case "networkSpan":
            resource = .span(TrackSpan(
                edge: .edge(try container.decode(Int.self, forKey: .edge)),
                start: try container.decode(Int64.self, forKey: .start), end: try container.decode(Int64.self, forKey: .end)
            ))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "A resource is a node, a link or a network span.")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch resource {
        case .node(.tile(let position)):
            try container.encode("node", forKey: .type)
            try container.encode(position.x, forKey: .x)
            try container.encode(position.y, forKey: .y)
        case .span(let span):
            switch span.edge {
            case .link(let from, let to):
                try container.encode("link", forKey: .type)
                try container.encode(PositionSummary(from), forKey: .from)
                try container.encode(PositionSummary(to), forKey: .to)
                // Never part of a link: written so a failure report shows it.
                if span.start != 0 || span.end != TrainPosition.linkLength {
                    try container.encode(span.start, forKey: .start)
                    try container.encode(span.end, forKey: .end)
                }
            case .edge(let number):
                try container.encode("networkSpan", forKey: .type)
                try container.encode(number, forKey: .edge)
                try container.encode(span.start, forKey: .start)
                try container.encode(span.end, forKey: .end)
            }
        case .node(.node(let number)):
            try container.encode("networkNode", forKey: .type)
            try container.encode(number, forKey: .node)
        }
    }
}

/// `{"resource", "trains": [id, ...]}` (see `TrackConflict`).
struct ConflictSummary: Codable, Equatable {
    var conflict: TrackConflict

    init(_ conflict: TrackConflict) {
        self.conflict = conflict
    }

    private enum CodingKeys: String, CodingKey {
        case resource, trains
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conflict = TrackConflict(
            resource: try container.decode(ResourceSummary.self, forKey: .resource).resource,
            trains: try container.decode([Int].self, forKey: .trains).map(TrainID.init(rawValue:))
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ResourceSummary(conflict.resource), forKey: .resource)
        try container.encode(conflict.trains.map(\.rawValue), forKey: .trains)
    }
}

/// `{"nodes": [{"x", "y"}, ...], "loop": true | false}` (see `TrackSection`).
struct SectionSummary: Codable, Equatable {
    var section: TrackSection

    init(_ section: TrackSection) {
        self.section = section
    }

    private enum CodingKeys: String, CodingKey {
        case nodes, loop
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        section = TrackSection(
            nodes: try container.decode([PositionSummary].self, forKey: .nodes).map(\.position),
            isLoop: try container.decode(Bool.self, forKey: .loop)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(section.nodes.map(PositionSummary.init), forKey: .nodes)
        try container.encode(section.isLoop, forKey: .loop)
    }
}

// MARK: - Track network (schema 16)

/// A curve as a fixture value, tagged by `"type"`: `{"type": "straight"}` or
/// `{"type": "cubic", "control1": {"x", "y"}, "control2": {"x", "y"}}`, in
/// world units. Read as written: whether it makes an edge is GameCore's
/// decision.
struct CurveSummary: Codable, Equatable {
    var curve: TrackCurve

    init(_ curve: TrackCurve) {
        self.curve = curve
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, control1, control2
    }

    private struct Point: Codable, Equatable {
        var x: Int64
        var y: Int64
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "straight":
            for key in [CodingKeys.control1, .control2] where container.contains(key) {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "A straight curve has no control points.")
            }
            curve = .straight
        case "cubic":
            let c1 = try container.decode(Point.self, forKey: .control1)
            let c2 = try container.decode(Point.self, forKey: .control2)
            curve = .cubic(PlanPoint(x: c1.x, y: c1.y), PlanPoint(x: c2.x, y: c2.y))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown curve type \"\(type)\".")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch curve {
        case .straight:
            try container.encode("straight", forKey: .type)
        case .cubic(let c1, let c2):
            try container.encode("cubic", forKey: .type)
            try container.encode(Point(x: c1.x, y: c1.y), forKey: .control1)
            try container.encode(Point(x: c2.x, y: c2.y), forKey: .control2)
        }
    }
}

/// A network edge travelled one way, as a fixture value:
/// `{"edge", "direction"}`, the edge's number and `"forward"` (from its
/// `from` node to its `to` node) or `"backward"`.
struct TraversalSummary: Codable, Equatable {
    var edge: Int
    var direction: String

    init(_ traversal: TrackTraversal) {
        switch traversal.edge {
        case .edge(let number): edge = number
        case .link: edge = 0
        }
        direction = traversal.direction == .forward ? "forward" : "backward"
    }

    init(edge: Int, direction: String) throws {
        guard direction == "forward" || direction == "backward" else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Unknown direction \"\(direction)\"."))
        }
        self.edge = edge
        self.direction = direction
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(edge: container.decode(Int.self, forKey: .edge), direction: container.decode(String.self, forKey: .direction))
    }

    var traversal: TrackTraversal {
        TrackTraversal(edge: .edge(edge), direction: direction == "forward" ? .forward : .backward)
    }
}

/// An edge as the graph sees it: `{"from", "to", "length"}`, node numbers
/// and its length in world units.
struct EdgeInfoSummary: Codable, Equatable {
    var from: Int
    var to: Int
    var length: Int64

    init(_ edge: TrackEdge) {
        self.init(from: edge.from.number, to: edge.to.number, length: edge.length)
    }

    init(from: Int, to: Int, length: Int64) {
        self.from = from
        self.to = to
        self.length = length
    }
}

/// A point on the track and the way it runs there: `{"x", "y", "z", "dx",
/// "dy"}` in world units; the way is not normalised.
struct LocationSummary: Codable, Equatable {
    var x: Int64
    var y: Int64
    var z: Int64
    var dx: Int64
    var dy: Int64

    init(_ location: TrackLocation) {
        x = location.position.x
        y = location.position.y
        z = location.position.z
        dx = location.direction.dx
        dy = location.direction.dy
    }
}

/// A world point: `{"x", "y", "z"}` in world units.
struct PointSummary: Codable, Equatable {
    var x: Int64
    var y: Int64
    var z: Int64

    init(_ point: WorldCoordinate) {
        x = point.x
        y = point.y
        z = point.z
    }

    var point: WorldCoordinate {
        WorldCoordinate(x: x, y: y, z: z)
    }
}

// MARK: - Vertical railway (schema 17)

/// A vertical profile as a fixture value: `{"startTransition",
/// "endTransition"}`, the lengths of the vertical curves at each end in
/// world units (0 for none). Read as written: whether it fits the edge is
/// GameCore's decision.
struct ProfileSummary: Codable, Equatable {
    var startTransition: Int64
    var endTransition: Int64

    init(_ profile: TrackProfile) {
        startTransition = profile.startTransition
        endTransition = profile.endTransition
    }

    var profile: TrackProfile {
        TrackProfile(startTransition: startTransition, endTransition: endTransition)
    }
}

/// A structure as a fixture value: `"surface"`, `"elevated"`, `"bridge"` or
/// `"tunnel"`, spelled out here rather than borrowed from GameCore.
struct StructureName: Codable, Equatable {
    var structure: TrackStructure

    init(_ structure: TrackStructure) {
        self.structure = structure
    }

    private static let names: [(String, TrackStructure)] = [("surface", .surface), ("elevated", .elevated), ("bridge", .bridge), ("tunnel", .tunnel)]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let structure = Self.names.first(where: { $0.0 == name })?.1 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown structure \"\(name)\".")
        }
        self.structure = structure
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.names.first { $0.1 == structure }!.0)
    }
}

/// A grade as a fixture value: `{"rise", "run"}` in lowest terms, the run
/// positive.
struct GradeSummary: Codable, Equatable {
    var rise: Int64
    var run: Int64

    init(_ grade: TrackGrade) {
        rise = grade.rise
        run = grade.run
    }
}

/// A point on the track with its heading and grade: `{"x", "y", "z", "dx",
/// "dy", "rise", "run"}` in world units, the way not normalised and the
/// grade along it in lowest terms.
struct PoseSummary: Codable, Equatable {
    var x: Int64
    var y: Int64
    var z: Int64
    var dx: Int64
    var dy: Int64
    var rise: Int64
    var run: Int64

    init(_ location: TrackLocation) {
        x = location.position.x
        y = location.position.y
        z = location.position.z
        dx = location.direction.dx
        dy = location.direction.dy
        rise = location.grade.rise
        run = location.grade.run
    }
}

/// An edge's vertical alignment: `{"structure", "segments": [{"kind",
/// "start", "end"}, ...], "steepest": {"rise", "run"}}`, from its `from`
/// node, the kinds `"level"`, `"up"`, `"down"` and `"transition"`.
struct AlignmentSummary: Codable, Equatable {
    struct Segment: Codable, Equatable {
        var kind: String
        var start: Int64
        var end: Int64
    }

    var structure: StructureName
    var segments: [Segment]
    var steepest: GradeSummary

    init(_ alignment: TrackAlignment) {
        self.init(structure: alignment.edge.structure, segments: alignment.segments, steepest: alignment.steepestGrade)
    }

    init(structure: TrackStructure, segments: [TrackProfileSegment], steepest: TrackGrade) {
        self.structure = StructureName(structure)
        self.segments = segments.map { segment in
            let kind = switch segment.kind {
            case .level: "level"
            case .up: "up"
            case .down: "down"
            case .transition: "transition"
            }
            return Segment(kind: kind, start: segment.start, end: segment.end)
        }
        self.steepest = GradeSummary(steepest)
    }
}

/// A platform on the track network: `{"station", "edge", "start", "end"}`.
struct PlatformSummary: Codable, Equatable {
    var station: Int
    var edge: Int
    var start: Int64
    var end: Int64

    init(_ platform: TrackPlatform) {
        station = platform.station.rawValue
        edge = platform.edge.number
        start = platform.start
        end = platform.end
    }
}

/// A platform's level: `{"edge", "start", "end", "height", "structure"}`.
struct PlatformLevelSummary: Codable, Equatable {
    var edge: Int
    var start: Int64
    var end: Int64
    var height: Int64
    var structure: StructureName

    init(_ platform: RailwaySnapshot.Platform) {
        self.init(platform: platform.platform, height: platform.height, structure: platform.structure)
    }

    init(platform: TrackPlatform, height: Int64, structure: TrackStructure) {
        edge = platform.edge.number
        start = platform.start
        end = platform.end
        self.height = height
        self.structure = StructureName(structure)
    }
}
