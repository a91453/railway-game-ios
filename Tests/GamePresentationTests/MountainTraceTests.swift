import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 515: a trace of a real mountain line over real ground climbs
/// as steeply as the line does, up to 70 in 1000, as mountain track;
/// track the player draws keeps to 40.
@MainActor
final class MountainTraceTests: XCTestCase {
    private let reach: Int64 = 2_048

    private static let heights = try? HeightGrid(
        data: Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealWorld/taiwan_heights.dat"))
    )

    /// A new game around Fenqihu, tracing the Alishan Forest Railway over
    /// real ground from Fenqihu (1,405 m) up to Duolin.
    private func fenqihu() throws -> (session: GameSession, from: PlanPoint, to: PlanPoint) {
        let start = try BundledRealData.station("奮起湖", in: "afr_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(start.anchor))
        try world.mapGround()
        let session = GameSession(world: world, language: .english)
        session.heights = try XCTUnwrap(Self.heights)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        let end = try BundledRealData.station("多林", in: "afr_sched")
        return (session, try BundledRealData.point(start.coordinate, in: world), try BundledRealData.point(end.coordinate, in: world))
    }

    private func permille(_ grade: TrackGrade) -> Double {
        abs(Double(grade.rise) / Double(grade.run) * 1_000)
    }

    func testTracingTheAlishanLineLaysMountainTrack() throws {
        let (session, from, to) = try fenqihu()
        session.tapNetwork(at: from, reach: reach)
        session.tapNetwork(at: to, reach: reach)
        XCTAssertNil(try XCTUnwrap(session.networkPreview).problem)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let world = session.world
        let mountain = world.network.edges.filter(\.mountain)
        XCTAssertGreaterThan(mountain.count, world.network.edges.count / 2, "most of the way climbs more steeply than 40")
        for edge in world.network.edges {
            let grade = permille(try XCTUnwrap(world.trackGeometry(of: edge.id)).steepestGrade)
            XCTAssertLessThanOrEqual(grade, 70)
            if edge.mountain {
                XCTAssertGreaterThan(grade, 40, "only what must be is mountain track")
                XCTAssertFalse(edge.speedLimits.isEmpty)
            } else {
                XCTAssertLessThanOrEqual(grade, 40)
            }
        }
        XCTAssertGreaterThan(world.network.edges.map { permille(world.trackGeometry(of: $0.id)!.steepestGrade) }.max() ?? 0, 62.5,
                             "as steep as the real line's ruling grade")

        // The command log keeps the mark, and only where it is.
        let entry = try XCTUnwrap(session.commandLog.entries.last)
        guard case .command(.buildTrackChain(let stretches)) = entry.action else { return XCTFail("one command") }
        XCTAssertEqual(stretches.filter(\.mountain).count, mountain.count)
        let data = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(CommandLog.Entry.self, from: data), entry)
        XCTAssertEqual(String(decoding: data, as: UTF8.self).components(separatedBy: "\"mountain\":true").count, mountain.count + 1)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"mountain\":false"))
    }

    /// The same stretch drawn by the player, not traced, is ordinary track
    /// and too steep.
    func testTheSameStretchDrawnByThePlayerIsRefused() throws {
        let (session, from, to) = try fenqihu()
        session.tapNetwork(at: from, reach: reach)
        session.tapNetwork(at: to, reach: reach)
        let plan = try XCTUnwrap(session.tracePlan(from: try XCTUnwrap(session.networkStart), to: try XCTUnwrap(session.networkEnd)))
        let traced = try XCTUnwrap(plan.stretches.first { $0.mountain && permille(TrackGeometry(from: $0.from, to: $0.to, curve: $0.curve)!.steepestGrade) > 60 })
        let drawn = PlayerCommand.TrackStretch(
            start: .point(traced.from.plan), end: .point(traced.to.plan), from: traced.from, to: traced.to, curve: traced.curve,
            profile: traced.profile, structure: traced.structure, ground: traced.ground
        )
        XCTAssertFalse(drawn.mountain)
        var world = session.world
        XCTAssertThrowsError(try drawn.build(in: &world, heights: session.heights)) { XCTAssertEqual($0 as? GameError, .trackTooSteep) }
        world = session.world
        let mountain = PlayerCommand.TrackStretch(
            start: drawn.start, end: drawn.end, from: drawn.from, to: drawn.to, curve: drawn.curve,
            profile: drawn.profile, structure: drawn.structure, ground: drawn.ground, mountain: true
        )
        let edge = try mountain.build(in: &world, heights: session.heights).edge
        XCTAssertEqual(world.network.edge(edge)?.mountain, true)
    }

    func testOnlyTheMountainLineClimbsMoreSteeply() {
        for system in [nil, "tra_sched", "thsr_sched", "mrt", "krtc"] {
            XCTAssertEqual(GameSession.traceGrade(ofSystem: system), GameSession.traceGrade, system ?? "drawn")
        }
        XCTAssertEqual(GameSession.traceGrade(ofSystem: "afr_sched"), GameSession.mountainTraceGrade)
        XCTAssertLessThan(GameSession.mountainTraceGrade, 0.07)
        XCTAssertEqual(GameSession.traceMinimumRadius(ofSystem: "afr_sched"), GameSession.urbanTraceMinimumRadius)
        XCTAssertEqual(GameSession.traceMinimumRadius(ofSystem: "tra_sched"), GameSession.traceMinimumRadius)
    }
}
