import GameCore
@testable import GamePresentation
import XCTest

/// Decision 826: the track preview coloured by GameCore's curve limits, its
/// tightest curve and steepest grade marked, and a drawn end lined up with
/// the track around it.
@MainActor
final class TrackPreviewMarksTests: XCTestCase {
    private let metre = WorldCoordinate.unitsPerMetre

    /// A preview of the edge from `from` to `to` shaped by `curve` and
    /// `profile`, as the network tool makes one.
    private func preview(from: WorldCoordinate, to: WorldCoordinate, curve: TrackCurve, profile: TrackProfile = .uniform) throws -> NetworkPreview {
        let geometry = try XCTUnwrap(TrackGeometry(from: from, to: to, curve: curve, profile: profile))
        return NetworkPreview(
            curve: curve, profile: profile, points: geometry.points, length: geometry.length,
            startHeight: from.z, endHeight: to.z, joinsStart: false, joinsEnd: false, cost: nil, problem: nil
        )
    }

    /// A quarter circle of radius `r` from the origin heading east, turning
    /// south (right on the map, whose y grows south).
    private func quarter(radius r: Int64) -> (to: WorldCoordinate, curve: TrackCurve) {
        let k = Int64((Double(r) * 0.5523).rounded())
        return (WorldCoordinate(x: r, y: r, z: 0), .cubic(PlanPoint(x: k, y: 0), PlanPoint(x: r, y: r - k)))
    }

    func testTheBandsSplitAt120And70() {
        XCTAssertNil(TrackSpeedBand(speed: nil))
        XCTAssertNil(TrackSpeedBand(speed: 120))
        XCTAssertNil(TrackSpeedBand(speed: 300))
        XCTAssertEqual(TrackSpeedBand(speed: 115), .reduced)
        XCTAssertEqual(TrackSpeedBand(speed: 70), .reduced)
        XCTAssertEqual(TrackSpeedBand(speed: 65), .slow)
        XCTAssertEqual(TrackSpeedBand(speed: CurveSpeedLimit.lowest), .slow)
    }

    /// A 200 m quarter circle is coloured by exactly the limits GameCore
    /// posts on the edge it would build, and its tightest point, in the
    /// middle of the curve, carries the limit there.
    func testATightCurveIsColouredByGameCoresLimits() throws {
        let r = 200 * metre
        let (to, curve) = quarter(radius: r)
        let start = WorldCoordinate(x: 0, y: 0, z: 0)
        let preview = try preview(from: start, to: to, curve: curve)
        let marks = TrackPreviewMarks(preview, curveSpeedLimits: true)

        let geometry = try XCTUnwrap(TrackGeometry(from: start, to: to, curve: curve))
        let limits = CurveSpeedLimit.limits(from: start.plan, to: to.plan, curve: curve, length: geometry.length)
        XCTAssertFalse(limits.isEmpty)
        XCTAssertEqual(marks.stretches.map(\.speed), limits.map(\.speed).filter { $0 < TrackSpeedBand.reducedBelow })
        XCTAssertEqual(marks.lowestSpeed, limits.map(\.speed).min())
        XCTAssertTrue(marks.stretches.allSatisfy { $0.band == .slow }, "about 4.4√200 = 62 km/h")
        for stretch in marks.stretches {
            XCTAssertGreaterThan(stretch.points.count, 1)
        }
        // Together they run the whole curve, end to end.
        XCTAssertEqual(marks.stretches.first?.points.first, geometry.points.first)
        XCTAssertEqual(marks.stretches.last?.points.last, geometry.points.last)

        let tightest = try XCTUnwrap(marks.tightest)
        XCTAssertEqual(tightest.radius / Double(r), 1, accuracy: 0.02)
        // On the drawn line, and carrying the limit of the stretch it is in.
        let index = try XCTUnwrap(geometry.points.firstIndex(of: tightest.position))
        let along = geometry.distances[index]
        XCTAssertEqual(tightest.speed, limits.first { $0.start <= along && along <= $0.end }?.speed)
        XCTAssertEqual(tightest.band, .slow)
        let speed = try XCTUnwrap(tightest.speed)
        XCTAssertEqual(tightest.text(in: .traditionalChinese), "半徑 200 公尺 · \(speed) km/h")
        XCTAssertNil(marks.steepest, "level")

        // The loupe gives the same speed as the colour.
        var withMarks = preview
        withMarks.marks = marks
        XCTAssertEqual(withMarks.radiusText(in: .english, curveSpeedLimits: true), "\(TrackCurvature.radiusText(withMarks.tightestRadius, in: .english)) · up to \(try XCTUnwrap(marks.lowestSpeed)) km/h")
    }

