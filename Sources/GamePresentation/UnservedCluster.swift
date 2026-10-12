import GameCore

// The biggest settlement no station serves (ARCHITECTURE decision 177): the
// station master points a first line that loses money at the next town, and
// later the commissions and the company's rating will ask the same
// question. Worked out from the world's land (a real-world map's people, a
// blank map's towns), so it needs no population file; presentation only,
// nothing is stored.

/// A settlement of land no station's catchment reaches.
public struct UnservedCluster: Hashable, Sendable {
    /// The middle of its people (a weighted centroid), where the camera goes.
    public let center: PlanPoint
    /// The residents and jobs in it.
    public let people: Int64

    public init(center: PlanPoint, people: Int64) {
        self.center = center
        self.people = people
    }

    /// The blocks the land is grouped into: 16 cells a side, 1,024 m.
    public static let blockCells = 16
    /// The least people a cluster has to count as a town to extend a line to.
    public static let minimumPeople: Int64 = 1_500

    /// The clusters of `world`'s land that no open station's catchment
    /// (``Land/catchmentRadius``) reaches, the biggest first. Ties go to
    /// the lower row, then column. Empty land and parks do not count.
    public static func all(in world: GameWorld) -> [UnservedCluster] {
        let reach = Land.catchmentRadius * Land.catchmentRadius
        let stations = world.stations.filter { $0.operationMode != .closed }.map(\.location)
        struct Block {
            var people: Int64 = 0
            var x: Int64 = 0
            var y: Int64 = 0
        }
        var blocks: [Int: Block] = [:]
        var keys: [Int] = []
        let columns = Land.columns(in: world.bounds) / blockCells + 2
        for cell in world.land.cells where cell.residents + cell.jobs > 0 && cell.use != .park {
            let middle = cell.middle
            let covered = stations.contains {
                let dx = $0.x - middle.x, dy = $0.y - middle.y
                return dx * dx + dy * dy < reach
            }
            if covered { continue }
            let key = (cell.row / blockCells) * columns + cell.column / blockCells
            let weight = cell.residents + cell.jobs
            if blocks[key] == nil { keys.append(key) }
            blocks[key, default: Block()].people += weight
            blocks[key, default: Block()].x += middle.x * weight
            blocks[key, default: Block()].y += middle.y * weight
        }
        return keys.sorted().compactMap { key in
            guard let block = blocks[key], block.people > 0 else { return nil }
            return UnservedCluster(center: PlanPoint(x: block.x / block.people, y: block.y / block.people), people: block.people)
        }
        .sorted { $0.people > $1.people }
    }

    /// The biggest unserved settlement, if one has ``minimumPeople``.
    public static func largest(in world: GameWorld) -> UnservedCluster? {
        all(in: world).first.flatMap { $0.people >= minimumPeople ? $0 : nil }
    }

    /// The settlement of ``minimumPeople`` and more nearest to a station
    /// (a station of the railway, so the line can reach it by extending),
    /// with that station's point. `nil` without a station or a settlement.
    public static func nearestToTheRailway(in world: GameWorld) -> (cluster: UnservedCluster, from: PlanPoint)? {
        let stations = world.stations.filter { $0.operationMode != .closed }.map(\.location)
        guard !stations.isEmpty else { return nil }
        var best: (cluster: UnservedCluster, from: PlanPoint, squared: Int64)?
        for cluster in all(in: world) where cluster.people >= minimumPeople {
            for station in stations {
                let dx = cluster.center.x - station.x, dy = cluster.center.y - station.y
                let squared = dx * dx + dy * dy
                if best == nil || squared < best!.squared { best = (cluster, station, squared) }
            }
        }
        return best.map { ($0.cluster, $0.from) }
    }

    /// Where `self` lies from `origin`: one of the eight compass points
    /// (north is up, so towards smaller y) and the distance in tenths of a
    /// kilometre (world units are 1/64 m).
    public func direction(from origin: PlanPoint) -> (compass: Compass, tenthsOfKm: Int64) {
        let dx = center.x - origin.x, dy = center.y - origin.y
        let squared = dx * dx + dy * dy
        let meters = Self.squareRoot(squared) / 64
        return (Compass(dx: dx, dy: -dy), (meters + 50) / 100)
    }

    /// Integer square root, rounded down.
    static func squareRoot(_ value: Int64) -> Int64 {
        guard value > 0 else { return 0 }
        var low: Int64 = 0, high: Int64 = 3_037_000_499
        while low < high {
            let mid = (low + high + 1) / 2
            if mid * mid <= value { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The eight compass points.
    public enum Compass: Int, Sendable {
        case east, northeast, north, northwest, west, southwest, south, southeast

        /// The point of the compass towards `(dx, dy)`, y up.
        init(dx: Int64, dy: Int64) {
            // The angle in eighths of a turn, by comparing against the
            // tangents of 22.5° and 67.5° (0.4142 and 2.4142) exactly
            // enough: 5/12 and 12/5 are within a hair.
            let (ax, ay) = (dx.magnitude, dy.magnitude)
            let axis: Int  // 0 east-west, 1 diagonal, 2 north-south
            if ay * 12 < ax * 5 { axis = 0 } else if ax * 12 < ay * 5 { axis = 2 } else { axis = 1 }
            switch (axis, dx >= 0, dy >= 0) {
            case (0, true, _): self = .east
            case (0, false, _): self = .west
            case (2, _, true): self = .north
            case (2, _, false): self = .south
            case (_, true, true): self = .northeast
            case (_, false, true): self = .northwest
            case (_, false, false): self = .southwest
            case (_, true, false): self = .southeast
            }
        }

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .east: language.text("east", "東")
            case .northeast: language.text("northeast", "東北")
            case .north: language.text("north", "北")
            case .northwest: language.text("northwest", "西北")
            case .west: language.text("west", "西")
            case .southwest: language.text("southwest", "西南")
            case .south: language.text("south", "南")
            case .southeast: language.text("southeast", "東南")
            }
        }
    }
}
