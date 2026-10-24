@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 387, continued: the sandbox challenges' stories, and the beats
/// told the day a goal's bar is first seen past a share.
final class ChallengeStorySandboxTests: XCTestCase {
    private func world(_ challenge: Challenge) -> GameWorld {
        GameWorld.newGame(challenge: challenge, eventSeed: 1)
    }

    /// The beats a goal's bar has passed by `today`, noting them in `seen`.
    private func progress(_ story: ChallengeStory, _ world: GameWorld, today: Int64, seen: inout Set<String>) -> [String] {
        story.progressBeats(in: world, today: today, seen: &seen).map(\.id)
    }

    func testTheScriptsHaveTheirBeatsAndEndings() throws {
        let speakers: Set<StoryCharacter> = [.stationMaster, .chou, .fang, .mayorChen]
        for (challenge, count) in [(Challenge.threeTowns, 12), (.cityBuilder, 12), (.tycoon, 12)] {
            let story = try XCTUnwrap(ChallengeStory.named(challenge.id))
            XCTAssertEqual(story.beats.count, count)
            XCTAssertEqual(Set(story.beats.map(\.id)).count, count)
            XCTAssertEqual(story.beats.filter(\.moment.isEnding).count, 4)
            XCTAssertEqual(Set(story.beats.map(\.speaker)), speakers)
            for beat in story.beats {
                // The player names the company.
                XCTAssertFalse(beat.text(in: .traditionalChinese).contains("晨星"), beat.id)
                XCTAssertFalse(beat.text(in: .english).localizedCaseInsensitiveContains("morning star"), beat.id)
                XCTAssertFalse(beat.text(in: .english).isEmpty)
            }
        }
        // Its deadline is the year's end, the day its ending is told.
        XCTAssertFalse(Challenge.threeTownsStory.beats.contains { $0.moment == .yearClosed })
        XCTAssertEqual(
            Challenge.cityBuilderStory.beats.compactMap { beat in beat.carries.map { "\(beat.id) \($0)" } },
            ["cityBuilder.1 welcome", "cityBuilder.5 crowding", "cityBuilder.7 debt"]
        )
        // It names the building tool and what it builds.
        let shops = try XCTUnwrap(Challenge.tycoonStory.beats.first { $0.id == "tycoon.6" })
        XCTAssertTrue(shops.text(in: .traditionalChinese).contains("建物工具"))
        XCTAssertTrue(shops.text(in: .english).contains("Buildings tool"))
    }

    /// A share of a goal with no history is told the first day the teller
    /// sees the bar past it, once; the day it first looks is noted, not told.
    func testTheTellerTellsAGoalsShareTheDayItIsSeen() throws {
        var world = world(.cityBuilder)
        var teller = StoryTeller()
        // Met, the population's bar is full.
        world.scenario?.achieved[0] = 0
        XCTAssertEqual(teller.look(at: world), [], "the first look tells nothing")
        try world.advance(ticks: 1_441)
        XCTAssertEqual(teller.look(at: world).map(\.id), ["cityBuilder.1"], "the shares seen at the first look stay untold")

        var later = StoryTeller()
        world.scenario?.achieved[0] = nil
        _ = later.look(at: world)
        world.scenario?.achieved[0] = 1
        try world.advance(ticks: 1_440)
        XCTAssertEqual(later.look(at: world).map(\.id), ["cityBuilder.3", "cityBuilder.5"])
        try world.advance(ticks: 1_440)
        XCTAssertEqual(later.look(at: world), [], "told once")
    }

    /// A share waits for the beat it follows: a dated beat's day, or a
    /// share's having been seen.
    func testASharesBeatWaitsForTheOneBefore() throws {
        var world = world(.cityBuilder)
        let story = Challenge.cityBuilderStory
        var seen: Set<String> = []
        world.scenario?.achieved[1] = 1
        // cityBuilder.4 waits for the mayor's word on day 15 (game day 14).
        XCTAssertEqual(progress(story, world, today: 13, seen: &seen), [])
        XCTAssertEqual(progress(story, world, today: 14, seen: &seen), ["cityBuilder.4", "cityBuilder.6"])
        XCTAssertEqual(progress(story, world, today: 15, seen: &seen), [])

        // tycoon.6 waits for tycoon.5 to have been seen.
        var tycoon = self.world(.tycoon)
        tycoon.scenario?.achieved[1] = 1
        var told: Set<String> = []
        XCTAssertEqual(progress(Challenge.tycoonStory, tycoon, today: 2, seen: &told), ["tycoon.5", "tycoon.6"])
        told = []
        let six = try XCTUnwrap(Challenge.tycoonStory.beats.first { $0.id == "tycoon.6" })
        let alone = ChallengeStory(challengeID: Challenge.tycoon.id, beats: [six])
        XCTAssertEqual(progress(alone, tycoon, today: 2, seen: &told), [], "not without the beat it follows")
    }

    /// Nothing is told about a goal's share once the challenge has ended.
    func testNoShareAfterTheEnd() {
        var world = world(.tycoon)
        world.scenario?.achieved[0] = 1
        world.scenario?.outcome = .failed(day: 2, reason: .deadline)
        var seen: Set<String> = []
        XCTAssertEqual(progress(Challenge.tycoonStory, world, today: 3, seen: &seen), [])
        XCTAssertEqual(seen, [])
    }

    /// Three Towns' riders' shares come from the days' riders, as the
    /// other challenges' do; its fourth beat waits for the towns' link.
    func testThreeTownsRidersWaitForTheLink() throws {
        var world = world(.threeTowns)
        let story = Challenge.threeTownsStory
        var day = DayAccount(day: 5)
        day.fareTrips = 180_000
        world.accounts.days = [day]
        XCTAssertEqual(story.beats(on: 6, in: world).map(\.id), ["threeTowns.3"])
        world.scenario?.achieved[0] = 9
        XCTAssertEqual(story.beats(on: 10, in: world).map(\.id), ["threeTowns.4", "threeTowns.5"])
    }
}
