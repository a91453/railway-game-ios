@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 671: the Neiwan Line's story.
final class ChallengeStoryNeiwanTests: XCTestCase {
    private func ids(_ world: GameWorld, today: Int64) -> [String] {
        BranchLineChallenge.neiwanStory.beats(on: today, in: world).map(\.id)
    }

    func testTheScript() throws {
        let story = try XCTUnwrap(ChallengeStory.named("branch.neiwan"))
        XCTAssertEqual(story.beats.count, 16)
        XCTAssertEqual(Set(story.beats.map(\.id)).count, 16)
        XCTAssertEqual(story.beats.filter(\.moment.isEnding).count, 4)
        XCTAssertEqual(Set(story.beats.map(\.speaker)), [.stationMaster, .pengPo, .luo, .xiaoYu])
        for beat in story.beats {
            XCTAssertFalse(beat.text(in: .english).isEmpty)
            XCTAssertFalse(beat.text(in: .traditionalChinese).isEmpty)
        }
        XCTAssertEqual(
            story.beats.compactMap { beat in beat.carries.map { "\(beat.id) \($0)" } },
            ["neiwan.1 welcome", "neiwan.6 debt", "neiwan.9 crowding"]
        )
        XCTAssertEqual(StoryCharacter.pengPo.name(in: .traditionalChinese), "彭阿婆")
        XCTAssertEqual(StoryCharacter.luo.name(in: .english), "Uncle Luo")
        XCTAssertEqual(StoryCharacter.luo.name(in: .traditionalChinese), "阿羅伯")
        XCTAssertEqual(StoryCharacter.xiaoYu.portrait, "StoryXiaoYu")
    }

    /// Every beat's moment can be told by the world: its day, a milestone,
    /// a share of the riders, and the endings.
    func testTheBeatsAreTold() {
        var world = BranchLineChallenge.neiwan.make()
        XCTAssertEqual(ids(world, today: 2), ["neiwan.1"])
        XCTAssertEqual(ids(world, today: 9), ["neiwan.2"])
        world.scenario?.achieved[0] = 1
        XCTAssertEqual(ids(world, today: 2), ["neiwan.1", "neiwan.3"])
        world.scenario?.achieved[1] = 1
        XCTAssertEqual(ids(world, today: 2), ["neiwan.1", "neiwan.3"], "Luo's memory waits for the one before")
        XCTAssertTrue(ids(world, today: 9).contains("neiwan.4"))
        world.scenario?.achieved[2] = 1
        XCTAssertTrue(ids(world, today: 2).contains("neiwan.8"))
    }

    /// Review L16-2: decision 668 measured that one two-car train stays
    /// near 33,096 riders a day for three years and fails at the deadline,
    /// and that four cars or two trains win gold. So the advice to
    /// lengthen or add a train must come while a short train can still
    /// get there, and nothing may tell the player to run short or
    /// sparingly.
    func testTheAdviceFitsTheGoal() throws {
        let story = BranchLineChallenge.neiwanStory
        // Decision 668, second round, "Two cars": riders a day on day 7
        // and at the three-year deadline.
        let twoCarsInAWeek: Int64 = 30_502, twoCarCeiling: Int64 = 33_096
        XCTAssertGreaterThan(NeiwanTargets.riders, twoCarCeiling, "a short train alone must not meet the goal")
        let crowding = try XCTUnwrap(story.beats.first { $0.carries == .crowding })
        guard case .riders(let percent) = crowding.moment else { return XCTFail("\(crowding.moment)") }
        XCTAssertLessThanOrEqual(NeiwanTargets.riders * percent / 100, twoCarsInAWeek, "a short train never gets to hear it")
        // Every line the station master says before an ending, and the
        // failure's, points the way the goal needs.
        for id in ["neiwan.1", "neiwan.9", "neiwan.failed"] {
            let beat = try XCTUnwrap(story.beats.first { $0.id == id })
            XCTAssertTrue(beat.text(in: .english).contains("engthen"), beat.text(in: .english))
            XCTAssertTrue(beat.text(in: .traditionalChinese).contains("加長"), beat.text(in: .traditionalChinese))
        }
        for beat in story.beats where beat.speaker == .stationMaster {
            let english = beat.text(in: .english), chinese = beat.text(in: .traditionalChinese)
            for wrong in ["Start with a short train", "Hold off on new trains", "go gently"] { XCTAssertFalse(english.contains(wrong), english) }
            for wrong in ["先用短車", "先別加車", "省一點"] { XCTAssertFalse(chinese.contains(wrong), chinese) }
        }
    }
}
