// Polygons with holes cut into triangles (decision 234): the base map's
// land cover and water, laid on the 3D map's ground.
//
// Ported from earcut 2.2.4 (https://github.com/mapbox/earcut, src/earcut.js),
// ear slicing with holes bridged in by David Eberly's method. Altered from
// the original: translated to Swift, the nodes kept in an array, and
// without the z-order hash (the pieces it cuts here are small). Its
// licence:
//
//   ISC License
//
//   Copyright (c) 2016, Mapbox
//
//   Permission to use, copy, modify, and/or distribute this software for any purpose
//   with or without fee is hereby granted, provided that the above copyright notice
//   and this permission notice appear in all copies.
//
//   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
//   REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
//   FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
//   INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
//   OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
//   TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
//   THIS SOFTWARE.

enum Earcut {
    /// The triangles covering the polygon `rings` (the outer ring first,
    /// then its holes; each ring's last point not repeating its first), as
    /// indices into the rings' points taken one ring after another.
    static func triangulate(_ rings: [[(x: Double, y: Double)]]) -> [Int] {
        var cutter = Cutter()
        for ring in rings {
            for point in ring { cutter.points.append(point) }
        }
        guard let outer = rings.first, outer.count >= 3 else { return [] }
        var start = 0
        var holes: [Range<Int>] = []
        for ring in rings {
            if start > 0 { holes.append(start..<(start + ring.count)) }
            start += ring.count
        }
        cutter.run(outer: 0..<outer.count, holes: holes)
        return cutter.triangles
    }

    private struct Node {
        let i: Int
        let x: Double, y: Double
        var prev = 0, next = 0
        var steiner = false
    }

    private struct Cutter {
        var points: [(x: Double, y: Double)] = []
        var nodes: [Node] = []
        var triangles: [Int] = []

        mutating func run(outer: Range<Int>, holes: [Range<Int>]) {
            guard var outerNode = linkedList(outer, clockwise: true), nodes[outerNode].next != nodes[outerNode].prev else { return }
            if !holes.isEmpty { outerNode = eliminateHoles(holes, outerNode: outerNode) }
            earcutLinked(outerNode, pass: 0)
        }

        // MARK: Lists

        mutating func linkedList(_ range: Range<Int>, clockwise: Bool) -> Int? {
            var last: Int?
            if clockwise == (signedArea(range) > 0) {
                for i in range { last = insertNode(i, last) }
            } else {
                for i in range.reversed() { last = insertNode(i, last) }
            }
            if let node = last, equals(node, nodes[node].next) {
                removeNode(node)
                last = nodes[node].next
            }
            return last
        }

        mutating func insertNode(_ i: Int, _ last: Int?) -> Int {
            let p = nodes.count
            nodes.append(Node(i: i, x: points[i].x, y: points[i].y))
            if let last {
                nodes[p].next = nodes[last].next
                nodes[p].prev = last
                nodes[nodes[last].next].prev = p
                nodes[last].next = p
            } else {
                nodes[p].prev = p
                nodes[p].next = p
            }
            return p
        }

        mutating func removeNode(_ p: Int) {
            nodes[nodes[p].next].prev = nodes[p].prev
            nodes[nodes[p].prev].next = nodes[p].next
        }

        func signedArea(_ range: Range<Int>) -> Double {
            var sum = 0.0
            var j = range.upperBound - 1
            for i in range {
                sum += (points[j].x - points[i].x) * (points[i].y + points[j].y)
                j = i
            }
            return sum
        }

        /// Takes out points that repeat the one before or lie on a line
        /// with their neighbours.
        mutating func filterPoints(_ start: Int, _ end: Int? = nil) -> Int {
            var end = end ?? start
            var p = start
            var again = false
            repeat {
                again = false
                if !nodes[p].steiner && (equals(p, nodes[p].next) || area(nodes[p].prev, p, nodes[p].next) == 0) {
                    removeNode(p)
                    p = nodes[p].prev
                    end = p
                    if p == nodes[p].next { break }
                    again = true
                } else {
                    p = nodes[p].next
                }
            } while again || p != end
            return end
        }

        // MARK: Ears

        mutating func earcutLinked(_ start: Int, pass: Int) {
            var ear = start, stop = start
            while nodes[ear].prev != nodes[ear].next {
                let prev = nodes[ear].prev, next = nodes[ear].next
                if isEar(ear) {
                    triangles += [nodes[prev].i, nodes[ear].i, nodes[next].i]
                    removeNode(ear)
                    // Skipping the next vertex leaves fewer slivers.
                    ear = nodes[next].next
                    stop = nodes[next].next
                    continue
                }
                ear = next
                if ear == stop {
                    switch pass {
                    case 0: earcutLinked(filterPoints(ear), pass: 1)
                    case 1: earcutLinked(cureLocalIntersections(filterPoints(ear)), pass: 2)
                    default: splitEarcut(ear)
                    }
                    break
                }
            }
        }

