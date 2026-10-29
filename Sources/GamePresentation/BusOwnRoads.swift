import Foundation
import GameCore

// Decision 476's sequel: the player's own roads (decision 438) in the bus
// roads' graph (decision 424), so that a bus goes from them onto the city's
// roads. On a real-world map the base map does not have them: each is
// taken as the line it is drawn as (``RoadCentreLines``), both ways and in
// the open; where it crosses a base map road the two meet there (a
// junction, the bus may turn), and where it ends within ``ownJoinReach`` of
// one, a short piece joins it to the nearest point of that road. The
// graph's own ``BusRoadNetwork/splitAtJunctions`` cuts the base map's road
// at that point. GameCore is not changed: it keeps the roads as cells.

extension BusRoadNetwork {
    /// How far from a base map road the end of a player's road is joined
    /// to it, in metres: a cell, so a road drawn up to the cell a street
    /// runs through meets it.
    static let ownJoinReach = Double(Land.cellLength) / Double(WorldCoordinate.unitsPerMetre)

    /// The player's roads `own` (their lines, ``RoadCentreLines``, in
    /// metres) as roads beside `base`: each cut where it crosses one of
    /// `base` out of a tunnel, so the two share a point, and a piece from
    /// each of `ends` to the nearest point of `base` within
    /// ``ownJoinReach`` (none where the end is on it already).
    static func joining(own: [[Point]], ends: [Point], to base: [Road]) -> [Road] {
        let open = base.filter { !$0.tunnel && $0.points.count >= 2 }
        let boxes = open.map { road -> (low: Point, high: Point) in
            let xs = road.points.map(\.x), ys = road.points.map(\.y)
            return (Point(x: xs.min() ?? 0, y: ys.min() ?? 0), Point(x: xs.max() ?? 0, y: ys.max() ?? 0))
        }
        func near(_ a: Point, _ b: Point, reach: Double) -> [Int] {
            let low = Point(x: min(a.x, b.x) - reach, y: min(a.y, b.y) - reach)
            let high = Point(x: max(a.x, b.x) + reach, y: max(a.y, b.y) + reach)
            return boxes.indices.filter { boxes[$0].low.x <= high.x && boxes[$0].high.x >= low.x && boxes[$0].low.y <= high.y && boxes[$0].high.y >= low.y }
        }
        var roads: [Road] = []
        for line in own {
            var points = [line[0]]
            for (p, q) in zip(line, line.dropFirst()) {
                // Where it crosses a base map road, nearer `p` first.
                var crossings: [(t: Double, point: Point)] = []
                for index in near(p, q, reach: 0) {
                    let road = open[index].points
                    for (a, b) in zip(road, road.dropFirst()) {
                        if let t = crossing(p, q, a, b) {
                            crossings.append((t, Point(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)))
                        }
                    }
                }
                for crossing in crossings.sorted(by: { $0.t < $1.t }) { points.append(crossing.point) }
                points.append(q)
            }
            roads.append(Road(points: points))
        }
        for end in ends {
            var best: (point: Point, away: Double)?
            for index in near(end, end, reach: ownJoinReach) {
                let road = open[index].points
                for (a, b) in zip(road, road.dropFirst()) {
                    let on = closest(on: a, b, to: end)
                    let away = on.distance(to: end)
                    if away <= ownJoinReach, best.map({ away < $0.away }) ?? true { best = (on, away) }
                }
            }
            if let best, best.away > mergeMetres { roads.append(Road(points: [end, best.point])) }
        }
        return roads
    }

    /// Where the piece from `p` to `q` crosses the one from `a` to `b`, as
    /// the share of the way from `p` to `q`; `nil` where they do not cross
    /// inside both (meeting at an end is not crossing).
    static func crossing(_ p: Point, _ q: Point, _ a: Point, _ b: Point) -> Double? {
        let rx = q.x - p.x, ry = q.y - p.y, sx = b.x - a.x, sy = b.y - a.y
        let denominator = rx * sy - ry * sx
        guard abs(denominator) > 1e-9 else { return nil }
        let t = ((a.x - p.x) * sy - (a.y - p.y) * sx) / denominator
        let u = ((a.x - p.x) * ry - (a.y - p.y) * rx) / denominator
        guard t > 0, t < 1, u > 0, u < 1 else { return nil }
        return t
    }

    /// The point of the piece from `a` to `b` nearest `point`.
    static func closest(on a: Point, _ b: Point, to point: Point) -> Point {
        let dx = b.x - a.x, dy = b.y - a.y, span = dx * dx + dy * dy
        let t = span > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / span, 0), 1) : 0
        return Point(x: a.x + dx * t, y: a.y + dy * t)
    }
}
