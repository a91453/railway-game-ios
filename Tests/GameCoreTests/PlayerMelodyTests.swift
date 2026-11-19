import Foundation
@testable import GameCore
import XCTest

/// Decision 883: the melodies the player writes, kept in the world,
/// checked whole, played by the stations set to them; free, saved only
/// when there are any, read by no rule.
final class PlayerMelodyTests: XCTestCase {
    private let track = TestLine(tiles: 7)

    /// `StationSoundsTests`' two stations and line, its train running all
    /// day, at the normal speed.
    private func world() throws -> (GameWorld, StationID, StationID) {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        try track.build(in: &world)
        let a = try track.buildStation(named: "A", beside: 1, at: 1, in: &world)
        let b = try track.buildStation(named: "B", beside: 5, at: 1, in: &world)
        let line = try world.createLine(named: "L", stops: [a, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        let train = try world.purchaseTrain(named: "T").id
        try world.placeTrain(train, at: track.at(1, facingEast: true))
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: line)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        world.setSpeed(.normal)
        return (world, a, b)
    }

    /// Official melody 1's tune with two more notes, a chord at the end.
    private let tune: [MelodyNote] = [(79, 0, 2), (84, 2, 2), (88, 4, 2), (93, 6, 3), (91, 9, 1), (89, 10, 2), (88, 12, 2), (86, 14, 2), (89, 16, 2), (84, 18, 6), (88, 18, 6)]
        .map { MelodyNote(pitch: $0.0, start: $0.1 * 480, length: $0.2 * 480) }

    func testAMelodyIsCheckedWhole() {
        XCTAssertTrue(PlayerMelody.isValid(tune))
        XCTAssertFalse(PlayerMelody.isValid([]), "a note at least")
        let full = (0..<128).map { MelodyNote(pitch: 72 + $0 % 25, start: ($0 / 25) * 240, length: 240) }
        XCTAssertTrue(PlayerMelody.isValid(full))
        let over = full + [MelodyNote(pitch: 72, start: 11_280, length: 240)]
        XCTAssertFalse(PlayerMelody.isValid(over), "128 notes at most")
        func one(_ pitch: Int, _ start: Int, _ length: Int) -> Bool {
            PlayerMelody.isValid([MelodyNote(pitch: pitch, start: start, length: length)])
        }
        XCTAssertTrue(one(72, 0, 240))
        XCTAssertTrue(one(96, 11_280, 240))
        XCTAssertFalse(one(71, 0, 240), "below C5")
        XCTAssertFalse(one(97, 0, 240), "above C7")
        XCTAssertFalse(one(84, -240, 480))
        XCTAssertFalse(one(84, 120, 240), "on a sixteenth")
        XCTAssertFalse(one(84, 0, 120), "a sixteenth at least")
        XCTAssertFalse(one(84, 0, 0))
        XCTAssertFalse(one(84, 11_280, 480), "ends by the fourth bar's end")
        let twice = [MelodyNote(pitch: 84, start: 0, length: 480), MelodyNote(pitch: 84, start: 0, length: 960)]
        XCTAssertFalse(PlayerMelody.isValid(twice), "no two alike in start and pitch")
        XCTAssertFalse(PlayerMelody.isValid(Array(tune.reversed())), "in order")
    }

    func testMelodiesAreAddedEditedPlayedAndRemoved() throws {
        var (world, a, b) = try world()
        let balance = world.economy.balance
        let first = try world.addPlayerMelody(named: "Mine", notes: tune)
        XCTAssertEqual(first.id, PlayerMelodyID(rawValue: 1))
        XCTAssertEqual(world.playerMelodies, [first])
        try world.setStationDepartureMelody(a, to: .c)
        try world.setStationPlayerMelody(a, to: first.id)
        XCTAssertEqual(world.station(id: a)?.playerMelody, first.id)
        XCTAssertNil(world.station(id: a)?.departureMelody, "in place of the official one")
        try world.setStationPlayerMelody(b, to: first.id)
        try world.setStationDepartureMelody(b, to: .d)
        XCTAssertNil(world.station(id: b)?.playerMelody, "the official one in its place")
        XCTAssertEqual(world.station(id: b)?.departureMelody, .d)
        try world.setStationDepartureMelody(b, to: nil)
        XCTAssertNil(world.station(id: b)?.departureMelody)

        let short = Array(tune.prefix(3))
        try world.editPlayerMelody(first.id, name: "Mine too", notes: short)
        XCTAssertEqual(world.playerMelody(id: first.id)?.notes, short)
        XCTAssertEqual(world.playerMelody(id: first.id)?.name, "Mine too")
        XCTAssertEqual(world.economy.balance, balance, "free")

        let second = try world.addPlayerMelody(named: "Other", notes: short)
        try world.removePlayerMelody(first.id)
        XCTAssertNil(world.station(id: a)?.playerMelody, "a station set to it plays each line's own again")
        XCTAssertEqual(world.playerMelodies.map(\.id), [second.id])
        let third = try world.addPlayerMelody(named: "Third", notes: short)
        XCTAssertEqual(third.id, PlayerMelodyID(rawValue: 3), "a number is never handed out twice")
    }

    func testRefusalsChangeNothing() throws {
        var (world, a, _) = try world()
        let before = world
        XCTAssertThrowsError(try world.addPlayerMelody(named: " ", notes: tune)) { XCTAssertEqual($0 as? GameError, .invalidName) }
        XCTAssertThrowsError(try world.addPlayerMelody(named: "X", notes: [])) { XCTAssertEqual($0 as? GameError, .invalidMelody) }
        let nowhere = PlayerMelodyID(rawValue: 4)
        XCTAssertThrowsError(try world.editPlayerMelody(nowhere, name: "X", notes: tune)) { XCTAssertEqual($0 as? GameError, .unknownPlayerMelody(nowhere)) }
        XCTAssertThrowsError(try world.removePlayerMelody(nowhere)) { XCTAssertEqual($0 as? GameError, .unknownPlayerMelody(nowhere)) }
        XCTAssertThrowsError(try world.setStationPlayerMelody(a, to: nowhere)) { XCTAssertEqual($0 as? GameError, .unknownPlayerMelody(nowhere)) }
        XCTAssertThrowsError(try world.setStationPlayerMelody(StationID(rawValue: 99), to: nil)) { XCTAssertEqual($0 as? GameError, .unknownStation(StationID(rawValue: 99))) }
        XCTAssertEqual(world, before)
        for index in 0..<PlayerMelody.maximumMelodies {
            try world.addPlayerMelody(named: "M\(index)", notes: tune)
        }
        let full = world
        XCTAssertThrowsError(try world.addPlayerMelody(named: "One more", notes: tune)) { XCTAssertEqual($0 as? GameError, .tooManyMelodies) }
        XCTAssertEqual(world, full)
        let melody = try XCTUnwrap(world.playerMelodies.first)
        XCTAssertThrowsError(try world.editPlayerMelody(melody.id, name: "M", notes: [])) { XCTAssertEqual($0 as? GameError, .invalidMelody) }
        XCTAssertEqual(world, full)
    }

    func testMelodiesAreSavedOnlyWhenThereAreAnyAndCheckedOnLoading() throws {
        var (world, a, _) = try world()
        let plain = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertFalse(plain.contains("playerMelod"))
        XCTAssertFalse(plain.contains("nextPlayerMelodyID"))
        let melody = try world.addPlayerMelody(named: "Mine", notes: tune)
        try world.setStationPlayerMelody(a, to: melody.id)
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        let text = String(decoding: try sorted.encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(#""playerMelody":1"#))
        XCTAssertTrue(text.contains(#""nextPlayerMelodyID":2"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8)), world)

        func refused(_ from: String, _ to: String, _ why: String) {
            let bad = text.replacingOccurrences(of: from, with: to)
            XCTAssertNotEqual(bad, text, why)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(bad.utf8)), why)
        }
        refused(#""playerMelody":1"#, #""playerMelody":2"#, "a station set to a melody that does not exist")
        refused(#""playerMelody":1"#, #""departureMelody":"a","playerMelody":1"#, "set to both")
        refused(#""nextPlayerMelodyID":2"#, #""nextPlayerMelodyID":1"#, "a number not handed out")
        refused(#""name":"Mine""#, #""name":" ""#, "a melody with no name")
        refused(#"{"length":2880,"pitch":84,"start":8640}"#, #"{"length":2880,"pitch":100,"start":8640}"#, "a note out of range")
    }

    /// The version 111 save (decision 883): a player melody, Station A set
    /// to it and Station B to official melody 3, run 30 minutes; it loads
    /// as the same world and runs on the same. Written with
    /// `PLAYER_MELODY_SAVE_NEW=1` by the build that first made it.
    func testTheVersion111SaveKeepsAPlayerMelody() throws {
        var (world, a, b) = try world()
        let melody = try world.addPlayerMelody(named: "My melody 1", notes: tune)
        try world.setStationPlayerMelody(a, to: melody.id)
        try world.setStationDepartureMelody(b, to: .c)
        try world.advance(ticks: 1_800)
        let url = SavedGameTests.fixtures.appendingPathComponent("v111-player-melody.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["PLAYER_MELODY_SAVE_NEW"] != nil, SavedGame.currentVersion == 111 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 111)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.station(id: a)?.playerMelody, melody.id)
        XCTAssertEqual(loaded.playerMelody(id: melody.id)?.notes, tune)
        XCTAssertEqual(loaded.station(id: b)?.departureMelody, .c)
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 600)
        try running.advance(ticks: 600)
        XCTAssertEqual(loaded, running)
    }
}
