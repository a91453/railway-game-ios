import Foundation
@testable import GameCore
import XCTest

/// Renaming stations and lines, and a line's own colour (the reference's
/// `PRESET_COLORS`).
final class RenameAndColourTests: XCTestCase {
    private func world() throws -> (GameWorld, StationID, LineID) {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        let a = try track.buildStation(named: "A", beside: 1, at: 1, in: &world)
        let b = try track.buildStation(named: "B", beside: 5, at: 1, in: &world)
        let line = try world.createLine(named: "L", stops: [a, b]).id
        return (world, a, line)
    }

    func testRenamingIsFreeAndChecked() throws {
        var (world, a, line) = try world()
        let balance = world.economy.balance
        try world.renameStation(a, to: "Central")
        try world.renameLine(line, to: "Blue Line")
        XCTAssertEqual(world.station(id: a)?.name, "Central")
        XCTAssertEqual(world.line(id: line)?.name, "Blue Line")
        XCTAssertEqual(world.economy.balance, balance)
        let before = world
        XCTAssertThrowsError(try world.renameStation(a, to: "")) { XCTAssertEqual($0 as? GameError, .invalidName) }
        XCTAssertThrowsError(try world.renameStation(StationID(rawValue: 9), to: "X")) { XCTAssertEqual($0 as? GameError, .unknownStation(StationID(rawValue: 9))) }
        XCTAssertThrowsError(try world.renameLine(LineID(rawValue: 9), to: "X")) { XCTAssertEqual($0 as? GameError, .unknownLine(LineID(rawValue: 9))) }
        XCTAssertEqual(world, before)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testALinesColourIsSavedAndChecked() throws {
        var (world, _, line) = try world()
        XCTAssertEqual(LineColor.presets.count, 20)
        XCTAssertEqual(LineColor.presets[1].rgb, 0xEF5350)
        XCTAssertNil(LineColor(rgb: 0x1000000))
        XCTAssertNil(LineColor(rgb: -1))
        let plain = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertFalse(plain.contains(#""color""#))
        try world.setLineColor(line, to: LineColor.presets[1])
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(#""color":15684432"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8)), world)
        let bad = text.replacingOccurrences(of: #""color":15684432"#, with: #""color":16777216"#)
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(bad.utf8)))
        try world.setLineColor(line, to: nil)
        XCTAssertNil(world.line(id: line)?.color)
        XCTAssertThrowsError(try world.setLineColor(LineID(rawValue: 9), to: nil))
    }

    /// Decision 216: a line's code, one to three capitals and digits, saved
    /// only when the player set one.
    func testALinesCodeIsSavedAndChecked() throws {
        var (world, _, line) = try world()
        XCTAssertEqual(LineCode("BL")?.text, "BL")
        XCTAssertEqual(LineCode("R2")?.text, "R2")
        XCTAssertEqual(LineCode("123")?.text, "123")
        for bad in ["", "bl", "ABCD", "B L", "線", "Ａ", "B-"] {
            XCTAssertNil(LineCode(bad), bad)
        }
        let balance = world.economy.balance
        let plain = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertFalse(plain.contains(#""code""#))
        try world.setLineCode(line, to: LineCode("BL"))
        XCTAssertEqual(world.line(id: line)?.code, LineCode("BL"))
        XCTAssertEqual(world.economy.balance, balance)
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertTrue(text.contains(#""code":"BL""#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8)), world)
        for bad in [#""code":"bl""#, #""code":"ABCD""#, #""code":"""#, #""code":7"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(text.replacingOccurrences(of: #""code":"BL""#, with: bad).utf8)), bad)
        }
        try world.setLineCode(line, to: nil)
        XCTAssertNil(world.line(id: line)?.code)
        let before = world
        XCTAssertThrowsError(try world.setLineCode(LineID(rawValue: 9), to: LineCode("R"))) {
            XCTAssertEqual($0 as? GameError, .unknownLine(LineID(rawValue: 9)))
        }
        XCTAssertEqual(world, before)
    }

    /// Save version 56 (decision 216): a line's code, read back as it was.
    func testVersionFiftySixKeepsALinesCode() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v56-line-code.json")
        var (made, _, line) = try world()
        try made.setLineColor(line, to: LineColor.presets[8])
        try made.setLineCode(line, to: LineCode("BL"))
        try made.advance(ticks: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["LINE_CODE_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 56)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertEqual(loaded.line(id: line)?.code, LineCode("BL"))
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 56,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
