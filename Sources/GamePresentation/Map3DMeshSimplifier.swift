import Foundation

/// Decision 420: fewer triangles for a model drawn small, made in the game.
///
/// Garland and Heckbert's quadric error edge collapses (1997), as decision
/// 408's `tools/hsr-trains-408/decimate.py` makes the N700S-G's cars
/// offline, ported here so every model the game builds gets its own
/// lighter versions: the corners welded where they meet, then half-edge
/// collapses, cheapest first, until a target is left. A corner only moves
/// onto a neighbour, so no new points appear and the model's box stays.
///
/// Colour is kept as the models paint it, by triangle: an edge between two
/// colours (a stripe's edge, a window's frame, a door) or with only one
/// triangle (an open edge, a part's outline) is a seam, held in place by a
/// plane standing upright on it, weighed 50 times a surface's. A corner on
/// one seam only slides along it, onto its neighbour on the same seam;
/// where seams meet (a window's corner) it stays. A collapse that would
/// turn a triangle over, leave it nearly flat or join two surfaces (the
/// link condition) is not made. Each triangle keeps its own corners'
/// colours and gets its own normal again (flat, the miniature look).
///
/// The same corners give the same triangles on every device: the order is
/// the cost, then the vertex numbers.
public enum Map3DMeshSimplifier {
    /// Corners closer than this, metres, are one vertex.
    static let weldStep: Double = 1e-4
    /// How much more a seam's plane weighs than a surface's.
    static let seamWeight: Double = 50

    /// `corners` (three to a triangle) with as few triangles left as each
    /// of `targets` asks, largest first; a target the collapses cannot
    /// reach gets the fewest they could leave. `areaWeighted`: whether a
    /// surface's error is weighed by its area (`decimate.py`'s choice per
    /// car; without it a small curved part costs as much as a large flat
    /// one).
    public static func simplify(_ corners: [Map3DVertex], targets: [Int], areaWeighted: Bool = true) -> [[Map3DVertex]] {
        var collapser = Collapser(corners: corners, areaWeighted: areaWeighted)
        return collapser.run(targets: targets.sorted(by: >))
    }
}

extension Map3DModelPack.Model {
    /// Decision 420: this model with about `share` of its triangles, its
    /// name and box as they are (a car's length lays out its train).
    public func simplified(to share: Double) -> Map3DModelPack.Model {
        simplified(to: [share])[0]
    }

    /// One model for each of `shares` (each from this model's triangles,
    /// made in one run, largest share first).
    public func simplified(to shares: [Double]) -> [Map3DModelPack.Model] {
        let targets = shares.map { Int((Double(triangleCount) * $0).rounded()) }
        let made = Map3DMeshSimplifier.simplify(vertices, targets: targets)
        let byTarget = Dictionary(zip(targets.sorted(by: >), made), uniquingKeysWith: { first, _ in first })
        return targets.map { Map3DModelPack.Model(name: name, vertices: byTarget[$0] ?? vertices, minimum: minimum, maximum: maximum) }
    }
}

extension Map3DMesh {
    /// Decision 420: this mesh with about `share` of its triangles, each
    /// with its own corners and flat normal.
    public func simplified(to share: Double) -> Map3DMesh {
        let corners = indices.map { vertices[Int($0)] }
        let target = Int((Double(triangleCount) * share).rounded())
        let made = Map3DMeshSimplifier.simplify(corners, targets: [target])[0]
        return Map3DMesh(vertices: made, indices: (0..<UInt32(made.count)).map { $0 })
    }
}

/// A symmetric 4 × 4 quadric, its upper triangle.
private struct Quadric {
    var a00 = 0.0, a01 = 0.0, a02 = 0.0, a03 = 0.0
    var a11 = 0.0, a12 = 0.0, a13 = 0.0
    var a22 = 0.0, a23 = 0.0
    var a33 = 0.0

    /// The plane `n·p + d = 0`'s, `weight` times.
    init(plane n: SIMD3<Double>, _ d: Double, weight: Double) {
        a00 = n.x * n.x * weight; a01 = n.x * n.y * weight; a02 = n.x * n.z * weight; a03 = n.x * d * weight
        a11 = n.y * n.y * weight; a12 = n.y * n.z * weight; a13 = n.y * d * weight
        a22 = n.z * n.z * weight; a23 = n.z * d * weight
        a33 = d * d * weight
    }

    init() {}

