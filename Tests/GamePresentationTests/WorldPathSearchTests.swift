@testable import GamePresentation
import XCTest

/// `WorldPath.nearest(_:)` and `point(at:)` were rewritten for speed: the
/// coordinates written out, and the last point before a distance found by
/// halving. These compare them, to the bit, with the vector arithmetic and
/// the scan they replaced, on paths with kinks, repeated distances' edges
/// and points far off.
final class WorldPathSearchTests: XCTestCase {
    /// The scan `nearest(_:)` replaced.
    private func scannedNearest(_ path: WorldPath, _ point: WorldVector) -> (along: Double, away: Double) {
        var best = (along: 0.0, away: Double.infinity)
        for index in path.points.indices.dropLast() {
            let a = path.points[index], b = path.points[index + 1]
            let along = b - a
            let squared = along.dot(along)
            let t = squared > 0 ? max(0, min(1, (point - a).dot(along) / squared)) : 0
            let away = (a + along * t - point).length
            if away < best.away {
                best = (path.distances[index] + t * (path.distances[index + 1] - path.distances[index]), away)
            }
        }
        return best
    }

    /// The scan `point(at:)` replaced.
    private func scannedPoint(_ path: WorldPath, at distance: Double) -> WorldVector {
        let distance = min(max(distance, 0), path.length)
        guard let index = path.distances.lastIndex(where: { $0 <= distance }), index < path.points.count - 1 else {
            return path.points[path.points.count - 1]
        }
        let a = path.distances[index], b = path.distances[index + 1]
        let t = b > a ? (distance - a) / (b - a) : 0
        return path.points[index] + (path.points[index + 1] - path.points[index]) * t
    }

    func testTheSearchesAnswerAsTheScansDid() {
        // A fixed sequence, so the test asks the same every run.
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        let metre = 64.0
        for count in [1, 2, 3, 7, 40, 300] {
            var points: [WorldVector] = []
            var x = 0.0, y = 0.0
            for _ in 0..<count {
                points.append(WorldVector(x: x, y: y))
                x += (next() * 200 - 20) * metre
                y += (next() * 200 - 100) * metre
            }
            let path = WorldPath(points)
            for _ in 0..<200 {
                let point = WorldVector(x: (next() * 2.4 - 0.2) * max(x, metre), y: (next() * 2 - 1) * 20_000 * metre)
                let found = path.nearest(point), scanned = scannedNearest(path, point)
                XCTAssertEqual(found.along.bitPattern, scanned.along.bitPattern)
                XCTAssertEqual(found.away.bitPattern, scanned.away.bitPattern)
                for distance in [next() * path.length, -metre, path.length + metre, path.length, 0, path.distances[path.distances.count / 2]] {
                    let at = path.point(at: distance), scannedAt = scannedPoint(path, at: distance)
                    XCTAssertEqual(at.x.bitPattern, scannedAt.x.bitPattern)
                    XCTAssertEqual(at.y.bitPattern, scannedAt.y.bitPattern)
                }
            }
        }
    }
}
