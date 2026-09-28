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
            extraTrain.expectedFinalState.trains.append(.init(id: 99, name: "Ghost", position: TrainPositionSummary(nil)))
            XCTAssertEqual(extraTrain.differences().count, 1, name)
        }
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
    /// a missing, extra or repeated neighbour, or the same neighbours in
    /// another order is reported at that step and nowhere else.
    func testChangedTopologyExpectationsAreReported() throws {
        var observationCount = 0
        var orderedAnswerCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, step) in committed.steps.enumerated() {
                guard case .observe(let observation, let expect) = step else { continue }
                observationCount += 1
                if case .neighbors(let neighbors) = expect, neighbors.count > 1 {
                    orderedAnswerCount += 1
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
        }
    }

    /// A fixture that wrongly expects a one-sided exit to be a link fails,
    /// and the message shows GameCore's actual answer.
    func testAWrongTopologyExpectationIsReported() throws {
        let json = #"""
            {
              "schemaVersion": 3,
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
        for version in [1, 2, 4] {
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
        ]
        for json in commands {
            XCTAssertThrowsError(try JSONDecoder().decode(ScenarioCommand.self, from: Data(json.utf8)), json)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "maybe"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "unknownTrain"}"#.utf8)))

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