    /// With the curve limits off nothing is coloured, but the tightest curve
    /// is still marked, without a speed; a gentle curve is marked nowhere.
    func testNoColourWithoutLimitsAndNoMarkOnAGentleCurve() throws {
        let (to, curve) = quarter(radius: 200 * metre)
        let marks = TrackPreviewMarks(try preview(from: WorldCoordinate(x: 0, y: 0, z: 0), to: to, curve: curve), curveSpeedLimits: false)
        XCTAssertTrue(marks.stretches.isEmpty)
        XCTAssertNil(marks.lowestSpeed)
        XCTAssertNil(try XCTUnwrap(marks.tightest).speed)
        XCTAssertEqual(try XCTUnwrap(marks.tightest).text(in: .english), "Radius 200 m")

        let (gentleEnd, gentle) = quarter(radius: 2_000 * metre)
        let wide = TrackPreviewMarks(try preview(from: WorldCoordinate(x: 0, y: 0, z: 0), to: gentleEnd, curve: gentle), curveSpeedLimits: true)
        XCTAssertTrue(wide.stretches.isEmpty, "2 km: about 195 km/h")
        XCTAssertNil(wide.tightest)
    }

    /// A stretch that climbs is marked in the middle of its steady grade,
    /// with the grade in per mille, and says when it is too steep to lay.
    func testTheSteepestGradeIsMarkedInTheMiddle() throws {
        let length = 1_000 * metre
        let start = WorldCoordinate(x: 0, y: 0, z: 0)
        // 25 m up over 1 km: 25‰.
        let climb = TrackPreviewMarks(try preview(from: start, to: WorldCoordinate(x: length, y: 0, z: 25 * metre), curve: .straight), curveSpeedLimits: true)
        let steepest = try XCTUnwrap(climb.steepest)
        XCTAssertEqual(steepest.perMille, 25)
        XCTAssertFalse(steepest.tooSteep)
        XCTAssertEqual(steepest.position.x, length / 2)
        XCTAssertEqual(steepest.text(in: .traditionalChinese), "最陡 25‰")
        XCTAssertNil(climb.tightest)

        // Eased at both ends, the steady middle is steeper (decision 164).
        let eased = TrackProfile(startTransition: length / 4, endTransition: length / 4)
        let easedMarks = TrackPreviewMarks(
            try preview(from: start, to: WorldCoordinate(x: length, y: 0, z: 25 * metre), curve: .straight, profile: eased), curveSpeedLimits: true
        )
        XCTAssertEqual(try XCTUnwrap(easedMarks.steepest).perMille, 33)

        let steep = TrackPreviewMarks(try preview(from: start, to: WorldCoordinate(x: length, y: 0, z: 50 * metre), curve: .straight), curveSpeedLimits: true)
        XCTAssertEqual(try XCTUnwrap(steep.steepest).perMille, 50)
        XCTAssertTrue(try XCTUnwrap(steep.steepest).tooSteep)
    }

    // MARK: - Lining up (TRACK-ALIGN)

