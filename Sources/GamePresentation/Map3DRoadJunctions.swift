import GameCore

// Decision 607: the junctions of raised roads at one height.
//
// The owner's screenshot (2026-11-05, a motorway interchange over the
// railway beside a river): link roads leaving a deck from its side at the
// ground, so the two surfaces crossed in a V; a ramp down from a bridge's
// end running on past the side streets meeting it, landing on them; and the
// parapets between them in pieces. A raised road's height was worked out
// road by road: the deck's own, and a ramp down along the road running on
// from its end (decision 391). Where another road met either, it lay at the
// ground.
//
// The slop-taipei elevated decks (`build-elevated.mjs`, MIT, Copyright (c)
// 2026 Mr.doob; `Railway/slop-taipei-reference-clean/`) give each node of
// the raised roads one height, a Dijkstra over the roads' shared nodes, so
// whatever meets at a node meets at one height. The tiles keep no node ids
// (a junction is where one road's point lies on another, within
// ``Map3DRoadBridges/join``), and the ramps here climb from the ground to
// the deck (a bridge keeps its clearance over the track) rather than fall
// from the deck to the ground, so the same idea runs the other way: from
// each deck the height spreads to the roads on the ground leaving it at
// one of its points (its link roads), each falling at its own grade from
// the junction until it is down. The streets meeting a ramp on the ground
// stay on the ground, as they are in the real world (game planning,
// 2026-11-06: their bus stops stay). The road meeting it keeps the raised one's height while it still
// lies on its surface (a link road's taper along a deck's side), so the two
// surfaces are one there.

/// Decision 607: one raised road a junction's height comes from.
enum Map3DRaisedRoad: Hashable, Sendable {
    /// A ramp down from a bridge's end, or a junction's (``Map3DRoadBridges/ends``).
    case end(Int)
    /// A road lifted over the track (``Map3DRoadBridges/joins``).
    case join(Int)
    /// A bridge's piece (``Map3DRoadBridges/pieces``).
    case piece(Int)
}

extension Map3DRoadBridges {
    /// Decision 607: the least height a junction's road is ramped from,
    /// metres over the ground: lower meets the ground road at a step a
    /// kerb's height.
    static let spreadRise: Float = 0.25
    /// How far a road meeting a raised one keeps its height at most while
    /// it lies on its surface, metres.
    static let longestTaper: Double = 150
    /// How far under another deck a road ramping from a junction keeps,
    /// metres (its girder, and a lorry under it), and the steepest it
    /// falls to keep under one; steeper, it is not ramped at all.
    static let underDeck: Float = 5.5
    static let steepestSpread: Float = 0.12

    /// The points of `road` from its point at fractional index `at` (a
    /// point `i` is `i`, a share `t` of the way to the next `i + t`) on to
    /// its end `forward` or its start.
    func points(of road: Int, from at: Double, forward: Bool) -> [Map3DBaseMap.Point] {
        let line = grounds[road].points
        let low = Int(at.rounded(.down)), share = at - Double(low)
        let start: Map3DBaseMap.Point
        if low + 1 < line.count, share > 0 {
            let a = line[low], b = line[low + 1]
            start = Map3DBaseMap.Point(x: a.x + (b.x - a.x) * share, z: a.z + (b.z - a.z) * share)
        } else {
            start = line[min(low, line.count - 1)]
        }
        let rest = forward ? Array(line[min(low + 1, line.count)...]) : Array(line[...min(low, line.count - 1)].reversed().dropFirst(share > 0 ? 0 : 1))
        return [start] + rest
    }
}

