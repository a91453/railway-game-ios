import GameCore

/// Chooses how large the world is drawn. Sizes are in points, given for
/// ``referenceLength`` of the world (the ``MapProjection/referenceSize``).
///
/// Presentation-only: the world itself has no notion of screen size.
public enum MapScale {
    /// The length of the world the map's sizes are given for: 1024 world
    /// units, 16 m. The zoom range, the levels of detail and the widths of
    /// lines and marks are sizes per 16 m. A drawing measure only: the world
    /// has no cells (Stage F3d). It was a tile's width until then, and the
    /// sizes kept their values.
    public static let referenceLength: Int64 = 1_024

    /// Below this, 16 m of the world is too small to tap reliably, so the
    /// whole map is not shown at once by default.
    public static let smallestComfortableSize = 22.0
    /// The default size when the whole map would be too small (phones).
    public static let compactSize = 32.0
    public static let largestSize = 64.0
    /// How many times one zoom button step changes the size (Stage E1):
    /// one zoom level of the references' web maps (MapLibre's `zoomIn`). A
    /// new game's 16 km map is a few hundred times smaller on a phone than
    /// at ``largestSize``, too far for steps of a fixed size.
    public static let zoomFactor = 2.0

    /// The size at which a world `worldWidth` × `worldHeight` units
    /// exactly fits a `width` × `height` viewport.
    public static func fittingSize(width: Double, height: Double, worldWidth: Double, worldHeight: Double) -> Double {
        guard worldWidth > 0, worldHeight > 0 else { return compactSize }
        let reference = Double(referenceLength)
        return max(0, min(width / (worldWidth / reference), height / (worldHeight / reference)))
    }

    /// The default size: the whole map when it stays comfortably tappable
    /// (tablets), otherwise ``compactSize`` with scrolling (phones).
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

    /// Where the world point `point` is drawn, in map coordinates, with
    /// ``referenceLength`` of the world `referenceSize` points long: the
    /// map is drawn from above, so the height is not shown (a top-down
    /// debug projection of the track network, Stage S3).
    public static func center(of point: WorldCoordinate, referenceSize: Double) -> (x: Double, y: Double) {
        let scale = referenceSize / Double(referenceLength)
        return (Double(point.x) * scale, Double(point.y) * scale)
    }

    /// Where a train at `position` is drawn, in map coordinates: its point
    /// on the edge's centre line in `world` (see ``GameWorld/location(of:)``),
    /// or the map's corner without a world that has it.
    ///
    /// Display only: worked out from the authoritative position each time
    /// the map is drawn, never stored, and never fed back into GameCore.
    public static func center(of position: TrainPosition, in world: GameWorld? = nil, referenceSize: Double) -> (x: Double, y: Double) {
        world?.location(of: position).map { center(of: $0.position, referenceSize: referenceSize) } ?? (0, 0)
    }

    /// The line a train's body is drawn along, in map coordinates: along
    /// the edges' centre lines in `world` (see ``GameWorld/bodyPath(of:)``)
    /// from its head to its tail; without a world that has the train, just
    /// the corner. Empty for an unplaced train.
    ///
    /// Display only, like ``center(of:in:referenceSize:)``.
    public static func bodyPoints(of train: Train, in world: GameWorld? = nil, referenceSize: Double) -> [(x: Double, y: Double)] {
        guard train.position != nil else { return [] }
        let path = world?.bodyPath(of: train.id) ?? []
        return path.isEmpty ? [(0, 0)] : path.map { center(of: $0, referenceSize: referenceSize) }
    }

    /// The unit vector, in map coordinates, of the way a train at `position`
    /// faces: the way its edge runs there in `world` (see
    /// ``GameWorld/location(of:)``), or east without a world that has it.
    public static func facing(of position: TrainPosition, in world: GameWorld? = nil) -> (dx: Double, dy: Double) {
        guard let direction = world?.location(of: position)?.direction else { return (1, 0) }
        let length = (Double(direction.dx) * Double(direction.dx) + Double(direction.dy) * Double(direction.dy)).squareRoot()
        return length > 0 ? (Double(direction.dx) / length, Double(direction.dy) / length) : (1, 0)
    }

    /// Below this size the map is drawn as an overview (see
    /// ``detail(forReferenceSize:)``).
    public static let overviewBelow = 20.0

    /// How much of the map to draw at `referenceSize` (Stage R's levels of
    /// detail): ``MapDetail/overview`` when 16 m is small on the screen,
    /// where only the lines of track, the stations as marks and the trains
    /// stay readable, and ``MapDetail/full`` otherwise.
    public static func detail(forReferenceSize referenceSize: Double) -> MapDetail {
        referenceSize < overviewBelow ? .overview : .full
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
