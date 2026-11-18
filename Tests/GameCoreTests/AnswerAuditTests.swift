import Foundation
import XCTest
@testable import GameCore

/// Decision 876 (TICK-REAL): a run's trip, a line's plans, the trains in
/// the way and the due runs that cannot leave are given again from a memo
/// rather than worked out each time they are asked. Here every answer
/// given again is checked against working it out again (the game never
/// pays for the check, ``GameWorld/AnswerAudit``), over the recorded
/// command streams, and the streams still replay to their states.
/// `SavedWorldTickReportTests` makes the same check over a saved game
/// with `SAVED_WORLD_AUDIT=1`.
final class AnswerAuditTests: XCTestCase {
    /// Runs `body` with every answer given again checked, and returns how
    /// many were.
    static func audited<Result>(_ body: () throws -> Result) rethrows -> (result: Result, audit: GameWorld.AnswerAudit) {
        let audit = GameWorld.AnswerAudit()
        let result = try GameWorld.$answerAudit.withValue(audit, operation: body)
        return (result, audit)
    }

    func testEveryRecordedStreamReplaysWithTheAnswersItWouldWorkOut() throws {
        var checked = 0
        for url in try ReplayFixture.urls() {
            let name = url.lastPathComponent
            let fixture = try JSONDecoder().decode(ReplayFixture.self, from: Data(contentsOf: url))
            let operations = try fixture.commands.map { try XCTUnwrap($0.operation, name) }
            let start = try fixture.startWorld()
            let (replayed, audit) = Self.audited {
                ReplayFixture.checksums(from: start, applying: operations, every: fixture.interval) { index, problem in
                    XCTFail("\(name): command \(index): \(problem)")
                }
            }
            XCTAssertEqual(replayed, fixture.checksums, name)
            checked += audit.checked
        }
        XCTAssertGreaterThan(checked, 0, "no stream was ever given an answer again, so nothing was checked")
    }
}
