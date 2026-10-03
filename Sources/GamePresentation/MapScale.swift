import GameCore

/// Chooses how large one map tile is drawn, and maps touch locations back to
/// tiles. Sizes are in points.
///
/// Presentation-only: the map itself has no notion of screen size.
public enum MapScale {
    /// Below this, tiles are too small to tap reliably, so the whole map is
    /// not shown at once by default.
    public static let smallestComfortableSize = 22.0
    /// Default tile size when the whole map would be too small (phones).
    public static let compactSize = 32.0
    public static let largestSize = 64.0
    /// How many times one zoom button step changes the tile size (Stage E1):
    /// one zoom level of the references' web maps (MapLibre's `zoomIn`). A
    /// new game's 16 km map is a few hundred times smaller on a phone than
    /// at ``largestSize``, too far for steps of a fixed size.
    public static let zoomFactor = 2.0

    /// The tile size at which a `columns` × `rows` map exactly fits a
    /// `width` × `height` viewport.
    public static func fittingSize(width: Double, height: Double, columns: Int, rows: Int) -> Double {
        guard columns > 0, rows > 0 else { return compactSize }
        return max(0, min(width / Double(columns), height / Double(rows)))
    }

    /// The default tile size: the whole map when its tiles stay comfortably
    /// tappable (tablets), otherwise ``compactSize`` with scrolling (phones).
    public static func automaticSize(fitting fittingSize: Double) -> Double {
        fittingSize >= smallestComfortableSize ? min(fittingSize, largestSize) : compactSize
    }

    /// The smallest size zooming out allows: the whole map, but never
    /// smaller than necessary.
    public static func minimumSize(fitting fittingSize: Double) -> Double {
        min(fittingSize, automaticSize(fitting: fittingSize))
    }

    /// Keeps a size inside the allowed zoom range for the current viewport.
    public static func clamped(_ size: Double, fitting fittingSize: Double) -> Double {
        min(max(size, minimumSize(fitting: fittingSize)), largestSize)
    }

    public static func zoomedIn(from size: Double, fitting fittingSize: Double) -> Double {
        clamped(size * zoomFactor, fitting: fittingSize)
    }

    public static func zoomedOut(from size: Double, fitting fittingSize: Double) -> Double {
        clamped(size / zoomFactor, fitting: fittingSize)
    }

    /// Where the world point `point` is drawn, in map coordinates: a tile
    /// is ``WorldCoordinate/tileSize`` world units wide, and the map is
    /// drawn from above, so the height is not shown (a top-down debug
    /// projection of the track network, Stage S3).
    public static func center(of point: WorldCoordinate, tileSize: Double) -> (x: Double, y: Double) {
        let scale = tileSize / Double(WorldCoordinate.tileSize)
        return (Double(point.x) * scale, Double(point.y) * scale)
    }

    /// Where a train at `position` is drawn, in map coordinates: its point
    /// on the edge's centre line in `world` (see ``GameWorld/location(of:)``),
    /// or the map's corner without a world that has it.
    ///
    /// Display only: worked out from the authoritative position each time
    /// the map is drawn, never stored, and never fed back into GameCore.
    public static func center(of position: TrainPosition, in world: GameWorld? = nil, tileSize: Double) -> (x: Double, y: Double) {
        world?.location(of: position).map { center(of: $0.position, tileSize: tileSize) } ?? (0, 0)
    }

    /// The line a train's body is drawn along, in map coordinates: along
    /// the edges' centre lines in `world` (see ``GameWorld/bodyPath(of:)``)
    /// from its head to its tail; without a world that has the train, just
    /// the corner. Empty for an unplaced train.
    ///
    /// Display only, like ``center(of:in:tileSize:)``.
    public static func bodyPoints(of train: Train, in world: GameWorld? = nil, tileSize: Double) -> [(x: Double, y: Double)] {
        guard train.position != nil else { return [] }
        let path = world?.bodyPath(of: train.id) ?? []
        return path.isEmpty ? [(0, 0)] : path.map { center(of: $0, tileSize: tileSize) }
    }

    /// The unit vector, in map coordinates, of the way a train at `position`
    /// faces: the way its edge runs there in `world` (see
    /// ``GameWorld/location(of:)``), or east without a world that has it.
    public static func facing(of position: TrainPosition, in world: GameWorld? = nil) -> (dx: Double, dy: Double) {
        guard let direction = world?.location(of: position)?.direction else { return (1, 0) }
        let length = (Double(direction.dx) * Double(direction.dx) + Double(direction.dy) * Double(direction.dy)).squareRoot()
        return length > 0 ? (Double(direction.dx) / length, Double(direction.dy) / length) : (1, 0)
    }

    /// Below this tile size the map is drawn as an overview (see
    /// ``detail(forTileSize:)``).
    public static let overviewBelow = 20.0

    /// How much of the map to draw at `tileSize` (Stage R's levels of
    /// detail): ``MapDetail/overview`` for small tiles, where only the lines
    /// of track, the stations as marks and the trains stay readable, and
    /// ``MapDetail/full`` otherwise.
    public static func detail(forTileSize tileSize: Double) -> MapDetail {
        tileSize < overviewBelow ? .overview : .full
    }

    /// Projects only segments touching the view (including the stroke's
    /// margin in screen points). Separate runs must stay separate: joining
    /// across an offscreen stretch could draw a false line through the view.
    /// Each vertex goes through the projection, also for turned/tilted maps.
    /// Overview drawing may skip vertices within `minimumSpacing` points;
    /// the first and last vertex of every visible run are always kept.
    public static func visiblePolylines(
        _ points: [WorldCoordinate],
        projection: some MapProjection,
        margin: Double,
        minimumSpacing: Double = 0
    ) -> [[ScreenPoint]] {
        guard points.count > 1 else { return [] }
        let region = projection.visibleRegion.expanded(by: max(0, margin) / projection.pointsPerUnit)
        var runs: [[ScreenPoint]] = []
        var run: [ScreenPoint] = []
        func finish() {
            guard run.count > 1 else { run = []; return }
            if minimumSpacing > 0 {
                var simplified = [run[0]]
                for point in run.dropFirst().dropLast() {
                    let last = simplified[simplified.count - 1]
                    let dx = point.x - last.x, dy = point.y - last.y
                    if dx * dx + dy * dy >= minimumSpacing * minimumSpacing {
                        simplified.append(point)
                    }
                }
                simplified.append(run[run.count - 1])
                runs.append(simplified)
            } else {
                runs.append(run)
            }
            run = []
        }
        for index in 1..<points.count {
            let start = points[index - 1], end = points[index]
            let bounds = WorldRegion(
                minX: Double(min(start.x, end.x)), minY: Double(min(start.y, end.y)),
                maxX: Double(max(start.x, end.x)), maxY: Double(max(start.y, end.y))
            )
            if region.intersects(bounds) {
                if run.isEmpty { run.append(projection.screenPoint(of: start)) }
                run.append(projection.screenPoint(of: end))
            } else {
                finish()
            }
        }
        finish()
        return runs
    }
}

/// How much of the map is drawn. Presentation only.
public enum MapDetail: Hashable, Sendable {
    /// Track as thin lines, stations as plain marks, trains; no rail
    /// detail, station symbols or names.
    case overview
    /// Everything: ballast and rails, buffer stops, station badges with
    /// their symbol and name, and trains. No grid lines (Stage F1).
    case full
}