        func isEar(_ ear: Int) -> Bool {
            let a = nodes[ear].prev, b = ear, c = nodes[ear].next
            if area(a, b, c) >= 0 { return false }  // reflex
            let (ax, ay, bx, by, cx, cy) = (nodes[a].x, nodes[a].y, nodes[b].x, nodes[b].y, nodes[c].x, nodes[c].y)
            let x0 = min(ax, bx, cx), y0 = min(ay, by, cy), x1 = max(ax, bx, cx), y1 = max(ay, by, cy)
            var p = nodes[c].next
            while p != a {
                let node = nodes[p]
                if node.x >= x0 && node.x <= x1 && node.y >= y0 && node.y <= y1
                    && pointInTriangle(ax, ay, bx, by, cx, cy, node.x, node.y) && area(node.prev, p, node.next) >= 0 {
                    return false
                }
                p = node.next
            }
            return true
        }

        mutating func cureLocalIntersections(_ begin: Int) -> Int {
            var start = begin, p = begin
            repeat {
                let a = nodes[p].prev, b = nodes[nodes[p].next].next
                if !equals(a, b) && intersects(a, p, nodes[p].next, b) && locallyInside(a, b) && locallyInside(b, a) {
                    triangles += [nodes[a].i, nodes[p].i, nodes[b].i]
                    removeNode(p)
                    removeNode(nodes[p].next)
                    p = b
                    start = b
                }
                p = nodes[p].next
            } while p != start
            return filterPoints(p)
        }

        mutating func splitEarcut(_ start: Int) {
            var a = start
            repeat {
                var b = nodes[nodes[a].next].next
                while b != nodes[a].prev {
                    if nodes[a].i != nodes[b].i && isValidDiagonal(a, b) {
                        var c = splitPolygon(a, b)
                        a = filterPoints(a, nodes[a].next)
                        c = filterPoints(c, nodes[c].next)
                        earcutLinked(a, pass: 0)
                        earcutLinked(c, pass: 0)
                        return
                    }
                    b = nodes[b].next
                }
                a = nodes[a].next
            } while a != start
        }

        // MARK: Holes

        mutating func eliminateHoles(_ holes: [Range<Int>], outerNode: Int) -> Int {
            var queue: [Int] = []
            for hole in holes {
                guard let list = linkedList(hole, clockwise: false) else { continue }
                if list == nodes[list].next { nodes[list].steiner = true }
                queue.append(leftmost(list))
            }
            queue.sort { nodes[$0].x < nodes[$1].x }
            var outer = outerNode
            for hole in queue { outer = eliminateHole(hole, outer) }
            return outer
        }

        mutating func eliminateHole(_ hole: Int, _ outerNode: Int) -> Int {
            guard let bridge = findHoleBridge(hole, outerNode) else { return outerNode }
            let reverse = splitPolygon(bridge, hole)
            _ = filterPoints(reverse, nodes[reverse].next)
            return filterPoints(bridge, nodes[bridge].next)
        }

        func findHoleBridge(_ hole: Int, _ outerNode: Int) -> Int? {
            var p = outerNode
            let hx = nodes[hole].x, hy = nodes[hole].y
            var qx = -Double.infinity
            var m: Int?
            // The segment a ray to the left from the hole's leftmost point
            // meets first; its end with the lesser x may be the bridge.
            repeat {
                let next = nodes[p].next
                if hy <= nodes[p].y && hy >= nodes[next].y && nodes[next].y != nodes[p].y {
                    let x = nodes[p].x + (hy - nodes[p].y) * (nodes[next].x - nodes[p].x) / (nodes[next].y - nodes[p].y)
                    if x <= hx && x > qx {
                        qx = x
                        m = nodes[p].x < nodes[next].x ? p : next
                        if x == hx { return m }  // the hole touches the segment
                    }
                }
                p = next
            } while p != outerNode
            guard var bridge = m else { return nil }
            // A point inside the triangle of the hole's point, the meeting
            // and the end: the one at the least angle to the ray instead.
            let stop = bridge, mx = nodes[bridge].x, my = nodes[bridge].y
            var tanMin = Double.infinity
            p = bridge
            repeat {
                let node = nodes[p]
                if hx >= node.x && node.x >= mx && hx != node.x
                    && pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, node.x, node.y) {
                    let tan = abs(hy - node.y) / (hx - node.x)
                    if locallyInside(p, hole)
                        && (tan < tanMin || (tan == tanMin && (node.x > nodes[bridge].x
                            || (node.x == nodes[bridge].x && sectorContainsSector(bridge, p))))) {
                        bridge = p
                        tanMin = tan
                    }
                }
                p = node.next
            } while p != stop
            return bridge
        }

        func sectorContainsSector(_ m: Int, _ p: Int) -> Bool {
            area(nodes[m].prev, m, nodes[p].prev) < 0 && area(nodes[p].next, m, nodes[m].next) < 0
        }

