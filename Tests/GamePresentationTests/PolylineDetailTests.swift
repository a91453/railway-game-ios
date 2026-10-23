import GameCore
@testable import GamePresentation
import XCTest

/// Decision 377: the flat map draws each edge with the points its zoom
/// shows (``PolylineDetail``), and the line drawn stays within the
/// tolerance of the whole one.
final class PolylineDetailTests: XCTestCase {
    /// A quarter circle of a kilometre, sampled about a metre apart.
    private func curve() throws -> TrackGeometry {
        let r = 1_000 * WorldCoordinate.unitsPerMetre, k = r * 5523 / 10_000
        return try XCTUnwrap(TrackGeometry(
            from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: r, y: r),
            curve: .cubic(PlanPoint(x: k, y: 0), PlanPoint(x: r, y: r - k))
        ))
    }

    func testBelowZeroItLeavesNothingOut() throws {
        let geometry = try curve()
        let detail = PolylineDetail(geometry.points)
        for (start, end) in [(Int64(0), geometry.length), (1_234, 40_000), (0, 77), (geometry.length / 2, geometry.length)] {
            XCTAssertEqual(geometry.points(from: start, to: end, detail: detail, tolerance: -1), geometry.points(from: start, to: end))
        }
    }

    func testTheEndsAreKeptAndAStraightLineIsTwoPoints() throws {
        let geometry = try XCTUnwrap(TrackGeometry(
            from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 5_000 * WorldCoordinate.unitsPerMetre, y: 0), curve: .straight
        ))
        let detail = PolylineDetail(geometry.points)
        XCTAssertEqual(detail.significance.first, .infinity)
        XCTAssertEqual(detail.significance.last, .infinity)
        XCTAssertEqual(geometry.points(from: 0, to: geometry.length, detail: detail, tolerance: 0), [geometry.points[0], geometry.points[geometry.points.count - 1]])
    }

    /// Every point of the whole line lies within the tolerance of the line
    /// drawn (twice it next to a cut end), and fewer points are drawn the
    /// further out the map is.
    func testTheLineDrawnStaysWithinTheTolerance() throws {
        let geometry = try curve()
        let detail = PolylineDetail(geometry.points)
        var drawn = Int.max
        for tolerance in [16.0, 64, 256, 1_024, 4_096] {
            for (start, end) in [(Int64(0), geometry.length), (12_345, geometry.length - 6_789)] {
                let whole = geometry.points(from: start, to: end)
                let kept = geometry.points(from: start, to: end, detail: detail, tolerance: tolerance)
                for point in whole {
                    XCTAssertLessThanOrEqual(Self.distance(from: point, to: kept), tolerance * (start == 0 ? 1 : 2) + 1, "at \(tolerance)")
                }
                if start == 0 {
                    XCTAssertLessThan(kept.count, drawn, "at \(tolerance)")
                    drawn = kept.count
                }
            }
        }
        XCTAssertGreaterThan(geometry.points.count, 500)
        XCTAssertLessThan(drawn, 10)
    }

    func testTheToleranceIsAQuarterOfAPointOfTheScreen() {
        XCTAssertEqual(PolylineDetail.tolerance(pointsPerUnit: 0.5), 0.5)
        XCTAssertEqual(PolylineDetail.tolerance(pointsPerUnit: 0), 0)
    }

    static func distance(from point: WorldCoordinate, to line: [WorldCoordinate]) -> Double {
        var best = Double.infinity
        for index in line.indices.dropFirst() {
            let a = line[index - 1], b = line[index]
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y), px = Double(point.x - a.x), py = Double(point.y - a.y)
            let squared = dx * dx + dy * dy
            let t = squared > 0 ? min(max((px * dx + py * dy) / squared, 0), 1) : 0
            let ex = px - t * dx, ey = py - t * dy
            best = min(best, (ex * ex + ey * ey).squareRoot())
        }
        return best
    }
}
