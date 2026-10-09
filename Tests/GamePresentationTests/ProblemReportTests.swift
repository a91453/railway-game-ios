import GameCore
import GamePresentation
import XCTest

/// Decision 127: the note "Report a Problem" shares, in both languages,
/// with the version, the device and, from a game, what is in it.
final class ProblemReportTests: XCTestCase {
    func testTheNoteAsksThreeQuestionsAndListsTheDetails() {
        let report = ProblemReport(version: "0.4.0", build: "12", system: "iOS 26.0", device: "iPhone17,1")
        XCTAssertEqual(report.versionText, "0.4.0 (12)")
        XCTAssertEqual(report.subject(in: .english), "Along the Line 0.4.0 (12): a problem")
        XCTAssertEqual(report.subject(in: .traditionalChinese), "沿線 0.4.0 (12)：問題回報")
        XCTAssertEqual(report.text(in: .english), """
            What happened?


            What did you expect?


            How can it be made to happen again?


            —
            Version: 0.4.0 (12)
            System: iOS 26.0, iPhone17,1
            """)
        let chinese = report.text(in: .traditionalChinese)
        XCTAssertTrue(chinese.hasPrefix("發生了什麼事？"))
        XCTAssertTrue(chinese.hasSuffix("版本：0.4.0 (12)\n系統：iOS 26.0，iPhone17,1"))
        XCTAssertFalse(chinese.contains("遊戲："), "no game from the start screen")
    }

    @MainActor
    func testFromAGameTheNoteSaysWhatIsInIt() throws {
        let session = GameSession(world: DemoWorld.make(in: .english))
        let game = session.problemReportGame
        XCTAssertTrue(game.hasPrefix("blank map · managed · "), game)
        XCTAssertTrue(game.contains("\(session.world.stations.count) stations, \(session.world.lines.count) lines"), game)
        XCTAssertTrue(game.hasSuffix("save version \(SavedGame.currentVersion)"), game)
        let report = ProblemReport(version: "1", build: "2", system: "iOS", device: "iPad", game: game)
        XCTAssertTrue(report.text(in: .english).hasSuffix("\nGame: \(game)"))

        let free = GameSession(world: try makeWorld())
        XCTAssertTrue(free.problemReportGame.hasPrefix("blank map · free · "))
    }
}