    static func += (q: inout Quadric, r: Quadric) {
        q.a00 += r.a00; q.a01 += r.a01; q.a02 += r.a02; q.a03 += r.a03
        q.a11 += r.a11; q.a12 += r.a12; q.a13 += r.a13
        q.a22 += r.a22; q.a23 += r.a23
        q.a33 += r.a33
    }

    /// The error at `p`.
    func error(at p: SIMD3<Double>) -> Double {
        let x = p.x, y = p.y, z = p.z
        return a00 * x * x + 2 * a01 * x * y + 2 * a02 * x * z + 2 * a03 * x
            + a11 * y * y + 2 * a12 * y * z + 2 * a13 * y
            + a22 * z * z + 2 * a23 * z + a33
    }
}

/// One collapse waiting its turn: `u` onto `v` for `cost`, while neither
/// has changed since (their versions).
private struct Candidate {
    let cost: Double
    let u: Int32, v: Int32
    let versionU: UInt32, versionV: UInt32

    static func < (a: Candidate, b: Candidate) -> Bool {
        if a.cost != b.cost { return a.cost < b.cost }
        if a.u != b.u { return a.u < b.u }
        if a.v != b.v { return a.v < b.v }
        if a.versionU != b.versionU { return a.versionU < b.versionU }
        return a.versionV < b.versionV
    }
}

/// The cheapest candidate first.
private struct CandidateHeap {
    private var items: [Candidate] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func push(_ item: Candidate) {
        items.append(item)
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child] < items[parent] else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Candidate? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var parent = 0
            while true {
                let left = parent * 2 + 1, right = left + 1
                var smallest = parent
                if left < items.count, items[left] < items[smallest] { smallest = left }
                if right < items.count, items[right] < items[smallest] { smallest = right }
                if smallest == parent { break }
                items.swapAt(parent, smallest)
                parent = smallest
            }
        }
        return first
    }
}

private struct Collapser {
    let corners: [Map3DVertex]
    /// Each welded vertex's place.
    var points: [SIMD3<Double>] = []
    /// Each triangle's three welded vertices, corner by corner as `corners`.
    var faces: [SIMD3<Int32>] = []
    /// Each triangle's paint: triangles of one colour share it; a triangle
    /// whose corners differ has its own.
    var paint: [Int32] = []
    var alive: [Bool] = []
    /// The triangles round each vertex.
    var around: [[Int32]] = []
    var quadrics: [Quadric] = []
    var version: [UInt32] = []
    var heap = CandidateHeap()
    var count = 0

    init(corners: [Map3DVertex], areaWeighted: Bool) {
        self.corners = corners
        let triangles = corners.count / 3
        var index: [SIMD3<Int64>: Int32] = [:]
        var paints: [PaintKey: Int32] = [:]
        faces.reserveCapacity(triangles)
        for t in 0..<triangles {
            var face = SIMD3<Int32>(repeating: 0)
            for k in 0..<3 {
                let c = corners[t * 3 + k]
                let p = SIMD3<Double>(Double(c.x), Double(c.y), Double(c.z))
                let key = SIMD3<Int64>(Int64((p.x / Map3DMeshSimplifier.weldStep).rounded()),
                                       Int64((p.y / Map3DMeshSimplifier.weldStep).rounded()),
                                       Int64((p.z / Map3DMeshSimplifier.weldStep).rounded()))
                if let found = index[key] {
                    face[k] = found
                } else {
                    let new = Int32(points.count)
                    index[key] = new
                    points.append(p)
                    face[k] = new
                }
            }
            let a = corners[t * 3], b = corners[t * 3 + 1], c = corners[t * 3 + 2]
            let key: PaintKey
            if PaintKey(a) == PaintKey(b), PaintKey(a) == PaintKey(c) {
                key = PaintKey(a)
            } else {
                key = PaintKey(own: t)
            }
            if let found = paints[key] {
                paint.append(found)
            } else {
                let new = Int32(paints.count)
                paints[key] = new
                paint.append(new)
            }
            faces.append(face)
        }
        alive = Array(repeating: true, count: faces.count)
        around = Array(repeating: [], count: points.count)
        for (i, f) in faces.enumerated() {
            for k in 0..<3 where !around[Int(f[k])].contains(Int32(i)) { around[Int(f[k])].append(Int32(i)) }
        }
        // A triangle with a corner twice is no surface.
        for (i, f) in faces.enumerated() where f[0] == f[1] || f[1] == f[2] || f[0] == f[2] {
            remove(face: i)
        }
        count = alive.lazy.filter { $0 }.count
        quadrics = Array(repeating: Quadric(), count: points.count)
        version = Array(repeating: 0, count: points.count)
        for (i, f) in faces.enumerated() where alive[i] {
            guard let (n, d, area) = plane(f) else { continue }
            let q = Quadric(plane: n, d, weight: areaWeighted ? area : 1)
            for k in 0..<3 { quadrics[Int(f[k])] += q }
        }
        // A plane through each seam, upright on its triangles, holds it in
        // place.
        var done = Set<SIMD2<Int32>>()
        for (i, f) in faces.enumerated() where alive[i] {
            for k in 0..<3 {
                let u = f[k], v = f[(k + 1) % 3]
                let edge = SIMD2(min(u, v), max(u, v))
                guard !done.contains(edge), isSeam(u, v) else { continue }
                done.insert(edge)
                let along = points[Int(v)] - points[Int(u)]
                let length = (along * along).sum().squareRoot()
                guard length > 1e-12 else { continue }
                for j in shared(u, v) {
                    guard let (n, _, _) = plane(faces[Int(j)]) else { continue }
                    guard let m = normalized(cross(along / length, n)) else { continue }
                    let q = Quadric(plane: m, -(m * points[Int(u)]).sum(),
                                    weight: (areaWeighted ? length * length : 1) * Map3DMeshSimplifier.seamWeight)
                    quadrics[Int(u)] += q
                    quadrics[Int(v)] += q
                }
            }
        }
    }

