import GameCore

/// Decision 377 (TestFlight 84.1: the whole High Speed Rail on the flat
/// map, the track and its lines drawn at up to 375 ms a time): how much of
/// a polyline is worth drawing at a zoom. A track's centre line is sampled
/// about a metre apart (``TrackGeometry``), so the whole line on a phone's
/// screen drew hundreds of thousands of points, hundreds to a point of
/// screen, for each of the lines over it. Each point's significance is the
/// Douglas–Peucker tolerance up to which it is kept (Douglas and Peucker,
/// 1973, the simplification MapLibre and OSM tools use; written here, no
/// code taken): worked out once for an edge, it gives the simplified line
/// at any zoom by leaving out the points not significant enough.
public struct PolylineDetail: Equatable, Sendable {
    /// Of each point, the largest tolerance, in world units, at which the
    /// simplification keeps it: the ends are always kept (infinity), a
    /// point on the straight line between its neighbours never (0).
    public let significance: [Double]

    /// How far a simplified line may stray from the whole one on the
    /// screen, in points: a quarter of a point, under a pixel on every
    /// screen, so the map looks the same.
    public static let screenTolerance = 0.25

    /// The tolerance in world units at `pointsPerUnit`.
    public static func tolerance(pointsPerUnit: Double) -> Double {
        pointsPerUnit > 0 ? screenTolerance / pointsPerUnit : 0
    }

    public init(_ points: [WorldCoordinate]) {
        let count = points.count
        var significance = [Double](repeating: 0, count: count)
        if count > 0 {
            significance[0] = .infinity
            significance[count - 1] = .infinity
        }
        // Each stretch to split, and the most its points may keep: a point
        // is kept only while the split that made its stretch is, so the
        // points kept at a tolerance are the ones Douglas–Peucker keeps.
        var stretches: [(first: Int, last: Int, limit: Double)] = count > 2 ? [(0, count - 1, .infinity)] : []
        while let (first, last, limit) = stretches.popLast() {
            guard last - first > 1 else { continue }
            let ax = Double(points[first].x), ay = Double(points[first].y)
            let dx = Double(points[last].x) - ax, dy = Double(points[last].y) - ay
            let squared = dx * dx + dy * dy
            var farthest = first + 1, distance = -1.0
            for index in (first + 1)..<last {
                let px = Double(points[index].x) - ax, py = Double(points[index].y) - ay
                // Its distance from the chord (as a segment, not a line).
                let t = squared > 0 ? min(max((px * dx + py * dy) / squared, 0), 1) : 0
                let ex = px - t * dx, ey = py - t * dy
                let away = (ex * ex + ey * ey).squareRoot()
                if away > distance {
                    distance = away
                    farthest = index
                }
            }
            let kept = min(distance, limit)
            significance[farthest] = kept
            stretches.append((first, farthest, kept))
            stretches.append((farthest, last, kept))
        }
        self.significance = significance
    }
}

extension TrackGeometry {
    /// ``points(from:to:)`` without the points `detail` (this geometry's
    /// own) leaves out at `tolerance`, in world units: every point of the
    /// whole line lies within `tolerance` of the line returned, or twice
    /// that between a cut end and the first point kept. A tolerance below
    /// 0 leaves none out.
    ///
    /// - Precondition: `0 <= start < end <= length`.
    public func points(from start: Int64, to end: Int64, detail: PolylineDetail, tolerance: Double) -> [WorldCoordinate] {
        precondition(start >= 0 && start < end && end <= length, "points(from:to:detail:tolerance:) needs a stretch of the edge")
        var result = [location(at: start).position]
        // The first point beyond `start`.
        var low = 0, high = distances.count
        while low < high {
            let middle = (low + high) / 2
            if distances[middle] > start { high = middle } else { low = middle + 1 }
        }
        var index = low
        while index < distances.count, distances[index] < end {
            if detail.significance[index] > tolerance, points[index].plan != result[result.count - 1].plan {
                result.append(points[index])
            }
            index += 1
        }
        let last = location(at: end).position
        if last.plan != result[result.count - 1].plan { result.append(last) }
        return result
    }
}
