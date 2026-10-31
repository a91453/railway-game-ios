import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 513: the owner's 99.1 report from Nan'ao (Yilan), a stretch
/// traced south along the North-Link Line refused as "0 m · 97 m → 65 m"
/// with the sentence that lists every reason. Its first end stood in the
/// real line's tunnel, about 180 m under the mountain, past the 64 m
/// GameCore allowed below the ground. Tunnels now go 1,024 m deep, and a
/// refusal names the check that refused it. And short traces nearby, whose
/// new ends were held to the ground beside a real tunnel or bridge.
@MainActor
final class TrackGeometryProblemTests: XCTestCase {
    private let metre = Double(WorldCoordinate.unitsPerMetre)
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre

    /// A real-world game at Nan'ao over real ground, the network tool
    /// tracing single track, and the North-Link Line through the station
    /// with the station's place along it.
    private func nanao() throws -> (session: GameSession, line: WorldPath, station: Double) {
        let nanao = try BundledRealData.station("南澳", in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(nanao.anchor))
        try world.mapGround()
        let railways = try BundledRealData.railways()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let station = WorldVector(try BundledRealData.point(nanao.coordinate, in: world))
        let paths = railways.lines.filter { $0.system.id == "tra_sched" && $0.points.count > 20 }.map { line in
            WorldPath(line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) })
        }
        let path = try XCTUnwrap(paths.min { ($0.point(at: $0.project(station)) - station).length < ($1.point(at: $1.project(station)) - station).length })
        let session = GameSession(world: world, language: .traditionalChinese)
        session.heights = try XCTUnwrap(HighSpeedDemoTests.heights)
        session.railways = railways
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = false
        return (session, path, path.project(station))
    }

    /// The owner's stretch: from the mountain 3 km along the line from
    /// Nan'ao back to 1 km from it, its start in the tunnel.
    func testTheNanaoTraceIntoTheTunnelIsBuilt() throws {
        let (session, line, station) = try nanao()
        session.tapNetwork(at: line.point(at: station + 3_000 * metre).plan, reach: reach)
        session.tapNetwork(at: line.point(at: station + 1_000 * metre).plan, reach: reach)
        let start = try XCTUnwrap(session.networkStart), end = try XCTUnwrap(session.networkEnd)
        let plan = try XCTUnwrap(session.traceAlong(from: start, to: end))
        let first = try XCTUnwrap(plan.stretches.first)
        var world = session.world
        try world.readGround(under: first.ground, from: session.heights)
        let ground = try XCTUnwrap(world.groundHeight(at: first.from.plan))
        // The report's heights, and the start deep in the mountain.
        XCTAssertEqual(Double(first.from.z) / metre, 96, accuracy: 3)
        XCTAssertGreaterThan(ground - first.from.z, 150 * WorldCoordinate.unitsPerMetre, "more than 64 m under the ground")

        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem, preview.problem ?? "")
        XCTAssertEqual(preview.traced, plan.stretches.count, "the whole of it")
        XCTAssertEqual(Double(preview.length) / metre, 2_000, accuracy: 100)
        let before = session.world
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertGreaterThan(session.world.network.edges.count, before.network.edges.count)
    }

    /// A traced stretch refused from its first edge shows the whole way
    /// and its far end, not 0 m and the first edge's end: here a track of
    /// the player's own crosses the line just past the start.
    func testATraceRefusedFromItsFirstEdgeShowsTheWholeWay() throws {
        let (plain, line, station) = try nanao()
        let a = station - 1_000 * metre, b = station + 1_000 * metre
        let near = line.point(at: a + 40 * metre), along = (line.point(at: a + 41 * metre) - near).unit
        let across = WorldVector(x: -along.y, y: along.x) * (40 * metre)
        var world = plain.world
        let ends = [(near + across).plan, (near - across).plan]
        try world.readGround(under: ends, from: plain.heights)
        let nodes = try ends.map { try world.buildTrackNode(at: WorldCoordinate(x: $0.x, y: $0.y, z: try XCTUnwrap(world.groundHeight(at: $0)))) }
        try world.buildTrackEdge(from: nodes[0], to: nodes[1], structure: .surface)

        let session = GameSession(world: world, language: .traditionalChinese)
        session.heights = plain.heights
        session.railways = plain.railways
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = false
        session.tapNetwork(at: line.point(at: a).plan, reach: reach)
        session.tapNetwork(at: line.point(at: b).plan, reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertEqual(preview.traced, 0, "refused from its first edge")
        XCTAssertNotNil(preview.problem)
        XCTAssertEqual(Double(preview.length) / metre, 2_000, accuracy: 100, "the whole way, not 0 m")
        let last = try XCTUnwrap(preview.points.last)
        XCTAssertEqual(preview.endHeight, last.z, "the far end's height")
    }

    /// Case 2 (the owner's 99.1 report, the same game): short stretches
    /// traced on the North-Link Line near Nan'ao, beside a real tunnel's
    /// mouth or a bridge's end, refused as "0 m · ↕ 0 m" and the 40‰
    /// sentence. Their new ends were held to the ground the game reads
    /// there (the hillside over the tunnel, the bank by the bridge), and a
    /// tunnel the trace ends in counted only as long as the part along it.
    func testShortTracesBesideARealTunnelOrBridgeAreLaid() throws {
        let (session, line, station) = try nanao()
        // Along the line from the station: where the trace starts, how long.
        for (offset, length) in [(1_500.0, 200.0), (1_200, 400), (-2_000, 200), (-4_300, 200), (-5_300, 400)] {
            let a = line.point(at: station + offset * metre).plan, b = line.point(at: station + (offset + length) * metre).plan
            let plan = try XCTUnwrap(session.tracePlan(from: .point(a), to: .point(b)), "\(offset)")
            XCTAssertFalse(plan.stretches.isEmpty, "\(offset) m: \(plan.problem ?? "")")
            XCTAssertEqual(plan.buildable, plan.stretches.count, "\(offset) m: \(plan.problem ?? "")")
        }
        session.tapNetwork(at: line.point(at: station + 1_500 * metre).plan, reach: reach)
        session.tapNetwork(at: line.point(at: station + 1_700 * metre).plan, reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem, preview.problem ?? "")
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
    }

    /// Where no grade reaches from one end to the other (the trace has no
    /// stretch at all), the card shows the real line's way, its length and
    /// its ends' heights, not "0 m · ↕ 0 m": here a short stretch out of a
    /// tunnel's mouth up steep ground south of Nan'ao.
    func testATraceNoGradeReachesShowsItsWay() throws {
        let (session, line, station) = try nanao()
        session.tapNetwork(at: line.point(at: station - 3_700 * metre).plan, reach: reach)
        session.tapNetwork(at: line.point(at: station - 3_500 * metre).plan, reach: reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertEqual(preview.traced, 0)
        XCTAssertEqual(preview.problem, "沿這段真實鐵路，從一端到另一端的高低差超過遊戲的坡度上限 40‰，鋪不上去。")
        XCTAssertEqual(Double(preview.length) / metre, 200, accuracy: 20, "the way, not 0 m")
        let first = try XCTUnwrap(preview.points.first), last = try XCTUnwrap(preview.points.last)
        XCTAssertEqual(preview.startHeight, first.z)
        XCTAssertEqual(preview.endHeight, last.z)
        XCTAssertGreaterThan(abs(preview.endHeight - preview.startHeight), 8 * WorldCoordinate.unitsPerMetre, "more than 40‰ of 200 m apart")
    }

    /// Case 3 (the owner's 99.1 report, the same game): a 16-car platform
    /// at Nan'ao station, on track traced through it, refused as "35‰,
    /// cannot be levelled": the traced track there climbed with the ground
    /// the game reads, though the real station stands on the flat. A real
    /// station of the line along the way now has its platform's length of
    /// level track.
    func testA16CarPlatformGoesOnTrackTracedThroughNanaoStation() throws {
        let (session, line, station) = try nanao()
        session.tapNetwork(at: line.point(at: station - 1_000 * metre).plan, reach: reach)
        session.tapNetwork(at: line.point(at: station + 1_000 * metre).plan, reach: reach)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        session.platformCars = 16
        session.tapNetwork(at: line.point(at: station).plan, reach: reach)
        XCTAssertEqual(session.networkPlatformGrade ?? 0, 0, "level at the station")
        let before = session.world.network.platforms.count
        session.stationName = "南澳"
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.platforms.count, before + 1)
    }

    /// A level at the path's very end, less than half a unit past the last
    /// sample of the grid, keeps a sample of its own: it bounds the track
    /// and is laid at the height the grade gives it, not its lowest.
    func testALevelAtThePathsEndHasItsSample() throws {
        let length = 25 * TrackRise.spacing + 0.25
        let path = WorldPath([WorldVector(x: 0, y: 0), WorldVector(x: length, y: 0)])
        let ground = 20 * metre
        let rise = try XCTUnwrap(TrackRise(
            path: path, ground: { _ in ground }, water: { _ in false },
            levels: [TrackRise.Level(length...length, from: ground - 10 * metre, to: ground + 10 * metre)]
        ))
        XCTAssertEqual(rise.height(at: length), ground, accuracy: 1, "on the ground, inside the level")
    }

    func testEachCheckNamesItself() throws {
        var world = try makeWorld(width: 16_384, height: 8_192, balance: 1_000_000, speed: .paused)
        let a = WorldCoordinate(x: 2_048, y: 2_048), b = WorldCoordinate(x: 6_144, y: 2_048)
        func stretch(_ from: WorldCoordinate, _ to: WorldCoordinate, curve: TrackCurve = .straight, start: NetworkAnchor? = nil) -> PlayerCommand.TrackStretch {
            PlayerCommand.TrackStretch(
                start: start ?? .point(from.plan), end: .point(to.plan), from: from, to: to, curve: curve, profile: .uniform,
                structure: .automatic, ground: [from.plan, to.plan]
            )
        }
        func problem(_ stretch: PlayerCommand.TrackStretch) -> TrackGeometryProblem? {
            TrackGeometryProblem.of(stretch, in: world, heights: nil)
        }
        XCTAssertNil(problem(stretch(a, b)))
        XCTAssertEqual(problem(stretch(a, WorldCoordinate(x: 6_144, y: 2_048, z: 4_160))), .tooHigh(4_160))
        XCTAssertEqual(problem(stretch(WorldCoordinate(x: 2_048, y: 2_048, z: -65_600), b)), .tooDeep(65_600))
        XCTAssertNil(problem(stretch(a, WorldCoordinate(x: 6_144, y: 2_048, z: -4_160))), "a tunnel 65 m down")
        XCTAssertEqual(problem(stretch(a, WorldCoordinate(x: 20_000, y: 2_048))), .geometry(.outsideMap))
        XCTAssertEqual(problem(stretch(a, WorldCoordinate(x: 2_048, y: 2_048, z: 64))), .geometry(.sameSpot))
        let fold = TrackCurve.cubic(PlanPoint(x: 6_000, y: 2_048), PlanPoint(x: 1_000, y: 2_048))
        XCTAssertEqual(problem(stretch(a, WorldCoordinate(x: 4_096, y: 2_048), curve: fold)), .geometry(.tooBent))
        _ = try world.buildTrackNode(at: b)
        XCTAssertEqual(problem(stretch(a, b)), .pointTaken)
        // What GameCore says matches.
        for (bad, expected) in [(stretch(WorldCoordinate(x: 2_048, y: 2_048, z: -65_600), WorldCoordinate(x: 2_048, y: 4_096)), TrackGeometryProblem.tooDeep(65_600))] {
            var copy = world
            XCTAssertThrowsError(try bad.build(in: &copy, heights: nil)) { error in
                XCTAssertEqual(error as? GameError, .invalidTrackGeometry)
                XCTAssertEqual(
                    (error as? GameError)?.playerMessage(building: bad, in: world, heights: nil, language: .traditionalChinese),
                    expected.text(in: .traditionalChinese)
                )
            }
        }
    }

    func testTheSentencesSayTheLimitsInBothLanguages() {
        XCTAssertEqual(TrackGeometryProblem.tooDeep(65_600).text(in: .traditionalChinese), "有一端會在地面下 1025 公尺，軌道最深只能到地下 1024 公尺。")
        XCTAssertEqual(TrackGeometryProblem.tooHigh(4_160).text(in: .english), "One end would stand 65 m above the ground; track stands at most 64 m above it.")
        var seen: Set<String> = []
        let all: [TrackGeometryProblem] = [.tooHigh(4_160), .tooDeep(65_600), .pointTaken] + NetworkBuilding.GeometryProblem.allCases.map { .geometry($0) }
        for problem in all {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                XCTAssertTrue(seen.insert(problem.text(in: language)).inserted, problem.text(in: language))
            }
        }
    }
}