    mutating func run(targets: [Int]) -> [[Map3DVertex]] {
        var made: [[Map3DVertex]] = []
        var next = 0
        while next < targets.count, count <= targets[next] {
            made.append(output()); next += 1
        }
        guard next < targets.count else { return made }
        for u in 0..<Int32(points.count) where !around[Int(u)].isEmpty { push(u) }
        while next < targets.count, let candidate = heap.pop() {
            let u = candidate.u, v = candidate.v
            guard version[Int(u)] == candidate.versionU, version[Int(v)] == candidate.versionV,
                  !around[Int(u)].isEmpty, !around[Int(v)].isEmpty, isValid(u, onto: v) else { continue }
            collapse(u, onto: v)
            while next < targets.count, count <= targets[next] {
                made.append(output()); next += 1
            }
        }
        while next < targets.count {
            made.append(output()); next += 1
        }
        return made
    }

    // MARK: - Collapsing

    private mutating func collapse(_ u: Int32, onto v: Int32) {
        for i in shared(u, v) {
            remove(face: Int(i))
            count -= 1
        }
        for i in around[Int(u)] {
            for k in 0..<3 where faces[Int(i)][k] == u { faces[Int(i)][k] = v }
            around[Int(v)].append(i)
        }
        around[Int(u)] = []
        quadrics[Int(v)] += quadrics[Int(u)]
        let ring = neighbours(v)
        version[Int(u)] &+= 1
        version[Int(v)] &+= 1
        for w in ring { version[Int(w)] &+= 1 }
        push(v)
        for w in ring { push(w) }
    }

    private mutating func remove(face i: Int) {
        alive[i] = false
        for k in 0..<3 {
            let v = Int(faces[i][k])
            if let at = around[v].firstIndex(of: Int32(i)) { around[v].remove(at: at) }
        }
    }

    private mutating func push(_ u: Int32) {
        for v in neighbours(u) {
            let q = quadrics[Int(u)].sum(quadrics[Int(v)])
            heap.push(Candidate(cost: q.error(at: points[Int(v)]), u: u, v: v,
                                versionU: version[Int(u)], versionV: version[Int(v)]))
        }
    }

    // MARK: - Which collapses may be made

    private func isValid(_ u: Int32, onto v: Int32) -> Bool {
        let ring = neighbours(u)
        var along: [Int32] = []
        for w in ring where isSeam(u, w) { along.append(w) }
        if !along.isEmpty {
            // On one seam, its corner slides along it; elsewhere it stays.
            var paints: [Int32] = []
            for i in around[Int(u)] where !paints.contains(paint[Int(i)]) { paints.append(paint[Int(i)]) }
            guard along.count == 2, paints.count <= 2, along.contains(v) else { return false }
        }
        let both = shared(u, v)
        guard !both.isEmpty else { return false }
        // The link condition: the two share no neighbour but the corners
        // of their shared triangles.
        var opposite: [Int32] = []
        for i in both {
            for k in 0..<3 {
                let w = faces[Int(i)][k]
                if w != u, w != v, !opposite.contains(w) { opposite.append(w) }
            }
        }
        let theirs = neighbours(v)
        var common = 0
        for w in ring where w != v && theirs.contains(w) {
            guard opposite.contains(w) else { return false }
            common += 1
        }
        guard common == opposite.count else { return false }
        for i in around[Int(u)] where !both.contains(i) {
            let f = faces[Int(i)]
            var g = f
            for k in 0..<3 where g[k] == u { g[k] = v }
            let p0 = points[Int(f[0])], p1 = points[Int(f[1])], p2 = points[Int(f[2])]
            let q0 = points[Int(g[0])], q1 = points[Int(g[1])], q2 = points[Int(g[2])]
            let n0 = cross(p1 - p0, p2 - p0), n1 = cross(q1 - q0, q2 - q0)
            let l0 = length(n0), l1 = length(n1)
            // Not over, nor turned more than 60°,
            if l1 < 1e-10 || (l0 > 1e-12 && (n0 * n1).sum() / (l0 * l1) < 0.5) { return false }
            // nor a sliver.
            let longest = max(length(q1 - q0), length(q2 - q1), length(q0 - q2))
            if l1 / (longest * longest) < 0.02 { return false }
        }
        return true
    }

