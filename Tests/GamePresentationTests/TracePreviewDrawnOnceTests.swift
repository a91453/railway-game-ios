import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 521's third sequel: a traced stretch's preview shows one way,
/// not two. The real line is not lit under it, a double track's glow is
/// one path, and a trace that joins track already laid draws each piece of
/// track once.
@MainActor
final class TracePreviewDrawnOnceTests: XCTestCase {
    private let reach: Int64 = 24 * WorldCoordinate.unitsPerMetre
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    private func session(at station: String) throws -> GameSession {
        let start = try BundledRealData.station(station, in: "tra_sched")
        let session = GameSession(world: GameWorld.newGame(anchor: try XCTUnwrap(start.anchor)), language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        return session
    }

    private func point(_ station: String, in session: GameSession) throws -> PlanPoint {
        try BundledRealData.point(try BundledRealData.station(station, in: "tra_sched").coordinate, in: session.world)
    }

    /// Every segment of `lines`, either way round.
    private func segments(_ lines: [[WorldCoordinate]]) -> [[PlanPoint]] {
        lines.flatMap { line in
            zip(line, line.dropFirst()).map { a, b in [a.plan, b.plan].sorted { ($0.x, $0.y) < ($1.x, $1.y) } }
        }
    }

    /// Luodong to Dongshan, double in the data: both tracks under one glow,
    /// each drawn solid once, and the real line not lit beside them.
    func testADoubleTraceIsTwoTracksUnderOneGlow() throws {
        let session = try session(at: "羅東")
        session.tapNetwork(at: try point("羅東", in: session), reach: reach)
        session.tapNetwork(at: try point("冬山", in: session), reach: reach)
        XCTAssertEqual(session.networkPreview?.tracedDouble, true)
        let overlay = try XCTUnwrap(session.networkOverlay)
        XCTAssertTrue(overlay.previewIsBuildable)
        XCTAssertFalse(overlay.crossing.isEmpty, "the second track")
        XCTAssertTrue(overlay.tracedWay.isEmpty, "the real line not lit beside the tracks")
        XCTAssertEqual(overlay.previewGlow, [overlay.preview, overlay.crossing])
        XCTAssertEqual(overlay.previewTracks, [overlay.preview, overlay.crossing])
        let drawn = segments(overlay.previewTracks)
        XCTAssertEqual(Set(drawn).count, drawn.count, "no piece of track drawn twice")
    }

    /// Taipei to Banqiao over track laid on its middle third (decision
    /// 468): the new pieces solid, the track already laid dashed, neither
    /// drawn again under the whole way.
    func testATraceThatJoinsTrackDrawsEachPieceOnce() throws {
        let session = try session(at: "臺北")
        session.networkBuildsDouble = false
        session.networkDoubleChosen = true
        let taipei = try point("臺北", in: session), banqiao = try point("板橋", in: session)
        let traces = try XCTUnwrap(session.realRailwayTraces)
        let way = WorldPath(try XCTUnwrap(traces.path(
            from: try XCTUnwrap(traces.snap(WorldVector(taipei), within: 50 * metre)).place,
            to: try XCTUnwrap(traces.snap(WorldVector(banqiao), within: 50 * metre)).place
        )))
        session.tapNetwork(at: way.point(at: way.length / 3).plan, reach: reach)
        session.tapNetwork(at: way.point(at: way.length * 2 / 3).plan, reach: reach)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.clearNetworkDraft()

        session.tapNetwork(at: taipei, reach: reach)
        session.tapNetwork(at: banqiao, reach: reach)
        let overlay = try XCTUnwrap(session.networkOverlay)
        XCTAssertTrue(overlay.previewIsBuildable)
        XCTAssertEqual(overlay.existing.count, 1)
        XCTAssertEqual(overlay.newPieces.count, 2)
        XCTAssertTrue(overlay.tracedWay.isEmpty, "the real line not lit beside the tracks")
        XCTAssertEqual(overlay.previewGlow, [overlay.preview], "one glow along the whole way")
        XCTAssertEqual(overlay.previewTracks, overlay.newPieces, "the whole way not drawn solid over the dashes")
        let solid = Set(segments(overlay.previewTracks)), dashed = Set(segments(overlay.existing))
        XCTAssertTrue(solid.isDisjoint(with: dashed), "the track already laid drawn dashed only")
    }

    /// A stretch that cannot be built has no glow and no solid track: it is
    /// drawn grey and dashed, as before.
    func testAPreviewThatCannotBeBuiltHasNoGlow() {
        var overlay = NetworkOverlay()
        overlay.preview = [WorldCoordinate(x: 0, y: 0, z: 0), WorldCoordinate(x: 1_000, y: 0, z: 0)]
        overlay.previewIsBuildable = false
        XCTAssertTrue(overlay.previewGlow.isEmpty)
        XCTAssertTrue(overlay.previewTracks.isEmpty)
    }

    /// The screenshot test's two traces (`-ui-test-trace-double`,
    /// `-ui-test-trace-joined`) draw what the tests above check.
    func testTheScreenshotTracesShowTheirPreviews() throws {
        let double = try session(at: "羅東")
        XCTAssertTrue(double.traceForPreviewScreenshot(from: "羅東", to: "冬山", joining: false), double.networkPreview?.problem ?? "")
        XCTAssertFalse(try XCTUnwrap(double.networkOverlay).crossing.isEmpty, "a double track")
        XCTAssertNotNil(double.cameraRequest)

        let joined = try session(at: "臺北")
        XCTAssertTrue(joined.traceForPreviewScreenshot(from: "臺北", to: "板橋", joining: true), joined.networkPreview?.problem ?? "")
        XCTAssertEqual(try XCTUnwrap(joined.networkOverlay).existing.count, 1, "joins the track laid first")
    }
}
