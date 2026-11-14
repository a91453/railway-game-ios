import Foundation
@testable import GameCore
import XCTest

/// Decision 740 (PLATFORM-BOOK PB-2): a leg's list of platforms.
///
/// The line of ``LineRoutePreferenceTests`` (W, M, E on a single track with
/// a loop at M), with a third platform at M near W on the main (edge 2,
/// 2,048 to 4,096) and a train with no service standing on the loop's
/// platform (edge 5), so the leg's first platform, the loop, is taken. The
/// leg's other platform is M's far one on the main (edge 2, 7,168 to 9,216).
final class PlatformListTests: XCTestCase {
    static func platforms(_ world: GameWorld) -> (loop: TrackPlatform, far: TrackPlatform, near: TrackPlatform) {
        let all = world.trackPlatforms(of: SingleTrackMeet.middle)
        return (all.first { $0.edge == .edge(5) }!, all.first { $0.edge == .edge(2) && $0.start == 7_168 }!, all.first { $0.edge == .edge(2) && $0.start == 2_048 }!)
    }

    static func world(list: Bool, farTaken: Bool = false) throws -> (world: GameWorld, line: LineID, train: TrainID) {
        var (world, _, line, train) = try LineRoutePreferenceTests.setup()
        try world.addTrackPlatform(SingleTrackMeet.middle, on: .edge(2), from: 2_048, to: 4_096)
        _ = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(5), offset: 5_120)
        if farTaken { _ = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(2), offset: 9_216) }
        let loop = LineRoutePreferenceTests.loop(world)
        let route = LineRoutePreference(from: 0, to: 1, tracks: loop.tracks, platform: loop.platform, alternates: list ? [platforms(world).far] : [])
        try world.setLineRoutePreferences(line, to: [route])
        return (world, line, train)
    }

    /// The edge and offset where `train`'s way to M ends once it has set
    /// off, stepping at most `seconds`; `nil` if it has not.
    static func setOff(_ world: inout GameWorld, _ train: TrainID, within seconds: Int64 = 600) throws -> (edge: TrackEdgeID, end: Int64?)? {
        while world.clock.now.seconds < seconds {
            try world.advance(ticks: 1)
            if let moving = world.train(id: train), case .travellingToStop(1, _)? = moving.execution,
               let last = moving.movement.remainingEdges.last {
                return (last, moving.movement.end)
            }
        }
        return nil
    }

    /// The gap this closes: with only the loop named, its train went to
    /// the nearest free platform, which the player had not named; with the
    /// far platform second on the list, it goes there.
    func testATakenFirstPlatformSendsTheTrainToTheNextOnTheList() throws {
        var (one, _, a) = try Self.world(list: false)
        let anywhere = try XCTUnwrap(try Self.setOff(&one, a))
        XCTAssertEqual(anywhere.edge, .edge(2))
        XCTAssertEqual(anywhere.end, 4_096, "without a list: the nearest free platform")
        var (listed, _, b) = try Self.world(list: true)
        let next = try XCTUnwrap(try Self.setOff(&listed, b))
        XCTAssertEqual(next.edge, .edge(2))
        XCTAssertEqual(next.end, 9_216, "the list's second platform")
        XCTAssertEqual(WorldInvariants.violations(in: listed), [])
    }

    /// Every platform of the list taken, the train waits at W rather than
    /// go to the free one outside the list; it is no deadlock (the trains
    /// in the way have no service and may be moved).
    func testWithEveryPlatformOfTheListTakenTheTrainWaits() throws {
        var (world, _, train) = try Self.world(list: true, farTaken: true)
        XCTAssertNil(try Self.setOff(&world, train, within: 900))
        XCTAssertEqual(world.train(id: train)?.position, .onEdge(SingleTrackMeet.forward(1), offset: 3_072), "still at W")
        XCTAssertEqual(world.deadlockedTrains(), [])
        // Without the list it goes to the near platform.
        var (anywhere, _, other) = try Self.world(list: false, farTaken: true)
        XCTAssertEqual(try XCTUnwrap(try Self.setOff(&anywhere, other)).end, 4_096)
    }

    /// One long advance ends where tenths of a second do, and a save goes
    /// on the same.
    func testBatchesStepsAndASaveAgree() throws {
        var batch = try Self.world(list: true).world
        var tenths = batch
        batch.setSpeed(.normal)
        try batch.advance(ticks: 20)
        for _ in 0..<6_000 { try tenths.advance(ticks: 1) }
        var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: tenths))).world
        for _ in 0..<6_000 {
            try tenths.advance(ticks: 1)
            try loaded.advance(ticks: 1)
        }
        XCTAssertEqual(loaded, tenths)
        tenths.setSpeed(.normal)
        XCTAssertEqual(tenths, batch)
    }

    /// The list is saved under `"alternates"`, only when there is one, and
    /// a list a leg may not have is refused: another station's platform,
    /// the first platform again, one twice, more than three after the first.
    func testTheListIsSavedAndCheckedLikeThePlatformBeforeIt() throws {
        var (world, line, _) = try Self.world(list: true)
        let (loop, far, near) = Self.platforms(world)
        let route = try XCTUnwrap(world.line(id: line)?.routePreferences.first)
        XCTAssertEqual(route.platformList, [loop, far])
        let data = try JSONEncoder().encode(route)
        XCTAssertNotNil(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])["alternates"])
        XCTAssertEqual(try JSONDecoder().decode(LineRoutePreference.self, from: data), route)
        let single = LineRoutePreference(from: 0, to: 1, platform: loop)
        XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(single)) as? [String: Any])["alternates"])
        XCTAssertNil(single.platformList)
        let west = try XCTUnwrap(world.trackPlatforms(of: SingleTrackMeet.west).first)
        let made = (1...4).map { TrackPlatform(station: SingleTrackMeet.middle, edge: .edge(2), start: Int64($0) * 128, end: Int64($0) * 128 + 64) }
        for alternates in [[west], [loop], [far, far], made] {
            let bad = LineRoutePreference(from: 0, to: 1, platform: loop, alternates: alternates)
            XCTAssertThrowsError(try world.setLineRoutePreferences(line, to: [bad])) { error in
                XCTAssertEqual(error as? GameError, .invalidLineRoutePreference)
            }
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(LineRoutePreference(from: 0, to: 1, platform: loop))) as? [String: Any])
            json["alternates"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(alternates))
            XCTAssertThrowsError(try JSONDecoder().decode(LineRoutePreference.self, from: JSONSerialization.data(withJSONObject: json)))
        }
        try world.setLineRoutePreferences(line, to: [LineRoutePreference(from: 0, to: 1, platform: loop, alternates: [far, near])])
        XCTAssertEqual(world.line(id: line)?.routePreferences.first?.platformList, [loop, far, near])
    }

    /// Lengthening a platform of the list keeps it on the list, as the
    /// first platform is kept (decision 687).
    func testALengthenedPlatformStaysOnTheList() throws {
        var (world, line, _) = try Self.world(list: true)
        let far = Self.platforms(world).far
        try world.extendTrackPlatform(SingleTrackMeet.middle, on: .edge(2), from: far.start, toStart: 6_144, end: far.end)
        let longer = try XCTUnwrap(world.trackPlatforms(of: SingleTrackMeet.middle).first { $0.edge == .edge(2) && $0.end == 9_216 })
        XCTAssertEqual(longer.start, 6_144)
        XCTAssertEqual(world.line(id: line)?.routePreferences.first?.alternates, [longer])
    }

    /// The version 101 save: the world above a minute on, its leg naming
    /// two platforms; it loads as the same world and runs on the same.
    static func savedWorld() throws -> GameWorld {
        var world = try Self.world(list: true).world
        try world.advance(ticks: 600)
        return world
    }

    func testTheVersion101SaveKeepsItsPlatformList() throws {
        let world = try Self.savedWorld()
        let url = SavedGameTests.fixtures.appendingPathComponent("v101-platform-list.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "printed by ZZPlatformListFixturePrintTests until committed")
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 101)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.lines.first?.routePreferences.first?.alternates.count, 1)
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 1_200)
        try running.advance(ticks: 1_200)
        XCTAssertEqual(loaded, running)
    }
}

/// Temporary: prints the version 101 save while it is not committed.
final class ZZPlatformListFixturePrintTests: XCTestCase {
    func testPrintTheVersion101Save() throws {
        let world = try PlatformListTests.savedWorld()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = Array(String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self))
        print("V101-FIXTURE-BEGIN \(text.count)")
        var start = 0
        while start < text.count {
            let end = min(start + 1_000, text.count)
            print("V101|" + String(text[start..<end]) + "|")
            start = end
        }
        print("V101-FIXTURE-END")
        XCTFail("print only: the v101 save is not committed yet")
    }
}
