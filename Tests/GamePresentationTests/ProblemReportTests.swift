import GameCore
import GamePresentation
import XCTest

/// Decision 127: the note "Report a Problem" shares, in both languages,
/// with the version, the device and, from a game, what is in it.
final class ProblemReportTests: XCTestCase {
    func testTheNoteAsksThreeQuestionsAndListsTheDetails() {
        let report = ProblemReport(version: "0.4.0", build: "12", system: "iOS 26.0", device: "iPhone17,1")
        XCTAssertEqual(report.versionText, "0.4.0 (12)")
        XCTAssertEqual(report.subject(in: .english), "Railway Game 0.4.0 (12): a problem")
        XCTAssertEqual(report.subject(in: .traditionalChinese), "鐵道遊戲 0.4.0 (12)：問題回報")
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
        // Decision 776, later: the map packs' downloads, when there are any.
        XCTAssertFalse(chinese.contains("地圖包"))
        let packs = ProblemReport(version: "1", build: "2", system: "iOS", device: "iPhone", mapPacks: "mappack-hongkong used")
        XCTAssertTrue(packs.text(in: .english).hasSuffix("\nMap packs: mappack-hongkong used"))
        XCTAssertTrue(packs.text(in: .traditionalChinese).hasSuffix("\n地圖包：mappack-hongkong used"))
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

    /// REVIEW-L37 (0.7.0, the first App Store build): a TestFlight tester is
    /// told to send it through TestFlight; a player of the App Store's build,
    /// who has no TestFlight, is pointed at the game's App Store page. The
    /// help answer says neither and points at the report itself.
    func testWhereToSendNamesTestFlightOnlyToTesters() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertTrue(ProblemReport.whereToSend(in: language, testing: true).contains("TestFlight"), "\(language)")
            let store = ProblemReport.whereToSend(in: language, testing: false)
            XCTAssertFalse(store.contains("TestFlight"), "\(language)")
            XCTAssertTrue(store.contains("App Store"), "\(language)")
            let help = try XCTUnwrap(HelpGuide.entries.first { $0.id == "reportProblem" }).answer(in: language)
            XCTAssertFalse(help.contains("TestFlight"), "\(language)")
        }
    }
}
