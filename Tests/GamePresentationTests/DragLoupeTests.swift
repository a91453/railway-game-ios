import GameCore
@testable import GamePresentation
import XCTest

/// Decision 204: the drawing magnifier and the stretch's tightest radius.
@MainActor
final class DragLoupeTests: XCTestCase {
    /// A quarter circle of radius 320 m as a cubic (handles 0.5523 of the
    /// radius along the tangents) has that radius, to within one per cent
    /// (the cubic is a little tighter than the circle at its middle); a
    /// straight edge has none.
    func testAQuarterCircleReadsItsRadius() throws {
        let r: Int64 = 320 * WorldCoordinate.unitsPerMetre
        let k = Int64((Double(r) * 0.5523).rounded())
        let curve = TrackCurve.cubic(PlanPoint(x: k, y: 0), PlanPoint(x: r, y: r - k))
        let radius = try XCTUnwrap(TrackCurvature.tightestRadius(from: PlanPoint(x: 0, y: 0), to: PlanPoint(x: r, y: r), curve: curve))
        XCTAssertEqual(radius / Double(r), 1, accuracy: 0.01)
        XCTAssertEqual(TrackCurvature.radiusText(radius, in: .english), "Radius 320 m")
        XCTAssertEqual(TrackCurvature.radiusText(radius, in: .traditionalChinese), "半徑 320 公尺")
        XCTAssertNil(TrackCurvature.tightestRadius(from: PlanPoint(x: 0, y: 0), to: PlanPoint(x: r, y: 0), curve: .straight))
        XCTAssertEqual(TrackCurvature.radiusText(nil, in: .traditionalChinese), "直線")
        // Handles along the chord: a cubic that is straight after all.
        XCTAssertNil(TrackCurvature.tightestRadius(
            from: PlanPoint(x: 0, y: 0), to: PlanPoint(x: 3_000, y: 0), curve: .cubic(PlanPoint(x: 1_000, y: 0), PlanPoint(x: 2_000, y: 0))
        ))
        XCTAssertEqual(TrackCurvature.radiusText(Double(45 * WorldCoordinate.unitsPerMetre) + 20, in: .english), "Radius 45 m")
    }

    /// The magnifier's camera is three times as close, centred on the
    /// finger, and the drag tells the map where the finger is until it
    /// lifts.
    func testTheMagnifierFollowsTheFinger() throws {
        let world = try makeWorld(width: 40_960, height: 20_480, balance: 10_000_000, speed: .paused)
        // At the map's largest zoom: the magnifier goes closer still.
        let camera = PlanCamera(bounds: world.bounds, viewport: ScreenSize(width: 800, height: 400)).zoomed(by: 64, around: ScreenPoint(x: 400, y: 200))
        XCTAssertFalse(camera.canZoomIn)
        let finger = PlanPoint(x: 20_480, y: 10_240)
        let loupe = camera.loupe(at: finger, size: ScreenSize(width: 120, height: 120), magnification: 3)
        XCTAssertEqual(loupe.pointsPerUnit / camera.pointsPerUnit, 3, accuracy: 0.001)
        XCTAssertEqual(loupe.screenPoint(of: finger).x, 60, accuracy: 0.5)
        XCTAssertEqual(loupe.screenPoint(of: finger).y, 60, accuracy: 0.5)

        let session = GameSession(world: world)
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 64)
        XCTAssertNil(session.networkDragFinger)
        session.dragNetwork(from: PlanPoint(x: 2_048, y: 10_240), to: PlanPoint(x: 12_288, y: 12_288), reach: 64)
        XCTAssertEqual(session.networkDragFinger, PlanPoint(x: 12_288, y: 12_288))
        XCTAssertEqual(session.networkPreview?.radiusText(in: .english), "Straight")
        session.endNetworkDrag(from: PlanPoint(x: 2_048, y: 10_240), to: PlanPoint(x: 12_288, y: 12_288), reach: 64)
        XCTAssertNil(session.networkDragFinger)
        XCTAssertNotNil(session.networkEnd)
    }
}
