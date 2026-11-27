// LANDMARK-PLINTH: a registered landmark that stands on level ground where
// the map's ground slopes under it (``Map3DLandmarkRegistration/plinth``).
// The map's ground is laid on a 64 m grid, so a hall whose real precinct
// is level gets a slope under it (Dazaifu's hall 2.6 m, its gate 1.4 m);
// stood on the lowest ground, its uphill side was sunk, the hall's front
// porch and railing cut off by the ground (the owner's screenshot of
// build 153, 2026-11-27). Such a landmark stands on the highest ground
// under its foot instead, on a base down to the lowest.

extension LandmarkMesh {
    /// How far below the lowest ground under it the base reaches, so its
    /// foot is not seen where the ground between the samples dips.
    static let plinthTuck: Float = 0.3

    /// The outline round the model's foot (its vertices within half a
    /// metre of its lowest, model metres east and north), counter-clockwise
    /// seen from above, and that lowest height; `nil` when it has fewer
    /// than three corners.
    func footOutline() -> (ring: [P2], z: Float)? {
        guard let low = vertices.map(\.z).min() else { return nil }
        var foot: [P2] = []
        for vertex in vertices where vertex.z <= low + 0.5 { foot.append((x: vertex.x, y: vertex.y)) }
        let ring = Self.convexHull(foot)
        guard ring.count >= 3 else { return nil }
        return (ring: ring, z: low)
    }

    /// The points the ground under `ring` is read at: its corners and a
    /// grid `step` metres apart inside it.
    static func plinthSamples(_ ring: [P2], step: Float = 4) -> [P2] {
        guard let x0 = ring.map(\.x).min(), let x1 = ring.map(\.x).max(),
              let y0 = ring.map(\.y).min(), let y1 = ring.map(\.y).max() else { return [] }
        var points = ring
        var x = x0
        while x <= x1 {
            var y = y0
            while y <= y1 {
                if contains(ring, (x: x, y: y)) { points.append((x: x, y: y)) }
                y += step
            }
            x += step
        }
        return points
    }

    /// A base of `colour` under the model: walls round `ring` from `top`
    /// down to `bottom`, capped at `top`.
    mutating func addPlinth(_ ring: [P2], top: Float, bottom: Float, colour: UInt32) {
        guard top > bottom else { return }
        wallBand(ring, bottom, ring, top, colour, Self.plain)
        cap(ring, top, colour)
    }

    /// Whether `point` is inside (or on) the counter-clockwise convex `ring`.
    static func contains(_ ring: [P2], _ point: P2) -> Bool {
        ring.indices.allSatisfy { k in
            let a = ring[k], b = ring[(k + 1) % ring.count]
            return (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x) >= -1e-3
        }
    }

    /// The convex hull of `points`, counter-clockwise (Andrew's monotone
    /// chain), without points on its edges.
    static func convexHull(_ points: [P2]) -> [P2] {
        let sorted = points.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard sorted.count >= 3 else { return sorted }
        func turn(_ o: P2, _ a: P2, _ b: P2) -> Float { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [P2] = [], upper: [P2] = []
        for p in sorted {
            while lower.count >= 2, turn(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2, turn(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}
