@testable import GameCore
import XCTest

/// Decision 912: a change of line at one station costs what the two lines'
/// platforms make it cost.
///
/// Station S has four platform tracks running east, side by side:
///
///   B  y + 11 m   ───────────────   island with A (11 m apart, nothing between)
///   A  y          ───────────────
///   C  y − 5 m    ───────────────   5 m from A: no island between them
///   V  y − 20 m, 8 m up (a viaduct)
///
/// Two lines call at S and at their own far stations W (west) and E (east).
final class PlatformTransferTests: XCTestCase {
    private static let unit = WorldCoordinate.unitsPerMetre
    private static let y: Int64 = 8_192

    private struct Scene {
        var world: GameWorld
        let s: StationID
        let w: StationID
        let e: StationID
        let a: TrackPlatform
        let b: TrackPlatform
        let c: TrackPlatform
        let v: TrackPlatform
    }

    /// The tracks, and a track between A and B when `between`.
    private static func scene(between: Bool = false) throws -> Scene {
        var world = try GameWorld(
            bounds: WorldBounds(width: 200_704, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 6 * 60), speed: .normal)
        )
        func track(_ dy: Int64, z: Int64 = 0) throws -> TrackEdgeID {
            let from = try world.buildTrackNode(at: WorldCoordinate(x: 40_960, y: y + dy, z: z))
            let to = try world.buildTrackNode(at: WorldCoordinate(x: 61_440, y: y + dy, z: z))
            return try world.buildTrackEdge(from: from, to: to, structure: z > 0 ? .elevated : .surface)
        }
        let a = try track(0)
        let b = try track(11 * unit)
        let c = try track(-5 * unit)
        let v = try track(-20 * unit, z: 8 * unit)
        if between { _ = try track(6 * unit) }
        let s = try world.buildStation(named: "S", at: PlanPoint(x: 51_200, y: y)).id
        let w = try world.buildStation(named: "W", at: PlanPoint(x: 8_192, y: y)).id
        let e = try world.buildStation(named: "E", at: PlanPoint(x: 190_000, y: y)).id
        for edge in [a, b, c, v] {
            try world.addTrackPlatform(s, on: edge, from: 2_048, to: 12_288)
        }
        let platforms = world.trackPlatforms(of: s)
        func on(_ edge: TrackEdgeID) -> TrackPlatform { platforms.first { $0.edge == edge }! }
        return Scene(world: world, s: s, w: w, e: e, a: on(a), b: on(b), c: on(c), v: on(v))
    }

    func testTheKindOfEachChange() throws {
        let scene = try Self.scene()
        let world = scene.world
        XCTAssertEqual(world.platformChange(from: scene.a, to: scene.a)?.kind, .acrossPlatform)
        let island = try XCTUnwrap(world.platformChange(from: scene.a, to: scene.b))
        XCTAssertEqual(island.kind, .acrossPlatform)
        XCTAssertEqual(island.minimumSeconds, 60)
        XCTAssertEqual(island.penaltySeconds, 720, "the reference's same-platform cost, as before")
        XCTAssertEqual(world.platformChange(from: scene.b, to: scene.a)?.kind, .acrossPlatform)

        let side = try XCTUnwrap(world.platformChange(from: scene.a, to: scene.c))
        XCTAssertEqual(side.kind, .sameLevel, "5 m apart: no platform between the two tracks")
        XCTAssertEqual(side.walkSeconds, 4, "5 m at 5 km/h, rounded up")
        XCTAssertEqual(side.minimumSeconds, 120)
        XCTAssertEqual(side.penaltySeconds, 1_080 + 4)

        let up = try XCTUnwrap(world.platformChange(from: scene.a, to: scene.v))
        XCTAssertEqual(up.kind, .otherLevel)
        XCTAssertEqual(up.climbSeconds, 60, "8 m: two 4 m steps")
        XCTAssertEqual(up.walkSeconds, 15, "20 m at 5 km/h")
        XCTAssertEqual(up.minimumSeconds, 120)
        XCTAssertEqual(up.penaltySeconds, 1_080 + 15 + 60)
        XCTAssertEqual(world.platformChange(from: scene.c, to: scene.b)?.kind, .sameLevel, "16 m apart, A between")
    }

    func testATrackBetweenTwoPlatformsIsNoIsland() throws {
        let scene = try Self.scene(between: true)
        XCTAssertEqual(scene.world.platformChange(from: scene.a, to: scene.b)?.kind, .sameLevel)
    }

    func testPlatformsOfTwoStationsHaveNoChange() throws {
        var scene = try Self.scene()
        let other = try scene.world.buildStation(named: "T", at: PlanPoint(x: 52_000, y: Self.y + 4_000)).id
        let elsewhere = TrackPlatform(station: other, edge: scene.a.edge, start: scene.a.start, end: scene.a.end)
        XCTAssertNil(scene.world.platformChange(from: scene.a, to: elsewhere))
    }

    /// Two lines W–S and S–E, each naming its platform at S, `first` and
    /// `second`.
    private static func lines(_ scene: inout Scene, first: TrackPlatform?, second: TrackPlatform?) throws -> (LineID, LineID) {
        let west = try scene.world.createLine(named: "West", stops: [scene.w, scene.s]).id
        let east = try scene.world.createLine(named: "East", stops: [scene.s, scene.e]).id
        if let first {
            try scene.world.setLineRoutePreferences(west, to: [LineRoutePreference(from: 0, to: 1, platform: first)])
        }
        if let second {
            try scene.world.setLineRoutePreferences(east, to: [LineRoutePreference(from: 1, to: 0, platform: second)])
        }
        return (west, east)
    }

    func testEachLineStandsAtItsNamedPlatformBothWays() throws {
        var scene = try Self.scene()
        let (west, east) = try Self.lines(&scene, first: scene.a, second: scene.b)
        let calls = scene.world.platformCalls(at: scene.s)
        XCTAssertEqual(calls.filter { $0.line == west }.map(\.platform), [scene.a, scene.a], "arriving, and turning back from there")
        XCTAssertEqual(calls.filter { $0.line == east }.map(\.platform), [scene.b, scene.b])
        let ridden = PassengerJourneyLeg(PassengerRouteLeg(line: west, pattern: nil, direction: .outbound, from: scene.w, to: scene.s, rideSeconds: 60))
        let next = PassengerJourneyLeg(PassengerRouteLeg(line: east, pattern: nil, direction: .outbound, from: scene.s, to: scene.e, rideSeconds: 60))
        XCTAssertEqual(scene.world.platformChange(from: ridden, to: next).kind, .acrossPlatform)
        XCTAssertEqual(scene.world.platformChange(from: ridden, to: next).minimumSeconds, 60)
    }

    func testALineNamingNoPlatformChangesAsBefore() throws {
        var scene = try Self.scene()
        let (west, east) = try Self.lines(&scene, first: scene.a, second: nil)
        let ridden = PassengerJourneyLeg(PassengerRouteLeg(line: west, pattern: nil, direction: .outbound, from: scene.w, to: scene.s, rideSeconds: 60))
        let next = PassengerJourneyLeg(PassengerRouteLeg(line: east, pattern: nil, direction: .outbound, from: scene.s, to: scene.e, rideSeconds: 60))
        let change = scene.world.platformChange(from: ridden, to: next)
        XCTAssertEqual(change, PlatformChange.unknown)
        XCTAssertEqual(change.minimumSeconds, PassengerTransferRules.minimumChangeSeconds)
        XCTAssertEqual(change.penaltySeconds, PassengerTransferTier.samePlatform.penaltySeconds)
    }

    /// A list of platforms leaves the train free among them: as before.
    func testAListOfPlatformsNamesNone() throws {
        var scene = try Self.scene()
        let (west, _) = try Self.lines(&scene, first: nil, second: scene.b)
        try scene.world.setLineRoutePreferences(west, to: [LineRoutePreference(from: 0, to: 1, platform: scene.a, alternates: [scene.c])])
        XCTAssertEqual(scene.world.platformCalls(at: scene.s).filter { $0.line == west }.map(\.platform), [nil, nil])
    }

    /// Track from W through A to E, with a platform at W and at E, so
    /// that both lines run (along A: a named platform the train cannot
    /// reach still names where passengers change).
    private static func connect(_ scene: inout Scene) throws {
        let west = try scene.world.buildTrackNode(at: WorldCoordinate(x: 8_192, y: y, z: 0))
        let east = try scene.world.buildTrackNode(at: WorldCoordinate(x: 190_000, y: y, z: 0))
        for platform in [scene.a] {
            let edge = try XCTUnwrap(scene.world.network.edge(platform.edge))
            let out = try scene.world.buildTrackEdge(from: west, to: edge.from, structure: .surface)
            let back = try scene.world.buildTrackEdge(from: edge.to, to: east, structure: .surface)
            if platform == scene.a {
                try scene.world.addTrackPlatform(scene.w, on: out, from: 2_048, to: 12_288)
                try scene.world.addTrackPlatform(scene.e, on: back, from: 70_000, to: 80_000)
            }
        }
    }

    /// The route graph weighs the change as its platforms make it: the
    /// island's 12 minutes, the viaduct's 18 and the walk and the climb.
    func testTheRouteGraphWeighsTheChange() throws {
        for (second, penalty) in [(\Scene.b, Int64(720)), (\Scene.v, 1_080 + 15 + 60)] {
            var scene = try Self.scene()
            try Self.connect(&scene)
            let (west, east) = try Self.lines(&scene, first: scene.a, second: scene[keyPath: second])
            for line in [west, east] {
                try scene.world.setLineServiceWindow(line, to: .allDay)
                try scene.world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
            }
            let graph = PassengerRouteGraph(world: scene.world)
            let pair = PassengerRouteGraph.PlatformPair(from: scene.a, to: scene[keyPath: second])
            XCTAssertEqual(graph.platformChanges[pair]?.penaltySeconds, penalty)
        }
    }
}
