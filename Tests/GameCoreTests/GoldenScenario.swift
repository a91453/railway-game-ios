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

// Fixture times other than the clock are whole minutes, and most tests were
// written when the basic step was a game minute and still work in them
// (Stage W2a made it a second): they read times and periods as minutes
// through these, which refuse a time between minutes. Here, beside the
// runner, so that the Wasm probe (Web/WasmProbe), which reuses this file
// alone, has them too.
extension GameTime {
    /// This time in whole minutes. A time between two minutes is a failure
    /// of the test that reads it.
    var minutes: Int64 {
        precondition(isWholeMinute, "\(seconds) s is not a whole minute")
        return minute
    }
}

/// `minutes` as a timetable period (``Train/timetablePeriod``), which
/// counts seconds; a period too large or too small for that is the largest
/// or smallest there is, so that tests of extreme periods keep meaning one.
func periodSeconds(_ minutes: Int64?) -> Int64? {
    minutes.map {
        let (seconds, overflow) = $0.multipliedReportingOverflow(by: GameTime.secondsPerMinute)
        return overflow ? ($0 > 0 ? .max : .min) : seconds
    }
}

extension Train {
    /// ``timetablePeriod`` in whole minutes; a period that is not whole
    /// minutes is a failure of the test that reads it.
    var timetablePeriodMinutes: Int64? {
        timetablePeriod.map {
            precondition($0 % GameTime.secondsPerMinute == 0, "a period of \($0) s is not whole minutes")
            return $0 / GameTime.secondsPerMinute
        }
    }
}

/// A checked-in scenario: a starting world, steps in order (commands with the
/// outcome each one must have, and read-only observations with the answer
/// each one must give), and the state the world must end in.
struct GoldenScenario: Decodable {
    static let schemaVersion = 48

    var description: String
    var initialState: InitialState
    var steps: [Step]
    var expectedFinalState: WorldSummary

    struct InitialState: Decodable {
        /// Schema 30 (Stage F3d): how far the world reaches, in world units.
        var worldWidth: Int64
        var worldHeight: Int64
        var balance: Int64
        var costs: Costs
        /// The clock, in whole minutes or (schema 23) in seconds: exactly
        /// one of the two (see ``GoldenScenario/clockSeconds(minutes:seconds:)``).
        var gameMinutes: Int64?
        var gameSeconds: Int64?
        var speed: SpeedName

        /// The clock in seconds.
        var seconds: Int64 {
            gameSeconds ?? gameMinutes! * GameTime.secondsPerMinute
        }

