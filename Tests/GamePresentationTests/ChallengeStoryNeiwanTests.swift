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
}
