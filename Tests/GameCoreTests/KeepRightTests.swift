import Foundation
@testable import GameCore
import XCTest

/// Lines keeping right (decision 564): ``KeepLeftTests``' two tracks
/// between West and East, the line Main between them.
final class KeepRightTests: XCTestCase {
    static let eastboundSouth = [3, 5, 7, 8].map { TrackTraversal(edge: .edge($0), direction: .forward) }

    static func world(keepsRight: Bool) throws -> (world: GameWorld, west: StationID, east: StationID, line: LineID) {
        var (world, west, east) = try KeepLeftTests.world(keepLeft: true)
        let line = try world.createLine(named: "Main", stops: [west, east]).id
        try world.setLineKeepsRight(line, to: keepsRight)
        return (world, west, east, line)
    }

    func testALineKeepingRightTakesTheTrackOnItsRight() throws {
        let (world, west, east, _) = try Self.world(keepsRight: true)
        XCTAssertTrue(world.keepsRight(toward: east))
        XCTAssertEqual(world.path(from: KeepLeftTests.fromWest, toStation: east)?.traversals, Self.eastboundSouth, "south, on the right going east")
        XCTAssertEqual(world.path(from: KeepLeftTests.fromEast, toStation: west)?.traversals, KeepLeftTests.westboundNorth, "north, on the right going west")
    }

    func testALineKeepingLeftIsAsBefore() throws {
        let (left, west, east, _) = try Self.world(keepsRight: false)
        XCTAssertFalse(left.keepsRight(toward: east))
        XCTAssertEqual(left.path(from: KeepLeftTests.fromWest, toStation: east)?.traversals, KeepLeftTests.eastbound)
        XCTAssertEqual(left.path(from: KeepLeftTests.fromEast, toStation: west)?.traversals, KeepLeftTests.westboundLeft)
        var off = left
        off.setKeepLeft(false)
        XCTAssertEqual(off.path(from: KeepLeftTests.fromWest, toStation: east)?.traversals, KeepLeftTests.eastbound, "the first of equally short ways, as with keeping left off")
    }

    /// The side is the line's: in a world whose trains do not keep left
    /// (the high-speed demo), a line keeping right still keeps right
    /// (bought there before this, the Wenhu Line's trains ran 139 of 951
    /// minutes on the left in the first three hours).
    func testALineKeepingRightKeepsRightInAWorldNotKeepingLeft() throws {
        var (world, west, east, _) = try Self.world(keepsRight: true)
        world.setKeepLeft(false)
        XCTAssertEqual(world.path(from: KeepLeftTests.fromWest, toStation: east)?.traversals, Self.eastboundSouth)
        XCTAssertEqual(world.path(from: KeepLeftTests.fromEast, toStation: west)?.traversals, KeepLeftTests.westboundNorth)
    }

    /// A station a line keeping left serves too keeps left, and so does
    /// one no line serves.
    func testAStationALineKeepingLeftServesKeepsLeft() throws {
        var (world, west, east, _) = try Self.world(keepsRight: true)
        let other = try world.buildStation(named: "Other", at: PlanPoint(x: 20_480, y: 2_048)).id
        XCTAssertFalse(world.keepsRight(toward: other))
        try world.createLine(named: "Branch", stops: [west, east])
        XCTAssertFalse(world.keepsRight(toward: east))
        XCTAssertEqual(world.path(from: KeepLeftTests.fromWest, toStation: east)?.traversals, KeepLeftTests.eastbound)
    }

    /// A crossover laid as an S-curve leaves its node along the track but
    /// for the tangents' rounding: here a hair to the right (south, going
    /// east) while it bends away north. Which side it is on comes from the
    /// chords (on the Sanying Line before this, a train keeping right took
    /// such a crossover onto the other way's track: 292 of 398 runs not
    /// sent out on the second day, simple rules).
    func testACrossoverStartingAlongTheTrackIsOnTheSideItBendsTo() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 40_960, height: 20_480), economy: fixtureEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 0, station: 0, train: 0)), clock: GameClock(speed: .normal))
        for (x, y): (Int64, Int64) in [(2_048, 10_240), (10_240, 10_240), (16_640, 10_240), (16_640, 9_216)] {
            try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        let arrival = try world.buildTrackEdge(from: .node(1), to: .node(2))
        let through = try world.buildTrackEdge(from: .node(2), to: .node(3))
        let crossover = try world.buildTrackEdge(from: .node(2), to: .node(4), curve: .cubic(PlanPoint(x: 12_373, y: 10_241), PlanPoint(x: 14_507, y: 9_216)))
        let after = TrackTraversal(edge: arrival, direction: .forward)
        let exits = world.transitions(after: after)
        XCTAssertEqual(Set(exits), [TrackTraversal(edge: through, direction: .forward), TrackTraversal(edge: crossover, direction: .forward)])
        XCTAssertEqual(world.rightOfLeftmost(after: after, among: exits), [TrackTraversal(edge: through, direction: .forward)], "the crossover, north, is the leftmost")
        XCTAssertEqual(world.rightOfLeftmost(after: after, among: exits, mirrored: true), [TrackTraversal(edge: crossover, direction: .forward)], "and not the rightmost")
    }

    func testTheSideIsSavedOnlyWhenRightAndACopyKeepsIt() throws {
        var (world, _, _, line) = try Self.world(keepsRight: true)
        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        let lines = try XCTUnwrap(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(world.line(id: line))) as? [String: Any])
        XCTAssertEqual(lines["keepsRight"] as? Bool, true)
        try world.setLineKeepsRight(line, to: false)
        let left = try XCTUnwrap(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(world.line(id: line))) as? [String: Any])
        XCTAssertNil(left["keepsRight"], "a line keeping left, as every line before decision 564, writes nothing")
        var written = left
        written["keepsRight"] = false
        XCTAssertThrowsError(try JSONDecoder().decode(ServiceLine.self, from: try JSONSerialization.data(withJSONObject: written)))
        try world.setLineKeepsRight(line, to: true)
        let copy = try world.duplicateLine(line, named: "Copy")
        XCTAssertTrue(copy.keepsRight)
        XCTAssertThrowsError(try world.setLineKeepsRight(LineID(rawValue: 99), to: true)) { error in
            XCTAssertEqual(error as? GameError, .unknownLine(LineID(rawValue: 99)))
        }
    }

    /// Version 82: the two tracks, Main keeping right, its train Blue at
    /// East ten ticks on, which a version 81 build would send back west on
    /// the south track. It saves byte for byte and is the world this build
    /// makes.
    func testVersionEightyTwoKeepsTheSide() throws {
        var (made, west, _, line) = try Self.world(keepsRight: true)
        let train = try made.purchaseTrain(named: "Blue").id
        try made.setTrainCars(train, to: 2)
        try made.placeTrain(train, at: KeepLeftTests.fromEast)
        try made.assignTrain(train, to: line)
        made.setSpeed(.normal)
        try made.advance(ticks: 10)
        let url = SavedGameTests.fixtures.appendingPathComponent("v82-keeps-right.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["KEEPS_RIGHT_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 82)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertEqual(loaded.line(id: line)?.keepsRight, true)
        XCTAssertEqual(loaded.path(from: KeepLeftTests.fromEast, toStation: west)?.traversals, KeepLeftTests.westboundNorth)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 82,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