        func makeWorld() throws(GameError) -> GameWorld {
            GameWorld(
                bounds: try WorldBounds(width: worldWidth, height: worldHeight),
                economy: GameEconomy(balance: Money(balance), costs: costs.constructionCosts),
                clock: GameClock(now: GameTime(seconds: seconds), speed: speed.speed)
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
        case invalidClock(String)
    }

    /// Checks a clock written as `gameMinutes` or `gameSeconds` (schema
    /// 23): exactly one of them, and `gameSeconds` only for a time that is
    /// not a whole minute, so each time has one way to be written.
    static func checkClock(minutes: Int64?, seconds: Int64?, in part: String) throws {
        switch (minutes, seconds) {
        case (_?, nil):
            return
        case (nil, let seconds?) where seconds % GameTime.secondsPerMinute != 0:
            return
        case (nil, _?):
            throw FixtureError.invalidClock("\(part): a whole minute is written as gameMinutes")
        default:
            throw FixtureError.invalidClock("\(part): needs exactly one of gameMinutes and gameSeconds")
        }
    }

    /// Decodes a fixture, rejecting schema versions this reader does not know
    /// before looking at anything else.
    static func decode(_ data: Data) throws -> GoldenScenario {
        struct Header: Decodable {
            var schemaVersion: Int
        }
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        guard (30..<schemaVersion).contains(version) || version == schemaVersion else { throw FixtureError.unsupportedSchemaVersion(version) }
        let scenario = try JSONDecoder().decode(GoldenScenario.self, from: data)
        try checkClock(minutes: scenario.initialState.gameMinutes, seconds: scenario.initialState.gameSeconds, in: "initialState")
        let final = scenario.expectedFinalState
        try checkClock(minutes: final.gameMinutes, seconds: final.gameSeconds, in: "expectedFinalState")
        if let tenths = final.pendingTenths, !(1..<10).contains(tenths) {
            throw FixtureError.invalidClock("expectedFinalState: pendingTenths is 1 to 9, or left out")
        }
        return scenario
    }

    /// Whether a step sets network routing or a station's operation mode
    /// (schema 35), which only GameCore runs.
    var usesPassengerNetwork: Bool {
        steps.contains { step in
            switch step {
            case .command(.setPassengerRoutingMode, _), .command(.setStationOperationMode, _): true
            default: false
            }
        }
    }

    /// Whether a step sets or observes land (schema 36, Phase 6a), its
    /// buildings or town growth (schema 37, Phase 6c-1), or the buildings
    /// the player places (schema 41, decision 92), which the
    /// reference model does not hold: ``LandTests`` checks the towns and
    /// ``BuildingTests`` the buildings against references of their own.
    var usesLand: Bool {
        steps.contains { step in
            switch step {
            case .command(.foundTowns, _), .command(.setLand, _), .command(.setLandDemand, _),
                 .command(.setCityBuildings, _), .command(.setTownGrowth, _),
                 .observe(.landCatchment, _), .observe(.landCell, _), .observe(.building, _), .observe(.townGrowth, _), .observe(.landValue, _),
                 .command(.placeBuilding, _), .command(.removePlacedBuilding, _), .observe(.placedBuilding, _),
                 .command(.setZone, _), .observe(.zone, _), .command(.setWater, _), .observe(.water, _), .command(.setSteep, _), .observe(.steep, _),
                 .command(.setGround, _), .observe(.groundHeight, _), .command(.mapGround, _),
                 .command(.buildTrackEdge(_, _, _, _, .automatic), _): true
            default: false
            }
        }
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
        case position, movement, found, stations, timetable, execution
        case level, journey, trains, minutes, loads, resources, conflicts, tracks
        case edge, location, transitions, path, points
        case pose, alignment, nodes, trackPlatforms, levels, trainPath, train
        case trip, daily, hourly, groups, ledger, riders, fare, accounts, report
        case times, lateness, scheduledWaits
        case landTotals, landCell, building, townGrowth, landValue, placedBuilding, zone, water, steep, groundHeight
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
            case .landCatchment:
                try requireOnly([.found, .landTotals], answering: "landCatchment")
                self = try .observe(observation, expect: .landTotals(Self.found(expect, .landTotals, LandTotalsSummary.self)))
            case .landCell:
                try requireOnly([.found, .landCell], answering: "landCell")
                self = try .observe(observation, expect: .landCell(Self.found(expect, .landCell, LandCellSummary.self)))
            case .building:
                try requireOnly([.found, .building], answering: "building")
                self = try .observe(observation, expect: .building(Self.found(expect, .building, BuildingSummary.self)))
            case .placedBuilding:
                try requireOnly([.found, .placedBuilding], answering: "placedBuilding")
                self = try .observe(observation, expect: .placedBuilding(Self.found(expect, .placedBuilding, PlacedBuildingSummary.self)))
            case .zone:
                try requireOnly([.found, .zone], answering: "zone")
                self = try .observe(observation, expect: .zone(Self.found(expect, .zone, Zone.self)))
            case .water:
                try requireOnly([.water], answering: "water")
                self = try .observe(observation, expect: .water(expect.decode(Bool.self, forKey: .water)))
            case .steep:
                try requireOnly([.steep], answering: "steep")
                self = try .observe(observation, expect: .steep(expect.decode(Bool.self, forKey: .steep)))
            case .groundHeight:
                try requireOnly([.found, .groundHeight], answering: "groundHeight")
                self = try .observe(observation, expect: .groundHeight(Self.found(expect, .groundHeight, Int64.self)))
            case .landValue:
                try requireOnly([.found, .landValue], answering: "landValue")
                self = try .observe(observation, expect: .landValue(Self.found(expect, .landValue, LandValueSummary.self)))
            case .townGrowth:
                try requireOnly([.found, .townGrowth], answering: "townGrowth")
                self = try .observe(observation, expect: .townGrowth(Self.found(expect, .townGrowth, TownGrowthSummary.self)))
            case .scheduledWaits:
                try requireOnly([.scheduledWaits], answering: "scheduledWaits")
                self = try .observe(observation, expect: .scheduledWaits(expect.decode([TrafficWaitSummary].self, forKey: .scheduledWaits)))
            case .train:
                try requireOnly([.position, .movement], answering: "train")
                let state = try TrainState(
                    position: expect.decode(TrainPositionSummary.self, forKey: .position),
                    movement: expect.decode(TrainMovementSummary.self, forKey: .movement)
                )
                self = .observe(observation, expect: .train(state))
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
            case .occupancy:
                try requireOnly([.resources], answering: "occupancy")
                self = try .observe(observation, expect: .resources(expect.decode([ResourceSummary].self, forKey: .resources).map(\.resource)))
            case .conflicts:
                try requireOnly([.conflicts], answering: "conflicts")
                self = try .observe(observation, expect: .conflicts(expect.decode([ConflictSummary].self, forKey: .conflicts).map(\.conflict)))
            case .parallelTracks:
                try requireOnly([.tracks], answering: "parallelTracks")
                self = try .observe(observation, expect: .tracks(expect.decode(Int.self, forKey: .tracks)))
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
            case .pathToStation:
                try requireOnly([.found, .trainPath], answering: "pathToStation")
                self = try .observe(observation, expect: .trainPath(Self.found(expect, .trainPath, PathSummary.self)))
            case .reservation, .heldResources:
                try requireOnly([.resources], answering: "a train's track")
                self = try .observe(observation, expect: .resources(expect.decode([ResourceSummary].self, forKey: .resources).map(\.resource)))
            case .routeHolder:
                try requireOnly([.found, .train], answering: "routeHolder")
                self = try .observe(observation, expect: .holder(Self.found(expect, .train, Int.self).map(TrainID.init(rawValue:))))
            case .passengerTrip:
                try requireOnly([.found, .trip], answering: "passengerTrip")
                self = try .observe(observation, expect: .trip(Self.found(expect, .trip, TripSummary.self)))
            case .demand:
                try requireOnly([.daily, .hourly], answering: "demand")
                let hourly = try expect.decode([Int64].self, forKey: .hourly)
                guard hourly.count == 24 else {
                    throw DecodingError.dataCorruptedError(forKey: .hourly, in: expect, debugDescription: "A day has 24 hours.")
                }
                self = try .observe(observation, expect: .demand(daily: expect.decode(Int64.self, forKey: .daily), hourly: hourly))
            case .waitingPassengers:
                try requireOnly([.groups], answering: "waitingPassengers")
                self = try .observe(observation, expect: .groups(expect.decode([WaitingGroupSummary].self, forKey: .groups)))
            case .passengerLedger:
                try requireOnly([.ledger], answering: "passengerLedger")
                self = try .observe(observation, expect: .ledger(expect.decode(LedgerSummary.self, forKey: .ledger)))
            case .riders:
                try requireOnly([.riders], answering: "riders")
                self = try .observe(observation, expect: .riders(expect.decode([RidingGroupSummary].self, forKey: .riders)))
            case .tripFare:
                try requireOnly([.found, .fare], answering: "tripFare")
                self = try .observe(observation, expect: .fare(Self.found(expect, .fare, Int64.self)))
            case .accounts:
                try requireOnly([.accounts], answering: "accounts")
                self = try .observe(observation, expect: .accounts(expect.decode(AccountsSummary.self, forKey: .accounts)))
            case .financeReport:
                try requireOnly([.report], answering: "financeReport")
                self = try .observe(observation, expect: .report(expect.decode(ReportSummary.self, forKey: .report)))
            case .serviceTimes:
                try requireOnly([.found, .times], answering: "serviceTimes")
                self = try .observe(observation, expect: .times(Self.found(expect, .times, TimesSummary.self)))
            case .lateness:
                try requireOnly([.found, .lateness], answering: "lateness")
                self = try .observe(observation, expect: .lateness(Self.found(expect, .lateness, Int64.self)))
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
    /// A station at a point of the world, taking no tile (schema 26,
    /// Stage F1).
    case buildStationAt(name: String, PlanPoint)
    case purchaseTrain(name: String)
    case setTrainCars(TrainID, Int)
    case placeTrain(TrainID, TrainPosition)
    case unplaceTrain(TrainID)
    case reverseTrain(TrainID)
    case setTrainMovementRate(TrainID, Int64)
    case setTrainTimetable(TrainID, [ScheduledStop], period: Int64?)
    case startTrainService(TrainID)
    case stopTrainService(TrainID)
    case createLine(name: String, stops: [StationID])
    case removeLine(LineID)
    case setLineStops(LineID, [StationID])
    /// Makes a line a ring or a line again (schema 27, decision 49).
    case setLineRing(LineID, Bool)
    case setLineRoutePreferences(LineID, [LineRoutePreference], pattern: Int?)
    case setLinePerformance(LineID, TrainPerformance)
    case setTrainPerformance(TrainID, TrainPerformance)
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
    case setTrainPath(TrainID, [TrackTraversal], end: Int64?)
    case addTrackPlatform(StationID, TrackEdgeID, start: Int64, end: Int64)
    case removeTrackPlatform(StationID, TrackEdgeID, start: Int64)
    case setTrafficControl(Bool)
    case setStationDemand(StationID, StationDemand?)
    case setEconomyMode(EconomyMode)
    case setFareRules(FareRules)
    /// Schema 35 (Phase 5F): network passenger routing and station modes.
    case setPassengerRoutingMode(PassengerRoutingMode)
    case setStationOperationMode(StationID, StationOperationMode)
    /// Schema 36 (Phase 6a): land.
    case foundTowns(UInt32)
    case setLand([LandCell])
    case setLandDemand(Bool)
    /// Schema 37 (Phase 6c-1): the city's buildings, and town growth, which
    /// grows the land.
    case setCityBuildings(Bool)
    case setTownGrowth(Bool)
    /// Schema 41 (decision 92): a building the player places.
    case placeBuilding(PlacedBuildingKind, PlanPoint)
    /// Schema 42 (decision 94): demolishing one.
    case removePlacedBuilding(PlacedBuildingID)
    /// Schema 43 (decision 98): zoning a rectangle of cells, or clearing it.
    case setZone(Zone?, rows: ClosedRange<Int>, columns: ClosedRange<Int>)
    /// Schema 44 (decision 105): a real-world map's water, as runs along
    /// rows.
    case setWater([WaterRun])
    /// Schema 46 (decision 115): a real-world map's steep slopes, as runs.
    case setSteep([WaterRun])
    /// Schema 47 (decision 124): the ground's heights of some blocks.
    case setGround([GroundBlock])
    /// Schema 48 (decision 124): a world with ground before any is read.
    case mapGround

    /// Applies the command through the matching `GameWorld` command.
    func apply(to world: inout GameWorld) -> StepOutcome {
        do throws(GameError) {
            switch self {
            case .buildStationAt(let name, let point):
                try world.buildStation(named: name, at: point)
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
            case .setTrainTimetable(let id, let stops, let period):
                try world.setTrainTimetable(id, to: stops, repeatingEvery: periodSeconds(period))
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
            case .setLineRing(let id, let isRing):
                try world.setLineRing(id, to: isRing)
            case .setLineRoutePreferences(let id, let routes, let pattern):
                try world.setLineRoutePreferences(id, to: routes, pattern: pattern)
            case .setLinePerformance(let id, let performance):
                try world.setLinePerformance(id, to: performance)
            case .setTrainPerformance(let id, let performance):
                try world.setTrainPerformance(id, to: performance)
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
            case .setTrainPath(let id, let path, let end):
                try world.setTrainContinuation(id, along: path, stoppingAt: end)
            case .addTrackPlatform(let station, let edge, let start, let end):
                try world.addTrackPlatform(station, on: edge, from: start, to: end)
            case .removeTrackPlatform(let station, let edge, let start):
                try world.removeTrackPlatform(station, on: edge, from: start)
            case .setTrafficControl(let enabled):
                try world.setTrafficControl(enabled)
            case .setStationDemand(let id, let demand):
                try world.setStationDemand(id, to: demand)
            case .setEconomyMode(let mode):
                world.setEconomyMode(mode)
            case .setFareRules(let rules):
                try world.setFareRules(rules)
            case .setPassengerRoutingMode(let mode):
                world.setPassengerRoutingMode(mode)
            case .setStationOperationMode(let id, let mode):
                try world.setStationOperationMode(id, to: mode)
            case .foundTowns(let seed):
                world.foundTowns(seed: seed)
            case .setLand(let cells):
                try world.setLand(cells)
            case .setLandDemand(let enabled):
                world.setLandDemand(enabled)
            case .setCityBuildings(let enabled):
                world.setCityBuildings(enabled)
            case .setTownGrowth(let enabled):
                world.setTownGrowth(enabled)
            case .placeBuilding(let kind, let point):
                try world.placeBuilding(kind, at: point)
            case .removePlacedBuilding(let id):
                try world.removePlacedBuilding(id)
            case .setZone(let zone, let rows, let columns):
                try world.setZone(zone, rows: rows, columns: columns)
            case .setWater(let runs):
                try world.setWater(runs.flatMap { run in (run.column..<run.column + run.count).map { CellPosition(row: run.row, column: $0) } })
            case .setSteep(let runs):
                try world.setSteep(runs.flatMap { run in (run.column..<run.column + run.count).map { CellPosition(row: run.row, column: $0) } })
            case .setGround(let blocks):
                try world.setGround(blocks)
            case .mapGround:
                try world.mapGround()
            }
            return .ok
        } catch {
            return .rejected(error)
        }
    }
}

extension ScenarioCommand: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, x, y, name, train, position, rate, timetable, `repeat`, speed, ticks
        case line, stops, window, trains, bands, targetHeadways, pattern, calls, station, cars, ring
        case z, from, to, curve, edge, node, path
        case profile, structure, start, end, enabled, demand, mode, rules
        case performance, point, routePreferences
        case seed, cells
        case kind, building
        case zone, rows, columns
        case runs
        case blocks
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        // Schema 36: land (Phase 6a).
        case "foundTowns":
            self = try .foundTowns(container.decode(UInt32.self, forKey: .seed))
        case "setLand":
            self = try .setLand(container.decode([LandCellSummary].self, forKey: .cells).map(\.cell))
        case "setLandDemand":
            self = try .setLandDemand(container.decode(Bool.self, forKey: .enabled))
        // Schema 37: city buildings (Phase 6c-1).
        case "setCityBuildings":
            self = try .setCityBuildings(container.decode(Bool.self, forKey: .enabled))
        case "setTownGrowth":
            self = try .setTownGrowth(container.decode(Bool.self, forKey: .enabled))
        // Schema 41: buildings the player places (decision 92).
        case "placeBuilding":
            self = try .placeBuilding(container.decode(PlacedBuildingKind.self, forKey: .kind), container.decode(PlanPoint.self, forKey: .point))
        // Schema 42: demolishing the company's buildings (decision 94).
        case "removePlacedBuilding":
            self = .removePlacedBuilding(PlacedBuildingID(rawValue: try container.decode(Int.self, forKey: .building)))
        // Schema 43: zoning (decision 98). `"zone"` is required, `null` to
        // clear; `"rows"` and `"columns"` are `[first, last]`.
        case "setZone":
            guard container.contains(.zone) else {
                throw DecodingError.keyNotFound(CodingKeys.zone, DecodingError.Context(codingPath: container.codingPath, debugDescription: "setZone needs \"zone\"."))
            }
            let rows = try container.decode([Int].self, forKey: .rows), columns = try container.decode([Int].self, forKey: .columns)
            guard rows.count == 2, columns.count == 2, rows[0] <= rows[1], columns[0] <= columns[1] else {
                throw DecodingError.dataCorruptedError(forKey: .rows, in: container, debugDescription: "setZone's rows and columns are [first, last].")
            }
            self = try .setZone(container.decodeIfPresent(Zone.self, forKey: .zone), rows: rows[0]...rows[1], columns: columns[0]...columns[1])
        // Schema 44: water (decision 105), `"runs": [{"row", "column",
        // "count"}]`.
        case "setWater":
            let runs = try container.decode([WaterRun].self, forKey: .runs)
            guard runs.allSatisfy({ $0.count > 0 && $0.count <= 1 << 16 }) else {
                throw DecodingError.dataCorruptedError(forKey: .runs, in: container, debugDescription: "setWater's runs hold 1 to 65,536 cells.")
            }
            self = .setWater(runs)
        // Schema 46: steep slopes (decision 115), as setWater.
        case "setSteep":
            let runs = try container.decode([WaterRun].self, forKey: .runs)
            guard runs.allSatisfy({ $0.count > 0 && $0.count <= 1 << 16 }) else {
                throw DecodingError.dataCorruptedError(forKey: .runs, in: container, debugDescription: "setSteep's runs hold 1 to 65,536 cells.")
            }
            self = .setSteep(runs)
        // Schema 47: the ground's height (decision 124), `"blocks": [{"row",
        // "column", "heights": [17 × 17 metres]}]`.
        case "setGround":
            self = try .setGround(container.decode([GroundBlock].self, forKey: .blocks))
        // Schema 48: a world with ground (decision 124).
        case "mapGround":
            self = .mapGround
        case "buildTrack", "buildTurnout", "buildCrossing", "removeTrack", "buildStation", "extendStation", "setTrainContinuation":
            // The grid's commands, which no fixture uses since Stage F3c
            // removed the grid (ARCHITECTURE decision 51).
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "\"\(type)\" is a command of the grid, which Stage F3c removed.")
        case "buildStationAt":
            self = try .buildStationAt(name: container.decode(String.self, forKey: .name), container.decode(PlanPoint.self, forKey: .point))
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
                throw DecodingError.dataCorruptedError(forKey: .position, in: container, debugDescription: "placeTrain needs an \"edge\" position.")
            }
            self = .placeTrain(train, position)
        case "unplaceTrain":
            self = try .unplaceTrain(container.decodeTrain(forKey: .train))
        case "reverseTrain":
            self = try .reverseTrain(container.decodeTrain(forKey: .train))
        case "setTrainMovementRate":
            // Read as written: rejecting a negative rate is GameCore's decision.
            self = try .setTrainMovementRate(container.decodeTrain(forKey: .train), container.decode(Int64.self, forKey: .rate))
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
        // Line commands are read as written: rejecting too few stops, a
        // performance, a window, counts or a day that do not fit is
        // GameCore's decision.
        case "createLine":
            let stops = try container.decode([Int].self, forKey: .stops).map(StationID.init(rawValue:))
            self = try .createLine(name: container.decode(String.self, forKey: .name), stops: stops)
        case "removeLine":
            self = try .removeLine(container.decodeLine(forKey: .line))
        case "setLineStops":
            let stops = try container.decode([Int].self, forKey: .stops).map(StationID.init(rawValue:))
            self = try .setLineStops(container.decodeLine(forKey: .line), stops)
        case "setLineRing":
            self = try .setLineRing(container.decodeLine(forKey: .line), container.decode(Bool.self, forKey: .ring))
        case "setLineRoutePreferences":
            self = try .setLineRoutePreferences(container.decodeLine(forKey: .line), container.decode([LineRoutePreference].self, forKey: .routePreferences), pattern: container.decodeIfPresent(Int.self, forKey: .pattern))
        case "setLinePerformance":
            let performance = try container.decode(PerformanceSummary.self, forKey: .performance).performance
            self = try .setLinePerformance(container.decodeLine(forKey: .line), performance)
        case "setTrainPerformance":
            // Read as written: rejecting a performance that is not valid is
            // GameCore's decision (schema 25, Stage W2c).
            let performance = try container.decode(PerformanceSummary.self, forKey: .performance).performance
            self = try .setTrainPerformance(container.decodeTrain(forKey: .train), performance)
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
            // Schema 18: "end" is absent for a path that runs to the end of
            // its last edge.
            let end = try container.contains(.end) ? container.decode(Int64.self, forKey: .end) : nil
            self = try .setTrainPath(container.decodeTrain(forKey: .train), path, end: end)
        case "setTrafficControl":
            // Schema 19: traffic control on or off.
            self = try .setTrafficControl(container.decode(Bool.self, forKey: .enabled))
        case "setStationDemand":
            // Schema 20: "demand" is required; `null` clears it. Read as
            // written: whether the trips are valid is GameCore's decision.
            guard container.contains(.demand) else {
                throw DecodingError.keyNotFound(CodingKeys.demand, DecodingError.Context(codingPath: container.codingPath, debugDescription: "setStationDemand needs \"demand\"."))
            }
            let demand = try container.decodeNil(forKey: .demand) ? nil : container.decode(DemandSummary.self, forKey: .demand).demand
            self = try .setStationDemand(container.decodeStation(forKey: .station), demand)
        // Schema 22: the economy (G1c).
        case "setEconomyMode":
            let mode = try container.decode(String.self, forKey: .mode)
            guard let value = EconomyMode(rawValue: mode) else {
                throw DecodingError.dataCorruptedError(forKey: .mode, in: container, debugDescription: "Unknown economy mode \"\(mode)\".")
            }
            self = .setEconomyMode(value)
        case "setFareRules":
            self = try .setFareRules(container.decode(FareRulesSummary.self, forKey: .rules).rules)
        // Schema 35: network passenger routing and station modes (Phase 5F).
        case "setPassengerRoutingMode":
            let mode = try container.decode(String.self, forKey: .mode)
            guard let value = PassengerRoutingMode(rawValue: mode) else {
                throw DecodingError.dataCorruptedError(forKey: .mode, in: container, debugDescription: "Unknown routing mode \"\(mode)\".")
            }
            self = .setPassengerRoutingMode(value)
        case "setStationOperationMode":
            let mode = try container.decode(String.self, forKey: .mode)
            guard let value = StationOperationMode(rawValue: mode) else {
                throw DecodingError.dataCorruptedError(forKey: .mode, in: container, debugDescription: "Unknown operation mode \"\(mode)\".")
            }
            self = try .setStationOperationMode(container.decodeStation(forKey: .station), value)
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
        case result, x, y, width, height, required, available, train, station, line, pattern, node, edge, edges, trains, trainType, building
        case row, column
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let result = try container.decode(String.self, forKey: .result)
        switch result {
        case "ok":
            self = .ok
        case "invalidMapSize":
            let width = try container.decode(Int64.self, forKey: .width)
            self = try .rejected(.invalidMapSize(width: width, height: container.decode(Int64.self, forKey: .height)))
        case "outOfBounds":
            // Schema 30 (Stage F3d): the point, in world units.
            self = try .rejected(.outOfBounds(container.decodePoint(x: .x, y: .y)))
        case "tileOccupied", "invalidTrackConnections", "noTrackToRemove", "trackInUse", "invalidStationTile":
            // The grid's errors, which no command can give since Stage F3c
            // removed the grid (ARCHITECTURE decision 51).
            throw DecodingError.dataCorruptedError(forKey: .result, in: container, debugDescription: "\"\(result)\" is an error of the grid, which Stage F3c removed.")
        case "invalidName":
            self = .rejected(.invalidName)
        case "insufficientFunds":
            let required = try Money(container.decode(Int64.self, forKey: .required))
            self = try .rejected(.insufficientFunds(required: required, available: Money(container.decode(Int64.self, forKey: .available))))
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
        case "invalidTrainPerformance":
            self = .rejected(.invalidTrainPerformance)
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
        case "invalidLineRoutePreference":
            self = .rejected(.invalidLineRoutePreference)
        case "invalidLinePattern":
            self = .rejected(.invalidLinePattern)
        case "unknownLinePattern":
            self = try .rejected(.unknownLinePattern(container.decode(Int.self, forKey: .pattern)))
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
        case "trackTooClose":
            self = try .rejected(.trackTooClose(.edge(container.decode(Int.self, forKey: .edge))))
        case "tracksWouldBeTooClose":
            let ids = try container.decode([Int].self, forKey: .edges)
            guard ids.count == 2 else {
                throw DecodingError.dataCorruptedError(forKey: .edges, in: container, debugDescription: "tracksWouldBeTooClose names two edges.")
            }
            self = .rejected(.tracksWouldBeTooClose(.edge(ids[0]), .edge(ids[1])))
        case "trackEdgeHasPlatform":
            self = try .rejected(.trackEdgeHasPlatform(.edge(container.decode(Int.self, forKey: .edge))))
        case "trackEdgeInLineRoute":
            self = try .rejected(.trackEdgeInLineRoute(container.decodeLine(forKey: .line)))
        case "invalidPlatform":
            self = .rejected(.invalidPlatform)
        case "trackReserved":
            self = try .rejected(.trackReserved(container.decodeTrain(forKey: .train)))
        case "trainsShareTrack":
            let ids = try container.decode([Int].self, forKey: .trains)
            guard ids.count == 2 else {
                throw DecodingError.dataCorruptedError(forKey: .trains, in: container, debugDescription: "trainsShareTrack names two trains.")
            }
            self = .rejected(.trainsShareTrack(TrainID(rawValue: ids[0]), TrainID(rawValue: ids[1])))
        case "invalidStationDemand":
            self = .rejected(.invalidStationDemand)
        case "invalidFareRules":
            self = .rejected(.invalidFareRules)
        case "invalidLoanAmount":
            self = .rejected(.invalidLoanAmount)
        case "loanNeedsManagement":
            self = .rejected(.loanNeedsManagement)
        case "invalidLand":
            self = .rejected(.invalidLand)
        case "stationDemandFromLand":
            self = .rejected(.stationDemandFromLand)
        case "invalidTransferGroup":
            self = .rejected(.invalidTransferGroup)
        case "invalidScenario":
            self = .rejected(.invalidScenario)
        case "trainTypeUnavailable":
            self = .rejected(.trainTypeUnavailable(try container.decode(TrainType.self, forKey: .trainType)))
        case "buildingOverlaps":
            self = .rejected(.buildingOverlaps(PlacedBuildingID(rawValue: try container.decode(Int.self, forKey: .building))))
        case "buildingOnTrack":
            self = try .rejected(.buildingOnTrack(.edge(container.decode(Int.self, forKey: .edge))))
        case "buildingOnStation":
            self = try .rejected(.buildingOnStation(container.decodeStation(forKey: .station)))
        case "unknownPlacedBuilding":
            self = .rejected(.unknownPlacedBuilding(PlacedBuildingID(rawValue: try container.decode(Int.self, forKey: .building))))
        case "invalidZoneArea":
            self = .rejected(.invalidZoneArea)
        // Schema 44 (decision 105).
        case "invalidTerrain":
            self = .rejected(.invalidTerrain)
        // Schema 47 (decision 124).
        case "invalidGround":
            self = .rejected(.invalidGround)
        // Schema 48 (decision 124).
        case "groundNotLoaded":
            self = .rejected(.groundNotLoaded)
        case "trackOverWater":
            self = .rejected(.trackOverWater)
        case "structureTooHigh":
            self = .rejected(.structureTooHigh)
        // Schema 46 (decision 115).
        case "onSteepSlope":
            self = try .rejected(.onSteepSlope(row: container.decode(Int.self, forKey: .row), column: container.decode(Int.self, forKey: .column)))
        // Schema 45 (decision 111).
        case "needsShore":
            self = .rejected(.needsShore)
        case "onWater":
            self = try .rejected(.onWater(row: container.decode(Int.self, forKey: .row), column: container.decode(Int.self, forKey: .column)))
        default:
            throw DecodingError.dataCorruptedError(forKey: .result, in: container, debugDescription: "Unknown result \"\(result)\".")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        func encode(_ point: PlanPoint) throws {
            try container.encode(point.x, forKey: .x)
            try container.encode(point.y, forKey: .y)
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
        case .rejected(.outOfBounds(let point)):
            try container.encode("outOfBounds", forKey: .result)
            try encode(point)
        case .rejected(.invalidName):
            try container.encode("invalidName", forKey: .result)
        case .rejected(.insufficientFunds(let required, let available)):
            try container.encode("insufficientFunds", forKey: .result)
            try container.encode(required.amount, forKey: .required)
            try container.encode(available.amount, forKey: .available)
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
        case .rejected(.invalidTrainPerformance):
            try container.encode("invalidTrainPerformance", forKey: .result)
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
        case .rejected(.invalidLineRoutePreference):
            try container.encode("invalidLineRoutePreference", forKey: .result)
        case .rejected(.invalidLinePattern):
            try container.encode("invalidLinePattern", forKey: .result)
        case .rejected(.unknownLinePattern(let pattern)):
            try container.encode("unknownLinePattern", forKey: .result)
            try container.encode(pattern, forKey: .pattern)
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
        case .rejected(.trackTooClose(let edge)):
            try container.encode("trackTooClose", forKey: .result)
            try encodeEdge(edge)
        case .rejected(.tracksWouldBeTooClose(let first, let second)):
            try container.encode("tracksWouldBeTooClose", forKey: .result)
            try container.encode([first.number, second.number], forKey: .edges)
        case .rejected(.trackEdgeHasPlatform(let edge)):
            try container.encode("trackEdgeHasPlatform", forKey: .result)
            try encodeEdge(edge)
        case .rejected(.trackEdgeInLineRoute(let id)):
            try container.encode("trackEdgeInLineRoute", forKey: .result)
            try container.encode(id.rawValue, forKey: .line)
        case .rejected(.invalidPlatform):
            try container.encode("invalidPlatform", forKey: .result)
        case .rejected(.trackReserved(let id)):
            try container.encode("trackReserved", forKey: .result)
            try container.encode(id.rawValue, forKey: .train)
        case .rejected(.trainsShareTrack(let first, let second)):
            try container.encode("trainsShareTrack", forKey: .result)
            try container.encode([first.rawValue, second.rawValue], forKey: .trains)
        case .rejected(.invalidStationDemand):
            try container.encode("invalidStationDemand", forKey: .result)
        case .rejected(.invalidFareRules):
            try container.encode("invalidFareRules", forKey: .result)
        case .rejected(.invalidLoanAmount):
            try container.encode("invalidLoanAmount", forKey: .result)
        case .rejected(.loanNeedsManagement):
            try container.encode("loanNeedsManagement", forKey: .result)
        case .rejected(.invalidLand):
            try container.encode("invalidLand", forKey: .result)
        case .rejected(.stationDemandFromLand):
            try container.encode("stationDemandFromLand", forKey: .result)
        case .rejected(.invalidTransferGroup):
            try container.encode("invalidTransferGroup", forKey: .result)
        case .rejected(.invalidScenario):
            try container.encode("invalidScenario", forKey: .result)
        case .rejected(.trainTypeUnavailable(let type)):
            try container.encode("trainTypeUnavailable", forKey: .result)
            try container.encode(type, forKey: .trainType)
        case .rejected(.buildingOverlaps(let id)):
            try container.encode("buildingOverlaps", forKey: .result)
            try container.encode(id.rawValue, forKey: .building)
        case .rejected(.buildingOnTrack(let edge)):
            try container.encode("buildingOnTrack", forKey: .result)
            try encodeEdge(edge)
        case .rejected(.buildingOnStation(let id)):
            try container.encode("buildingOnStation", forKey: .result)
            try container.encode(id.rawValue, forKey: .station)
        case .rejected(.invalidZoneArea):
            try container.encode("invalidZoneArea", forKey: .result)
        case .rejected(.invalidTerrain):
            try container.encode("invalidTerrain", forKey: .result)
        case .rejected(.invalidGround):
            try container.encode("invalidGround", forKey: .result)
        case .rejected(.groundNotLoaded):
            try container.encode("groundNotLoaded", forKey: .result)
        case .rejected(.trackOverWater):
            try container.encode("trackOverWater", forKey: .result)
        case .rejected(.structureTooHigh):
            try container.encode("structureTooHigh", forKey: .result)
        case .rejected(.needsShore):
            try container.encode("needsShore", forKey: .result)
        case .rejected(.onSteepSlope(let row, let column)):
            try container.encode("onSteepSlope", forKey: .result)
            try container.encode(row, forKey: .row)
            try container.encode(column, forKey: .column)
        case .rejected(.onWater(let row, let column)):
            try container.encode("onWater", forKey: .result)
            try container.encode(row, forKey: .row)
            try container.encode(column, forKey: .column)
        case .rejected(.unknownPlacedBuilding(let id)):
            try container.encode("unknownPlacedBuilding", forKey: .result)
            try container.encode(id.rawValue, forKey: .building)
        }
        // Fixtures name network nodes and edges by number.
        func encodeNode(_ node: TrackNodeID) throws {
            try container.encode(node.number, forKey: .node)
        }
        func encodeEdge(_ edge: TrackEdgeID) throws {
            try container.encode(edge.number, forKey: .edge)
        }
    }
}