    /// An edge with other than two triangles, or between two paints.
    private func isSeam(_ u: Int32, _ v: Int32) -> Bool {
        let both = shared(u, v)
        return both.count != 2 || paint[Int(both[0])] != paint[Int(both[1])]
    }

    private func shared(_ u: Int32, _ v: Int32) -> [Int32] {
        around[Int(u)].filter { i in
            let f = faces[Int(i)]
            return f[0] == v || f[1] == v || f[2] == v
        }
    }

    /// The vertices joined to `u`, in order.
    private func neighbours(_ u: Int32) -> [Int32] {
        var out: [Int32] = []
        out.reserveCapacity(around[Int(u)].count * 2)
        for i in around[Int(u)] {
            let f = faces[Int(i)]
            for k in 0..<3 where f[k] != u { out.append(f[k]) }
        }
        out.sort()
        var unique: [Int32] = []
        unique.reserveCapacity(out.count)
        for w in out where unique.last != w { unique.append(w) }
        return unique
    }

    private func plane(_ f: SIMD3<Int32>) -> (SIMD3<Double>, Double, Double)? {
        let a = points[Int(f[0])], b = points[Int(f[1])], c = points[Int(f[2])]
        let n = cross(b - a, c - a), size = length(n)
        guard size >= 1e-12 else { return nil }
        let unit = n / size
        return (unit, -(unit * a).sum(), size / 2)
    }

    // MARK: - Output

    /// The triangles left, in their first order, each corner's colour as
    /// it was and the triangle's own normal again, turned the way its
    /// first one was.
    private func output() -> [Map3DVertex] {
        var out: [Map3DVertex] = []
        out.reserveCapacity(count * 3)
        for (i, f) in faces.enumerated() where alive[i] {
            let a = points[Int(f[0])], b = points[Int(f[1])], c = points[Int(f[2])]
            guard let unit = normalized(cross(b - a, c - a)) else { continue }
            let first = corners[i * 3]
            let was = SIMD3<Double>(Double(first.nx), Double(first.ny), Double(first.nz))
            let normal = (unit * was).sum() < 0 ? -unit : unit
            let n = Map3DPoint(Float(normal.x), Float(normal.y), Float(normal.z))
            for k in 0..<3 {
                let corner = corners[i * 3 + k], p = points[Int(f[k])]
                out.append(Map3DVertex(Map3DPoint(Float(p.x), Float(p.y), Float(p.z)), normal: n, color: corner.color,
                                       u: corner.u, v: corner.v, layer: corner.layer))
            }
        }
        return out
    }
}

/// What makes two triangles one paint: the colour, its share of the line's
/// colour (alpha), the shader's layer and the texture's place.
private struct PaintKey: Hashable {
    let color: UInt32
    let layer: Float
    let u: Float, v: Float
    /// A triangle whose corners differ: its number, so it is its own.
    let own: Int

    init(_ corner: Map3DVertex) {
        color = corner.color; layer = corner.layer; u = corner.u; v = corner.v; own = -1
    }

    init(own triangle: Int) {
        color = 0; layer = 0; u = 0; v = 0; own = triangle
    }
}

extension Quadric {
    fileprivate func sum(_ other: Quadric) -> Quadric {
        var q = self
        q += other
        return q
    }
}

private func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

private func length(_ a: SIMD3<Double>) -> Double { (a * a).sum().squareRoot() }

private func normalized(_ a: SIMD3<Double>) -> SIMD3<Double>? {
    let size = length(a)
    return size > 1e-12 ? a / size : nil
}
