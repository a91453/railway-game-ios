import GameCore
@testable import GamePresentation
import XCTest

/// Decision 687: a platform lengthened from the station's panel, to a
/// whole number of cars, where it stands.
final class PlatformExtensionSessionTests: XCTestCase {
    /// A straight track 480 m long (30720 units) west to east; cars of
    /// 16 m (1024 units). Station Middle's platform of `cars` cars starts
    /// `start` along it.
    private func world(start: Int64 = 12_288, cars: Int64 = 6, speed: GameSpeed = .paused) throws -> (GameWorld, TrackPlatform) {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: speed)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let station = try world.buildStation(named: "Middle", at: PlanPoint(x: 16_384, y: 8_704)).id
        try world.addTrackPlatform(station, on: edge, from: start, to: start + cars * 1_024)
        return (world, try XCTUnwrap(world.trackPlatforms(of: station).first))
    }

    /// Each longer length up to the longest train, with what is added.
    @MainActor
    func testTheMenuListsEachLongerLength() throws {
        let (world, platform) = try world()
        let session = GameSession(world: world)
        XCTAssertEqual(session.platformLengthText(of: platform), "6 cars · 96 m")
        let choices = session.platformExtensionMenuChoices(for: platform)
        XCTAssertEqual(choices.map(\.id.cars), Array(7...16))
        XCTAssertEqual(choices.first?.title, "7 cars · 112 m")
        XCTAssertEqual(choices.first?.detail, "Adds 16 m · free")
        XCTAssertEqual(choices.last?.title, "16 cars · 256 m")
        XCTAssertEqual(choices.last?.detail, "Adds 160 m · free")
        let chinese = GameSession(world: world, language: .traditionalChinese)
        XCTAssertEqual(chinese.platformLengthText(of: platform), "6 節車廂 · 96 公尺")
        XCTAssertEqual(chinese.platformExtensionMenuChoices(for: platform).first?.title, "7 節車廂 · 112 公尺")
        XCTAssertEqual(chinese.platformExtensionMenuChoices(for: platform).first?.detail, "加長 16 公尺 · 免費")
        chinese.extendPlatform(try XCTUnwrap(chinese.platformExtensionMenuChoices(for: platform).first?.id))
        XCTAssertEqual(chinese.message?.text, "Middle 的月台已加長到 7 節車廂（112 公尺）。")
    }

    /// Half to each end; what one end has no room for goes to the other.
    func testItGrowsEvenlyAndTowardsTheRoomThereIs() throws {
        // In the middle: 6 → 10 cars adds 4096, 2048 to each end.
        let (world, platform) = try world()
        let even = try XCTUnwrap(world.platformExtension(of: platform, toCars: 10))
        XCTAssertEqual([even.start, even.end], [10_240, 20_480])
        // An odd unit goes after: 6144 → 7169 would add 1025, 512 and 513.
        // 1024 from the track's start: 6 → 10 cars has only 1024 before.
        let (near, nearPlatform) = try self.world(start: 1_024)
        let shifted = try XCTUnwrap(near.platformExtension(of: nearPlatform, toCars: 10))
        XCTAssertEqual([shifted.start, shifted.end], [0, 10_240])
        // Up against the track's end: all of it before.
        let (far, farPlatform) = try self.world(start: 30_720 - 6_144)
        let back = try XCTUnwrap(far.platformExtension(of: farPlatform, toCars: 8))
        XCTAssertEqual([back.start, back.end], [22_528, 30_720])
        // No longer, or no room.
        XCTAssertNil(world.platformExtension(of: platform, toCars: 6))
        XCTAssertNil(world.platformExtension(of: platform, toCars: 31))
    }

    /// A track only 10 cars long offers up to 10; a platform that fills
    /// its track offers nothing, and the menu says why.
    @MainActor
    func testTheMenuStopsAtTheRoomThereIs() throws {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 11_264, y: 8_192))
        let edge = try world.buildTrackEdge(from: west, to: east)
        let station = try world.buildStation(named: "Short", at: PlanPoint(x: 6_144, y: 8_704)).id
        try world.addTrackPlatform(station, on: edge, from: 0, to: 8_192)
        let session = GameSession(world: world)
        let platform = try XCTUnwrap(world.trackPlatforms(of: station).first)
        XCTAssertEqual(session.platformExtensionMenuChoices(for: platform).map(\.id.cars), [9, 10])
        session.extendPlatform(try XCTUnwrap(session.platformExtensionMenuChoices(for: platform).last?.id))
        let full = try XCTUnwrap(session.world.trackPlatforms(of: station).first)
        XCTAssertEqual([full.start, full.end], [0, 10_240])
        XCTAssertEqual(session.platformExtensionMenuChoices(for: full), [])
        XCTAssertEqual(session.platformExtensionNoRoomText, "No room to lengthen: the track ends, slopes or meets another platform here.")
    }

    /// Through the session: one platform, longer, for nothing; said, logged
    /// and undone as one command, and the log replays to the same world.
    @MainActor
    func testLengtheningIsOneFreeCommandThatUndoesAndReplays() throws {
        let (world, platform) = try world()
        let session = GameSession(world: world)
        let choice = try XCTUnwrap(session.platformExtensionMenuChoices(for: platform).first { $0.id.cars == 12 })
        session.extendPlatform(choice.id)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.message?.text, "Middle’s platform now takes 12 cars (192 m).")
        XCTAssertEqual(session.world.trackPlatforms(of: platform.station), [TrackPlatform(station: platform.station, edge: platform.edge, start: 9_216, end: 21_504)])
        XCTAssertEqual(session.world.economy.balance, world.economy.balance)
        XCTAssertEqual(session.commandLog.entries.map(\.action), [.command(.extendPlatform(platform, start: 9_216, end: 21_504))])

        // The same choice again names a platform no longer there: refused,
        // nothing changed.
        let after = session.world
        session.extendPlatform(choice.id)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world, after)
        XCTAssertEqual(session.commandLog.entries.last?.refused, true)

        let report = try JSONDecoder().decode(
            CommandLogReport.self, from: session.commandLogReport(version: "0.5.0", build: "1", data: [:]).encoded()
        )
        let replay = try CommandLogReplay(report)
        XCTAssertNil(replay.stopped?.reason)
        XCTAssertEqual(replay.session.world, session.world)

        session.undo()
        XCTAssertEqual(session.world.trackPlatforms(of: platform.station), [platform])
        session.redo()
        XCTAssertEqual(session.world, after)
    }

    /// The command through its file and back.
    func testTheCommandKeepsItsFormThroughItsFile() throws {
        let command = PlayerCommand.extendPlatform(TrackPlatform(station: StationID(rawValue: 3), edge: .edge(7), start: 100, end: 900), start: 40, end: 1_200)
        XCTAssertEqual(command.name, "extendPlatform")
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command)), command)
        XCTAssertThrowsError(try JSONDecoder().decode(
            PlayerCommand.self, from: Data(#"{"kind":"extendPlatform","station":3,"edge":7,"startDistance":100,"endDistance":900}"#.utf8)
        ))
    }
}