// MARK: - Observations

/// A read-only query as a scenario step, tagged by `"type"`: one train's
/// position and movement, the stations a train is stopped at, one train's
/// timetable, how far its timetable service has got, what is derived for a
/// service line (its level at a time, its journey, how many trains it can
/// and does run, and its headway), the track network and what trains hold
/// on it, passengers and the accounts. Observations are not commands: they
/// ask the world through its public queries and never change it.
enum ScenarioObservation: Equatable {
    case train(TrainID)
    case stationStops(TrainID)
    case wholeTrainStops(TrainID)
    case timetable(TrainID)
    case execution(TrainID)
    case serviceLevel(LineID, at: GameTime)
    case lineJourney(LineID, pattern: Int?)
    case lineMaximumTrains(LineID, pattern: Int?)
    case lineTrainsInService(LineID, ServiceLevel, pattern: Int?)
    case lineHeadway(LineID, ServiceLevel, pattern: Int?)
    case lineSegmentLoads(LineID, ServiceLevel)
    case occupancy(TrainID)
    case conflicts
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
    case pathToStation(from: TrainPosition, station: StationID, cars: Int)
    case reservation(TrainID)
    case heldResources(TrainID)
    case routeHolder(TrainID)
    case passengerTrip(from: StationID, to: StationID)
    case demand(from: StationID, to: StationID)
    case waitingPassengers(StationID)
    case passengerLedger(StationID)
    case riders(TrainID)
    case tripFare(from: StationID, to: StationID)
    case accounts
    case financeReport(FinancePeriod)
    /// Schema 24 (Stage W2b): a train's service times, and its lateness.
    case serviceTimes(TrainID)
    case scheduledWaits
    case lateness(TrainID)
    /// Schema 36 (Phase 6a): a station's catchment and a cell of land.
    case landCatchment(StationID)
    case landCell(row: Int, column: Int)
    /// Schema 37 (Phase 6c-1): the building on a cell and what it holds.
    case building(row: Int, column: Int)
    /// Schema 38 (Phase 6c-2): how town growth measures a station.
    case townGrowth(StationID)
    /// Schema 39 (Phase 6c-3): what a cell of land is worth.
    case landValue(row: Int, column: Int)
    /// Schema 41 (decision 92): a building the player placed.
    case placedBuilding(PlacedBuildingID)
    /// Schema 43 (decision 98): a cell's zone.
    case zone(row: Int, column: Int)
    /// Schema 44 (decision 105): whether a cell is water.
    case water(row: Int, column: Int)
    /// Schema 46 (decision 115): whether a cell is steep.
    case steep(row: Int, column: Int)
    /// Schema 47 (decision 124): the ground's height at a point, in world
    /// units.
    case groundHeight(PlanPoint)

    func answer(in world: GameWorld) -> ObservationAnswer {
        switch self {
        case .landCatchment(let id):
            .landTotals(world.landCatchment(of: id).map(LandTotalsSummary.init))
        case .landCell(let row, let column):
            .landCell(world.land.cell(row: row, column: column).map(LandCellSummary.init))
        case .townGrowth(let id):
            .townGrowth(world.townGrowth(of: id).map(TownGrowthSummary.init))
        case .landValue(let row, let column):
            .landValue(world.landValue(row: row, column: column).map(LandValueSummary.init))
        case .placedBuilding(let id):
            .placedBuilding(world.placedBuilding(id: id).map(PlacedBuildingSummary.init))
        case .zone(let row, let column):
            .zone(world.zones.zone(row: row, column: column))
        case .water(let row, let column):
            .water(world.isWater(row: row, column: column))
        case .steep(let row, let column):
            .steep(world.isSteep(row: row, column: column))
        case .groundHeight(let point):
            .groundHeight(world.groundHeight(at: point))
        case .building(let row, let column):
            .building(world.buildings.building(row: row, column: column).flatMap { building in
                world.buildingCapacity(row: row, column: column).map { BuildingSummary(building, capacity: $0) }
            })
        case .scheduledWaits:
            .scheduledWaits(world.scheduledTrafficWaits().map(TrafficWaitSummary.init))
        case .train(let id):
            .train(world.train(id: id).map(TrainState.init))
        case .stationStops(let train):
            .stations(world.stationsStoppedAt(by: train))
        case .wholeTrainStops(let train):
            .stations(world.stationsBesideWholeTrain(train))
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
        case .occupancy(let id):
            .resources(world.occupiedResources(of: id))
        case .conflicts:
            .conflicts(world.occupancyConflicts())
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
        case .pathToStation(let start, let station, let cars):
            .trainPath(world.path(from: start, toStation: station, length: Int64(cars - 1) * Train.carLength).map(PathSummary.init))
        case .reservation(let id):
            .resources(world.reservedResources(of: id))
        case .heldResources(let id):
            .resources(world.heldResources(of: id))
        case .routeHolder(let id):
            .holder(world.trainHoldingRoute(of: id))
        case .passengerTrip(let origin, let destination):
            .trip(world.passengerTrip(from: origin, to: destination).map(TripSummary.init))
        case .demand(let origin, let destination):
            .demand(daily: world.dailyDemand(from: origin, to: destination), hourly: world.hourlyDemand(from: origin, to: destination))
        case .waitingPassengers(let id):
            .groups(world.waitingPassengers(at: id).map(WaitingGroupSummary.init))
        case .passengerLedger(let id):
            .ledger(LedgerSummary(world.passengerLedger(of: id)))
        case .riders(let id):
            .riders(world.riders(of: id).map(RidingGroupSummary.init))
        case .tripFare(let origin, let destination):
            .fare(world.tripFare(from: origin, to: destination)?.amount)
        case .accounts:
            .accounts(AccountsSummary(world.accounts))
        case .financeReport(let period):
            .report(ReportSummary(world.financeReport(period)))
        case .serviceTimes(let id):
            .times(world.train(id: id)?.times.map(TimesSummary.init))
        case .lateness(let id):
            .lateness(world.lateness(of: id))
        }
    }
}

