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

    /// Where a train at `position` is drawn, in map coordinates: the centre
    /// of its tile, or `offset / linkLength` of the way from the centre of
    /// `from` to the centre of `to`.
    ///
    /// Display only: worked out from the authoritative position each time
    /// the map is drawn, never stored, and never fed back into GameCore.
    public static func center(of position: TrainPosition, tileSize: Double) -> (x: Double, y: Double) {
        switch position {
        case .atNode(let tile, _):
            return center(of: tile, tileSize: tileSize)
        case .onLink(let from, let to, let offset):
            let start = center(of: from, tileSize: tileSize)
            let end = center(of: to, tileSize: tileSize)
            let fraction = Double(offset) / Double(TrainPosition.linkLength)
            return (start.x + (end.x - start.x) * fraction, start.y + (end.y - start.y) * fraction)
        }
    }

    /// The unit vector, in map coordinates, of the way a train at `position`
    /// faces: its heading at a node, or from `from` toward `to` on a link.
    public static func facing(of position: TrainPosition) -> (dx: Double, dy: Double) {
        switch position {
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
}
