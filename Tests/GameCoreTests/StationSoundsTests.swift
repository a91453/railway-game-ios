import Foundation
@testable import GameCore
import XCTest

/// Decision 866: the arrival chime and the departure melody the player
/// sets a station to play: free, saved only when set, read by no rule.
final class StationSoundsTests: XCTestCase {
    private let track = TestLine(tiles: 7)

    /// Two stations, a line between them and its train running all day, at
    /// the normal speed.
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

    func testTheSoundsAreFreeCheckedAndSavedOnlyWhenSet() throws {
        var (world, a, b) = try world()
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        let plain = String(decoding: try sorted.encode(world), as: UTF8.self)
        XCTAssertFalse(plain.contains(#""chime""#))
        XCTAssertFalse(plain.contains(#""departureMelody""#))
        let balance = world.economy.balance
        try world.setStationChime(a, to: .tourist)
        try world.setStationDepartureMelody(b, to: .c)
        XCTAssertEqual(world.station(id: a)?.chime, .tourist)
        XCTAssertNil(world.station(id: a)?.departureMelody)
        XCTAssertEqual(world.station(id: b)?.departureMelody, .c)
        XCTAssertEqual(world.economy.balance, balance, "free")
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(#""chime":"tourist""#))
        XCTAssertTrue(text.contains(#""departureMelody":"c""#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8)), world)
        let bad = text.replacingOccurrences(of: #""departureMelody":"c""#, with: #""departureMelody":"g""#)
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(bad.utf8)), "a melody the game does not have")

        let before = world
        let nowhere = StationID(rawValue: 9)
        XCTAssertThrowsError(try world.setStationChime(nowhere, to: .metro)) { XCTAssertEqual($0 as? GameError, .unknownStation(nowhere)) }
        XCTAssertThrowsError(try world.setStationDepartureMelody(nowhere, to: nil)) { XCTAssertEqual($0 as? GameError, .unknownStation(nowhere)) }
        XCTAssertEqual(world, before, "a refused command changes nothing")

        try world.setStationChime(a, to: nil)
        try world.setStationDepartureMelody(b, to: nil)
        XCTAssertEqual(String(decoding: try sorted.encode(world), as: UTF8.self), plain, "back to the form before")
    }

    /// No rule reads them: the same world runs the same with or without.
    func testTheyChangeNothingTheGameRuns() throws {
        var (plain, a, b) = try world()
        var set = plain
        try set.setStationChime(a, to: .metro)
        try set.setStationDepartureMelody(b, to: .b)
        try plain.advance(ticks: 1_800)
        try set.advance(ticks: 1_800)
        try set.setStationChime(a, to: nil)
        try set.setStationDepartureMelody(b, to: nil)
        XCTAssertEqual(set, plain)
    }

    /// The version 109 save: a station set to ring the interchange bell and
    /// another to play melody 2, run 30 minutes; it loads as the same world
    /// and runs on the same. Written with `STATION_SOUNDS_SAVE_NEW=1` by
    /// the build that first made it.
    func testTheVersion109SaveKeepsTheStationsSounds() throws {
        var (world, a, b) = try world()
        try world.setStationChime(a, to: .metro)
        try world.setStationDepartureMelody(b, to: .b)
        try world.advance(ticks: 1_800)
        let url = SavedGameTests.fixtures.appendingPathComponent("v109-station-sounds.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["STATION_SOUNDS_SAVE_NEW"] != nil, SavedGame.currentVersion == 109 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 109)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.station(id: a)?.chime, .metro)
        XCTAssertEqual(loaded.station(id: b)?.departureMelody, .b)
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 600)
        try running.advance(ticks: 600)
        XCTAssertEqual(loaded, running)
    }

    /// The version 110 save (decision 868): a station set to play melody
    /// 5, one of the three a version 109 build does not know, run 30
    /// minutes; it loads as the same world and runs on the same. Written
    /// with `MORE_MELODIES_SAVE_NEW=1` by the build that first made it.
    func testTheVersion110SaveKeepsALaterMelody() throws {
        var (world, a, b) = try world()
        try world.setStationDepartureMelody(a, to: .e)
        try world.setStationDepartureMelody(b, to: .b)
        try world.advance(ticks: 1_800)
        let url = SavedGameTests.fixtures.appendingPathComponent("v110-more-melodies.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["MORE_MELODIES_SAVE_NEW"] != nil, SavedGame.currentVersion == 110 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 110)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.station(id: a)?.departureMelody, .e)
        XCTAssertEqual(loaded.station(id: b)?.departureMelody, .b)
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 600)
        try running.advance(ticks: 600)
        XCTAssertEqual(loaded, running)
    }
}
