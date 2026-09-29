import Foundation
import GameCore
import XCTest

/// Runs every checked-in scenario in `GoldenScenarios/` against GameCore and
/// compares the outcome with the expectations committed in the fixture.
///
/// The fixtures are the portable behavior contract: a port of GameCore to
/// another language must reproduce the same outcomes from the same files.
final class GoldenScenarioTests: XCTestCase {
    func testGoldenScenariosMatchCommittedExpectations() throws {
        let urls = try GoldenScenarioFixtures.urls()
        XCTAssertFalse(urls.isEmpty, "No fixtures in \(GoldenScenarioFixtures.directory.path)")

        for url in urls {
            let scenario: GoldenScenario
            do {
                scenario = try GoldenScenario.decode(Data(contentsOf: url))
            } catch {
                XCTFail("\(url.lastPathComponent): \(error)")
                continue
            }
            for difference in scenario.differences() {
                XCTFail("\(url.lastPathComponent): \(difference)")
            }
        }
    }

    /// ASCII only, and numbers only as plain integers every JSON reader
    /// represents exactly.
    func testFixturesUsePortableJSON() throws {
        for url in try GoldenScenarioFixtures.urls() {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.unicodeScalars.allSatisfy(\.isASCII), "\(url.lastPathComponent) is not ASCII")
            XCTAssertEqual(GoldenScenarioFixtures.nonPortableNumbers(in: text), [], url.lastPathComponent)
        }
    }

    // MARK: - The mechanism itself

    /// A golden test that cannot fail protects nothing: changing a committed
    /// expectation in any fixture must be reported.
    func testChangedExpectationsAreReported() throws {
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            XCTAssertEqual(committed.differences(), [], name)

            var wrongOutcome = committed
            let first = try XCTUnwrap(committed.steps.firstIndex { if case .command = $0 { true } else { false } }, name)
            if case .command(let command, let expect) = committed.steps[first] {
                wrongOutcome.steps[first] = .command(command, expect: expect == .ok ? .rejected(.invalidName) : .ok)
            }
            XCTAssertEqual(wrongOutcome.differences().count, 1, name)

            var wrongBalance = committed
            wrongBalance.expectedFinalState.balance += 1
            XCTAssertEqual(wrongBalance.differences().count, 1, name)

            var wrongTime = committed
            wrongTime.expectedFinalState.gameMinutes += 1
            XCTAssertEqual(wrongTime.differences().count, 1, name)

            var extraTrain = committed
            extraTrain.expectedFinalState.trains.append(.init(id: 99, name: "Ghost", position: TrainPositionSummary(nil), movement: TrainMovementSummary(.idle), timetable: []))
            XCTAssertEqual(extraTrain.differences().count, 1, name)
        }
    }

    /// A train's expected movement is compared exactly: another rate, cursor
    /// or continuation is reported once.
    func testChangedTrainMovementExpectationsAreReported() throws {
        var movingCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, train) in committed.expectedFinalState.trains.enumerated() {
                if train.movement.rate > 0 {
                    movingCount += 1
                }
                var wrongMovements: [TrainMovementSummary] = []
                var changed = train.movement
                changed.rate += 1
                wrongMovements.append(changed)
                changed = train.movement
                changed.cursor += 1
                wrongMovements.append(changed)
                changed = train.movement
                changed.continuation.append(PositionSummary(GridPosition(x: 0, y: 0)))
                wrongMovements.append(changed)
                for wrong in wrongMovements {
                    var scenario = committed
                    scenario.expectedFinalState.trains[index].movement = wrong
                    XCTAssertEqual(scenario.differences().count, 1, "\(name) train \(train.id) expecting \(wrong)")
                }
            }
        }
        XCTAssertGreaterThan(movingCount, 0, "No fixture expects a train with a rate")
    }

    /// A train's expected timetable is compared exactly, in order: an extra,
    /// missing or repeated stop, another station, a time one minute off, or
    /// the same stops in another order is reported once.
    func testChangedTrainTimetableExpectationsAreReported() throws {
        var scheduledCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, train) in committed.expectedFinalState.trains.enumerated() {
                if train.timetable.count > 1 {
                    scheduledCount += 1
                }
                for wrong in Self.wrongTimetables(for: train.timetable) {
                    var scenario = committed
                    scenario.expectedFinalState.trains[index].timetable = wrong
                    XCTAssertEqual(scenario.differences().count, 1, "\(name) train \(train.id) expecting \(wrong)")
                }
            }
        }
        XCTAssertGreaterThan(scheduledCount, 0, "No fixture expects a train with a timetable of more than one stop")
    }

    /// Timetables that differ from `stops` in one way each.
    private static func wrongTimetables(for stops: [StopSummary]) -> [[StopSummary]] {
        var wrong: [[StopSummary]] = [stops + [StopSummary(ScheduledStop(station: StationID(rawValue: 99), arrival: .zero, departure: .zero))]]
        guard let first = stops.first else { return wrong }
        wrong.append(Array(stops.dropLast()))
        wrong.append([first] + stops)
        var changed = stops
        changed[0].station += 1
        wrong.append(changed)
        changed = stops
        changed[0].arrival += 1
        wrong.append(changed)
        changed = stops
        changed[stops.count - 1].departure += 1
        wrong.append(changed)
        if stops.count > 1 {
            wrong.append(stops.reversed())
        }
        return wrong
    }

    /// A train's expected position is compared exactly: unplaced instead of
    /// placed (or the reverse), the other heading, the other end of a link,
    /// or an offset one unit off is reported once.
    func testChangedTrainPositionExpectationsAreReported() throws {
        var placedCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, train) in committed.expectedFinalState.trains.enumerated() {
                var wrongPositions: [TrainPosition?] = []
                switch train.position.position {
                case nil:
                    wrongPositions = [.atNode(GridPosition(x: 0, y: 0), heading: .north)]
                case .atNode(let tile, let heading)?:
                    placedCount += 1
                    wrongPositions = [nil, .atNode(tile, heading: heading.opposite)]
                case .onLink(let from, let to, let offset)?:
                    placedCount += 1
                    wrongPositions = [nil, .onLink(from: to, to: from, offset: offset), .onLink(from: from, to: to, offset: offset + 1)]
                }
                for wrong in wrongPositions {
                    var changed = committed
                    changed.expectedFinalState.trains[index].position = TrainPositionSummary(wrong)
                    XCTAssertEqual(changed.differences().count, 1, "\(name) train \(train.id) expecting \(String(describing: wrong))")
                }
            }
        }
        XCTAssertGreaterThan(placedCount, 0, "No fixture expects a placed train")
    }

    /// Every observation's expectation is compared exactly: a flipped answer,
    /// a missing, extra or repeated neighbour, the same neighbours in another
    /// order, or any change to a train's position or movement is reported at
    /// that step and nowhere else.
    func testChangedObservationExpectationsAreReported() throws {
        var observationCount = 0
        var orderedAnswerCount = 0
        var trainAnswerCount = 0
        var routeAnswerCount = 0
        var platformAnswerCount = 0
        var stationRouteCount = 0
        var sharedStopCount = 0
        var timetableAnswerCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, step) in committed.steps.enumerated() {
                guard case .observe(let observation, let expect) = step else { continue }
                observationCount += 1
                if case .neighbors(let neighbors) = expect, neighbors.count > 1 {
                    orderedAnswerCount += 1
                }
                if case .train = expect {
                    trainAnswerCount += 1
                }
                if case .route(let nodes?) = expect, nodes.count > 1 {
                    routeAnswerCount += 1
                }
                if case .platforms(let platforms) = expect, !platforms.isEmpty {
                    platformAnswerCount += 1
                }
                if case .routeToStation = observation, case .route(let nodes?) = expect, nodes.count > 1 {
                    stationRouteCount += 1
                }
                if case .stations(let stations) = expect, stations.count > 1 {
                    sharedStopCount += 1
                }
                if case .timetable(let stops?) = expect, stops.count > 1 {
                    timetableAnswerCount += 1
                }
                for wrong in Self.wrongAnswers(for: expect) {
                    var changed = committed
                    changed.steps[index] = .observe(observation, expect: wrong)
                    let differences = changed.differences()
                    XCTAssertEqual(differences.count, 1, "\(name) steps[\(index)] expecting \(wrong)")
                    XCTAssertTrue(differences.first?.hasPrefix("steps[\(index)]: ") == true, "\(name) steps[\(index)]")
                }
            }
        }
        XCTAssertGreaterThan(observationCount, 0, "No fixture observes track connectivity")
        XCTAssertGreaterThan(orderedAnswerCount, 0, "No fixture pins the order of connected neighbours")
        XCTAssertGreaterThan(trainAnswerCount, 0, "No fixture observes a train")
        XCTAssertGreaterThan(routeAnswerCount, 0, "No fixture pins a route of more than one node")
        XCTAssertGreaterThan(platformAnswerCount, 0, "No fixture pins a station's platforms")
        XCTAssertGreaterThan(stationRouteCount, 0, "No fixture pins a route to a station of more than one node")
        XCTAssertGreaterThan(sharedStopCount, 0, "No fixture pins a train stopped at more than one station")
        XCTAssertGreaterThan(timetableAnswerCount, 0, "No fixture pins a timetable of more than one stop")
    }

    private static func wrongAnswers(for answer: ObservationAnswer) -> [ObservationAnswer] {
        switch answer {
        case .connected(let connected):
            return [.connected(!connected)]
        case .neighbors(let neighbors):
            var wrong: [ObservationAnswer] = [.neighbors(neighbors + [GridPosition(x: 99, y: 99)])]
            if let first = neighbors.first {
                wrong.append(.neighbors(Array(neighbors.dropFirst())))
                wrong.append(.neighbors(neighbors + [first]))
            }
            if neighbors.count > 1 {
                wrong.append(.neighbors(neighbors.reversed()))
            }
            return wrong
        case .route(nil):
            return [.route([])]
        case .route(let nodes?):
            var wrong: [ObservationAnswer] = [.route(nil), .route(nodes + [GridPosition(x: 99, y: 99)])]
            if !nodes.isEmpty {
                wrong.append(.route(Array(nodes.dropLast())))
            }
            if nodes.count > 1 {
                wrong.append(.route(nodes.reversed()))
            }
            return wrong
        case .train(nil):
            return []
        case .train(let state?):
            return [.train(nil)] + wrongStates(for: state).map { .train($0) }
        case .platforms(let platforms):
            var wrong: [ObservationAnswer] = [.platforms(platforms + [GridPosition(x: 99, y: 99)])]
            if let first = platforms.first {
                wrong.append(.platforms(Array(platforms.dropFirst())))
                wrong.append(.platforms(platforms + [first]))
            }
            if platforms.count > 1 {
                wrong.append(.platforms(platforms.reversed()))
            }
            return wrong
        case .stations(let stations):
            var wrong: [ObservationAnswer] = [.stations(stations + [StationID(rawValue: 99)])]
            if let first = stations.first {
                wrong.append(.stations(Array(stations.dropFirst())))
                wrong.append(.stations(stations + [first]))
            }
            if stations.count > 1 {
                wrong.append(.stations(stations.reversed()))
            }
            return wrong
        case .timetable(nil):
            return []
        case .timetable(let stops?):
            return [.timetable(nil)] + wrongTimetables(for: stops.map(StopSummary.init)).map { .timetable($0.map(\.stop)) }
        }
    }

    /// Train states that differ from `state` in one field each.
    private static func wrongStates(for state: TrainState) -> [TrainState] {
        var wrong: [TrainState] = []
        var changed = state
        switch state.position.position {
        case nil:
            changed.position = TrainPositionSummary(.atNode(GridPosition(x: 0, y: 0), heading: .north))
        case .atNode(let tile, let heading)?:
            changed.position = TrainPositionSummary(.atNode(tile, heading: heading.opposite))
        case .onLink(let from, let to, let offset)?:
            changed.position = TrainPositionSummary(.onLink(from: from, to: to, offset: offset + 1))
        }
        wrong.append(changed)
        changed = state
        changed.movement.rate += 1
        wrong.append(changed)
        changed = state
        changed.movement.cursor += 1
        wrong.append(changed)
        changed = state
        changed.movement.continuation.append(PositionSummary(GridPosition(x: 99, y: 99)))
        wrong.append(changed)
        return wrong
    }

    /// A fixture that wrongly expects a one-sided exit to be a link fails,
    /// and the message shows GameCore's actual answer.
    func testAWrongTopologyExpectationIsReported() throws {
        let json = #"""
            {
              "schemaVersion": 8,
              "description": "Deliberately wrong: expects a one-sided exit to join.",
              "initialState": {
                "mapWidth": 2, "mapHeight": 1, "balance": 2000,
                "costs": { "track": 1000, "station": 50000, "train": 200000 },
                "gameMinutes": 0, "speed": "paused"
              },
              "steps": [
                {
                  "command": { "type": "buildTrack", "x": 0, "y": 0, "connections": ["east"] },
                  "expect": { "result": "ok" }
                },
                {
                  "command": { "type": "buildTrack", "x": 1, "y": 0, "connections": ["north"] },
                  "expect": { "result": "ok" }
                },
                {
                  "observe": { "type": "isConnected", "from": { "x": 0, "y": 0 }, "to": { "x": 1, "y": 0 } },
                  "expect": { "connected": true }
                },
                {
                  "observe": { "type": "connectedNeighbors", "x": 0, "y": 0 },
                  "expect": { "neighbors": [{ "x": 1, "y": 0 }] }
                }
              ],
              "expectedFinalState": {
                "gameMinutes": 0, "speed": "paused", "balance": 0, "stations": [],
                "tracks": [
                  { "x": 0, "y": 0, "connections": ["east"] },
                  { "x": 1, "y": 0, "connections": ["north"] }
                ],
                "trains": []
              }
            }
            """#

        let scenario = try GoldenScenario.decode(Data(json.utf8))

        XCTAssertEqual(scenario.differences(), [
            #"steps[2]: expected {"connected":true}, got {"connected":false}"#,
            #"steps[3]: expected {"neighbors":[{"x":1,"y":0}]}, got {"neighbors":[]}"#,
        ])
    }

    func testUnsupportedSchemaVersionIsRejected() {
        for version in [1, 2, 3, 4, 5, 6, 7, 9] {
            let data = Data(#"{"schemaVersion": \#(version)}"#.utf8)

            XCTAssertThrowsError(try GoldenScenario.decode(data)) { error in
                XCTAssertEqual(error as? GoldenScenario.FixtureError, .unsupportedSchemaVersion(version))
            }
        }
    }

    func testMalformedStepsAreRejectedRatherThanGuessed() {
        let commands = [
            #"{"type": "demolish", "x": 1, "y": 1}"#,
            #"{"type": "buildTrack", "x": 1, "y": 1, "connections": ["up"]}"#,
            #"{"type": "buildTrack", "x": 1, "y": 1, "connections": ["east", "east"]}"#,
            #"{"type": "advance", "ticks": -1}"#,
            #"{"type": "setSpeed", "speed": "triple"}"#,
            // Observations are not commands.
            #"{"type": "connectedNeighbors", "x": 1, "y": 1}"#,
            // Train commands need a train, and a placement a node or link.
            #"{"type": "reverseTrain"}"#,
            #"{"type": "unplaceTrain", "train": "1"}"#,
            #"{"type": "placeTrain", "position": {"type": "node", "x": 1, "y": 1, "heading": "east"}}"#,
            #"{"type": "placeTrain", "train": 1}"#,
            #"{"type": "placeTrain", "train": 1, "position": {"type": "unplaced"}}"#,
            // Movement commands need a train and a value of the right kind.
            #"{"type": "setTrainMovementRate", "train": 1}"#,
            #"{"type": "setTrainMovementRate", "rate": 5}"#,
            #"{"type": "setTrainMovementRate", "train": 1, "rate": "fast"}"#,
            #"{"type": "setTrainContinuation", "train": 1}"#,
            #"{"type": "setTrainContinuation", "train": 1, "continuation": [{"x": 1}]}"#,
            #"{"type": "setTrainContinuation", "train": 1, "continuation": ["east"]}"#,
            // Observations are not commands.
            #"{"type": "train", "train": 1}"#,
            #"{"type": "timetable", "train": 1}"#,
            // A timetable needs a train and stops with a station and two
            // integer times each.
            #"{"type": "setTrainTimetable", "train": 1}"#,
            #"{"type": "setTrainTimetable", "timetable": []}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 1, "arrival": 0}]}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"arrival": 0, "departure": 0}]}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": "Alpha", "arrival": 0, "departure": 0}]}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 1, "arrival": "08:00", "departure": 0}]}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 1, "arrival": 0.5, "departure": 1}]}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": {"station": 1, "arrival": 0, "departure": 0}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": null}"#,
        ]
        for json in commands {
            XCTAssertThrowsError(try JSONDecoder().decode(ScenarioCommand.self, from: Data(json.utf8)), json)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "maybe"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "unknownTrain"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "unknownStation"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "unknownStation", "station": "Alpha"}"#.utf8)))

        let negativeCost = #"{"track": -1, "station": 0, "train": 0}"#
        XCTAssertThrowsError(try JSONDecoder().decode(GoldenScenario.Costs.self, from: Data(negativeCost.utf8)))
    }

    func testMalformedObservationsAreRejectedRatherThanGuessed() {
        let from = #""from": {"x": 0, "y": 0}"#
        let to = #""to": {"x": 1, "y": 0}"#
        let steps = [
            // Exactly one of command and observe.
            #"{"expect": {"result": "ok"}}"#,
            #"{"command": {"type": "pause"}, "observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"result": "ok"}}"#,
            // Unknown observation.
            #"{"observe": {"type": "shortestPath", "x": 0, "y": 0}, "expect": {"neighbors": []}}"#,
            // An answer of another observation's kind, or a command result.
            #"{"observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"connected": false}}"#,
            #"{"observe": {"type": "isConnected", \#(from), \#(to)}, "expect": {"neighbors": []}}"#,
            #"{"observe": {"type": "isConnected", \#(from), \#(to)}, "expect": {"result": "ok"}}"#,
            // Both answers at once: neither may be silently ignored.
            #"{"observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"neighbors": [], "connected": false}}"#,
            #"{"observe": {"type": "isConnected", \#(from), \#(to)}, "expect": {"connected": false, "neighbors": []}}"#,
            // Missing or ill-typed values.
            #"{"observe": {"type": "isConnected", \#(from)}, "expect": {"connected": false}}"#,
            #"{"observe": {"type": "isConnected", \#(from), \#(to)}, "expect": {"connected": "yes"}}"#,
            #"{"observe": {"type": "connectedNeighbors", "x": 0}, "expect": {"neighbors": []}}"#,
            #"{"observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"neighbors": [{"x": 1}]}}"#,
            #"{"observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"neighbors": ["east"]}}"#,
            // A train is answered by its position and movement, both required,
            // and by nothing else.
            #"{"observe": {"type": "train"}, "expect": {"position": {"type": "unplaced"}, "movement": {"rate": 0, "continuation": [], "cursor": 0}}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "unplaced"}}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"movement": {"rate": 0, "continuation": [], "cursor": 0}}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "unplaced"}, "movement": {"rate": 0, "continuation": []}}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "unplaced"}, "movement": {"rate": 0, "continuation": [], "cursor": 0}, "connected": true}}"#,
            #"{"observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"neighbors": [], "position": {"type": "unplaced"}}}"#,
            // A route is answered by "found", with "route" exactly when found.
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"route": []}}"#,
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"found": false, "route": []}}"#,
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"found": "yes", "route": []}}"#,
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"found": false, "connected": false}}"#,
            // A route starts from a placed position and needs a destination.
            #"{"observe": {"type": "route", "from": {"type": "unplaced"}, "to": {"x": 1, "y": 0}}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "route", "from": {"x": 0, "y": 0}, "to": {"x": 1, "y": 0}}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}}, "expect": {"found": false}}"#,
            // A route to a station answers like a route, and needs a start
            // and a station ID.
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1}, "expect": {"found": false, "route": []}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1}, "expect": {"found": false, "platforms": []}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "unplaced"}, "station": 1}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": "Central"}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"found": false}}"#,
            // Platforms and station stops have answers of their own.
            #"{"observe": {"type": "platforms"}, "expect": {"platforms": []}}"#,
            #"{"observe": {"type": "platforms", "station": 1}, "expect": {"neighbors": []}}"#,
            #"{"observe": {"type": "platforms", "station": 1}, "expect": {"platforms": [], "stations": []}}"#,
            #"{"observe": {"type": "platforms", "station": 1}, "expect": {"platforms": [{"x": 1}]}}"#,
            #"{"observe": {"type": "stationStops"}, "expect": {"stations": []}}"#,
            #"{"observe": {"type": "stationStops", "train": 1}, "expect": {"platforms": []}}"#,
            #"{"observe": {"type": "stationStops", "train": 1}, "expect": {"stations": ["Central"]}}"#,
            #"{"observe": {"type": "stationStops", "train": 1}, "expect": {"stations": [], "found": false}}"#,
            // A timetable is answered by its stops, and by nothing else.
            #"{"observe": {"type": "timetable"}, "expect": {"timetable": []}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {"stations": []}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {"timetable": [], "stations": []}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {"timetable": [{"station": 1, "arrival": 0}]}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {"timetable": null}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "unplaced"}, "movement": {"rate": 0, "continuation": [], "cursor": 0}, "timetable": []}}"#,
        ]
        for json in steps {
            XCTAssertThrowsError(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), json)
        }
    }

    func testObservationStepsDecode() throws {
        let neighbors = #"{"observe": {"type": "connectedNeighbors", "x": 2, "y": 1}, "expect": {"neighbors": [{"x": 2, "y": 0}, {"x": 1, "y": 1}]}}"#
        let connected = #"{"observe": {"type": "isConnected", "from": {"x": 2, "y": 1}, "to": {"x": 3, "y": 1}}, "expect": {"connected": true}}"#

        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(neighbors.utf8)),
            .observe(.connectedNeighbors(GridPosition(x: 2, y: 1)), expect: .neighbors([GridPosition(x: 2, y: 0), GridPosition(x: 1, y: 1)]))
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(connected.utf8)),
            .observe(.isConnected(GridPosition(x: 2, y: 1), to: GridPosition(x: 3, y: 1)), expect: .connected(true))
        )

        let found = #"{"observe": {"type": "route", "from": {"type": "link", "from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}, "offset": 9}, "to": {"x": 3, "y": 2}}, "expect": {"found": true, "route": [{"x": 3, "y": 1}, {"x": 3, "y": 2}]}}"#
        let notFound = #"{"observe": {"type": "route", "from": {"type": "node", "x": 1, "y": 1, "heading": "west"}, "to": {"x": 3, "y": 2}}, "expect": {"found": false}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(found.utf8)),
            .observe(
                .route(from: .onLink(from: GridPosition(x: 1, y: 1), to: GridPosition(x: 2, y: 1), offset: 9), to: GridPosition(x: 3, y: 2)),
                expect: .route([GridPosition(x: 3, y: 1), GridPosition(x: 3, y: 2)])
            )
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(notFound.utf8)),
            .observe(.route(from: .atNode(GridPosition(x: 1, y: 1), heading: .west), to: GridPosition(x: 3, y: 2)), expect: .route(nil))
        )

        let platforms = #"{"observe": {"type": "platforms", "station": 2}, "expect": {"platforms": [{"x": 4, "y": 0}, {"x": 3, "y": 1}]}}"#
        let toStation = #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 1, "y": 1, "heading": "east"}, "station": 2}, "expect": {"found": true, "route": [{"x": 2, "y": 1}, {"x": 3, "y": 1}]}}"#
        let noStationRoute = #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 1, "y": 1, "heading": "west"}, "station": 9}, "expect": {"found": false}}"#
        let stops = #"{"observe": {"type": "stationStops", "train": 3}, "expect": {"stations": [1, 4]}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(platforms.utf8)),
            .observe(.platforms(StationID(rawValue: 2)), expect: .platforms([GridPosition(x: 4, y: 0), GridPosition(x: 3, y: 1)]))
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(toStation.utf8)),
            .observe(
                .routeToStation(from: .atNode(GridPosition(x: 1, y: 1), heading: .east), station: StationID(rawValue: 2)),
                expect: .route([GridPosition(x: 2, y: 1), GridPosition(x: 3, y: 1)])
            )
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(noStationRoute.utf8)),
            .observe(.routeToStation(from: .atNode(GridPosition(x: 1, y: 1), heading: .west), station: StationID(rawValue: 9)), expect: .route(nil))
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(stops.utf8)),
            .observe(.stationStops(TrainID(rawValue: 3)), expect: .stations([StationID(rawValue: 1), StationID(rawValue: 4)]))
        )

        let timetable = #"{"observe": {"type": "timetable", "train": 2}, "expect": {"timetable": [{"station": 3, "arrival": 0, "departure": 0}, {"station": 1, "arrival": 1440, "departure": 1450}]}}"#
        let emptyTimetable = #"{"observe": {"type": "timetable", "train": 1}, "expect": {"timetable": []}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(timetable.utf8)),
            .observe(.timetable(TrainID(rawValue: 2)), expect: .timetable([
                ScheduledStop(station: StationID(rawValue: 3), arrival: GameTime(minutes: 0), departure: GameTime(minutes: 0)),
                ScheduledStop(station: StationID(rawValue: 1), arrival: GameTime(minutes: 1440), departure: GameTime(minutes: 1450)),
            ]))
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(emptyTimetable.utf8)),
            .observe(.timetable(TrainID(rawValue: 1)), expect: .timetable([]))
        )

        let train = #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "link", "from": {"x": 2, "y": 1}, "to": {"x": 3, "y": 1}, "offset": 532}, "movement": {"rate": 1300, "continuation": [{"x": 3, "y": 1}, {"x": 4, "y": 1}], "cursor": 1}}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(train.utf8)),
            .observe(.train(TrainID(rawValue: 1)), expect: .train(TrainState(
                position: TrainPositionSummary(.onLink(from: GridPosition(x: 2, y: 1), to: GridPosition(x: 3, y: 1), offset: 532)),
                movement: TrainMovementSummary(rate: 1300, continuation: [GridPosition(x: 3, y: 1), GridPosition(x: 4, y: 1)], cursor: 1)
            )))
        )
    }

    func testTrainCommandsAndResultsDecode() throws {
        let commands: [(String, ScenarioCommand)] = [
            (#"{"type": "placeTrain", "train": 2, "position": {"type": "node", "x": 3, "y": 1, "heading": "west"}}"#,
             .placeTrain(TrainID(rawValue: 2), .atNode(GridPosition(x: 3, y: 1), heading: .west))),
            (#"{"type": "placeTrain", "train": 1, "position": {"type": "link", "from": {"x": 1, "y": 2}, "to": {"x": 1, "y": 1}, "offset": 256}}"#,
             .placeTrain(TrainID(rawValue: 1), .onLink(from: GridPosition(x: 1, y: 2), to: GridPosition(x: 1, y: 1), offset: 256))),
            // Read as written: rejecting offset 0 is GameCore's decision.
            (#"{"type": "placeTrain", "train": 1, "position": {"type": "link", "from": {"x": 1, "y": 2}, "to": {"x": 1, "y": 1}, "offset": 0}}"#,
             .placeTrain(TrainID(rawValue: 1), .onLink(from: GridPosition(x: 1, y: 2), to: GridPosition(x: 1, y: 1), offset: 0))),
            (#"{"type": "unplaceTrain", "train": 3}"#, .unplaceTrain(TrainID(rawValue: 3))),
            (#"{"type": "reverseTrain", "train": 4}"#, .reverseTrain(TrainID(rawValue: 4))),
            (#"{"type": "setTrainMovementRate", "train": 2, "rate": 1300}"#, .setTrainMovementRate(TrainID(rawValue: 2), 1300)),
            // Read as written: rejecting a negative rate is GameCore's decision.
            (#"{"type": "setTrainMovementRate", "train": 2, "rate": -1}"#, .setTrainMovementRate(TrainID(rawValue: 2), -1)),
            (#"{"type": "setTrainContinuation", "train": 1, "continuation": [{"x": 3, "y": 1}, {"x": 3, "y": 2}]}"#,
             .setTrainContinuation(TrainID(rawValue: 1), [GridPosition(x: 3, y: 1), GridPosition(x: 3, y: 2)])),
            (#"{"type": "setTrainContinuation", "train": 1, "continuation": []}"#, .setTrainContinuation(TrainID(rawValue: 1), [])),
            (#"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 2, "arrival": 20, "departure": 25}, {"station": 2, "arrival": 25, "departure": 25}]}"#,
             .setTrainTimetable(TrainID(rawValue: 1), [
                ScheduledStop(station: StationID(rawValue: 2), arrival: GameTime(minutes: 20), departure: GameTime(minutes: 25)),
                ScheduledStop(station: StationID(rawValue: 2), arrival: GameTime(minutes: 25), departure: GameTime(minutes: 25)),
             ])),
            (#"{"type": "setTrainTimetable", "train": 3, "timetable": []}"#, .setTrainTimetable(TrainID(rawValue: 3), [])),
            // Read as written: rejecting a negative time, a departure before
            // the arrival or an unknown station is GameCore's decision.
            (#"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 0, "arrival": -1, "departure": -5}]}"#,
             .setTrainTimetable(TrainID(rawValue: 1), [ScheduledStop(station: StationID(rawValue: 0), arrival: GameTime(minutes: -1), departure: GameTime(minutes: -5))])),
        ]
        for (json, expected) in commands {
            XCTAssertEqual(try JSONDecoder().decode(ScenarioCommand.self, from: Data(json.utf8)), expected, json)
        }

        let results: [(String, StepOutcome)] = [
            (#"{"result": "trackInUse", "x": 1, "y": 2}"#, .rejected(.trackInUse(GridPosition(x: 1, y: 2)))),
            (#"{"result": "unknownTrain", "train": 9}"#, .rejected(.unknownTrain(TrainID(rawValue: 9)))),
            (#"{"result": "trainAlreadyPlaced", "train": 1}"#, .rejected(.trainAlreadyPlaced(TrainID(rawValue: 1)))),
            (#"{"result": "trainNotPlaced", "train": 1}"#, .rejected(.trainNotPlaced(TrainID(rawValue: 1)))),
            (#"{"result": "invalidTrainPosition"}"#, .rejected(.invalidTrainPosition)),
            (#"{"result": "invalidMovementRate"}"#, .rejected(.invalidMovementRate)),
            (#"{"result": "invalidContinuation"}"#, .rejected(.invalidContinuation)),
            (#"{"result": "clockOverflow"}"#, .rejected(.clockOverflow)),
            (#"{"result": "idsExhausted"}"#, .rejected(.idsExhausted)),
            (#"{"result": "invalidTimetable"}"#, .rejected(.invalidTimetable)),
            (#"{"result": "unknownStation", "station": 4}"#, .rejected(.unknownStation(StationID(rawValue: 4)))),
        ]
        for (json, expected) in results {
            XCTAssertEqual(try JSONDecoder().decode(StepOutcome.self, from: Data(json.utf8)), expected, json)
        }
    }

    func testMalformedTrainPositionsAreRejectedRatherThanGuessed() {
        let positions = [
            #"{"type": "moving"}"#,
            #"{"x": 1, "y": 1, "heading": "east"}"#,
            // Missing, ill-typed or unknown values.
            #"{"type": "node", "x": 1, "y": 1}"#,
            #"{"type": "node", "x": 1, "y": 1, "heading": "up"}"#,
            #"{"type": "link", "from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}}"#,
            #"{"type": "link", "from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}, "offset": "256"}"#,
            #"{"type": "link", "from": {"x": 1, "y": 1}, "to": {"x": 2}, "offset": 256}"#,
            // Fields of another type are not silently ignored.
            #"{"type": "unplaced", "x": 1, "y": 1}"#,
            #"{"type": "node", "x": 1, "y": 1, "heading": "east", "offset": 256}"#,
            #"{"type": "link", "from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}, "offset": 256, "heading": "east"}"#,
            #"{"type": "link", "x": 1, "y": 1, "from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}, "offset": 256}"#,
        ]
        for json in positions {
            XCTAssertThrowsError(try JSONDecoder().decode(TrainPositionSummary.self, from: Data(json.utf8)), json)
        }
    }

    func testDirectionOrderDoesNotMatter() throws {
        let json = #"{"type": "buildTrack", "x": 1, "y": 2, "connections": ["west", "north"]}"#

        let command = try JSONDecoder().decode(ScenarioCommand.self, from: Data(json.utf8))

        XCTAssertEqual(command, .buildTrack(GridPosition(x: 1, y: 2), [.north, .west]))
    }

    func testNonPortableNumbersAreDetected() {
        let json = #"{"a": 1.0, "b": 1e3, "c": 9007199254740992, "d": -9007199254740991, "e": 0, "f": "2.5", "g": true, "h": 012}"#

        XCTAssertEqual(
            GoldenScenarioFixtures.nonPortableNumbers(in: json),
            ["1.0", "1e3", "9007199254740992", "012"]
        )
        // A combining mark right after a quote must not hide the string's end.
        XCTAssertEqual(GoldenScenarioFixtures.nonPortableNumbers(in: #"{"s": "\#u{301}x", "n": 2.5}"#), ["2.5"])
    }
}
