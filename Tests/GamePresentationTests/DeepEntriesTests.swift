import GameCore
@testable import GamePresentation
import XCTest

/// Decision 383: features that were folded too deep to find, brought up a
/// level: the train card's hold, resume and reverse, the track card's
/// "Open …", the express on the line's page, the network's switches in
/// their own block, the build tool's options named by what they hold, and
/// help that says the new ways in.
@MainActor
final class DeepEntriesTests: XCTestCase {
    private let track = TestLine(tiles: 7, row: 1)

    private func makeTrainSession() throws -> (GameSession, TrainID) {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        try track.build(in: &world)
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: track.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1_024)
        return (GameSession(world: world, language: .english), train.id)
    }

    func testTheTrainCardHoldsResumesAndReversesATrainOnTheTrack() throws {
        let (session, train) = try makeTrainSession()
        XCTAssertEqual(session.trainCardActions(of: train), [.hold, .reverse])

        session.runTrainCardAction(.hold, on: train)
        XCTAssertEqual(session.world.train(id: train)?.movement.rate, 0)
        XCTAssertEqual(session.selectedTrainID, train, "the train tool shows the same train")
        XCTAssertEqual(session.trainCardActions(of: train), [.resume, .reverse])

        session.runTrainCardAction(.resume, on: train)
        XCTAssertEqual(session.trainCardActions(of: train).first, .hold)

        let before = try XCTUnwrap(session.world.train(id: train)?.position)
        session.runTrainCardAction(.reverse, on: train)
        XCTAssertNotEqual(session.world.train(id: train)?.position, before, "turned round")
    }

    func testATrainOffTheTrackOrUnknownHasNoCardActions() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        let train = try world.purchaseTrain(named: "T1")
        let session = GameSession(world: world, language: .english)
        XCTAssertEqual(session.trainCardActions(of: train.id), [])
        XCTAssertEqual(session.trainCardActions(of: TrainID(rawValue: 99)), [])
        let selected = session.selectedTrainID
        session.runTrainCardAction(.reverse, on: TrainID(rawValue: 99))
        XCTAssertEqual(session.selectedTrainID, selected, "an unknown train selects nothing")
    }

    func testTheCardsWordsAreInBothLanguages() {
        for action in TrainCardAction.allCases {
            XCTAssertNotEqual(action.title(in: .english), action.title(in: .traditionalChinese))
        }
        XCTAssertEqual(TrainCardAction.hold.title(in: .traditionalChinese), "暫停列車")
        XCTAssertEqual(TrainCardAction.resume.title(in: .traditionalChinese), "恢復列車")
        XCTAssertNotEqual(TrainCardAction.resume.title(in: .english), "Resume", "not the clock's button")
        XCTAssertEqual(TrainCardAction.reverse.title(in: .traditionalChinese), "折返")
        XCTAssertEqual(TrackHoldHint.openTitle("縱貫線", in: .traditionalChinese), "打開縱貫線")
        XCTAssertEqual(TrackHoldHint.openTitle("Main", in: .english), "Open Main")
        XCTAssertEqual(StoppingPatternEntry.title(in: .traditionalChinese), "加快車（停車模式）")
        XCTAssertEqual(NetworkSwitches.title(in: .traditionalChinese), "整個路網")
        XCTAssertEqual(NetworkOptionsEntry.title(in: .traditionalChinese), "高架、坡度、曲線")
        XCTAssertEqual(NetworkOptionsEntry.title(in: .english), "Elevated, grade, curves")
    }

    /// Help says the ways in as they are now: no Advanced for the express
    /// or the network's switches, and no More for the report.
    func testHelpSaysTheNewWaysIn() throws {
        func answer(_ id: String, _ language: DisplayLanguage) throws -> String {
            try XCTUnwrap(HelpGuide.entries.first { $0.id == id }).answer(in: language)
        }
        XCTAssertTrue(try answer("express", .traditionalChinese).contains(StoppingPatternEntry.title(in: .traditionalChinese)))
        XCTAssertTrue(try answer("express", .english).contains(StoppingPatternEntry.title(in: .english)))
        for id in ["trafficControl", "oneTrain"] {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                let text = try answer(id, language)
                XCTAssertTrue(text.contains(NetworkSwitches.title(in: language)), "\(id) in \(language)")
                XCTAssertFalse(text.contains(language.text("Advanced", "進階")), "\(id) in \(language)")
            }
        }
        XCTAssertFalse(try answer("reportProblem", .traditionalChinese).contains("更多"))
        XCTAssertFalse(try answer("reportProblem", .english).contains("More"))
    }
}
