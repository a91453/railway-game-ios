import Foundation
import GameCore
@testable import GamePresentation

// Decision 422: the N700S-G's far bodies, written once into
// Sources/GamePresentation/Map3DN700SGFarMesh.swift, resampled from each
// unit's near body (`Map3DN700SG.encodedMeshes`, decision 408's mesh of
// the author's model, the bogies not in it):
//
// 1. Sections: every 5 cm along the car a ray every 1° round its middle
//    (half way up the car, or the nose where it is low) finds the
//    outermost surface and its colour.
// 2. The shell keeps the sections it needs (none on the straight sides;
//    on the nose, its ends and the pantograph cover until no dropped
//    section's painted body above the skirt is more than `tolerance`
//    off) and, round each, every 20° (but within 6° of a change)
//    and each angle where the body's paint changes (the two dark green
//    lines, the skirt, the roof); every vertex is a point found in 1.
// 3. A shell cell takes its samples' commonest colour (glass from a
//    third, the windscreen); an end, the paint a ray along the car
//    meets there; on the sides
//    (within 50° of level) not the windows' and doors' (they come next).
// 4. A window or a door is one flat pane, its samples' span and its
//    reveals, a little proud; a green line a ribbon along its edges; the lamps are the near mesh's own triangles.
// 5. The shell's roof is the car's own (the straight middle's), so the
//    D car's pantograph cover takes no sections round the whole car: it
//    is a patch of its own over the roof's angles.
//
// The game's simplifier (decision 420) was tried first: it stops at
// 2,300 to 3,900 triangles a car, the near mesh's seams already locked
// by decimate.py. Run from the repository root:
//
//   n700sg_far Sources/GamePresentation/Map3DN700SGFarMesh.swift
typealias V = SIMD3<Double>
let step = 0.05, fine = 360, tolerance = 0.08, uniform = 20
let line = 1, glass = 2, skirt = 3, door = 4, lamp = 8
func cross(_ a: V, _ b: V) -> V { V(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }
func dot(_ a: V, _ b: V) -> Double { (a * b).sum() }

struct Triangle { let a: V, b: V, c: V, paint: Int }

/// The nearest hit of the ray from `origin` along `direction` and its
/// triangle's paint.
func nearest(_ origin: V, _ direction: V, _ triangles: [Triangle]) -> (Double, Int)? {
    var best: (Double, Int)? = nil
    for t in triangles {
        let e1 = t.b - t.a, e2 = t.c - t.a, p = cross(direction, e2), det = dot(e1, p)
        guard abs(det) > 1e-12 else { continue }
        let s = origin - t.a, u = dot(s, p) / det
        guard u >= -1e-9, u <= 1 + 1e-9 else { continue }
        let q = cross(s, e1), v = dot(direction, q) / det
        guard v >= -1e-9, u + v <= 1 + 1e-9 else { continue }
        let d = dot(e2, q) / det
        if d > 0, d < (best?.0 ?? .infinity) { best = (d, t.paint) }
    }
    return best
}

/// The farthest hit of the ray from `origin` along `direction` and its
/// triangle's paint; Möller–Trumbore.
func farthest(_ origin: V, _ direction: V, _ triangles: [Triangle]) -> (Double, Int)? {
    var best: (Double, Int)? = nil
    for t in triangles {
        let e1 = t.b - t.a, e2 = t.c - t.a, p = cross(direction, e2), det = dot(e1, p)
        guard abs(det) > 1e-12 else { continue }
        let s = origin - t.a, u = dot(s, p) / det
        guard u >= -1e-9, u <= 1 + 1e-9 else { continue }
        let q = cross(s, e1), v = dot(direction, q) / det
        guard v >= -1e-9, u + v <= 1 + 1e-9 else { continue }
        let d = dot(e2, q) / det
        if d > 0, d > (best?.0 ?? -1) { best = (d, t.paint) }
    }
    return best
}

func farBody(_ unit: Map3DN700SG.Unit) -> (near: Int, bytes: [UInt8]) {
    let text = Map3DN700SG.encodedMeshes[unit]!
    let near = Map3DN700SG.decodedMesh([UInt8](Data(base64Encoded: text, options: .ignoreUnknownCharacters)!), named: "near")!
    let palette = Map3DN700SG.meshPalette
    let triangles = stride(from: 0, to: near.vertices.count, by: 3).map { s -> Triangle in
        let p = (0..<3).map { V(Double(near.vertices[s + $0].x), Double(near.vertices[s + $0].y), Double(near.vertices[s + $0].z)) }
        return Triangle(a: p[0], b: p[1], c: p[2], paint: palette.firstIndex(of: near.vertices[s].color)!)
    }
    // Triangles by 25 cm slab along the car, for the rays.
    let low = Double(near.minimum.x), high = Double(near.maximum.x)
    let slabs = Int(((high - low) / 0.25).rounded(.up)) + 1
    var bySlab = [[Triangle]](repeating: [], count: slabs)
    for t in triangles {
        let a = min(t.a.x, t.b.x, t.c.x), b = max(t.a.x, t.b.x, t.c.x)
        for k in max(0, Int((a - low) / 0.25))...min(slabs - 1, Int((b - low) / 0.25)) { bySlab[k].append(t) }
    }
    // 1. The sections.
    // Off the mesh's millimetres, so no ray runs along an edge.
    let xs = Array(stride(from: low + 0.0123, through: high - 0.01, by: step))
    // One middle for the car, half way between its floor and its roof
    // where it is whole (the median), but on the nose where the roof
    // comes down within 0.4 m of it, half way up there.
    var spans = [(Double, Double)]()
    for x in xs {
        let near = bySlab[Int((x - low) / 0.25)]
        let up = farthest(V(x, 0, -10), V(0, 0, 1), near)?.0 ?? 0, down = farthest(V(x, 0, 20), V(0, 0, -1), near)?.0 ?? 0
        spans.append(up > 0 && down > 0 ? (20 - down, -10 + up) : (0, 0))
    }
    let whole = spans.map { ($0.0 + $0.1) / 2 }.sorted()[xs.count / 2]
    let middle = spans.map { $0.1 < whole + 0.4 ? ($0.0 + $0.1) / 2 : whole }
    var radius = [[Double]](), paint = [[Int]]()
    for (x, zc) in zip(xs, middle) {
        let near = bySlab[Int((x - low) / 0.25)]
        var r = [Double](), c = [Int]()
        for j in 0..<fine {
            let a = Double(j) * 2 * .pi / Double(fine)
            let hit = farthest(V(x, 0, zc), V(0, cos(a), sin(a)), near)
            r.append(hit?.0 ?? -1); c.append(hit?.1 ?? 0)
        }
        // A ray through a crack takes its nearest neighbours' (none past
        // the nose's tip: all of them miss there).
        if r.contains(where: { $0 >= 0 }) {
            for j in 0..<fine where r[j] < 0 {
                var a = 1, b = 1
                while r[(j - a + fine) % fine] < 0 { a += 1 }
                while r[(j + b) % fine] < 0 { b += 1 }
                let ra = r[(j - a + fine) % fine], rb = r[(j + b) % fine]
                r[j] = -(ra + (rb - ra) * Double(a) / Double(a + b))
                c[j] = a <= b ? c[(j - a + fine) % fine] : c[(j + b) % fine]
            }
            r = r.map(abs)
        } else {
            r = r.map { _ in 0 }
        }
        radius.append(r); paint.append(c)
    }
    // The roof (more than 25° up) as the straight middle half has it; the
    // shell's roof no higher, a cover above it its own patch (5.).
    let roof = Set((0..<fine).filter { sin(Double($0) * 2 * .pi / Double(fine)) >= sin(25 * Double.pi / 180) })
    var roofline = [Double](repeating: 0, count: fine)
    for j in roof { roofline[j] = (xs.count / 4..<3 * xs.count / 4).map { radius[$0][j] }.sorted()[xs.count / 4] }
    let shell = radius.map { r in r.indices.map { roof.contains($0) ? min(r[$0], roofline[$0] + 0.02) : r[$0] } }
    // 2. The stations: greedy, the farthest each can reach within the
    // tolerance; the angles: uniform and the paint's changes along the
    // straight middle half.
    func select(_ low: Int, _ high: Int, _ radius: [[Double]], _ judged: (Int, Int) -> Bool) -> [Int] {
        var stations = [low]
        while stations.last! < high {
            let s = stations.last!
            var e = s + 1
            search: while e + 1 <= high {
                let next = e + 1
                for k in s + 1..<next {
                    let t = Double(k - s) / Double(next - s)
                    for j in 0..<fine where judged(k, j) {
                        let r = radius[s][j] + (radius[next][j] - radius[s][j]) * t
                        let z = middle[s] + (middle[next] - middle[s]) * t
                        let p = V(0, r * cos(Double(j) * 2 * .pi / Double(fine)), z + r * sin(Double(j) * 2 * .pi / Double(fine)))
                        let q = V(0, radius[k][j] * cos(Double(j) * 2 * .pi / Double(fine)), middle[k] + radius[k][j] * sin(Double(j) * 2 * .pi / Double(fine)))
                        if ((p - q) * (p - q)).sum() > tolerance * tolerance { break search }
                    }
                }
                e = next
            }
            stations.append(e)
        }
        return stations
    }
    // Judged on the painted body only: not the windows' and doors'
    // recesses, nor the skirt's openings (the far bogies stand there;
    // the skirt's grey above 1.6 m is the pantograph cover's).
    let stations = select(0, xs.count - 1, shell) { k, j in
        let z = middle[k] + shell[k][j] * sin(Double(j) * 2 * .pi / Double(fine))
        return ![glass, door, lamp].contains(paint[k][j]) && z > 1.0 && (paint[k][j] != skirt || z > 1.6)
    }
    var body = [Int]()
    for j in 0..<fine {
        var count = [Int: Int]()
        for i in xs.count / 4..<3 * xs.count / 4 where ![line, glass, door, lamp].contains(paint[i][j]) { count[paint[i][j], default: 0] += 1 }
        body.append(count.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key ?? 0)
    }
    let changes = (0..<fine).filter { body[$0] != body[($0 + fine - 1) % fine] }
    // A uniform angle within 6° of a change is the change's.
    let byChange = { (j: Int) in changes.contains { min(abs($0 - j), fine - abs($0 - j)) <= 6 } }
    let ring = Set(stride(from: 0, to: fine, by: uniform).filter { !byChange($0) } + changes).sorted()
    // 3. The shell.
    var out: [(V, V, V, Int)] = []
    func point(_ i: Int, _ j: Int, proud: Double = 0, on surface: [[Double]]? = nil) -> V {
        let radius = surface ?? shell
        let a = Double(j) * 2 * .pi / Double(fine), r = radius[i][j] + (radius[i][j] > 0 ? proud : 0)
        return V(xs[i], r * cos(a), middle[i] + r * sin(a))
    }
    func emit(_ a: V, _ b: V, _ c: V, _ colour: Int, centre: V) {
        let n = cross(b - a, c - a)
        guard dot(n, n) > 1e-12 else { return }
        out.append(dot(n, (a + b + c) / 3 - centre) >= 0 ? (a, b, c, colour) : (a, c, b, colour))
    }
    /// The shell as drawn at sample `i`, angle `j`, `proud` off it: between
    /// its sections and its angles.
    func drawn(_ i: Int, _ j: Int, proud: Double) -> V {
        let e = stations.first { $0 >= i }!, s = stations.last { $0 <= i }!
        let k = ring.lastIndex { $0 <= j } ?? ring.count - 1, j0 = ring[k], j1 = ring[(k + 1) % ring.count]
        let t = e == s ? 0 : Double(i - s) / Double(e - s), u = Double((j - j0 + fine) % fine) / Double(max(1, (j1 - j0 + fine) % fine))
        func along(_ j: Int) -> V { point(s, j) + (point(e, j) - point(s, j)) * t }
        let p = along(j0) + (along(j1) - along(j0)) * u
        let a = Double(j) * 2 * .pi / Double(fine)
        return p + V(0, cos(a), sin(a)) * proud
    }
    /// The 4-connected samples of `colour` on the sides from (i, j): their
    /// first and last sample along the car and, at each, its angles in
    /// order round the gap none of them is in.
    var seen = Set<Int>()
    func component(_ i: Int, _ j: Int, _ colour: Int) -> [Int: (Int, Int)] {
        var stack = [(i, j)], at = [Int: Set<Int>]()
        seen.insert(i * fine + j)
        while let (a, b) = stack.popLast() {
            at[a, default: []].insert(b)
            for (p, q) in [(a + 1, b), (a - 1, b), (a, (b + 1) % fine), (a, (b + fine - 1) % fine)]
            where xs.indices.contains(p) && sides.contains(q) && paint[p][q] == colour && !seen.contains(p * fine + q) {
                seen.insert(p * fine + q); stack.append((p, q))
            }
        }
        return at.mapValues { js in
            let sorted = js.sorted()
            if let gap = zip(sorted, sorted.dropFirst()).first(where: { $0.1 - $0.0 > 1 }) { return (gap.1, gap.0) }
            return (sorted[0], sorted.last!)
        }
    }
    // The sides, within 50° of level: their glass and doors are panes.
    let sides = Set((0..<fine).filter { abs(sin(Double($0) * 2 * .pi / Double(fine))) < sin(50 * Double.pi / 180) })
    for (s, e) in zip(stations, stations.dropFirst()) {
        for (k, j0) in ring.enumerated() {
            let j1 = ring[(k + 1) % ring.count], span = (j1 - j0 + fine) % fine
            var count = [Int: Int]()
            for i in s...e { for d in 0...span {
                let c = paint[i][(j0 + d) % fine]
                if c == lamp || (sides.contains((j0 + d) % fine) && [line, glass, door].contains(c)) { continue }
                count[c, default: 0] += 1
            } }
            // The windscreen's cells glass from a third of them.
            let colour = 3 * (count[glass] ?? 0) >= count.values.reduce(0, +) ? glass
                : count.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key ?? 0
            let centre = V((xs[s] + xs[e]) / 2, 0, (middle[s] + middle[e]) / 2)
            emit(point(s, j0), point(e, j0), point(e, j1), colour, centre: centre)
            emit(point(s, j0), point(e, j1), point(s, j1), colour, centre: centre)
        }
    }
    for i in [0, xs.count - 1] {
        let centre = V(xs[i], 0, middle[i]), inside = centre + V(i == 0 ? 1 : -1, 0, 0)
        for (k, j0) in ring.enumerated() {
            var count = [Int: Int]()
            let j1 = ring[(k + 1) % ring.count]
            // The end's own paint where a ray along the car meets it, at
            // the fan's corners and middle.
            let a = point(i, j0), b = point(i, j1)
            for p in [(centre + a + b) / 3, (centre * 2 + a) / 3, (centre * 2 + b) / 3, (centre + a * 2) / 3, (centre + b * 2) / 3] {
                let from = V(i == 0 ? low - 1 : high + 1, p.y, p.z)
                if let hit = nearest(from, V(i == 0 ? 1 : -1, 0, 0), triangles), hit.1 != lamp { count[hit.1, default: 0] += 1 }
            }
            emit(centre, a, b, count.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key ?? 0, centre: inside)
        }
    }
    // 4. The windows and doors on the sides, one flat pane each, on the
    // shell as drawn; the green lines a ribbon each, a point where its
    // edges bend more than a degree.
    for i in xs.indices {
        for j in 0..<fine where sides.contains(j) && [line, glass, door].contains(paint[i][j]) && !seen.contains(i * fine + j) {
            let colour = paint[i][j], at = component(i, j, colour)
            let i0 = at.keys.min()!, i1 = at.keys.max()!
            guard i1 > i0 else { continue }
            let mid = (i0 + i1) / 2, centre = V(xs[mid], 0, middle[mid])
            var points = [i0]
            if colour == line {
                // Every sample of it, gaps filled from their neighbours.
                var edges = [(Double, Double)]()
                for k in i0...i1 {
                    if let e = at[k] { edges.append((Double(e.0), Double(e.0 + (e.1 - e.0 + fine) % fine))) } else { edges.append(edges.last!) }
                }
                while points.last! < i1 {
                    let s = points.last!
                    var e = s + 1
                    search: while e + 1 <= i1 {
                        for k in s + 1...e {
                            let t = Double(k - s) / Double(e + 1 - s)
                            for side in [0, 1] {
                                let a = side == 0 ? edges[s - i0].0 : edges[s - i0].1, b = side == 0 ? edges[e + 1 - i0].0 : edges[e + 1 - i0].1
                                let mine = side == 0 ? edges[k - i0].0 : edges[k - i0].1
                                if abs(a + (b - a) * t - mine) > 1 { break search }
                            }
                        }
                        e += 1
                    }
                    points.append(e)
                }
                for (s, e) in zip(points, points.dropFirst()) {
                    let a = edges[s - i0], b = edges[e - i0]
                    let p = [drawn(s, Int(a.0) % fine, proud: 0.012), drawn(e, Int(b.0) % fine, proud: 0.012),
                             drawn(e, (Int(b.1) + 1) % fine, proud: 0.012), drawn(s, (Int(a.1) + 1) % fine, proud: 0.012)]
                    emit(p[0], p[1], p[2], colour, centre: centre); emit(p[0], p[2], p[3], colour, centre: centre)
                }
            } else {
                // Not the specks a door's edge leaves; a pane grown by its
                // reveals (the rays meet their walls first): 2° up and
                // down, a sample at each end.
                guard at.values.reduce(0, { $0 + ($1.1 - $1.0 + fine) % fine + 1 }) >= 8 else { continue }
                let ref = at[i0]!.0, rel = { (j: Int) in (j - ref + fine + fine / 2) % fine - fine / 2 }
                let first = (ref + at.values.map { rel($0.0) }.min()! - 2 + fine) % fine
                let last = (ref + at.values.map { rel($0.1) }.max()! + 3 + fine) % fine
                let a0 = max(0, i0 - 1), a1 = min(xs.count - 1, i1 + 1)
                let p = [drawn(a0, first, proud: 0.015), drawn(a1, first, proud: 0.015), drawn(a1, last, proud: 0.015), drawn(a0, last, proud: 0.015)]
                emit(p[0], p[1], p[2], colour, centre: centre); emit(p[0], p[2], p[3], colour, centre: centre)
            }
        }
    }
    // 5. A cover on the roof: where the roof stands 5 cm above the
    // roofline, its own sections (a step either side, on the roof) over
    // its own angles (a degree either side, every 10° and its ends).
    let raised = xs.indices.filter { i in roof.contains { radius[i][$0] > roofline[$0] + 0.05 } && middle[i] == whole }
    var runs: [(Int, Int)] = []
    for i in raised { if let last = runs.last, last.1 == i - 1 { runs[runs.count - 1].1 = i } else { runs.append((i, i)) } }
    for (first, last) in runs where last - first > 2 {
        let low = max(0, first - 1), high = min(xs.count - 1, last + 1)
        let up = roof.filter { j in (first...last).contains { radius[$0][j] > roofline[j] + 0.05 } }
        let from = max(roof.min()!, up.min()! - 1), to = min(roof.max()!, up.max()! + 1)
        let span = Set(stride(from: from, to: to, by: 10)).union([to]).sorted()
        let sections = select(low, high, radius) { _, j in (from...to).contains(j) }
        print("  cover \(String(format: "%.2f", xs[low]))…\(String(format: "%.2f", xs[high])) m: \(sections.count) sections, \(span.count) angles")
        for (s, e) in zip(sections, sections.dropFirst()) {
            for (j0, j1) in zip(span, span.dropFirst()) {
                var count = [Int: Int]()
                for i in s...e { for j in j0...j1 { count[paint[i][j], default: 0] += 1 } }
                let colour = count.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key ?? 0
                let centre = V((xs[s] + xs[e]) / 2, 0, middle[s])
                emit(point(s, j0, on: radius), point(e, j0, on: radius), point(e, j1, on: radius), colour, centre: centre)
                emit(point(s, j0, on: radius), point(e, j1, on: radius), point(s, j1, on: radius), colour, centre: centre)
            }
        }
    }
    // The lamps as the near mesh has them, a little proud.
    for t in triangles where t.paint == lamp {
        let n = cross(t.b - t.a, t.c - t.a), lift = n / (dot(n, n).squareRoot()) * 0.01
        out.append((t.a + lift, t.b + lift, t.c + lift, lamp))
    }
    // The bytes, ``Map3DN700SG/decodedMesh(_:named:)``'s format.
    var index: [SIMD3<Int16>: Int] = [:], points: [SIMD3<Int16>] = [], bytes: [UInt8] = []
    func u16(_ n: Int) { precondition((0...0xFFFF).contains(n)); bytes += [UInt8(n & 0xFF), UInt8(n >> 8)] }
    func id(_ p: V) -> Int {
        let q = SIMD3(Int16((p.x * 1000).rounded()), Int16((p.y * 1000).rounded()), Int16((p.z * 1000).rounded()))
        if let i = index[q] { return i }
        index[q] = points.count; points.append(q); return points.count - 1
    }
    let faces = out.map { (id($0.0), id($0.1), id($0.2), $0.3) }.filter { $0.0 != $0.1 && $0.1 != $0.2 && $0.0 != $0.2 }
    u16(points.count)
    for p in points { for c in [p.x, p.y, p.z] { u16(Int(UInt16(bitPattern: c))) } }
    u16(faces.count)
    for f in faces { u16(f.0); u16(f.1); u16(f.2); bytes.append(UInt8(f.3)) }
    print("\(unit.rawValue.uppercased()): \(stations.count) sections, \(ring.count) angles")
    return (near.triangleCount, bytes)
}

var lines = ["// Generated by tools/hsr-far-422/n700sg_far.swift from Map3DN700SGMesh.swift",
             "// (decision 408's mesh of the author's N700S-G, with the author's consent):",
             "// its sections resampled (decision 422). Do not edit: run the tool again",
             "// (tools/hsr-far-422/README.md).",
             "//"]
var entries: [String] = []
for unit in [Map3DN700SG.Unit.a, .c, .d] {
    let (near, bytes) = farBody(unit)
    let far = Map3DN700SG.decodedMesh(bytes, named: "far")!
    lines.append("//   \(unit.rawValue.uppercased()): \(near) -> \(far.triangleCount) triangles")
    var wrapped: [String] = [], rest = Substring(Data(bytes).base64EncodedString())
    while !rest.isEmpty { wrapped.append("        " + rest.prefix(100)); rest = rest.dropFirst(100) }
    entries.append("        .\(unit.rawValue): \"\"\"\n" + wrapped.joined(separator: "\n") + "\n        \"\"\",")
}
lines += ["", "extension Map3DN700SG {",
          "    /// Decision 422: each unit's far body, base64 of ``decodedMesh(_:named:)``'s bytes.",
          "    static let encodedFarMeshes: [Unit: String] = ["] + entries + ["    ]", "}", ""]
try lines.joined(separator: "\n").write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
print(lines.filter { $0.hasPrefix("//   ") }.joined(separator: "\n"))