extension Map3DScene.Builder {
    /// Decision 607: each road on the ground meeting a raised one
    /// (``Map3DRaisedRoad``) at its height, ramping down from the
    /// junction at its own grade, each one met in turn the same way: new
    /// ``Map3DRoadBridges/ends``.
    mutating func spreadRamps(into result: inout Map3DRoadBridges) {
        typealias Point = Map3DBaseMap.Point
        func distance(_ a: Point, _ b: Point) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).squareRoot() }
        let grounds = result.grounds
        guard !grounds.isEmpty, !result.pieces.isEmpty || !result.joins.isEmpty else { return }
        // A raised road's height over the ground at `q`, if it reaches it.
        func rise(of raised: Map3DRaisedRoad, at q: Point) -> Float? {
            switch raised {
            case .end(let number):
                let end = result.ends[number]
                let out = (q.x - end.point.x) * end.outward.x + (q.z - end.point.z) * end.outward.z
                guard out >= -1 else { return nil }
                let fall = Float(max(out, 0)) - end.plateau
                guard fall <= Map3DRoadBridges.longestRamp else { return nil }
                return end.rise - end.grade * max(fall, 0)
            case .join(let number):
                let join = result.joins[number]
                let out = Float(abs((q.x - join.point.x) * join.along.x + (q.z - join.point.z) * join.along.z))
                guard out <= join.reach else { return nil }
                return join.height - join.grade * max(0, out - join.plateau) - drawnGround(x: Float(q.x), z: Float(q.z))
            case .piece(let number):
                return deckRise(result.decks[result.pieces[number].deck], at: q)
            }
        }
        // Its surface's segments (a line, half its width) near `q`.
        func surface(of raised: Map3DRaisedRoad) -> [(a: Point, b: Point, half: Double)] {
            func ground(_ roads: [(road: Int, index: Int)]) -> [(a: Point, b: Point, half: Double)] {
                roads.map { segment in
                    let line = grounds[segment.road].points
                    return (line[segment.index - 1], line[segment.index], Double(grounds[segment.road].kind.width(ramp: false)) / 2)
                }
            }
            switch raised {
            case .end(let number): return ground(result.ends[number].roads)
            case .join(let number): return ground(result.joins[number].roads)
            case .piece(let number):
                let piece = result.pieces[number]
                return zip(piece.points, piece.points.dropFirst()).map { ($0.0, $0.1, Double(piece.kind.width(ramp: false)) / 2) }
            }
        }
        // The roads a raised road already lifts.
        func own(_ raised: Map3DRaisedRoad) -> Set<Int> {
            switch raised {
            case .end(let number): Set(result.ends[number].roads.map(\.road))
            case .join(let number): Set(result.joins[number].roads.map(\.road))
            case .piece: []
            }
        }
        // Where roads on the ground meet `raised`: a road's point within
        // ``Map3DRoadBridges/join`` of its line, or a road crossing it, as
        // (road, fractional index).
        func junctions(of raised: Map3DRaisedRoad) -> [(road: Int, at: Double, point: Point)] {
            let skip = own(raised)
            let isPiece: Bool
            if case .piece = raised { isPiece = true } else { isPiece = false }
            var found: [String: (road: Int, at: Double, point: Point)] = [:]
            for line in surface(of: raised) {
                let pad = Map3DRoadBridges.join
                let low = Map3DRoadBridges.key(min(line.a.x, line.b.x) - pad, min(line.a.z, line.b.z) - pad)
                let high = Map3DRoadBridges.key(max(line.a.x, line.b.x) + pad, max(line.a.z, line.b.z) + pad)
                for row in low.row...high.row {
                    for column in low.column...high.column {
                        let key = Map3DScene.ChunkKey(column: column, row: row)
                        for (road, index) in result.groundPoints[key] ?? [] where !skip.contains(road) {
                            // A road meets a bridge's deck only at its end:
                            // one passing under it is no junction.
                            if isPiece, index != 0, index != grounds[road].points.count - 1 { continue }
                            let p = grounds[road].points[index]
                            guard Map3DRoadBridges.nearest(p, line.a, line.b).distance <= pad else { continue }
                            // And at one of the deck's own points (the
                            // node they share), not under its span.
                            if isPiece, distance(p, line.a) > pad, distance(p, line.b) > pad { continue }
                            found["\(road) \(index)"] = (road, Double(index), p)
                        }
                        for (road, index) in isPiece ? [] : result.groundCells[key] ?? [] where !skip.contains(road) {
                            let points = grounds[road].points
                            guard let share = Map3DRoadBridges.crossing(points[index - 1], points[index], line.a, line.b) else { continue }
                            let at = Double(index - 1) + share
                            let p = Point(x: points[index - 1].x + (points[index].x - points[index - 1].x) * share,
                                          z: points[index - 1].z + (points[index].z - points[index - 1].z) * share)
                            found["\(road) \(Int((at * 100).rounded()))"] = found["\(road) \(Int((at * 100).rounded()))"] ?? (road, at, p)
                        }
                    }
                }
            }
            return found.values.sorted { ($0.road, $0.at) < ($1.road, $1.at) }
        }
        // Only a deck's own junctions: the link road leaving it is raised
        // down to the ground, the streets meeting that link or a ramp on
        // the ground stay on the ground, as they are.
        let queue: [Map3DRaisedRoad] = result.pieces.indices.map { .piece($0) }
        var best: [String: Float] = [:]
        var next = 0
        // Bounded: each new end is lower than the road it meets.
        while next < queue.count, result.ends.count < 200_000 {
            let raised = queue[next]
            next += 1
            let lines = surface(of: raised)
            for junction in junctions(of: raised) {
                guard let height = rise(of: raised, at: junction.point), height >= Map3DRoadBridges.spreadRise else { continue }
                let kind = grounds[junction.road].kind
                for forward in [true, false] {
                    let way = result.points(of: junction.road, from: junction.at, forward: forward)
                    guard way.count > 1, let away = way.dropFirst().first(where: { distance($0, junction.point) >= 5 }) ?? way.last,
                          distance(away, junction.point) > 0.5 else { continue }
                    let length = distance(away, junction.point)
                    let outward = Point(x: (away.x - junction.point.x) / length, z: (away.z - junction.point.z) / length)
                    let key = "\(junction.road) \(Int((junction.point.x * 2).rounded())) \(Int((junction.point.z * 2).rounded())) \(forward)"
                    guard (best[key] ?? -1) < height - 0.05 else { continue }
                    best[key] = height
                    // How far out along it its middle still lies on the
                    // raised road's surface, every 2 m.
                    var taper = 0.0, travelled = 0.0
                    walk: for (a, b) in zip(way, way.dropFirst()) {
                        let step = distance(a, b)
                        var done = 0.0
                        while done < step, travelled + done <= Map3DRoadBridges.longestTaper {
                            let p = Point(x: a.x + (b.x - a.x) * done / step, z: a.z + (b.z - a.z) * done / step)
                            guard lines.contains(where: { Map3DRoadBridges.nearest(p, $0.a, $0.b).distance <= $0.half }) else { break walk }
                            taper = travelled + done
                            done += 2
                        }
                        travelled += step
                    }
                    // Decision 607: under another deck it keeps clear:
                    // falling faster when it must, else not raised.
                    var grade = Map3DRoadBridges.grade(kind)
                    let source: Int?
                    if case .piece(let number) = raised { source = result.pieces[number].deck } else { source = nil }
                    var fits = false
                    for _ in 0..<4 {
                        var needed: Float?
                        var travelled = 0.0
                        scan: for (a, b) in zip(way, way.dropFirst()) {
                            let step = distance(a, b)
                            var done = 0.0
                            while done < step {
                                let d = travelled + done
                                let r = height - grade * max(Float(d - taper), 0)
                                if r < Map3DRoadBridges.spreadRise || d > Double(Map3DRoadBridges.longestRamp) + taper { break scan }
                                let q = Point(x: a.x + (b.x - a.x) * done / step, z: a.z + (b.z - a.z) * done / step)
                                for (number, index) in result.segments[Map3DRoadBridges.key(q.x, q.z)] ?? [] where result.pieces[number].deck != source || d > taper + 10 {
                                    let piece = result.pieces[number]
                                    guard Map3DRoadBridges.nearest(q, piece.points[index - 1], piece.points[index]).distance <= Double(piece.kind.width(ramp: false)) / 2
                                    else { continue }
                                    let over = deckRise(result.decks[piece.deck], at: q)
                                    // Only a deck over it: one under it (a bridge at the
                                    // ground's height it runs on to) is passed over.
                                    guard over - r > 0.5, over - r < Map3DRoadBridges.underDeck else { continue }
                                    needed = (height - max(over - Map3DRoadBridges.underDeck, 0)) / max(Float(d - taper), 1)
                                    break scan
                                }
                                done += 4
                            }
                            travelled += step
                        }
                        guard let steeper = needed else { fits = true; break }
                        guard steeper <= Map3DRoadBridges.steepestSpread, steeper > grade else { break }
                        grade = steeper
                    }
                    guard fits else { continue }
                    let reach = Double(min(height / grade, Map3DRoadBridges.longestRamp)) + taper + Double(Map3DRoadBridges.half(kind)) + 4
                    var end = Map3DRoadBridges.End(point: junction.point, outward: outward, half: Map3DRoadBridges.half(kind), rise: height, grade: grade,
                                                   roads: result.runOn(from: junction.point, axis: outward, reach: reach, first: [junction.road]).filter { segment in
                                                       // Only those ahead of it: one leaving the
                                                       // junction the other way is not lifted, so is
                                                       // met there in turn.
                                                       let line = grounds[segment.road].points
                                                       return [line[segment.index - 1], line[segment.index]].contains {
                                                           ($0.x - junction.point.x) * outward.x + ($0.z - junction.point.z) * outward.z > 1
                                                       }
                                                   })
                    end.plateau = Float(taper)
                    let low = Map3DRoadBridges.key(junction.point.x - reach, junction.point.z - reach)
                    let high = Map3DRoadBridges.key(junction.point.x + reach, junction.point.z + reach)
                    for row in low.row...high.row {
                        for column in low.column...high.column { result.endCells[Map3DScene.ChunkKey(column: column, row: row), default: []].append(result.ends.count) }
                    }
                    result.ends.append(end)
                }
            }
        }
    }
}