extension ScenarioObservation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, from, to, train, station, line, gameMinutes, level, pattern, cars, building
        case edge, direction, distance, node, period
        case row, column
        case point
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "connectedNeighbors", "isConnected", "route", "routeToStation", "platforms", "platformTracks", "exits", "trackSections":
            // The grid's observations, which no fixture uses since Stage F3c
            // removed the grid (ARCHITECTURE decision 51).
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "\"\(type)\" is an observation of the grid, which Stage F3c removed.")
        case "scheduledWaits":
            self = .scheduledWaits
        // Schema 36: land (Phase 6a).
        case "landCatchment":
            self = try .landCatchment(container.decodeStation(forKey: .station))
        case "landCell":
            self = try .landCell(row: container.decode(Int.self, forKey: .row), column: container.decode(Int.self, forKey: .column))
        // Schema 37: city buildings (Phase 6c-1).
        case "building":
            self = try .building(row: container.decode(Int.self, forKey: .row), column: container.decode(Int.self, forKey: .column))
        // Schema 38: town growth's measures (Phase 6c-2).
        case "townGrowth":
            self = try .townGrowth(container.decodeStation(forKey: .station))
        // Schema 39: land value (Phase 6c-3).
        case "landValue":
            self = try .landValue(row: container.decode(Int.self, forKey: .row), column: container.decode(Int.self, forKey: .column))
        // Schema 41: buildings the player places (decision 92).
        case "placedBuilding":
            self = .placedBuilding(PlacedBuildingID(rawValue: try container.decode(Int.self, forKey: .building)))
        // Schema 43: zoning (decision 98).
        case "zone":
            self = try .zone(row: container.decode(Int.self, forKey: .row), column: container.decode(Int.self, forKey: .column))
        // Schema 44: water (decision 105).
        case "water":
            self = try .water(row: container.decode(Int.self, forKey: .row), column: container.decode(Int.self, forKey: .column))
        // Schema 46: steep slopes (decision 115).
        case "steep":
            self = try .steep(row: container.decode(Int.self, forKey: .row), column: container.decode(Int.self, forKey: .column))
        // Schema 47: the ground's height (decision 124).
        case "groundHeight":
            self = try .groundHeight(container.decode(PlanPoint.self, forKey: .point))
        case "train":
            self = try .train(container.decodeTrain(forKey: .train))
        case "stationStops":
            self = try .stationStops(container.decodeTrain(forKey: .train))
        case "wholeTrainStops":
            self = try .wholeTrainStops(container.decodeTrain(forKey: .train))
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
        case "occupancy":
            self = try .occupancy(container.decodeTrain(forKey: .train))
        case "conflicts":
            self = .conflicts
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
        case "pathToStation":
            // Schema 18: the network's way to a station, from a position on
            // an edge.
            guard let start = try container.decode(TrainPositionSummary.self, forKey: .from).position else {
                throw DecodingError.dataCorruptedError(forKey: .from, in: container, debugDescription: "A path to a station starts from an \"edge\" position.")
            }
            let cars = try container.contains(.cars) ? container.decode(Int.self, forKey: .cars) : 1
            guard (Train.minimumCars...Train.maximumCars).contains(cars) else {
                throw DecodingError.dataCorruptedError(forKey: .cars, in: container, debugDescription: "A path is for 1 to \(Train.maximumCars) cars.")
            }
            self = try .pathToStation(from: start, station: container.decodeStation(forKey: .station), cars: cars)
        // Schema 19: route reservation under traffic control.
        case "reservation":
            self = try .reservation(container.decodeTrain(forKey: .train))
        case "heldResources":
            self = try .heldResources(container.decodeTrain(forKey: .train))
        case "routeHolder":
            self = try .routeHolder(container.decodeTrain(forKey: .train))
        // Schema 20: passengers (G1a).
        case "passengerTrip":
            self = try .passengerTrip(from: container.decodeStation(forKey: .from), to: container.decodeStation(forKey: .to))
        case "demand":
            self = try .demand(from: container.decodeStation(forKey: .from), to: container.decodeStation(forKey: .to))
        case "waitingPassengers":
            self = try .waitingPassengers(container.decodeStation(forKey: .station))
        case "passengerLedger":
            self = try .passengerLedger(container.decodeStation(forKey: .station))
        // Schema 21: riders (G1b).
        case "riders":
            self = try .riders(container.decodeTrain(forKey: .train))
        // Schema 22: the economy (G1c).
        case "tripFare":
            self = try .tripFare(from: container.decodeStation(forKey: .from), to: container.decodeStation(forKey: .to))
        case "serviceTimes":
            self = try .serviceTimes(container.decodeTrain(forKey: .train))
        case "lateness":
            self = try .lateness(container.decodeTrain(forKey: .train))
        case "accounts":
            self = .accounts
        case "financeReport":
            let period = try container.decode(String.self, forKey: .period)
            guard let value = FinancePeriod(rawValue: period) else {
                throw DecodingError.dataCorruptedError(forKey: .period, in: container, debugDescription: "Unknown period \"\(period)\".")
            }
            self = .financeReport(value)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown observation type \"\(type)\".")
        }
    }
}

/// What an observation answered. Encoded as `{"position", "movement"}` for
/// a train, `{"stations": [id, ...]}` for the stations a train is stopped
/// at, `{"timetable": [{"station", "arrival", "departure"}, ...]}` for a
/// train's timetable in its order, `{"execution": {"type", ...}}` for its
/// service, `{"level": "peak" | "offPeak" | "low" | "closed"}` for a line's
/// service level, `{"found": true, "journey": {...}}` / `{"found": false}`
/// for its journey, `{"found": true, "trains": n}` / `{"found": false}` for
/// how many trains it can or does run, and `{"found": true, "minutes": n}` /
/// `{"found": false}` for its headway, and `{"found": true, "loads": [n,
/// ...]}` / `{"found": false}` for the load on each of its segments; for
/// track resources `{"resources": [...]}` for what a train occupies,
/// `{"conflicts": [{"resource", "trains"}, ...]}` and `{"tracks": n}` for
/// the parallel tracks between two stations; `{"stations": [id, ...]}` for
/// the stations a train stands beside with its whole length; under traffic
/// control (schema 19) `{"resources": [...]}` for what a train has reserved
/// or holds, and `{"found": true, "train": id}` / `{"found": false}` for the
/// train holding the route another waits for. A train the world does not
/// have answers `{}` to `train`, `timetable` and `execution`, which no
/// fixture can expect. (Until Stage F3c the grid's observations answered
/// too: neighbours, connections, routes, platforms, exits, sections and
/// platform tracks.)
enum ObservationAnswer: Equatable {
    case train(TrainState?)
    case stations([StationID])
    case timetable([ScheduledStop]?)
    case execution(ExecutionSummary?)
    case level(ServiceLevel?)
    case journey(JourneySummary?)
    case trains(Int?)
    case minutes(Int64?)
    case loads([Int]?)
    case resources([TrackResource])
    case conflicts([TrackConflict])
    case tracks(Int)
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
    case trainPath(PathSummary?)
    case holder(TrainID?)
    case trip(TripSummary?)
    case demand(daily: Int64, hourly: [Int64])
    case groups([WaitingGroupSummary])
    case ledger(LedgerSummary)
    case riders([RidingGroupSummary])
    case fare(Int64?)
    case accounts(AccountsSummary)
    case report(ReportSummary)
    case times(TimesSummary?)
    case lateness(Int64?)
    case scheduledWaits([TrafficWaitSummary])
    case landTotals(LandTotalsSummary?)
    case landCell(LandCellSummary?)
    case building(BuildingSummary?)
    case townGrowth(TownGrowthSummary?)
    case landValue(LandValueSummary?)
    case placedBuilding(PlacedBuildingSummary?)
    case zone(Zone?)
    case water(Bool)
    case steep(Bool)
    case groundHeight(Int64?)
}

extension ObservationAnswer: Encodable {
    private enum CodingKeys: String, CodingKey {
        case position, movement, found, stations, timetable, execution
        case level, journey, trains, minutes, loads, resources, conflicts, tracks
        case edge, location, transitions, path, points
        case pose, alignment, nodes, trackPlatforms, levels, trainPath, train
        case trip, daily, hourly, groups, ledger, riders, fare, accounts, report
        case times, lateness, scheduledWaits
        case landTotals, landCell, building, townGrowth, landValue, placedBuilding, zone, water, steep, groundHeight
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .scheduledWaits(let waits):
            try container.encode(waits, forKey: .scheduledWaits)
        case .train(let state?):
            try container.encode(state.position, forKey: .position)
            try container.encode(state.movement, forKey: .movement)
        case .train(nil):
            break
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
        case .trainPath(let path?):
            try container.encode(true, forKey: .found)
            try container.encode(path, forKey: .trainPath)
        case .holder(let id?):
            try container.encode(true, forKey: .found)
            try container.encode(id.rawValue, forKey: .train)
        case .trip(let trip?):
            try container.encode(true, forKey: .found)
            try container.encode(trip, forKey: .trip)
        case .demand(let daily, let hourly):
            try container.encode(daily, forKey: .daily)
            try container.encode(hourly, forKey: .hourly)
        case .groups(let groups):
            try container.encode(groups, forKey: .groups)
        case .ledger(let ledger):
            try container.encode(ledger, forKey: .ledger)
        case .riders(let riders):
            try container.encode(riders, forKey: .riders)
        case .fare(let fare?):
            try container.encode(true, forKey: .found)
            try container.encode(fare, forKey: .fare)
        case .fare(nil):
            try container.encode(false, forKey: .found)
        case .accounts(let accounts):
            try container.encode(accounts, forKey: .accounts)
        case .report(let report):
            try container.encode(report, forKey: .report)
        case .times(let times?):
            try container.encode(true, forKey: .found)
            try container.encode(times, forKey: .times)
        case .lateness(let lateness?):
            try container.encode(true, forKey: .found)
            try container.encode(lateness, forKey: .lateness)
        case .times(nil), .lateness(nil), .landTotals(nil), .landCell(nil), .building(nil), .townGrowth(nil), .landValue(nil), .placedBuilding(nil), .zone(nil),
             .groundHeight(nil):
            try container.encode(false, forKey: .found)
        case .landTotals(let totals?):
            try container.encode(true, forKey: .found)
            try container.encode(totals, forKey: .landTotals)
        case .landCell(let cell?):
            try container.encode(true, forKey: .found)
            try container.encode(cell, forKey: .landCell)
        case .building(let building?):
            try container.encode(true, forKey: .found)
            try container.encode(building, forKey: .building)
        case .townGrowth(let place?):
            try container.encode(true, forKey: .found)
            try container.encode(place, forKey: .townGrowth)
        case .landValue(let value?):
            try container.encode(true, forKey: .found)
            try container.encode(value, forKey: .landValue)
        case .placedBuilding(let building?):
            try container.encode(true, forKey: .found)
            try container.encode(building, forKey: .placedBuilding)
        case .zone(let zone?):
            try container.encode(true, forKey: .found)
            try container.encode(zone, forKey: .zone)
        case .water(let water):
            try container.encode(water, forKey: .water)
        case .steep(let steep):
            try container.encode(steep, forKey: .steep)
        case .groundHeight(let height?):
            try container.encode(true, forKey: .found)
            try container.encode(height, forKey: .groundHeight)
        case .journey(nil), .trains(nil), .minutes(nil), .loads(nil), .edge(nil), .location(nil), .path(nil), .pose(nil), .alignment(nil), .trainPath(nil),
             .holder(nil), .trip(nil):
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
        case .resources(let resources):
            try container.encode(resources.map(ResourceSummary.init), forKey: .resources)
        case .conflicts(let conflicts):
            try container.encode(conflicts.map(ConflictSummary.init), forKey: .conflicts)
        case .tracks(let count):
            try container.encode(count, forKey: .tracks)
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

// MARK: - Final state

/// The externally meaningful state of a world: time, money, what has been
/// built or bought (each station at its point), where each train is and how
/// it moves, each train's timetable, how it repeats, and service, its cars,
/// its body and its reservation, the service lines, the service day, the
/// track network and whether traffic control is on. Lists are in the
/// contract's canonical order (stations and trains by ascending ID), sorted
/// here rather than inherited from how GameCore stores them.
struct WorldSummary: Codable, Equatable {
    /// The clock: in whole minutes, or (schema 23) in seconds when it is
    /// between two minutes; exactly one is written.
    var gameMinutes: Int64?
    var gameSeconds: Int64?
    /// The clock's pending tenths of a second (schema 23), left out when 0.
    var pendingTenths: Int64?
    var speed: SpeedName
    var balance: Int64
    var stations: [StationSummary]
    var trains: [TrainSummary]
    var lines: [LineSummary]
    var serviceDay: [BandSummary]
    var network: NetworkSummary
    /// Whether traffic control is on (schema 19).
    var trafficControl: Bool
    /// The passengers of every station with demand or with passengers ever
    /// released there, by ascending station (schema 20).
    var passengers: [PassengerSummary]
    /// The passengers riding each train that carries any, by ascending
    /// train (schema 21).
    var riders: [RiderSummary]
    /// The company's accounts (schema 22).
    var accounts: AccountsSummary
    /// `"network"` while passengers are routed across the network (schema
    /// 35); left out for direct routing, as in every earlier fixture.
    var passengerRoutingMode: String?
    /// The land's cells, residents and jobs (schema 36, Phase 6a); left out
    /// for a world without land, as in every earlier fixture.
    var land: LandSummary?
    /// `true` while a managed company's ridership comes from the land
    /// (schema 36, Phase 6b); left out otherwise.
    var landDemand: Bool?
    /// How many buildings of each density stand while the city's buildings
    /// are on (schema 37, Phase 6c-1); left out while they are off.
    var cityBuildings: CityBuildingsSummary?
    /// The buildings the player placed (schema 41, decision 92), by ID;
    /// left out when there are none.
    var placedBuildings: [PlacedBuildingSummary]?
    /// How many cells are zoned, in all and of each zone that has any
    /// (schema 43, decision 98); left out when none is.
    var zones: [String: Int]?
    /// How many cells are water (schema 44, decision 105); left out when
    /// none is.
    var water: Int?
    /// How many cells are steep (schema 46, decision 115); left out when
    /// none is.
    var steep: Int?
    /// How many blocks of the ground's height are read (schema 47, decision
    /// 124); left out when none is.
    var groundBlocks: Int?