    func testAnEndNearlyParallelIsDrawnParallel() throws {
        let start = PlanPoint(x: 0, y: 0)
        let length = 10_000.0
        let off = 2.0 * .pi / 180
        let end = PlanPoint(x: Int64((length * cos(off)).rounded()), y: Int64((length * sin(off)).rounded()))
        let track = TrackAlignment.Reference(direction: PlanVector(dx: -5, dy: 0), at: PlanPoint(x: 3_000, y: 2_000), continues: false)
        let (moved, guide) = try XCTUnwrap(TrackAlignment.align(start: start, end: end, references: [track], reach: 100))
        XCTAssertEqual(moved, PlanPoint(x: 10_000, y: 0))
        XCTAssertEqual(guide.kind, .parallel)
        XCTAssertEqual(guide.lines.count, 2, "its own line and a piece along the track")
        XCTAssertEqual(guide.lines[0].first, start)
        XCTAssertEqual(guide.lines[0].last, PlanPoint(x: 10_200, y: 0))
        XCTAssertEqual(guide.lines[1], [PlanPoint(x: 3_300, y: 2_000), PlanPoint(x: 2_700, y: 2_000)])
        XCTAssertEqual(guide.text(in: .traditionalChinese), "與軌道平行")

        // 5° off lines up with nothing.
        let wide = 5.0 * .pi / 180
        let away = PlanPoint(x: Int64((length * cos(wide)).rounded()), y: Int64((length * sin(wide)).rounded()))
        XCTAssertNil(TrackAlignment.align(start: start, end: away, references: [track], reach: 100))
    }

    func testRightAnglesAndStraightOn() throws {
        let start = PlanPoint(x: 0, y: 0)
        let track = TrackAlignment.Reference(direction: PlanVector(dx: 1, dy: 0), at: PlanPoint(x: 0, y: 500), continues: false)
        // 88° from the track.
        let end = PlanPoint(x: 349, y: -9_994)
        let (moved, guide) = try XCTUnwrap(TrackAlignment.align(start: start, end: end, references: [track], reach: 100))
        XCTAssertEqual(guide.kind, .perpendicular)
        XCTAssertEqual(moved, PlanPoint(x: 0, y: -10_000))

        // The track it starts from wins over a nearer angle to another.
        let leaving = TrackAlignment.Reference(direction: PlanVector(dx: 1, dy: 1), at: start, continues: true)
        let other = TrackAlignment.Reference(direction: PlanVector(dx: 100, dy: 101), at: PlanPoint(x: 900, y: 0), continues: false)
        let diagonal = PlanPoint(x: 7_000, y: 7_200)
        let (_, straight) = try XCTUnwrap(TrackAlignment.align(start: start, end: diagonal, references: [other, leaving], reach: 100))
        XCTAssertEqual(straight.kind, .straightOn)
        XCTAssertEqual(straight.lines.count, 1)
        // It cannot be continued backwards.
        let back = PlanPoint(x: -7_000, y: -7_100)
        XCTAssertNil(TrackAlignment.align(start: start, end: back, references: [leaving], reach: 100))
    }

    func testTheTurnIsReadRightAndLeft() throws {
        let (to, curve) = quarter(radius: 200 * metre)
        XCTAssertEqual(TrackAlignment.turn(from: PlanPoint(x: 0, y: 0), to: to.plan, curve: curve), 90)
        let mirrored = TrackCurve.cubic(PlanPoint(x: 7_070, y: 0), PlanPoint(x: 12_800, y: -5_730))
        XCTAssertEqual(TrackAlignment.turn(from: PlanPoint(x: 0, y: 0), to: PlanPoint(x: 12_800, y: -12_800), curve: mirrored), -90)
        XCTAssertEqual(TrackAlignment.turn(from: PlanPoint(x: 0, y: 0), to: PlanPoint(x: 100, y: 0), curve: .straight), 0)
        XCTAssertEqual(TrackAlignment.turnText(90, in: .traditionalChinese), "向右轉 90°")
        XCTAssertEqual(TrackAlignment.turnText(-35, in: .english), "Turns 35° left")
        XCTAssertNil(TrackAlignment.turnText(0, in: .english))
    }

