import GameCore

// The whole map, small, in a corner of the game screen (ARCHITECTURE
// decision 116): the track and the lines over a plain ground, with a frame
// round what the map view shows; a tap moves the map there. TheoTown keeps
// such a map in its status bar and OpenTTD has a "map of the world"
// window; the references have none (the web maps zoom out instead). What it
// draws is read from the world when the network or the lines change, and
// the frame from the camera; nothing is stored.

/// What the small map draws: straight lines between the ends of each
/// stretch of track (curves are lost at that size), each line as straight
/// lines through its stops in order (a ring back to its first), and the
/// stations.
public struct MiniMap: Equatable, Sendable {
    /// One straight line, in world units.
    public struct Segment: Equatable, Sendable {
        public let from: WorldPoint
        public let to: WorldPoint

        public init(from: WorldPoint, to: WorldPoint) {
            self.from = from
            self.to = to
        }
    }

    /// A service line through its stops.
    public struct Line: Equatable, Sendable {
        public let id: LineID
        /// The player's colour, `nil` for the line's own (``LineColor``).
        public let color: LineColor?
        public let stops: [WorldPoint]

        public init(id: LineID, color: LineColor?, stops: [WorldPoint]) {
            self.id = id
            self.color = color
            self.stops = stops
        }
    }

    /// A point in world units, x east and y south.
    public struct WorldPoint: Hashable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// The part of the world the small map shows: the whole map.
    public let region: WorldRegion
    /// Every stretch of track, by edge ID.
    public let track: [Segment]
    /// The lines with two stops or more, by ID.
    public let lines: [Line]
    /// The stations, by ID.
    public let stations: [WorldPoint]

    public init(region: WorldRegion, track: [Segment] = [], lines: [Line] = [], stations: [WorldPoint] = []) {
        self.region = region
        self.track = track
        self.lines = lines
        self.stations = stations
    }

    /// What `world` shows on its small map.
    public init(world: GameWorld) {
        let network = world.network
        var positions: [TrackNodeID: WorldPoint] = [:]
        for node in network.nodes {
            positions[node.id] = WorldPoint(x: Double(node.position.x), y: Double(node.position.y))
        }
        let track = network.edges.compactMap { edge -> Segment? in
            guard let from = positions[edge.from], let to = positions[edge.to] else { return nil }
            return Segment(from: from, to: to)
        }
        let lines = world.lines.compactMap { line -> Line? in
            var stops = line.stops.compactMap { world.station(id: $0).map(Self.point) }
            guard stops.count > 1 else { return nil }
            // A ring runs on from its last stop to its first (decision 49).
            if line.isRing, let first = stops.first { stops.append(first) }
            return Line(id: line.id, color: line.color, stops: stops)
        }
        self.init(
            region: WorldRegion(bounds: world.bounds),
            track: track,
            lines: lines,
            stations: world.stations.map(Self.point)
        )
    }

    private static func point(_ station: Station) -> WorldPoint {
        WorldPoint(x: Double(station.location.x), y: Double(station.location.y))
    }

    /// The size the small map takes for `region`: its longer side
    /// `longestSide`, its shorter side in proportion but at least
    /// ``shortestSide`` (a long, thin map, as Taiwan, stays wide enough
    /// to tap).
    public static func size(of region: WorldRegion, longestSide: Double) -> ScreenSize {
        let width = max(region.width, 1), height = max(region.height, 1)
        if width >= height {
            return ScreenSize(width: longestSide, height: max(shortestSide, longestSide * height / width))
        }
        return ScreenSize(width: max(shortestSide, longestSide * width / height), height: longestSide)
    }

    /// The narrowest side of the small map, in points.
    public static let shortestSide = 44.0
}

/// Where the world lies on the small map: the whole of ``MiniMap/region``
/// fitted into `size`, centred along the side it does not fill.
public struct MiniMapProjection: Equatable, Sendable {
    public let region: WorldRegion
    public let size: ScreenSize
    /// Points per world unit.
    public let scale: Double
    /// Where the region's top-left corner lies, in points.
    public let origin: ScreenPoint

    public init(region: WorldRegion, size: ScreenSize) {
        self.region = region
        self.size = size
        let width = max(region.width, 1), height = max(region.height, 1)
        scale = min(size.width / width, size.height / height)
        origin = ScreenPoint(x: (size.width - width * scale) / 2, y: (size.height - height * scale) / 2)
    }

    /// Where `point` lies on the small map.
    public func screenPoint(of point: MiniMap.WorldPoint) -> ScreenPoint {
        ScreenPoint(x: origin.x + (point.x - region.minX) * scale, y: origin.y + (point.y - region.minY) * scale)
    }

    /// The world point under `point` of the small map, kept within the
    /// region: a tap beside the map goes to its nearest edge.
    public func worldPoint(at point: ScreenPoint) -> MiniMap.WorldPoint {
        let x = region.minX + (point.x - origin.x) / scale
        let y = region.minY + (point.y - origin.y) / scale
        return MiniMap.WorldPoint(x: min(max(x, region.minX), region.maxX), y: min(max(y, region.minY), region.maxY))
    }

    /// The frame of `visible` (the map view's ``PlanCamera/visibleRegion``)
    /// on the small map, as its corners, cut to the small map; `nil` when
    /// none of it lies on the map.
    public func frame(of visible: WorldRegion) -> (topLeft: ScreenPoint, bottomRight: ScreenPoint)? {
        let minX = max(visible.minX, region.minX), minY = max(visible.minY, region.minY)
        let maxX = min(visible.maxX, region.maxX), maxY = min(visible.maxY, region.maxY)
        guard minX < maxX, minY < maxY else { return nil }
        return (screenPoint(of: .init(x: minX, y: minY)), screenPoint(of: .init(x: maxX, y: maxY)))
    }
}