    /// A station at a point (schema 26, Stage F1), `{ "id", "name", "point":
    /// { "x", "y" } }`. A station on tiles (`"x"`, `"y"` and `"annexes"`)
    /// is rejected: Stage F3c removed the grid (ARCHITECTURE decision 51).
    struct StationSummary: Codable, Equatable {
        var id: Int
        var name: String
        var point: PlanPoint
        /// Schema 35: `"flowControl"` or `"closed"`; left out while open.
        var operationMode: String?

        init(id: Int, name: String, point: PlanPoint, operationMode: String? = nil) {
            self.id = id
            self.name = name
            self.point = point
            self.operationMode = operationMode
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, x, y, annexes, point, operationMode
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            for key in [CodingKeys.x, .y, .annexes] where container.contains(key) {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "A station on tiles is a station of the grid, which Stage F3c removed.")
            }
            point = try container.decode(PlanPoint.self, forKey: .point)
            operationMode = try container.decodeIfPresent(String.self, forKey: .operationMode)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(point, forKey: .point)
            try container.encodeIfPresent(operationMode, forKey: .operationMode)
        }
    }

    struct TrainSummary: Codable, Equatable {
        var id: Int
        var name: String
        var position: TrainPositionSummary
        var movement: TrainMovementSummary
        var timetable: [StopSummary]
        var `repeat`: RepeatSummary
        var execution: ExecutionSummary
        /// Its service's times while it runs one (schema 24, Stage W2b):
        /// absent without a service, never `null`.
        var times: TimesSummary?
        /// Its cars; `1` for a train of one car.
        var cars: Int
        /// On the track network (schema 16): the edges its body lies over
        /// behind its head's edge, nearest first, by number.
        var trailEdges: [Int]
        /// Under traffic control (schema 19): the track it has reserved,
        /// in resource order; `[]` for none.
        var reservation: [ResourceSummary]
        /// Its performance (schema 25, Stage W2c): absent for the standard
        /// performance, never `null`.
        var performance: PerformanceSummary

        private enum CodingKeys: String, CodingKey {
            case id, name, position, movement, timetable, `repeat`, execution, times, cars, trailEdges, reservation, performance
        }

        init(
            id: Int, name: String, position: TrainPositionSummary, movement: TrainMovementSummary, timetable: [StopSummary],
            repeat: RepeatSummary, execution: ExecutionSummary, times: TimesSummary? = nil, cars: Int,
            trailEdges: [Int], reservation: [ResourceSummary], performance: TrainPerformance = .standard
        ) {
            self.id = id
            self.name = name
            self.position = position
            self.movement = movement
            self.timetable = timetable
            self.repeat = `repeat`
            self.execution = execution
            self.times = times
            self.cars = cars
            self.trailEdges = trailEdges
            self.reservation = reservation
            self.performance = PerformanceSummary(performance)
        }

        /// Every field is required but `times`, which is absent without a
        /// service, and `performance`, absent for the standard one: an
        /// explicit `null` is rejected.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            position = try container.decode(TrainPositionSummary.self, forKey: .position)
            movement = try container.decode(TrainMovementSummary.self, forKey: .movement)
            timetable = try container.decode([StopSummary].self, forKey: .timetable)
            self.repeat = try container.decode(RepeatSummary.self, forKey: .repeat)
            execution = try container.decode(ExecutionSummary.self, forKey: .execution)
            times = try container.contains(.times) ? container.decode(TimesSummary.self, forKey: .times) : nil
            cars = try container.decode(Int.self, forKey: .cars)
            trailEdges = try container.decode([Int].self, forKey: .trailEdges)
            reservation = try container.decode([ResourceSummary].self, forKey: .reservation)
            performance = try container.contains(.performance)
                ? container.decode(PerformanceSummary.self, forKey: .performance) : PerformanceSummary(.standard)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(position, forKey: .position)
            try container.encode(movement, forKey: .movement)
            try container.encode(timetable, forKey: .timetable)
            try container.encode(self.repeat, forKey: .repeat)
            try container.encode(execution, forKey: .execution)
            try container.encodeIfPresent(times, forKey: .times)
            try container.encode(cars, forKey: .cars)
            try container.encode(trailEdges, forKey: .trailEdges)
            try container.encode(reservation, forKey: .reservation)
            if performance.performance != .standard {
                try container.encode(performance, forKey: .performance)
            }
        }
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
            /// Schema 48 (decision 124): an automatic edge's sections, `[{"kind",
            /// "lengths"}]`; left out for an explicit structure.
            var sections: [TrackSection]?
        }

        init(_ network: RailwayNetwork) {
            nodes = network.nodes.map { NodeSummary(id: $0.id.number, x: $0.position.x, y: $0.position.y, z: $0.position.z) }
            edges = network.edges.map {
                EdgeSummary(
                    id: $0.id.number, from: $0.from.number, to: $0.to.number, curve: CurveSummary($0.curve), length: $0.length,
                    profile: ProfileSummary($0.profile), structure: StructureName($0.structure), sections: $0.sections.isEmpty ? nil : $0.sections
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
        let now = world.clock.now
        gameMinutes = now.isWholeMinute ? now.minute : nil
        gameSeconds = now.isWholeMinute ? nil : now.seconds
        pendingTenths = world.clock.pendingTenths == 0 ? nil : world.clock.pendingTenths
        speed = SpeedName(world.clock.speed)
        balance = world.economy.balance.amount
        stations = world.stations
            .map { StationSummary(id: $0.id.rawValue, name: $0.name, point: $0.point,
                                  operationMode: $0.operationMode == .normalFlow ? nil : $0.operationMode.rawValue) }
            .sorted { $0.id < $1.id }
        trains = world.trains
            .map {
                TrainSummary(
                    id: $0.id.rawValue, name: $0.name, position: TrainPositionSummary($0.position),
                    movement: TrainMovementSummary($0.movement), timetable: $0.timetable.map(StopSummary.init),
                    repeat: RepeatSummary($0.timetablePeriodMinutes), execution: ExecutionSummary($0.execution),
                    times: $0.times.map(TimesSummary.init), cars: $0.cars, trailEdges: $0.trailEdges.map(\.number),
                    reservation: $0.reservation.map(ResourceSummary.init), performance: $0.performance
                )
            }
            .sorted { $0.id < $1.id }
        lines = world.lines.map(LineSummary.init).sorted { $0.id < $1.id }
        serviceDay = world.serviceDay.bands.map(BandSummary.init)
        network = NetworkSummary(world.network)
        trafficControl = world.isTrafficControlEnabled
        passengers = world.passengers
            .filter { $0.demand != nil || $0.released > 0 }
            .map(PassengerSummary.init)
            .sorted { $0.station < $1.station }
        riders = world.riders
            .map { RiderSummary(train: $0.train.rawValue, groups: $0.groups.map(RidingGroupSummary.init)) }
            .sorted { $0.train < $1.train }
        accounts = AccountsSummary(world.accounts)
        passengerRoutingMode = world.passengerRoutingMode == .direct ? nil : world.passengerRoutingMode.rawValue
        land = world.land.isEmpty ? nil : LandSummary(world.land)
        landDemand = world.landDemand ? true : nil
        cityBuildings = world.cityBuildings ? CityBuildingsSummary(world.buildings) : nil
        placedBuildings = world.placedBuildings.isEmpty ? nil : world.placedBuildings.map(PlacedBuildingSummary.init)
        zones = world.zones.isEmpty ? nil : world.zones.cells.reduce(into: ["cells": world.zones.cells.count]) { $0[$1.zone.rawValue, default: 0] += 1 }
        water = world.terrain.water.isEmpty ? nil : world.terrain.waterCellCount
        steep = world.terrain.steep.isEmpty ? nil : world.terrain.steepCellCount
        groundBlocks = world.ground.isEmpty ? nil : world.ground.blocks.count
    }
}

// MARK: - Land

/// The city's buildings in a fixture's final state (schema 37):
/// `{"buildings", "d1", "d2", "d3", "d4", "existingStock"}`, how many stand,
/// the city buildings of each density and the existing stock.
struct CityBuildingsSummary: Codable, Equatable {
    var buildings: Int
    var d1: Int
    var d2: Int
    var d3: Int
    var d4: Int
    var existingStock: Int

    init(_ buildings: CityBuildings) {
        let city = buildings.all.filter { $0.kind == .city }
        self.buildings = buildings.all.count
        d1 = city.count { $0.density == .d1 }
        d2 = city.count { $0.density == .d2 }
        d3 = city.count { $0.density == .d3 }
        d4 = city.count { $0.density == .d4 }
        existingStock = buildings.all.count - city.count
    }
}

/// What a cell of land is worth (schema 39): `{"value", "base",
/// "servicePremium", "accessPremium", "station"}`, cents a m², and the
/// station the premiums are measured at (`null` for none).
struct LandValueSummary: Equatable {
    var value: Int64
    var base: Int64
    var servicePremium: Int64
    var accessPremium: Int64
    var station: Int?
    /// Schema 43 (decision 98): the premium of a zoned cell near the
    /// company's buildings, written only when it is not 0.
    var companyPremium: Int64
    /// Schema 45 (decision 111): the premium by the water, written only
    /// when it is not 0.
    var waterPremium: Int64

    init(_ value: LandValue) {
        self.value = value.value
        base = value.base
        servicePremium = value.servicePremium
        accessPremium = value.accessPremium
        station = value.station?.rawValue
        companyPremium = value.companyPremium
        waterPremium = value.waterPremium
    }
}

extension LandValueSummary: Codable {
    private enum CodingKeys: String, CodingKey {
        case value, base, servicePremium, accessPremium, station, companyPremium, waterPremium
    }

    /// `"station"` is required, `null` for none.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(Int64.self, forKey: .value)
        base = try container.decode(Int64.self, forKey: .base)
        servicePremium = try container.decode(Int64.self, forKey: .servicePremium)
        accessPremium = try container.decode(Int64.self, forKey: .accessPremium)
        guard container.contains(.station) else {
            throw DecodingError.keyNotFound(CodingKeys.station, DecodingError.Context(codingPath: container.codingPath, debugDescription: "landValue needs \"station\"."))
        }
        station = try container.decodeIfPresent(Int.self, forKey: .station)
        companyPremium = try container.decodeIfPresent(Int64.self, forKey: .companyPremium) ?? 0
        waterPremium = try container.decodeIfPresent(Int64.self, forKey: .waterPremium) ?? 0
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(base, forKey: .base)
        try container.encode(servicePremium, forKey: .servicePremium)
        try container.encode(accessPremium, forKey: .accessPremium)
        try container.encode(station, forKey: .station)
        if companyPremium != 0 {
            try container.encode(companyPremium, forKey: .companyPremium)
        }
        if waterPremium != 0 {
            try container.encode(waterPremium, forKey: .waterPremium)
        }
    }
}

/// How town growth measures a station (schema 38): `{"base", "lastGrowth",
/// "lastService", "lastReached"}`, its start, its last growth in
/// thousandths, and the last day's service share (thousandths) and stations
/// reached.
struct TownGrowthSummary: Codable, Equatable {
    var base: Int64
    var lastGrowth: Int64
    var lastService: Int64
    var lastReached: Int64

    init(_ place: TownGrowth.Place) {
        base = place.base
        lastGrowth = place.lastGrowth
        lastService = place.lastService
        lastReached = place.lastReached
    }
}

/// A building the player placed in a fixture (schema 41, decision 92):
/// `{"id", "kind", "x", "y"}`, the kind `"house"`, `"shop"` or `"office"`
/// and its centre; since schema 42 (decision 94) also `"residents"`,
/// `"jobs"`, `"buildingCost"` and `"landCost"`, each only when not 0.
struct PlacedBuildingSummary: Codable, Equatable {
    var id: Int
    var kind: PlacedBuildingKind
    var x: Int64
    var y: Int64
    var residents: Int64?
    var jobs: Int64?
    var buildingCost: Int64?
    var landCost: Int64?

