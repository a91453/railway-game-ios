import GameCore
@testable import GamePresentation
import XCTest

/// Decision 380: the cab view held steady, and the overhead line drawn
/// close up all along. (The high-speed demo's own cab view and wires are
/// checked in ``Map3DSceneMemoryTests``, which opens the demo.)
///
/// The owner's 85.1 video of the high-speed demo's cab view at 1× shook
/// left and right by about 2 px (of 640) from frame to frame, the sign
/// changing each frame: the track's points, sampled about a metre apart
/// and rounded to the world's 1/64 m, turn this way and that by up to a
/// degree, and the cab faced the way the piece of track under the train's
/// head ran, a new one nearly every frame.
final class Map3DCabTests: XCTestCase {
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A straight track due east, a point every 0.92 m, each a world unit
    /// north or south of the line, or on it, as rounding leaves them.
    private func zigzag() -> TrainMotion.Trail {
        let offsets: [Double] = [0, 1, -1, 1, 0, -1, 0, 0, 1, -1]
        let points = (0..<400).map { index in
            TrainMotion.Point(x: Double(400 - index) * 0.92 * metre, y: offsets[index % offsets.count])
        }
        return TrainMotion.Trail(points)
    }

    private func run(on trail: TrainMotion.Trail) -> TrainMotion.Run {
        TrainMotion.Run(train: TrainID(rawValue: 1), look: .plain, isHighSpeed: true, livery: .of(type: nil, performance: .standard),
                        trail: trail, lag: 100 * metre, length: 200 * metre, carPitch: 20 * metre, heading: TrainMotion.Point(x: 1, y: 0))
    }

    /// On the rounded straight track, the steady head faces east within a
    /// fiftieth of a degree and stays within half a unit of the line,
    /// wherever it is; the piece of track under the head turns up to two
    /// degrees.
    func testTheSteadyHeadRunsStraightOnRoundedTrack() throws {
        let run = run(on: zigzag())
        var worst = (angle: 0.0, aside: 0.0, piece: 0.0)
        for step in 0...600 {
            let progress = Double(step) / 600
            let steady = try XCTUnwrap(run.steadyHead(at: progress, over: Map3DTrains.steadySpan))
            worst.angle = max(worst.angle, abs(atan2(steady.heading.y, steady.heading.x)))
            worst.aside = max(worst.aside, abs(steady.point.y))
            if let piece = run.head(at: progress)?.heading { worst.piece = max(worst.piece, abs(atan2(piece.y, piece.x))) }
        }
        XCTAssertLessThan(worst.angle, 0.0004)
        XCTAssertLessThan(worst.aside, 0.5)
        XCTAssertGreaterThan(worst.piece, 0.02, "the pieces of track themselves turn")
        XCTAssertNil(run.steadyHead(at: 1, over: 100_000 * metre), "too little track behind the head")
    }

    /// On a 300 m curve (a tight one on TRA's lines), sampled every metre,
    /// the steady head faces along the curve at the head, within a tenth
    /// of a degree: no lag behind it, as a chord back along it would have
    /// (a 40 m chord, nearly 4°). It stands within 10 cm inside the curve.
    func testTheSteadyHeadFollowsACurve() throws {
        let radius = 300 * metre
        let points = (0..<300).map { index in
            let angle = Double(index) * metre / radius
            return TrainMotion.Point(x: (radius * cos(angle)).rounded(), y: (radius * sin(angle)).rounded())
        }
        let run = run(on: TrainMotion.Trail(points))
        for progress in [0.0, 0.5, 1] {
            let steady = try XCTUnwrap(run.steadyHead(at: progress, over: Map3DTrains.steadySpan))
            let along = 100 * metre * (1 - progress)
            let angle = along / radius
            // Running towards the trail's start: clockwise round the curve.
            let tangent = (x: sin(angle), y: -cos(angle))
            XCTAssertLessThan(abs(steady.heading.x * tangent.y - steady.heading.y * tangent.x), 0.002, "at \(progress)")
            XCTAssertGreaterThan(steady.heading.x * tangent.x + steady.heading.y * tangent.y, 0)
            XCTAssertEqual(steady.point.x, radius * cos(angle), accuracy: 0.1 * metre)
            XCTAssertEqual(steady.point.y, radius * sin(angle), accuracy: 0.1 * metre)
        }
    }

    /// A coarse chunk draws its closest detail, the overhead line, close
    /// up, as a chunk drawn in full does; neither does from afar, nor a
    /// chunk in full drawn simplified.
    func testACoarseChunkDrawsItsWiresCloseUp() {
        let camera = Map3DCamera(target: Map3DPoint(0, 0, 0), distance: 60, viewport: (390, 844))
        let near = (Map3DPoint(-100, 0, -100), Map3DPoint(400, 20, 400)), far = (Map3DPoint(3_000, 0, 3_000), Map3DPoint(3_512, 20, 3_512))
        XCTAssertTrue(camera.drawsClose(minimum: near.0, maximum: near.1, detailed: true, coarse: false))
        XCTAssertTrue(camera.drawsClose(minimum: near.0, maximum: near.1, detailed: false, coarse: true))
        XCTAssertFalse(camera.drawsClose(minimum: near.0, maximum: near.1, detailed: false, coarse: false))
        XCTAssertFalse(camera.drawsClose(minimum: far.0, maximum: far.1, detailed: false, coarse: true))
    }
}
