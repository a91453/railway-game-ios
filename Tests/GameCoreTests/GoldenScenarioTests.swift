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
            let first = try XCTUnwrap(committed.steps.indices.first, name)
            wrongOutcome.steps[first].expect = committed.steps[first].expect == .ok ? .rejected(.invalidName) : .ok
            XCTAssertEqual(wrongOutcome.differences().count, 1, name)

            var wrongBalance = committed
            wrongBalance.expectedFinalState.balance += 1
            XCTAssertEqual(wrongBalance.differences().count, 1, name)

            var wrongTime = committed
            wrongTime.expectedFinalState.gameMinutes += 1
            XCTAssertEqual(wrongTime.differences().count, 1, name)

            var extraTrain = committed
            extraTrain.expectedFinalState.trains.append(.init(id: 99, name: "Ghost"))
            XCTAssertEqual(extraTrain.differences().count, 1, name)
        }
    }

    func testUnsupportedSchemaVersionIsRejected() {
        let data = Data(#"{"schemaVersion": 2}"#.utf8)

        XCTAssertThrowsError(try GoldenScenario.decode(data)) { error in
            XCTAssertEqual(error as? GoldenScenario.FixtureError, .unsupportedSchemaVersion(2))
        }
    }

    func testMalformedStepsAreRejectedRatherThanGuessed() {
        let commands = [
            #"{"type": "demolish", "x": 1, "y": 1}"#,
            #"{"type": "buildTrack", "x": 1, "y": 1, "connections": ["up"]}"#,
            #"{"type": "buildTrack", "x": 1, "y": 1, "connections": ["east", "east"]}"#,
            #"{"type": "advance", "ticks": -1}"#,
            #"{"type": "setSpeed", "speed": "triple"}"#,
        ]
        for json in commands {
            XCTAssertThrowsError(try JSONDecoder().decode(ScenarioCommand.self, from: Data(json.utf8)), json)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "maybe"}"#.utf8)))

        let negativeCost = #"{"track": -1, "station": 0, "train": 0}"#
        XCTAssertThrowsError(try JSONDecoder().decode(GoldenScenario.Costs.self, from: Data(negativeCost.utf8)))
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