    init(_ building: PlacedBuilding) {
        id = building.id.rawValue
        kind = building.kind
        x = building.centre.x
        y = building.centre.y
        residents = building.residents == 0 ? nil : building.residents
        jobs = building.jobs == 0 ? nil : building.jobs
        buildingCost = building.buildingCost == .zero ? nil : building.buildingCost.amount
        landCost = building.landCost == .zero ? nil : building.landCost.amount
    }
}

/// A building and what it holds on the cell observed (schema 37): `{"id",
/// "kind", "use", "density", "residents", "jobs"}`, the kind `"city"` or
/// `"existingStock"`, the density 1 to 4, and the residents and jobs it
/// holds there.
struct BuildingSummary: Codable, Equatable {
    var id: Int
    var kind: BuildingKind
    var use: LandUse
    var density: Int
    var residents: Int64
    var jobs: Int64

    init(_ building: Building, capacity: BuildingCapacity) {
        id = building.id.rawValue
        kind = building.kind
        use = building.use
        density = building.density.rawValue
        residents = capacity.residents
        jobs = capacity.jobs
    }
}

/// A world's land in a fixture's final state (schema 36): how many cells
/// it lists and everyone and every job on them.
struct LandSummary: Codable, Equatable {
    var cells: Int
    var residents: Int64
    var jobs: Int64

    init(_ land: Land) {
        cells = land.cells.count
        residents = land.totals.residents
        jobs = land.totals.jobs
    }
}

/// `{"residents", "jobs"}` (schema 36).
struct LandTotalsSummary: Codable, Equatable {
    var residents: Int64
    var jobs: Int64

    init(_ totals: LandTotals) {
        residents = totals.residents
        jobs = totals.jobs
    }
}

/// A cell of land (schema 36): `{"row", "column", "use", "residents",
/// "jobs"}`, the use `"residential"`, `"commercial"` or `"office"`.
struct LandCellSummary: Codable, Equatable {
    var row: Int
    var column: Int
    var use: LandUse
    var residents: Int64
    var jobs: Int64

    init(_ cell: LandCell) {
        row = cell.row
        column = cell.column
        use = cell.use
        residents = cell.residents
        jobs = cell.jobs
    }

    var cell: LandCell {
        LandCell(row: row, column: column, use: use, residents: residents, jobs: jobs)
    }
}

// MARK: - Passengers

/// A station's demand as a fixture value (schema 20): `{"kind",
/// "dailyTrips"}`, the kind `"residential"`, `"office"`, `"shopping"`,
/// `"scenic"` or (decision 91) `"civic"`.
struct DemandSummary: Codable, Equatable {
    var kind: String
    var dailyTrips: Int64

    private static let kinds: [(String, StationDemandKind)] = [
        ("residential", .residential), ("office", .office), ("shopping", .shopping), ("scenic", .scenic), ("civic", .civic),
    ]

    init(_ demand: StationDemand) {
        kind = Self.kinds.first { $0.1 == demand.kind }!.0
        dailyTrips = demand.dailyTrips
    }

    private enum CodingKeys: String, CodingKey {
        case kind, dailyTrips
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        dailyTrips = try container.decode(Int64.self, forKey: .dailyTrips)
        guard Self.kinds.contains(where: { $0.0 == kind }) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown demand kind \"\(kind)\".")
        }
    }

    var demand: StationDemand {
        StationDemand(kind: Self.kinds.first { $0.0 == kind }!.1, dailyTrips: dailyTrips)
    }
}

/// A direction along a line: `"outbound"` or `"inbound"`.
struct DirectionAlongLine: Codable, Equatable {
    var direction: LineDirection

    init(_ direction: LineDirection) {
        self.direction = direction
    }

    private static let names: [(String, LineDirection)] = [("outbound", .outbound), ("inbound", .inbound)]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let direction = Self.names.first(where: { $0.0 == name })?.1 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown direction along a line \"\(name)\".")
        }
        self.direction = direction
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.names.first { $0.1 == direction }!.0)
    }
}

/// The trip between two stations: `{"line", "direction"}`.
struct TripSummary: Codable, Equatable {
    var line: Int
    var direction: DirectionAlongLine

    init(_ trip: PassengerTrip) {
        line = trip.line.rawValue
        direction = DirectionAlongLine(trip.direction)
    }
}

/// A waiting group: `{"line", "direction", "destination", "since",
/// "count"}`. Schema 35 (Phase 5F): a group that changed trains got off
/// between two minutes, so it has `"sinceSeconds"` instead of `"since"`,
/// and `"readyAtSeconds"`, when it may board the next train.
struct WaitingGroupSummary: Codable, Equatable {
    var line: Int
    var direction: DirectionAlongLine
    var destination: Int
    var since: Int64?
    var sinceSeconds: Int64?
    var readyAtSeconds: Int64?
    var count: Int64

    init(_ group: WaitingGroup) {
        line = group.line.rawValue
        direction = DirectionAlongLine(group.direction)
        destination = group.destination.rawValue
        since = group.since.isWholeMinute ? group.since.minute : nil
        sinceSeconds = group.since.isWholeMinute ? nil : group.since.seconds
        readyAtSeconds = group.readyAt?.seconds
        count = group.count
    }
}

/// A station's conservation audit: `{"released", "waiting", "riding",
/// "arrived", "overflowed", "abandoned", "refused"}` (`riding`, `arrived`
/// and `refused` since schema 21).
struct LedgerSummary: Codable, Equatable {
    var released: Int64
    var waiting: Int64
    var riding: Int64
    var arrived: Int64
    var overflowed: Int64
    var abandoned: Int64
    var refused: Int64

    init(_ ledger: PassengerLedger) {
        released = ledger.released
        waiting = ledger.waiting
        riding = ledger.riding
        arrived = ledger.arrived
        overflowed = ledger.overflowed
        abandoned = ledger.abandoned
        refused = ledger.refused
    }
}

/// Passengers riding a train together (schema 21): `{"origin",
/// "destination", "count"}`.
struct RidingGroupSummary: Codable, Equatable {
    var origin: Int
    var destination: Int
    var count: Int64

    init(_ group: RidingGroup) {
        origin = group.origin.rawValue
        destination = group.destination.rawValue
        count = group.count
    }
}

/// A train's riders in the final state (schema 21): `{"train", "groups"}`.
struct RiderSummary: Codable, Equatable {
    var train: Int
    var groups: [RidingGroupSummary]
}

/// A station's passengers in the final state: `{"station", "demand",
/// "waiting", "released", "arrived", "overflowed", "abandoned",
/// "refused"}` (`arrived` and `refused` since schema 21), every field
/// required; `demand` is `null` for a station without demand.
struct PassengerSummary: Codable, Equatable {
    var station: Int
    var demand: DemandSummary?
    var waiting: [WaitingGroupSummary]
    var released: Int64
    var arrived: Int64
    var overflowed: Int64
    var abandoned: Int64
    var refused: Int64

    init(
        station: Int, demand: DemandSummary?, waiting: [WaitingGroupSummary], released: Int64, arrived: Int64,
        overflowed: Int64, abandoned: Int64, refused: Int64
    ) {
        self.station = station
        self.demand = demand
        self.waiting = waiting
        self.released = released
        self.arrived = arrived
        self.overflowed = overflowed
        self.abandoned = abandoned
        self.refused = refused
    }

    init(_ record: StationPassengers) {
        self.init(
            station: record.station.rawValue, demand: record.demand.map(DemandSummary.init), waiting: record.waiting.map(WaitingGroupSummary.init),
            released: record.released, arrived: record.arrived, overflowed: record.overflowed, abandoned: record.abandoned, refused: record.refused
        )
    }

    private enum CodingKeys: String, CodingKey {
        case station, demand, waiting, released, arrived, overflowed, abandoned, refused
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        station = try container.decode(Int.self, forKey: .station)
        guard container.contains(.demand) else {
            throw DecodingError.keyNotFound(CodingKeys.demand, DecodingError.Context(codingPath: container.codingPath, debugDescription: "\"demand\" is required; null for none."))
        }
        demand = try container.decodeNil(forKey: .demand) ? nil : container.decode(DemandSummary.self, forKey: .demand)
        waiting = try container.decode([WaitingGroupSummary].self, forKey: .waiting)
        released = try container.decode(Int64.self, forKey: .released)
        arrived = try container.decode(Int64.self, forKey: .arrived)
        overflowed = try container.decode(Int64.self, forKey: .overflowed)
        abandoned = try container.decode(Int64.self, forKey: .abandoned)
        refused = try container.decode(Int64.self, forKey: .refused)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(station, forKey: .station)
        if let demand {
            try container.encode(demand, forKey: .demand)
        } else {
            try container.encodeNil(forKey: .demand)
        }
        try container.encode(waiting, forKey: .waiting)
        try container.encode(released, forKey: .released)
        try container.encode(arrived, forKey: .arrived)
        try container.encode(overflowed, forKey: .overflowed)
        try container.encode(abandoned, forKey: .abandoned)
        try container.encode(refused, forKey: .refused)
    }
}

// MARK: - Service lines

/// A service line as a fixture value: `{"id", "name", "stops",
/// "performance", "window", "trainsInService", "targetHeadways", "trains",
/// "lastDispatch", "patterns"}` (see `ServiceLine`). Every field is
/// required but `performance` (schema 25, Stage W2c; it replaces the rate
/// before it), which is absent for the standard performance, never
/// `null`; `lastDispatch` is `null` for a line that never sent a train
/// out, and `patterns` is `[]` for a line without any. A ring (schema 27,
/// decision 49) also has `"ring": true` and `"outerLastDispatch"` (the
/// minute it last sent a train the outer way, or `null`); a line that is
/// not a ring has neither.
struct LineSummary: Codable, Equatable {
    var id: Int
    var name: String
    var stops: [Int]
    var isRing = false
    var performance: PerformanceSummary
    var window: WindowSummary
    var trainsInService: TrainsSummary
    var targetHeadways: TargetHeadwaysSummary
    var trains: [Int]
    var lastDispatch: Int64?
    var outerLastDispatch: Int64?
    var patterns: [PatternSummary]
    var routePreferences: [LineRoutePreference] = []

