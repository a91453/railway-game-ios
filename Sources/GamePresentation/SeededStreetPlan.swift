import GameCore

/// ARCHITECTURE decision 270: a blank map's seeded streets (decision 263)
/// for the 2D map, the same the 3D map lays: each grid line's run of
/// edges of one kind, one road, in world units, with its width.
public struct SeededStreetPlan: Sendable {
    public struct Road: Hashable, Sendable {
        /// From one end to the other along a grid line, world units.
        public let points: [PlanPoint]
        /// Its paved width, metres (``Map3DBaseMap/RoadKind/width(ramp:)``).
        public let width: Double
        /// A main road or a street (the real map's major roads), not a lane.
        public let major: Bool
        /// The larger is drawn over the smaller.
        public let rank: Int
    }

    public let roads: [Road]

    public var isEmpty: Bool { roads.isEmpty }

    init(edges: [Map3DSeededStreets.Edge: Map3DBaseMap.RoadKind]) {
        let cell = Int64(Land.cellLength)
        var lines: [Map3DSeededStreets.Edge: [(along: Int, kind: Map3DBaseMap.RoadKind)]] = [:]
        for (edge, kind) in edges {
            lines[Map3DSeededStreets.Edge(horizontal: edge.horizontal, line: edge.line, along: 0), default: []].append((edge.along, kind))
        }
        var roads: [Road] = []
        for (line, edges) in lines.sorted(by: { $0.key < $1.key }) {
            let sorted = edges.sorted { $0.along < $1.along }
            var start = 0
            for index in 1...sorted.count {
                // A run ends where the next edge is not next to it or is of
                // another kind.
                guard index == sorted.count || sorted[index].along != sorted[index - 1].along + 1 || sorted[index].kind != sorted[start].kind else { continue }
                let first = Int64(sorted[start].along) * cell, last = Int64(sorted[index - 1].along + 1) * cell, at = Int64(line.line) * cell
                let kind = sorted[start].kind
                roads.append(Road(points: line.horizontal ? [PlanPoint(x: first, y: at), PlanPoint(x: last, y: at)]
                                      : [PlanPoint(x: at, y: first), PlanPoint(x: at, y: last)],
                                  width: Double(kind.width(ramp: false)), major: kind.rawValue >= Map3DBaseMap.RoadKind.tertiary.rawValue,
                                  rank: kind.rawValue))
                start = index
            }
        }
        self.roads = roads.sorted { $0.rank < $1.rank }
    }

    /// The roads touching `region` (world units), the smaller first.
    public func roads(in region: WorldRegion) -> [Road] {
        roads.filter { road in
            let xs = road.points.map(\.x), ys = road.points.map(\.y)
            return Double(xs.max() ?? 0) >= region.minX && Double(xs.min() ?? 0) <= region.maxX
                && Double(ys.max() ?? 0) >= region.minY && Double(ys.min() ?? 0) <= region.maxY
        }
    }
}
