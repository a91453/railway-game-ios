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
    /// How much one zoom step changes the tile size.
    public static let zoomStep = 8.0

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
        clamped(size + zoomStep, fitting: fittingSize)
    }

    public static func zoomedOut(from size: Double, fitting fittingSize: Double) -> Double {
        clamped(size - zoomStep, fitting: fittingSize)
    }

    /// The tile under a point in map coordinates, where `(0, 0)` is the
    /// north-west corner and x grows east, y south. The result may lie
    /// outside the map; callers check it against the map.
    public static func position(atX x: Double, y: Double, tileSize: Double) -> GridPosition {
        precondition(tileSize > 0, "position(atX:y:tileSize:) requires a positive tile size")
        return GridPosition(x: Int((x / tileSize).rounded(.down)), y: Int((y / tileSize).rounded(.down)))
    }

    /// The centre of the tile at `position`, in map coordinates.
    public static func center(of position: GridPosition, tileSize: Double) -> (x: Double, y: Double) {
        ((Double(position.x) + 0.5) * tileSize, (Double(position.y) + 0.5) * tileSize)
    }

    /// Where the world point `point` is drawn, in map coordinates: a tile
    /// is ``WorldCoordinate/tileSize`` world units wide, and the map is
    /// drawn from above, so the height is not shown (a top-down debug
    /// projection of the track network, Stage S3).
    public static func center(of point: WorldCoordinate, tileSize: Double) -> (x: Double, y: Double) {
        let scale = tileSize / Double(WorldCoordinate.tileSize)
        return (Double(point.x) * scale, Double(point.y) * scale)
    }

    /// Where a train at `position` is drawn, in map coordinates: the centre
    /// of its tile, or `offset / linkLength` of the way from the centre of
    /// `from` to the centre of `to`; on the track network (Stage S3), its
    /// point on the edge's centre line in `world` (see
    /// ``GameWorld/location(of:)``), or the map's corner without a world
    /// that has it. A position on the grid needs no world.
    ///
    /// Display only: worked out from the authoritative position each time
    /// the map is drawn, never stored, and never fed back into GameCore.
    public static func center(of position: TrainPosition, in world: GameWorld? = nil, tileSize: Double) -> (x: Double, y: Double) {
        switch position {
        case .atNode(let tile, _):
            return center(of: tile, tileSize: tileSize)
        case .onLink(let from, let to, let offset):
            let start = center(of: from, tileSize: tileSize)
            let end = center(of: to, tileSize: tileSize)
            let fraction = Double(offset) / Double(TrainPosition.linkLength)
            return (start.x + (end.x - start.x) * fraction, start.y + (end.y - start.y) * fraction)
        case .onEdge:
            return world?.location(of: position).map { center(of: $0.position, tileSize: tileSize) } ?? (0, 0)
        }
    }

    /// The line a train's body is drawn along, in map coordinates: from
    /// where its head is drawn (see ``center(of:tileSize:)``) through
    /// the centre of each node of its trail to its tail, `length` behind
    /// the head. Just the head for a train of one car; empty for an
    /// unplaced train.
    ///
    /// On the track network (Stage S3) it follows the edges' centre lines
    /// in `world` (see ``GameWorld/bodyPath(of:)``); without a world that
    /// has the train, just the corner. A train on the grid needs no world.
    ///
    /// Display only, like ``center(of:in:tileSize:)``.
    public static func bodyPoints(of train: Train, in world: GameWorld? = nil, tileSize: Double) -> [(x: Double, y: Double)] {
        guard let position = train.position else { return [] }
        if case .onEdge = position {
            let path = world?.bodyPath(of: train.id) ?? []
            return path.isEmpty ? [(0, 0)] : path.map { center(of: $0, tileSize: tileSize) }
        }
        var points = [center(of: position, in: world, tileSize: tileSize)]
        let length = train.length
        var distance: Int64 = 0
        var next: Int64
        switch position {
        case .atNode: next = TrainPosition.linkLength
        case .onLink(_, _, let offset): next = offset
        case .onEdge: return points
        }
        for node in train.trail {
            let previous = points[points.count - 1]
            let target = center(of: node, tileSize: tileSize)
            if next <= length {
                points.append(target)
            } else {
                // The tail lies on the way to this node.
                let fraction = Double(length - distance) / Double(next - distance)
                points.append((previous.x + (target.x - previous.x) * fraction, previous.y + (target.y - previous.y) * fraction))
                break
            }
            distance = next
            next += TrainPosition.linkLength
        }
        return points
    }

    /// The unit vector, in map coordinates, of the way a train at `position`
    /// faces: its heading at a node, or from `from` toward `to` on a link;
    /// on the track network (Stage S3), the way its edge runs there in
    /// `world` (see ``GameWorld/location(of:)``), or east without a world
    /// that has it. A position on the grid needs no world.
    public static func facing(of position: TrainPosition, in world: GameWorld? = nil) -> (dx: Double, dy: Double) {
        switch position {
        case .onEdge:
            guard let direction = world?.location(of: position)?.direction else { return (1, 0) }
            let length = (Double(direction.dx) * Double(direction.dx) + Double(direction.dy) * Double(direction.dy)).squareRoot()
            return length > 0 ? (Double(direction.dx) / length, Double(direction.dy) / length) : (1, 0)
        case .atNode(_, let heading):
            switch heading {
            case .north: return (0, -1)
            case .east: return (1, 0)
            case .south: return (0, 1)
            case .west: return (-1, 0)
            }
        case .onLink(let from, let to, _):
            // The ends of a link on the track are orthogonal neighbours.
            // Comparing rather than subtracting cannot overflow.
            return (step(from: from.x, to: to.x), step(from: from.y, to: to.y))
        }
    }

    private static func step(from start: Int, to end: Int) -> Double {
        end > start ? 1 : end < start ? -1 : 0
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