    init(
        id: Int, name: String, stops: [Int], performance: PerformanceSummary = PerformanceSummary(.standard), window: WindowSummary,
        trainsInService: TrainsSummary, targetHeadways: TargetHeadwaysSummary, trains: [Int], lastDispatch: Int64?,
        patterns: [PatternSummary] = []
    ) {
        self.id = id
        self.name = name
        self.stops = stops
        self.performance = performance
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
        performance = PerformanceSummary(line.performance)
        window = WindowSummary(line.window)
        trainsInService = TrainsSummary(line.trainsInService)
        targetHeadways = TargetHeadwaysSummary(line.targetHeadways)
        trains = line.trains.map(\.rawValue)
        lastDispatch = line.lastDispatch?.minutes
        isRing = line.isRing
        outerLastDispatch = line.outerLastDispatch?.minutes
        patterns = line.patterns.map(PatternSummary.init)
        routePreferences = line.routePreferences
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, stops, performance, window, trainsInService, targetHeadways, trains, lastDispatch, patterns, routePreferences
        case isRing = "ring", outerLastDispatch
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        stops = try container.decode([Int].self, forKey: .stops)
        performance = try container.contains(.performance)
            ? container.decode(PerformanceSummary.self, forKey: .performance) : PerformanceSummary(.standard)
        window = try container.decode(WindowSummary.self, forKey: .window)
        trainsInService = try container.decode(TrainsSummary.self, forKey: .trainsInService)
        targetHeadways = try container.decode(TargetHeadwaysSummary.self, forKey: .targetHeadways)
        trains = try container.decode([Int].self, forKey: .trains)
        // Required: a missing key is an error, not a line that never
        // dispatched.
        lastDispatch = try container.decodeNil(forKey: .lastDispatch) ? nil : container.decode(Int64.self, forKey: .lastDispatch)
        patterns = try container.decode([PatternSummary].self, forKey: .patterns)
        routePreferences = container.contains(.routePreferences) ? try container.decode([LineRoutePreference].self, forKey: .routePreferences) : []
        // Schema 27: a ring says so, and its outer dispatch is then
        // required; a line that is not a ring writes neither.
        if container.contains(.isRing) {
            guard try container.decode(Bool.self, forKey: .isRing) else {
                throw DecodingError.dataCorruptedError(forKey: .isRing, in: container, debugDescription: "\"ring\" is written only as true.")
            }
            isRing = true
            outerLastDispatch = try container.decodeNil(forKey: .outerLastDispatch)
                ? nil : container.decode(Int64.self, forKey: .outerLastDispatch)
        } else if container.contains(.outerLastDispatch) {
            throw DecodingError.dataCorruptedError(
                forKey: .outerLastDispatch, in: container, debugDescription: "Only a ring has \"outerLastDispatch\"."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(stops, forKey: .stops)
        if performance.performance != .standard {
            try container.encode(performance, forKey: .performance)
        }
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
        if !routePreferences.isEmpty { try container.encode(routePreferences, forKey: .routePreferences) }
        if isRing {
            try container.encode(true, forKey: .isRing)
            if let outerLastDispatch {
                try container.encode(outerLastDispatch, forKey: .outerLastDispatch)
            } else {
                try container.encodeNil(forKey: .outerLastDispatch)
            }
        }
    }
}

/// A line's pattern as a fixture value: `{"calls", "trainsInService",
/// "targetHeadways", "trains", "lastDispatch"}` (see `LinePattern`), every
/// field required as on a line; `lastDispatch` is `null` for a pattern
/// that never sent a train out.
struct PatternSummary: Codable, Equatable {
    var calls: [Int]
    var routePreferences: [LineRoutePreference] = []
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
        routePreferences = pattern.routePreferences
        trainsInService = TrainsSummary(pattern.trainsInService)
        targetHeadways = TargetHeadwaysSummary(pattern.targetHeadways)
        trains = pattern.trains.map(\.rawValue)
        lastDispatch = pattern.lastDispatch?.minutes
    }

    private enum CodingKeys: String, CodingKey {
        case calls, trainsInService, targetHeadways, trains, lastDispatch, routePreferences
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calls = try container.decode([Int].self, forKey: .calls)
        routePreferences = container.contains(.routePreferences) ? try container.decode([LineRoutePreference].self, forKey: .routePreferences) : []
        trainsInService = try container.decode(TrainsSummary.self, forKey: .trainsInService)
        targetHeadways = try container.decode(TargetHeadwaysSummary.self, forKey: .targetHeadways)
        trains = try container.decode([Int].self, forKey: .trains)
        lastDispatch = try container.decodeNil(forKey: .lastDispatch) ? nil : container.decode(Int64.self, forKey: .lastDispatch)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(calls, forKey: .calls)
        if !routePreferences.isEmpty { try container.encode(routePreferences, forKey: .routePreferences) }
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
/// "path", "seconds"}, ...], "roundTripSeconds", "roundTripMinutes"}` (see
/// `LineJourney`; since schema 25, Stage W2c, a leg takes whole seconds,
/// and the round trip is in seconds and rounded up to minutes). A ring's
/// lap (schema 27) also has `"ring": true`; other journeys do not have it.
struct JourneySummary: Codable, Equatable {
    /// A leg, with its path on the track network (schema 18). (Until Stage
    /// F3c a leg on the grid had a `"route"` of tiles instead.)
    struct Leg: Codable, Equatable {
        var from: Int
        var to: Int
        var path: PathSummary
        var seconds: Int64
    }

    var start: TrainPositionSummary
    var legs: [Leg]
    var roundTripSeconds: Int64
    var roundTripMinutes: Int64
    var ring: Bool?
    /// Schema 34: omitted for the legacy forward-only journeys.
    var intermediateTurnbacks: [Int]?

    init(_ journey: LineJourney) {
        start = TrainPositionSummary(journey.start)
        legs = journey.legs.map { Leg(from: $0.from, to: $0.to, path: PathSummary($0.path), seconds: $0.seconds) }
        roundTripSeconds = journey.roundTripSeconds
        roundTripMinutes = journey.roundTripMinutes
        ring = journey.isRing ? true : nil
        intermediateTurnbacks = journey.intermediateTurnbacks.isEmpty ? nil : journey.intermediateTurnbacks
    }
}

/// A path on the track network (schema 18): `{"traversals": [{"edge",
/// "direction"}, ...], "end", "distance"}`, the edges entered after the
/// train's own, where the head stops on the last (absent at its end) and
/// how far that is.
struct PathSummary: Codable, Equatable {
    var traversals: [TraversalSummary]
    var end: Int64?
    var distance: Int64

    init(_ path: TrainPath) {
        traversals = path.traversals.map(TraversalSummary.init)
        end = path.end
        distance = path.distance
    }
}

// MARK: - Names

/// A game speed as its fixture name: `"paused"`, `"x1"`, `"x10"`, `"x60"`
/// (schema 23), `"normal"` or `"double"`.
struct SpeedName: Codable, Equatable {
    var speed: GameSpeed

    init(_ speed: GameSpeed) {
        self.speed = speed
    }

    private static func name(of speed: GameSpeed) -> String {
        switch speed {
        case .paused: "paused"
        case .x1: "x1"
        case .x10: "x10"
        case .x60: "x60"
        case .normal: "normal"
        case .double: "double"
        case .fast: "fast"
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

/// A train position as a fixture value, tagged by `"type"`:
/// `{"type": "unplaced"}` or `{"type": "edge", "edge", "direction",
/// "offset"}` (schema 16). The grid's `"node"` and `"link"` positions are
/// rejected: Stage F3c removed the grid (ARCHITECTURE decision 51).
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
        case type, offset, edge, direction
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let fields: [CodingKeys]
        switch type {
        case "unplaced":
            fields = []
            position = nil
        case "node", "link":
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "A \"\(type)\" position is on the grid, which Stage F3c removed.")
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
        case .onEdge(let traversal, let offset)?:
            try container.encode("edge", forKey: .type)
            try container.encode(traversal.edge.networkNumberForFixture, forKey: .edge)
            try container.encode(traversal.direction == .forward ? "forward" : "backward", forKey: .direction)
            try container.encode(offset, forKey: .offset)
        }
    }
}

/// A train's movement as a fixture value: `{"rate", "cursor", "edges",
/// "end"}`, in GameCore's terms (see `TrainMovement`): `rate` units per
/// basic step, the edges of its path in order (schema 16), how many of them
/// have been entered, and where the path stops on its last edge (schema 18;
/// absent when it runs to that edge's end). A spent path is `[]` with
/// cursor 0; an idle train is `{"rate": 0, "cursor": 0, "edges": []}`.
/// (Until schema 28 it also had `"continuation"`, the grid's path.)
struct TrainMovementSummary: Codable, Equatable {
    var rate: Int64
    var cursor: Int
    var edges: [Int]
    var end: Int64?

    init(rate: Int64, cursor: Int, edges: [Int] = [], end: Int64? = nil) {
        self.rate = rate
        self.cursor = cursor
        self.edges = edges
        self.end = end
    }

    init(_ movement: TrainMovement) {
        self.init(rate: movement.rate, cursor: movement.cursor, edges: movement.edges.map(\.number), end: movement.end)
    }
}

/// A timetable stop as a fixture value: `{"station", "arrival", "departure",
/// "reverse"}`, a station ID, two game minutes and whether the train turns
/// round as it leaves (see `ScheduledStop`). Read as written, not checked:
/// whether a timetable is valid is GameCore's decision, so a fixture can
/// expect a negative time to be rejected.
struct StopSummary: Equatable {
    var station: Int
    /// In seconds; written in whole minutes, or since schema 24 (Stage W2b)
    /// in seconds between two minutes (see the `Codable` conformance).
    var arrival: Int64
    var departure: Int64
    var reverse: Bool

    init(_ stop: ScheduledStop) {
        station = stop.station.rawValue
        arrival = stop.arrival.seconds
        departure = stop.departure.seconds
        reverse = stop.reverses
    }

    var stop: ScheduledStop {
        ScheduledStop(
            station: StationID(rawValue: station), arrival: GameTime(seconds: arrival), departure: GameTime(seconds: departure),
            reverses: reverse
        )
    }
}

/// `{"station", "arrival", "departure", "reverse"}`, the times in whole
/// minutes. Schema 24 (Stage W2b): a time between two minutes is written
/// in seconds instead, as `"arrivalSeconds"` or `"departureSeconds"`;
/// exactly one of each pair, as for the clock, so each time has one way to
/// be written.
extension StopSummary: Codable {
    private enum CodingKeys: String, CodingKey {
        case station, arrival, arrivalSeconds, departure, departureSeconds, reverse
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func time(minutes: CodingKeys, seconds: CodingKeys) throws -> Int64 {
            switch (container.contains(minutes), container.contains(seconds)) {
            case (true, false):
                let (time, overflow) = try container.decode(Int64.self, forKey: minutes).multipliedReportingOverflow(by: GameTime.secondsPerMinute)
                guard !overflow else {
                    throw DecodingError.dataCorruptedError(forKey: minutes, in: container, debugDescription: "A time must fit in a game second.")
                }
                return time
            case (false, true):
                let time = try container.decode(Int64.self, forKey: seconds)
                guard time % GameTime.secondsPerMinute != 0 else {
                    throw DecodingError.dataCorruptedError(forKey: seconds, in: container, debugDescription: "A whole minute is written as \"\(minutes.stringValue)\".")
                }
                return time
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: minutes, in: container, debugDescription: "A stop needs exactly one of \"\(minutes.stringValue)\" and \"\(seconds.stringValue)\"."
                )
            }
        }
        station = try container.decode(Int.self, forKey: .station)
        arrival = try time(minutes: .arrival, seconds: .arrivalSeconds)
        departure = try time(minutes: .departure, seconds: .departureSeconds)
        reverse = try container.decode(Bool.self, forKey: .reverse)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        func encode(_ time: Int64, minutes: CodingKeys, seconds: CodingKeys) throws {
            if time % GameTime.secondsPerMinute == 0 {
                try container.encode(time / GameTime.secondsPerMinute, forKey: minutes)
            } else {
                try container.encode(time, forKey: seconds)
            }
        }
        try container.encode(station, forKey: .station)
        try encode(arrival, minutes: .arrival, seconds: .arrivalSeconds)
        try encode(departure, minutes: .departure, seconds: .departureSeconds)
        try container.encode(reverse, forKey: .reverse)
    }
}

/// A service's times (schema 24, Stage W2b; see `ServiceTimes`), in game
/// seconds: `{"arrival", "exchangeEnd", "closing", "departure", "run"}`,
/// all but the first only when set, never `null`. `run` (schema 25, Stage
/// W2c; see `ServiceRun`) is `{"start", "length", "seconds"}`.
struct TimesSummary: Equatable {
    struct Run: Codable, Equatable {
        var start: Int64
        var length: Int64
        var seconds: Int64
    }

    var arrival: Int64
    var exchangeEnd: Int64?
    var closing: Int64?
    var departure: Int64?
    var run: Run?

    init(arrival: Int64, exchangeEnd: Int64? = nil, closing: Int64? = nil, departure: Int64? = nil, run: Run? = nil) {
        self.arrival = arrival
        self.exchangeEnd = exchangeEnd
        self.closing = closing
        self.departure = departure
        self.run = run
    }

    init(_ times: ServiceTimes) {
        self.init(
            arrival: times.arrival.seconds, exchangeEnd: times.exchangeEnd?.seconds, closing: times.closing?.seconds,
            departure: times.departure?.seconds,
            run: times.run.map { Run(start: $0.start.seconds, length: $0.length, seconds: $0.seconds) }
        )
    }
}

extension TimesSummary: Codable {
    private enum CodingKeys: String, CodingKey {
        case arrival, exchangeEnd, closing, departure, run
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arrival = try container.decode(Int64.self, forKey: .arrival)
        exchangeEnd = try container.contains(.exchangeEnd) ? container.decode(Int64.self, forKey: .exchangeEnd) : nil
        closing = try container.contains(.closing) ? container.decode(Int64.self, forKey: .closing) : nil
        departure = try container.contains(.departure) ? container.decode(Int64.self, forKey: .departure) : nil
        run = try container.contains(.run) ? container.decode(Run.self, forKey: .run) : nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(arrival, forKey: .arrival)
        try container.encodeIfPresent(exchangeEnd, forKey: .exchangeEnd)
        try container.encodeIfPresent(closing, forKey: .closing)
        try container.encodeIfPresent(departure, forKey: .departure)
        try container.encodeIfPresent(run, forKey: .run)
    }
}

/// A performance (schema 25, Stage W2c; see `TrainPerformance`): the name
/// of a preset, such as `"standard"`, `"metro"` or `"express"`, or
/// `{"acceleration", "braking", "topSpeed"}` with `"alternativeAcceleration"`,
/// `"alternativeBraking"` and `"coast": {"deceleration", "speedRatio"}`
/// when set. Written as the first preset's name it equals, otherwise as
/// the object. Read as written: an object need not be valid, so a fixture
/// can expect GameCore to reject it.
struct PerformanceSummary: Codable, Equatable {
    var performance: TrainPerformance

    init(_ performance: TrainPerformance) {
        self.performance = performance
    }

    static let presets: [(name: String, performance: TrainPerformance)] = [
        ("standard", .standard), ("metro", .metro), ("local", .local), ("express", .express), ("semiExpress", .semiExpress),
        ("ordinary", .ordinary), ("highSpeed", .highSpeed), ("dieselRailcar", .dieselRailcar), ("dieselExpress", .dieselExpress),
        ("forestRailway", .forestRailway), ("tiltingTaroko", .tiltingTaroko), ("tiltingPuyuma", .tiltingPuyuma),
        ("pushPull", .pushPull), ("emu3000", .emu3000),
    ]

    private enum CodingKeys: String, CodingKey {
        case acceleration, braking, topSpeed, alternativeAcceleration, alternativeBraking, coast
    }

    private struct CoastSummary: Codable {
        var deceleration: Int64
        var speedRatio: Int64
    }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            guard let preset = Self.presets.first(where: { $0.name == name }) else {
                throw DecodingError.dataCorruptedError(in: single, debugDescription: "Unknown performance \"\(name)\".")
            }
            performance = preset.performance
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coast = try container.decodeIfPresent(CoastSummary.self, forKey: .coast)
        performance = TrainPerformance(
            acceleration: try container.decode(Int64.self, forKey: .acceleration),
            braking: try container.decode(Int64.self, forKey: .braking),
            topSpeed: try container.decode(Int64.self, forKey: .topSpeed),
            alternativeAcceleration: try container.decodeIfPresent(Int64.self, forKey: .alternativeAcceleration),
            alternativeBraking: try container.decodeIfPresent(Int64.self, forKey: .alternativeBraking),
            coast: coast.map { TrainPerformance.Coast(deceleration: $0.deceleration, speedRatio: $0.speedRatio) }
        )
    }

    func encode(to encoder: any Encoder) throws {
        if let preset = Self.presets.first(where: { $0.performance == performance }) {
            var single = encoder.singleValueContainer()
            try single.encode(preset.name)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(performance.acceleration, forKey: .acceleration)
        try container.encode(performance.braking, forKey: .braking)
        try container.encode(performance.topSpeed, forKey: .topSpeed)
        try container.encodeIfPresent(performance.alternativeAcceleration, forKey: .alternativeAcceleration)
        try container.encodeIfPresent(performance.alternativeBraking, forKey: .alternativeBraking)
        try container.encodeIfPresent(
            performance.coast.map { CoastSummary(deceleration: $0.deceleration, speedRatio: $0.speedRatio) }, forKey: .coast
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
    /// A point stored as two flat integer fields, in world units.
    fileprivate func decodePoint(x: Key, y: Key) throws -> PlanPoint {
        try PlanPoint(x: decode(Int64.self, forKey: x), y: decode(Int64.self, forKey: y))
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

/// A track resource as a fixture value (schema 16): `{"type":
/// "networkNode", "node"}` or `{"type": "networkSpan", "edge", "start",
/// "end"}` (see `TrackResource` and `TrackSpan`). The grid's `"node"` and
/// `"link"` resources are rejected: Stage F3c removed the grid
/// (ARCHITECTURE decision 51).
struct ResourceSummary: Codable, Equatable {
    var resource: TrackResource

    init(_ resource: TrackResource) {
        self.resource = resource
    }

    private enum CodingKeys: String, CodingKey {
        case type, node, edge, start, end
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "networkNode":
            resource = .node(.node(try container.decode(Int.self, forKey: .node)))
        case "networkSpan":
            resource = .span(TrackSpan(
                edge: .edge(try container.decode(Int.self, forKey: .edge)),
                start: try container.decode(Int64.self, forKey: .start), end: try container.decode(Int64.self, forKey: .end)
            ))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "A resource is a network node or a network span.")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch resource {
        case .node(let node):
            try container.encode("networkNode", forKey: .type)
            try container.encode(node.number, forKey: .node)
        case .span(let span):
            try container.encode("networkSpan", forKey: .type)
            try container.encode(span.edge.number, forKey: .edge)
            try container.encode(span.start, forKey: .start)
            try container.encode(span.end, forKey: .end)
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
        edge = traversal.edge.number
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

/// A structure as a fixture value: `"surface"`, `"elevated"`, `"bridge"`,
/// `"tunnel"` or (schema 48) `"automatic"`, spelled out here rather than
/// borrowed from GameCore.
struct StructureName: Codable, Equatable {
    var structure: TrackStructure

    init(_ structure: TrackStructure) {
        self.structure = structure
    }

    private static let names: [(String, TrackStructure)] = [
        ("surface", .surface), ("elevated", .elevated), ("bridge", .bridge), ("tunnel", .tunnel), ("automatic", .automatic),
    ]

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

// MARK: - Economy (schema 22)

/// Fare rules as a fixture value (schema 22): `{"mode": "flat", "fare"}` or
/// `{"mode": "distance", "bands": [{"fromMeters", "toMeters", "fare"}]}`,
/// `toMeters` `null` for the open-ended step. Read as written: whether the
/// rules are valid is GameCore's decision.
struct FareRulesSummary: Codable, Equatable {
    struct Band: Codable, Equatable {
        var fromMeters: Int64
        var toMeters: Int64?
        var fare: Int64

        init(fromMeters: Int64, toMeters: Int64?, fare: Int64) {
            self.fromMeters = fromMeters
            self.toMeters = toMeters
            self.fare = fare
        }

        private enum CodingKeys: String, CodingKey {
            case fromMeters, toMeters, fare
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fromMeters = try container.decode(Int64.self, forKey: .fromMeters)
            guard container.contains(.toMeters) else {
                throw DecodingError.keyNotFound(CodingKeys.toMeters, DecodingError.Context(codingPath: container.codingPath, debugDescription: "\"toMeters\" is required; null for none."))
            }
            toMeters = try container.decodeNil(forKey: .toMeters) ? nil : container.decode(Int64.self, forKey: .toMeters)
            fare = try container.decode(Int64.self, forKey: .fare)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(fromMeters, forKey: .fromMeters)
            try container.encode(toMeters, forKey: .toMeters)
            try container.encode(fare, forKey: .fare)
        }
    }

    var mode: String
    var fare: Int64?
    var bands: [Band]?

    init(_ rules: FareRules) {
        switch rules {
        case .flat(let fare):
            mode = "flat"
            self.fare = fare.amount
            bands = nil
        case .distance(let bands):
            mode = "distance"
            fare = nil
            self.bands = bands.map { Band(fromMeters: $0.fromMeters, toMeters: $0.toMeters, fare: $0.fare.amount) }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mode, fare, bands
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(String.self, forKey: .mode)
        switch mode {
        case "flat":
            fare = try container.decode(Int64.self, forKey: .fare)
            bands = nil
            guard !container.contains(.bands) else { throw DecodingError.dataCorruptedError(forKey: .bands, in: container, debugDescription: "A flat fare has no bands.") }
        case "distance":
            bands = try container.decode([Band].self, forKey: .bands)
            fare = nil
            guard !container.contains(.fare) else { throw DecodingError.dataCorruptedError(forKey: .fare, in: container, debugDescription: "Distance fares have no single fare.") }
        default:
            throw DecodingError.dataCorruptedError(forKey: .mode, in: container, debugDescription: "Unknown fare mode \"\(mode)\".")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        if let fare { try container.encode(fare, forKey: .fare) }
        if let bands { try container.encode(bands, forKey: .bands) }
    }

    var rules: FareRules {
        if let bands {
            return .distance(bands.map { FareBand(fromMeters: $0.fromMeters, toMeters: $0.toMeters, fare: Money($0.fare)) })
        }
        return .flat(Money(fare ?? 0))
    }
}

/// The hour being accrued: `{"fareRevenue", "fareTrips", "departures",
/// "trainDistance", "passengers", "seats"}`.
struct PendingSummary: Codable, Equatable {
    var fareRevenue: Int64
    var fareTrips: Int64
    var departures: Int64
    var trainDistance: Int64
    var passengers: Int64
    var seats: Int64

    init(fareRevenue: Int64, fareTrips: Int64, departures: Int64, trainDistance: Int64, passengers: Int64, seats: Int64) {
        self.fareRevenue = fareRevenue
        self.fareTrips = fareTrips
        self.departures = departures
        self.trainDistance = trainDistance
        self.passengers = passengers
        self.seats = seats
    }

    init(_ pending: HourlyAccrual) {
        self.init(
            fareRevenue: pending.fareRevenue.amount, fareTrips: pending.fareTrips, departures: pending.departures,
            trainDistance: pending.trainDistance, passengers: pending.passengers, seats: pending.seats
        )
    }
}

/// A ledger row: `{"kind", "time", "amount", "breakdown": [{"item",
/// "amount"}], "crowding"}`, `crowding` `{"crowdedStations", "fullTrains",
/// "maxWaiting", "maxLoad"}` or `null`.
struct LedgerRowSummary: Codable, Equatable {
    struct Line: Codable, Equatable {
        var item: String
        var amount: Int64
    }

    struct Crowding: Codable, Equatable {
        var crowdedStations: Int64
        var fullTrains: Int64
        var maxWaiting: Int64
        var maxLoad: Int64
    }

    var kind: String
    var time: Int64
    var amount: Int64
    var breakdown: [Line]
    var crowding: Crowding?

    init(_ entry: LedgerEntry) {
        kind = entry.kind.rawValue
        time = entry.time.minutes
        amount = entry.amount.amount
        breakdown = entry.breakdown.map { Line(item: $0.item.rawValue, amount: $0.amount.amount) }
        crowding = entry.crowding.map {
            Crowding(crowdedStations: $0.crowdedStations, fullTrains: $0.fullTrains, maxWaiting: $0.maxWaiting, maxLoad: $0.maxLoad)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, time, amount, breakdown, crowding
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        time = try container.decode(Int64.self, forKey: .time)
        amount = try container.decode(Int64.self, forKey: .amount)
        breakdown = try container.decode([Line].self, forKey: .breakdown)
        guard container.contains(.crowding) else {
            throw DecodingError.keyNotFound(CodingKeys.crowding, DecodingError.Context(codingPath: container.codingPath, debugDescription: "\"crowding\" is required; null for none."))
        }
        crowding = try container.decodeNil(forKey: .crowding) ? nil : container.decode(Crowding.self, forKey: .crowding)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(time, forKey: .time)
        try container.encode(amount, forKey: .amount)
        try container.encode(breakdown, forKey: .breakdown)
        try container.encode(crowding, forKey: .crowding)
    }
}

/// A day's totals: `{"day", "fareRevenue", "operatingCost",
/// "maintenanceCost", "energyCost", "staffCost"}`.
struct DaySummary: Codable, Equatable {
    var day: Int64
    var fareRevenue: Int64
    var operatingCost: Int64
    var maintenanceCost: Int64
    var energyCost: Int64
    var staffCost: Int64
    /// Since schema 42 (decision 94): the company's buildings' rent, and
    /// their upkeep, land tax and demolition; absent when 0.
    var propertyRevenue: Int64?
    var propertyCost: Int64?
}

/// The company's accounts (schema 22): `{"mode", "fareRules", "openedAt",
/// "pending", "ledger", "days"}`, every field required; `fareRules` and
/// `openedAt` `null` for none. `openedAt` is in minutes in a fixture and
/// kept here in seconds (Stage W2a), since a company opened between two
/// minutes has no whole minute to write; such a time is printed in
/// diagnostics as `"openedAtSeconds"`.
struct AccountsSummary: Codable, Equatable {
    var mode: String
    var fareRules: FareRulesSummary?
    /// In seconds.
    var openedAt: Int64?
    var pending: PendingSummary
    var ledger: [LedgerRowSummary]
    var days: [DaySummary]

    init(mode: String, fareRules: FareRulesSummary?, openedAt: Int64?, pending: PendingSummary, ledger: [LedgerRowSummary], days: [DaySummary]) {
        self.mode = mode
        self.fareRules = fareRules
        self.openedAt = openedAt
        self.pending = pending
        self.ledger = ledger
        self.days = days
    }

    init(_ accounts: CompanyAccounts) {
        self.init(
            mode: accounts.mode.rawValue, fareRules: accounts.fareRules.map(FareRulesSummary.init), openedAt: accounts.openedAt?.seconds,
            pending: PendingSummary(accounts.pending), ledger: accounts.entries.map(LedgerRowSummary.init),
            days: accounts.days.map {
                DaySummary(
                    day: $0.day, fareRevenue: $0.fareRevenue.amount, operatingCost: $0.operatingCost.amount,
                    maintenanceCost: $0.maintenanceCost.amount, energyCost: $0.energyCost.amount, staffCost: $0.staffCost.amount,
                    propertyRevenue: $0.propertyRevenue == .zero ? nil : $0.propertyRevenue.amount,
                    propertyCost: $0.propertyCost == .zero ? nil : $0.propertyCost.amount
                )
            }
        )
    }

    /// A new world's accounts.
    static let pristine = AccountsSummary(
        mode: "free", fareRules: nil, openedAt: nil, pending: PendingSummary(HourlyAccrual.empty), ledger: [], days: []
    )

    private enum CodingKeys: String, CodingKey {
        case mode, fareRules, openedAt, openedAtSeconds, pending, ledger, days
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.fareRules, .openedAt] where !container.contains(key) {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: container.codingPath, debugDescription: "\"\(key.stringValue)\" is required; null for none."))
        }
        mode = try container.decode(String.self, forKey: .mode)
        fareRules = try container.decodeNil(forKey: .fareRules) ? nil : container.decode(FareRulesSummary.self, forKey: .fareRules)
        openedAt = try container.decodeNil(forKey: .openedAt) ? nil : container.decode(Int64.self, forKey: .openedAt) * GameTime.secondsPerMinute
        pending = try container.decode(PendingSummary.self, forKey: .pending)
        ledger = try container.decode([LedgerRowSummary].self, forKey: .ledger)
        days = try container.decode([DaySummary].self, forKey: .days)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(fareRules, forKey: .fareRules)
        if let openedAt, openedAt % GameTime.secondsPerMinute != 0 {
            try container.encode(openedAt, forKey: .openedAtSeconds)
        } else {
            try container.encode(openedAt.map { $0 / GameTime.secondsPerMinute }, forKey: .openedAt)
        }
        try container.encode(pending, forKey: .pending)
        try container.encode(ledger, forKey: .ledger)
        try container.encode(days, forKey: .days)
    }
}

/// A period's statement: `{"index", "fareRevenue", "operatingCost",
/// "maintenanceCost", "energyCost", "staffCost"}`.
struct PeriodSummary: Codable, Equatable {
    var index: Int64
    var fareRevenue: Int64
    var operatingCost: Int64
    var maintenanceCost: Int64
    var energyCost: Int64
    var staffCost: Int64

    init(index: Int64, fareRevenue: Int64, operatingCost: Int64, maintenanceCost: Int64, energyCost: Int64, staffCost: Int64) {
        self.index = index
        self.fareRevenue = fareRevenue
        self.operatingCost = operatingCost
        self.maintenanceCost = maintenanceCost
        self.energyCost = energyCost
        self.staffCost = staffCost
    }

    init(_ summary: FinanceSummary) {
        self.init(
            index: summary.index, fareRevenue: summary.fareRevenue.amount, operatingCost: summary.operatingCost.amount,
            maintenanceCost: summary.maintenanceCost.amount, energyCost: summary.energyCost.amount, staffCost: summary.staffCost.amount
        )
    }
}

/// The finance report for a period: `{"current", "previous"}`.
struct ReportSummary: Codable, Equatable {
    var current: PeriodSummary
    var previous: PeriodSummary

    init(current: PeriodSummary, previous: PeriodSummary) {
        self.current = current
        self.previous = previous
    }

    init(_ report: (current: FinanceSummary, previous: FinanceSummary)) {
        self.init(current: PeriodSummary(report.current), previous: PeriodSummary(report.previous))
    }
}

/// Portable V3 plan observations, independent of the Swift save schema.
struct TrafficWaitSummary: Codable, Equatable {
    var train: Int
    var station: Int
    var stop: Int
    var cycle: Int64
    var other: Int
    var otherStop: Int
    var otherCycle: Int64
    var kind: String
    var departureSeconds: Int64
    var clearanceSeconds: Int64
    init(_ wait: ScheduledTrafficWait) {
        train = wait.train.rawValue; station = wait.station.rawValue; stop = wait.stop; cycle = wait.cycle
        other = wait.other.rawValue; otherStop = wait.otherStop; otherCycle = wait.otherCycle; kind = wait.kind.rawValue
        departureSeconds = wait.departure.seconds; clearanceSeconds = wait.clearance
    }
}
