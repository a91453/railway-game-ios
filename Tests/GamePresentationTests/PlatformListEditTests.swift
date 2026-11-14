import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 755 (PLATFORM-BOOK PB-3): the line panel's list of platforms
/// for one leg: its rows, the edits, and what it warns of.
///
/// A 512 m single track W – M – E with a passing loop at M (the layout of
/// the GameCore tests' `SingleTrackMeet`), a third platform at M near W on
/// the main track, and a line W – M – E naming M's loop for its leg W → M.
@MainActor
final class PlatformListEditTests: XCTestCase {
    private static let west = StationID(rawValue: 1), middle = StationID(rawValue: 2)

    private func session(trains: Int = 0) throws -> (session: GameSession, line: LineID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 36_864, height: 12_288),
            economy: GameEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 10, station: 1_000, train: 500)),
            clock: GameClock(speed: .normal)
        )
        for (x, y) in [(1_024, 4_096), (9_216, 4_096), (25_600, 4_096), (33_792, 4_096), (13_312, 6_144), (21_504, 6_144)] as [(Int64, Int64)] {
            _ = try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        }
        for edge in 1...3 { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        _ = try world.buildTrackEdge(from: .node(2), to: .node(5), curve: .cubic(.init(x: 11_264, y: 4_096), .init(x: 11_264, y: 6_144)))
        _ = try world.buildTrackEdge(from: .node(5), to: .node(6))
        _ = try world.buildTrackEdge(from: .node(6), to: .node(3), curve: .cubic(.init(x: 23_552, y: 6_144), .init(x: 23_552, y: 4_096)))
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 8_192))
        }
        for (station, edge, start, end) in [(1, 1, 1_024, 3_072), (2, 2, 7_168, 9_216), (2, 5, 3_072, 5_120), (3, 3, 5_120, 7_168), (2, 2, 2_048, 4_096)] as [(Int, Int, Int64, Int64)] {
            try world.addTrackPlatform(StationID(rawValue: station), on: .edge(edge), from: start, to: end)
        }
        let line = try world.createLine(named: "Route", stops: [StationID(rawValue: 1), Self.middle, StationID(rawValue: 3)]).id
        for index in 0..<trains {
            let train = try world.purchaseTrain(named: "T\(index)").id
            try world.setTrainCars(train, to: 2)
            try world.assignTrain(train, to: line)
        }
        let loop = try XCTUnwrap(world.trackPlatforms(of: Self.middle).first { $0.edge == .edge(5) })
        try world.setLineRoutePreferences(line, to: [LineRoutePreference(from: 0, to: 1, platform: loop)])
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectLine(line)
        return (session, line)
    }

    private func platforms(_ session: GameSession) -> (loop: TrackPlatform, far: TrackPlatform, near: TrackPlatform) {
        let all = session.world.trackPlatforms(of: Self.middle)
        return (all.first { $0.edge == .edge(5) }!, all.first { $0.edge == .edge(2) && $0.start == 7_168 }!, all.first { $0.edge == .edge(2) && $0.start == 2_048 }!)
    }

    private func list(_ session: GameSession, _ line: LineID) -> [TrackPlatform]? {
        session.world.line(id: line)?.routePreferences.first.map { $0.platformList ?? [$0.platform] }
    }

    /// A leg naming one platform lists it alone, with the station's other
    /// two to add; a leg naming none has no list.
    func testALegNamingOnePlatformListsItWithTheOthersToAdd() throws {
        let (session, _) = try session()
        let (loop, far, near) = platforms(session)
        let leg = try XCTUnwrap(session.platformListLeg(from: 0, to: 1))
        XCTAssertEqual(leg.entries.map(\.platform), [loop])
        XCTAssertFalse(leg.isList)
        XCTAssertEqual(Set(leg.choices), [far, near])
        XCTAssertEqual(leg.entries[0].text, "月台在軌段 #5（32 公尺）")
        XCTAssertNil(leg.entries[0].problem)
        XCTAssertNil(leg.warning)
        XCTAssertNil(session.platformListLeg(from: 1, to: 2), "the leg M → E names no platform")
    }

    /// Adding, moving and removing go through the world's command, in
    /// order, the first platform staying first.
    func testAddMoveAndRemoveEditTheList() throws {
        let (session, line) = try session()
        let (loop, far, near) = platforms(session)
        session.addSelectedLinePlatform(far, from: 0, to: 1)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.addSelectedLinePlatform(near, from: 0, to: 1)
        XCTAssertEqual(list(session, line), [loop, far, near])
        let full = try XCTUnwrap(session.platformListLeg(from: 0, to: 1))
        XCTAssertTrue(full.isList)
        XCTAssertEqual(full.choices, [], "the station has no other platform")
        session.moveSelectedLinePlatform(at: 2, by: -1, from: 0, to: 1)
        XCTAssertEqual(list(session, line), [loop, near, far])
        session.moveSelectedLinePlatform(at: 1, by: -1, from: 0, to: 1)
        XCTAssertEqual(list(session, line), [loop, near, far], "the first stays first")
        session.removeSelectedLinePlatform(at: 1, from: 0, to: 1)
        XCTAssertEqual(list(session, line), [loop, far])
        session.removeSelectedLinePlatform(at: 0, from: 0, to: 1)
        XCTAssertEqual(list(session, line), [loop, far], "the first is the route menu's")
        session.removeSelectedLinePlatform(at: 1, from: 0, to: 1)
        XCTAssertEqual(list(session, line), [loop])
    }

    /// The edits refuse what a list may not hold.
    func testTheEditsKeepAListALegMayHave() {
        let station = StationID(rawValue: 2)
        let made = (0..<5).map { TrackPlatform(station: station, edge: .edge(2), start: Int64($0) * 128, end: Int64($0) * 128 + 64) }
        let first = LineRoutePreference(from: 0, to: 1, platform: made[0])
        XCTAssertNil(PlatformListEdit.adding(made[0], to: first), "the first again")
        XCTAssertNil(PlatformListEdit.adding(TrackPlatform(station: StationID(rawValue: 1), edge: .edge(1), start: 0, end: 64), to: first), "another station's")
        var full = first
        for platform in made.dropFirst().prefix(3) { full = try! XCTUnwrap(PlatformListEdit.adding(platform, to: full)) }
        XCTAssertEqual(full.platformList, Array(made.prefix(4)))
        XCTAssertNil(PlatformListEdit.adding(made[4], to: full), "four in all")
        XCTAssertNil(PlatformListEdit.adding(made[1], to: first.withAlternates([made[1]])), "one twice")
        XCTAssertNil(PlatformListEdit.moving(at: 3, by: 1, in: full))
        XCTAssertNil(PlatformListEdit.removing(at: 4, from: full))
    }

    /// Picking a new first platform in the route menu keeps the list
    /// behind it, the old first next, less the one now first.
    func testANewFirstPlatformKeepsTheList() throws {
        let (session, line) = try session()
        let (loop, far, near) = platforms(session)
        session.addSelectedLinePlatform(far, from: 0, to: 1)
        session.setSelectedLineRoute(from: 0, to: 1, preference: LineRoutePreference(from: 0, to: 1, platform: near))
        XCTAssertEqual(list(session, line), [near, loop, far])
        session.setSelectedLineRoute(from: 0, to: 1, preference: LineRoutePreference(from: 0, to: 1, platform: far))
        XCTAssertEqual(list(session, line), [far, near, loop])
        session.setSelectedLineRoute(from: 0, to: 1, preference: nil)
        XCTAssertNil(list(session, line), "automatic: no platform, no list")
        session.setSelectedLineRoute(from: 0, to: 1, preference: LineRoutePreference(from: 0, to: 1, platform: loop))
        XCTAssertEqual(list(session, line), [loop], "one platform picked with no list before")
    }

    /// A platform too short for the line's longest train, and one gone, are
    /// marked on the list.
    func testAPlatformTheTrainsCannotUseIsMarked() throws {
        let (session, _) = try session(trains: 1)
        let (_, far, _) = platforms(session)
        session.addSelectedLinePlatform(far, from: 0, to: 1)
        var world = session.world
        let train = try XCTUnwrap(world.line(id: LineID(rawValue: 1))?.trains.first)
        try world.setTrainCars(train, to: 6)
        let leg = try XCTUnwrap(world.platformListLeg(LineID(rawValue: 1), from: 0, to: 1, in: .traditionalChinese))
        XCTAssertGreaterThan(try XCTUnwrap(world.train(id: train)).length, far.length)
        XCTAssertEqual(leg.entries.map { $0.problem != nil }, [true, true])
        XCTAssertTrue(try XCTUnwrap(leg.entries[1].problem).hasPrefix("放不下這條線最長的列車"))
        let english = try XCTUnwrap(world.platformListLeg(LineID(rawValue: 1), from: 0, to: 1, in: .english))
        XCTAssertTrue(try XCTUnwrap(english.entries[1].problem).hasPrefix("Too short"))
    }
}

private extension LineRoutePreference {
    func withAlternates(_ alternates: [TrackPlatform]) -> LineRoutePreference {
        LineRoutePreference(from: from, to: to, tracks: tracks, platform: platform, alternates: alternates)
    }
}
