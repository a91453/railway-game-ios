@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 387, continued: the Liu Mingchuan and Jiji stories, their
/// milestones and shares of the riders' goal, the beats that wait for
/// another, and the station master's word one card stands for.
final class ChallengeStoryLiuJijiTests: XCTestCase {
    private func ids(_ story: ChallengeStory, _ world: GameWorld, today: Int64) -> [String] {
        story.beats(on: today, in: world).map(\.id)
    }

    /// Days whose riders are `trips`, from day `first`.
    private func days(from first: Int64, trips: [Int64]) -> [DayAccount] {
        trips.enumerated().map { index, trips in
            var day = DayAccount(day: first + Int64(index))
            day.fareTrips = trips
            return day
        }
    }

    func testTheScriptsHaveTheirBeatsAndEndings() throws {
        let liu = try XCTUnwrap(ChallengeStory.named("history.liuMingchuan"))
        let jiji = try XCTUnwrap(ChallengeStory.named("branch.jiji"))
        for (story, count, speakers) in [
            (liu, 14, Set<StoryCharacter>([.stationMaster, .ahShui, .walsh, .ye])),
            (jiji, 16, Set<StoryCharacter>([.stationMaster, .ahKun, .lin, .xiulan])),
        ] {
            XCTAssertEqual(story.beats.count, count)
            XCTAssertEqual(Set(story.beats.map(\.id)).count, count)
            XCTAssertEqual(story.beats.filter(\.moment.isEnding).count, 4)
            XCTAssertEqual(Set(story.beats.map(\.speaker)), speakers)
            for beat in story.beats {
                XCTAssertFalse(beat.text(in: .english).isEmpty)
                XCTAssertFalse(beat.text(in: .traditionalChinese).isEmpty)
            }
        }
        XCTAssertEqual(liu.beats.compactMap { beat in beat.carries.map { "\(beat.id) \($0)" } }, ["liu.3 shortSteamTrains", "liu.8 debt"])
        XCTAssertEqual(
            jiji.beats.compactMap { beat in beat.carries.map { "\(beat.id) \($0)" } },
            ["jiji.1 welcome", "jiji.5 debt", "jiji.9 crowding"]
        )
        XCTAssertEqual(
            LiuMingchuanChallenge.milestoneCheer(3, in: .traditionalChinese),
            "通車到新竹了！清代的鐵路就鋪到這裡，就像 1893 年。"
        )
        XCTAssertTrue(BranchLineChallenge.jiji.challenge.story(in: .traditionalChinese).contains("臺灣電力株式會社"))
    }

    /// The milestones' beats, the day after each is reached; Shiqiuling's
    /// waits for the beat that says to begin there.
    func testLiuMingchuansMilestones() throws {
        var world = LiuMingchuanChallenge.make()
        let story = LiuMingchuanChallenge.story
        XCTAssertEqual(ids(story, world, today: 4), ["liu.1"])
        world.scenario?.achieved[0] = 1
        XCTAssertEqual(ids(story, world, today: 2), [], "not before the beat it waits for")
        XCTAssertEqual(ids(story, world, today: 4), ["liu.1", "liu.2"])
        world.scenario?.achieved[0] = 10
        XCTAssertEqual(ids(story, world, today: 4), ["liu.1"])
        XCTAssertEqual(ids(story, world, today: 11), ["liu.2"])
        world.scenario?.achieved[1] = 20
        world.scenario?.achieved[2] = 20
        XCTAssertEqual(ids(story, world, today: 21), ["liu.4", "liu.6"])
        world.scenario?.achieved[3] = 30
        XCTAssertEqual(ids(story, world, today: 31), ["liu.9"])
        XCTAssertEqual(ids(story, world, today: 32), [])
    }

    /// The first day each share of the riders' goal (15,000) is carried;
    /// a later day that carries it again says nothing.
    func testLiuMingchuansRiders() throws {
        var world = LiuMingchuanChallenge.make()
        let story = LiuMingchuanChallenge.story
        world.accounts.days = days(from: 5, trips: [3_000, 4_000, 3_000, 7_600, 11_300, 4_000])
        XCTAssertEqual(ids(story, world, today: 6), [])
        XCTAssertEqual(ids(story, world, today: 7), ["liu.3"])
        XCTAssertEqual(ids(story, world, today: 8), [])
        XCTAssertEqual(ids(story, world, today: 9), ["liu.5"])
        XCTAssertEqual(ids(story, world, today: 10), ["liu.7"])
        XCTAssertEqual(ids(story, world, today: 11), [])
        // Once the challenge's first days are no longer in the accounts,
        // which day was first cannot be told: nothing is said.
        XCTAssertEqual(ids(story, world, today: Int64(CompanyAccounts.keptDays) + 7), [])
    }

    /// Ah-Kun's letters come in order: the second waits for the first, the
    /// third for the second, and they are told one after the other.
    func testAhKunsLettersComeInOrder() throws {
        var world = BranchLineChallenge.jiji.make()
        let story = BranchLineChallenge.jijiStory
        world.scenario?.achieved[1] = 5
        world.scenario?.achieved[3] = 3
        XCTAssertEqual(ids(story, world, today: 6), [], "Shuili is reached before the first letter")
        XCTAssertEqual(ids(story, world, today: 9), ["jiji.2", "jiji.6", "jiji.10"])
        world.scenario?.achieved[1] = 40
        world.scenario?.achieved[3] = 60
        XCTAssertEqual(ids(story, world, today: 9), ["jiji.2"])
        XCTAssertEqual(ids(story, world, today: 41), ["jiji.6"])
        XCTAssertEqual(ids(story, world, today: 61), ["jiji.10"])
    }

    /// Jiji's station is spoken of only once the line reaches it.
    func testJijisStationWaitsForTheLine() throws {
        var world = BranchLineChallenge.jiji.make()
        let story = BranchLineChallenge.jijiStory
        world.accounts.days = days(from: 1, trips: [1_000, 5_000, 6_000])
        XCTAssertEqual(ids(story, world, today: 3), [], "a quarter of the riders before the line reaches Jiji")
        world.scenario?.achieved[0] = 7
        XCTAssertEqual(ids(story, world, today: 8), ["jiji.3", "jiji.4"])
        XCTAssertEqual(ids(story, world, today: 2), ["jiji.1"])
    }

    /// Decision 387: the story's card stands for the station master's word
    /// on the same thing: shown under the line where it adds something,
    /// only kept from being said apart where the line says it already.
    func testTheCardStandsForTheStationMastersWord() throws {
        var world = BranchLineChallenge.jiji.make()
        let welcome = try XCTUnwrap(BranchLineChallenge.jijiStory.beats.first { $0.id == "jiji.1" })
        XCTAssertEqual(welcome.advice(in: world), .scenarioWelcome(scenario: "branch.jiji"))
        XCTAssertNil(welcome.adviceLine(in: world), "its first words are long, and the line says them")
        let debt = try XCTUnwrap(BranchLineChallenge.jijiStory.beats.first { $0.id == "jiji.5" })
        XCTAssertNil(debt.advice(in: world))
        world.setEconomyMode(.management)
        world.economy = GameEconomy(balance: Money(-100))
        XCTAssertEqual(debt.advice(in: world), .inDebt)
        XCTAssertNil(debt.adviceLine(in: world))
        let pingxi = try XCTUnwrap(PingxiChallenge.story.beats.first { $0.id == "pingxi.9" })
        XCTAssertEqual(pingxi.carries, .debt)
    }
}