    /// Drawing beside existing track: a finger a degree and a half off its
    /// line puts the end exactly parallel, the map draws the guides while
    /// the finger is down, and lifting it keeps the end and drops them.
    func testDrawingBesideTrackLinesUpWithIt() throws {
        let world = try makeWorld(width: 40_960, height: 20_480, balance: 10_000_000, speed: .paused)
        let session = GameSession(world: world)
        session.selectTool(.network)
        let reach: Int64 = 640
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 4_096), reach: reach)
        session.tapNetwork(at: PlanPoint(x: 30_720, y: 4_096), reach: reach)
        session.buildNetworkTrack()
        XCTAssertEqual(session.world.network.edges.count, 1)

        // 36 m south of it, beyond a tap's reach but within the guide's.
        let from = PlanPoint(x: 2_048, y: 6_400)
        let finger = PlanPoint(x: 30_720, y: 7_100)
        session.dragNetwork(from: from, to: finger, reach: reach)
        XCTAssertEqual(session.networkStart, .point(from))
        XCTAssertEqual(session.networkDragGuide?.kind, .parallel)
        guard case .point(let end)? = session.networkEnd else { return XCTFail("a free end") }
        XCTAssertEqual(end.y, from.y, "exactly parallel")
        XCTAssertEqual(session.networkDragGuideText, "Parallel to the track")
        XCTAssertEqual(session.networkOverlay?.guides.count, 2)

        session.endNetworkDrag(from: from, to: finger, reach: reach)
        XCTAssertNil(session.networkDragGuide)
        XCTAssertEqual(session.networkOverlay?.guides, [])
        XCTAssertEqual(session.networkEnd, .point(end), "the end stays lined up")

        // With snapping off the end is where the finger is.
        session.networkSnapsToTrack = false
        session.dragNetwork(from: from, to: finger, reach: reach)
        XCTAssertEqual(session.networkEnd, .point(finger))
        XCTAssertNil(session.networkDragGuide)
        session.cancelNetworkDrag()
    }

    /// Continuing from the end of the track a little off its line carries
    /// it straight on; the preview's overlay carries its marks.
    func testContinuingTrackStraightOn() throws {
        let world = try makeWorld(width: 40_960, height: 20_480, balance: 10_000_000, speed: .paused)
        let session = GameSession(world: world)
        session.selectTool(.network)
        let reach: Int64 = 640
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 4_096), reach: reach)
        session.tapNetwork(at: PlanPoint(x: 20_480, y: 4_096), reach: reach)
        session.buildNetworkTrack()

        let from = PlanPoint(x: 20_480, y: 4_096)
        let finger = PlanPoint(x: 38_000, y: 4_600)
        session.dragNetwork(from: from, to: finger, reach: reach)
        XCTAssertEqual(session.networkDragGuide?.kind, .straightOn)
        guard case .point(let end)? = session.networkEnd else { return XCTFail("a free end") }
        XCTAssertEqual(end.y, 4_096)
        XCTAssertEqual(session.networkPreview?.turn, 0)

        // Further round: a curve, its turn and its marks.
        let round = PlanPoint(x: 30_000, y: 14_000)
        session.dragNetwork(from: from, to: round, reach: reach)
        XCTAssertNil(session.networkDragGuide)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertGreaterThan(preview.turn, 0, "south of east is to the right")
        XCTAssertEqual(session.networkDragGuideText, TrackAlignment.turnText(preview.turn, in: session.language))
        XCTAssertNotNil(preview.marks)
        session.endNetworkDrag(from: from, to: round, reach: reach)
        XCTAssertNil(session.networkDragGuideText, "only while the finger is down")
    }

    /// The screenshot scenes show what they are for: a slow curve with
    /// its marks, and a held finger lined up parallel.
    func testTheScreenshotScenes() throws {
        let curve = GameSession(world: ScreenshotScene.trackCurve.make(in: .traditionalChinese), language: .traditionalChinese)
        ScreenshotScene.prepareTrackCurve(curve, holdsFinger: false)
        let marks = try XCTUnwrap(curve.networkPreview?.marks)
        XCTAssertNil(curve.networkPreview?.problem)
        XCTAssertTrue(marks.stretches.contains { $0.band == .slow })
        XCTAssertNotNil(marks.tightest?.speed)
        XCTAssertNotNil(marks.steepest)
        XCTAssertEqual(curve.networkOverlay?.marks.count, 2)

        let align = GameSession(world: ScreenshotScene.trackAlign.make(in: .traditionalChinese), language: .traditionalChinese)
        ScreenshotScene.prepareTrackCurve(align, holdsFinger: true)
        XCTAssertEqual(align.networkDragGuide?.kind, .parallel)
        XCTAssertEqual(align.networkDragGuideText, "與軌道平行")
        XCTAssertNotNil(align.networkDragFinger)
    }
}