        func leftmost(_ start: Int) -> Int {
            var p = start, left = start
            repeat {
                if nodes[p].x < nodes[left].x || (nodes[p].x == nodes[left].x && nodes[p].y < nodes[left].y) { left = p }
                p = nodes[p].next
            } while p != start
            return left
        }

        // MARK: Geometry

        func pointInTriangle(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double,
                             _ px: Double, _ py: Double) -> Bool {
            (cx - px) * (ay - py) >= (ax - px) * (cy - py)
                && (ax - px) * (by - py) >= (bx - px) * (ay - py)
                && (bx - px) * (cy - py) >= (cx - px) * (by - py)
        }

        func isValidDiagonal(_ a: Int, _ b: Int) -> Bool {
            let an = nodes[a], bn = nodes[b]
            return nodes[an.next].i != bn.i && nodes[an.prev].i != bn.i && !intersectsPolygon(a, b)
                && ((locallyInside(a, b) && locallyInside(b, a) && middleInside(a, b)
                    && (area(an.prev, a, bn.prev) != 0 || area(a, bn.prev, b) != 0))
                    || (equals(a, b) && area(an.prev, a, an.next) > 0 && area(bn.prev, b, bn.next) > 0))
        }

        func area(_ p: Int, _ q: Int, _ r: Int) -> Double {
            (nodes[q].y - nodes[p].y) * (nodes[r].x - nodes[q].x) - (nodes[q].x - nodes[p].x) * (nodes[r].y - nodes[q].y)
        }

        func equals(_ a: Int, _ b: Int) -> Bool {
            nodes[a].x == nodes[b].x && nodes[a].y == nodes[b].y
        }

        func intersects(_ p1: Int, _ q1: Int, _ p2: Int, _ q2: Int) -> Bool {
            func sign(_ value: Double) -> Int { value > 0 ? 1 : value < 0 ? -1 : 0 }
            let o1 = sign(area(p1, q1, p2)), o2 = sign(area(p1, q1, q2))
            let o3 = sign(area(p2, q2, p1)), o4 = sign(area(p2, q2, q1))
            if o1 != o2 && o3 != o4 { return true }
            if o1 == 0 && onSegment(p1, p2, q1) { return true }
            if o2 == 0 && onSegment(p1, q2, q1) { return true }
            if o3 == 0 && onSegment(p2, p1, q2) { return true }
            if o4 == 0 && onSegment(p2, q1, q2) { return true }
            return false
        }

        func onSegment(_ p: Int, _ q: Int, _ r: Int) -> Bool {
            nodes[q].x <= max(nodes[p].x, nodes[r].x) && nodes[q].x >= min(nodes[p].x, nodes[r].x)
                && nodes[q].y <= max(nodes[p].y, nodes[r].y) && nodes[q].y >= min(nodes[p].y, nodes[r].y)
        }

        func intersectsPolygon(_ a: Int, _ b: Int) -> Bool {
            var p = a
            repeat {
                let next = nodes[p].next
                if nodes[p].i != nodes[a].i && nodes[next].i != nodes[a].i && nodes[p].i != nodes[b].i && nodes[next].i != nodes[b].i
                    && intersects(p, next, a, b) {
                    return true
                }
                p = next
            } while p != a
            return false
        }

        func locallyInside(_ a: Int, _ b: Int) -> Bool {
            let node = nodes[a]
            return area(node.prev, a, node.next) < 0
                ? area(a, b, node.next) >= 0 && area(a, node.prev, b) >= 0
                : area(a, b, node.prev) < 0 || area(a, node.next, b) < 0
        }

        func middleInside(_ a: Int, _ b: Int) -> Bool {
            var p = a, inside = false
            let px = (nodes[a].x + nodes[b].x) / 2, py = (nodes[a].y + nodes[b].y) / 2
            repeat {
                let node = nodes[p], next = nodes[node.next]
                if (node.y > py) != (next.y > py) && next.y != node.y
                    && px < (next.x - node.x) * (py - node.y) / (next.y - node.y) + node.x {
                    inside.toggle()
                }
                p = node.next
            } while p != a
            return inside
        }

        /// Links `a` and `b` with a bridge: splits a ring in two, or joins
        /// a hole to its outer ring.
        mutating func splitPolygon(_ a: Int, _ b: Int) -> Int {
            let a2 = nodes.count
            nodes.append(Node(i: nodes[a].i, x: nodes[a].x, y: nodes[a].y))
            let b2 = nodes.count
            nodes.append(Node(i: nodes[b].i, x: nodes[b].x, y: nodes[b].y))
            let an = nodes[a].next, bp = nodes[b].prev
            nodes[a].next = b
            nodes[b].prev = a
            nodes[a2].next = an
            nodes[an].prev = a2
            nodes[b2].next = a2
            nodes[a2].prev = b2
            nodes[bp].next = b2
            nodes[b2].prev = bp
            return b2
        }
    }
}
