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
            let scenario = try GoldenScenario.decode(Data(contentsOf: url))
            for difference in scenario.differences() {
                XCTFail("\(url.lastPathComponent): \(difference)")
            }
        }
    }

    func testFixturesContainOnlyPortableIntegers() throws {
        for url in try GoldenScenarioFixtures.urls() {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(GoldenScenarioFixtures.nonPortableNumbers(in: text), [], url.lastPathComponent)
        }
    }

    // MARK: - The mechanism itself

    /// A golden test that cannot fail protects nothing: changing any committed
    /// expectation must be reported.
    func testChangedExpectationsAreReported() throws {
        let url = GoldenScenarioFixtures.directory.appendingPathComponent("build-starter-line.json")
        let committed = try GoldenScenario.decode(Data(contentsOf: url))
        XCTAssertEqual(committed.differences(), [])

        var wrongOutcome = committed
        wrongOutcome.steps[7].expect = .ok
        XCTAssertEqual(wrongOutcome.differences().count, 1)

        var wrongBalance = committed
        wrongBalance.expectedFinalState.balance = Money(45_001)
        XCTAssertEqual(wrongBalance.differences().count, 1)

        var missingTrack = committed
        missingTrack.expectedFinalState.tracks.removeLast()
        XCTAssertEqual(missingTrack.differences().count, 1)
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
    }
}
