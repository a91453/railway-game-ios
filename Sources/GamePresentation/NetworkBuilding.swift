import GameCore

// Building the track network at any angle (Stage C1). GameCore has had the
// continuous network since Stage S3 (nodes at world coordinates, straight and
// cubic Bézier edges, heights and structures from S4, platforms from S4/S5);
// this file is what the network tool needs to lay it from taps on the map:
// which node or point a tap means, the curve that joins existing track
// smoothly, and what the stretch would cost, worked out by running the very
// commands on a copy of the world. Nothing here is a game rule: GameCore
// decides whether the track can be built, and a refused build changes
// nothing.

/// One end of the stretch of track the network tool lays: a node of the
/// track network, or a point where a new node goes.
public enum NetworkAnchor: Hashable, Sendable {
    case node(TrackNodeID)
    case point(PlanPoint)
}

/// What a tap does with the network tool.
public enum NetworkToolMode: CaseIterable, Hashable, Sendable {
    /// Taps pick the two ends of a new stretch of track.
    case build
    /// A tap picks a place on an edge for a station's platform.
    case platform
    /// A tap picks an edge to remove.
    case remove

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .build: language.text("Build", "鋪設")
        case .platform: language.text("Platform", "月台")
        case .remove: language.text("Remove", "拆除")
        }
    }
}

/// A place on an edge of the track network: `distance` along it from its
/// `from` node.
public struct NetworkEdgePoint: Hashable, Sendable {
    public let edge: TrackEdgeID
    public let distance: Int64

    public init(edge: TrackEdgeID, distance: Int64) {
        self.edge = edge
        self.distance = distance
    }
}

/// The stretch of track the network tool would build between its two
/// anchors, as GameCore would build it.
public struct NetworkPreview: Hashable, Sendable {
    public let curve: TrackCurve
    public let profile: TrackProfile
    /// The centre line, for drawing; just the two ends when the network
    /// tool refuses them before asking GameCore, or they make no edge.
    public let points: [WorldCoordinate]
    /// The length in world units (horizontal chainage); the straight
    /// distance between the ends without a curve, 0 when they make no edge.
    public let length: Int64
    public let startHeight: Int64
    public let endHeight: Int64
    /// Whether it joins the track already at its start, or at its end: it
    /// leaves that node the opposite way to an edge ending there, so trains
    /// pass from one to the other.
    public let joinsStart: Bool
    public let joinsEnd: Bool
    /// What GameCore charged for it on a copy of the world, or `nil` when
    /// it refused.
    public let cost: Money?
    /// Why GameCore refused it, as the player reads it; `nil` when it
    /// would be built.
    public let problem: String?
}

/// The network tool's geometry, ported from the owner's `Ci/` reference
/// build mode (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`):
/// points are placed freely, at any angle and off any lattice; a new stretch
/// continues the track it starts from smoothly; and a turn of more than 90°
/// from the track to the new point is refused. Presentation only: the curve
/// is a suggestion in whole world units that GameCore then checks like any
/// other command.
public enum NetworkBuilding {
    /// The closest a new node may be to the node it is joined from: 22 m,
    /// the reference's `ANCHOR_MIN_SPACING_M` ("too close to an existing
    /// node", `metro.edit.node.too_close`).
    public static let minimumSpacing: Int64 = 22 * WorldCoordinate.unitsPerMetre

    /// How far, in screen points, a tap reaches to an existing node or
    /// edge. The reference picks within 50 m (`ANCHOR_PICK_RADIUS_M`) on a
    /// city map; this map is drawn about ten times closer, so the reach is
    /// set on the screen instead.
    public static let touchRadius = 24.0

    /// The height steps the tool offers for a new node: 2 m, from 64 m below
    /// the ground to 64 m above it (GameCore's height range).
    public static let heightStep: Int64 = 2 * WorldCoordinate.unitsPerMetre
    public static let heightRange: ClosedRange<Int64> = -4_096...4_096

    /// The curve from `start` to `end`: straight, or a cubic Bézier that
    /// leaves `start` along `startTangent` and leaves `end`, back along the
    /// edge, along `endTangent`, whichever are given. `nil` when the ends
    /// are the same point, or a tangent turns more than 90° from the
    /// straight line to the other end.
    ///
    /// The reference draws a line as a centripetal Catmull-Rom spline
    /// through its points (`catmullRom`), the end points repeated, which as
    /// a Bézier puts each end's handle a third of the chord along the chord.
    /// It reshapes the whole line as it grows; a GameCore edge never changes
    /// once built, so here the end that continues existing track keeps
    /// that track's direction instead (handle a third of the chord along
    /// it), and a free end is the reference's: along the chord. Two free
    /// ends make a straight edge, as in the reference. Its turn check
    /// (`_turnAngleDeg` against `MIN_TURN_ANGLE_DEG`, an angle of 90° or
    /// more at the vertex) is the sign of a dot product, exact in integers.
    ///
    /// The handles are rounded to whole units, which turns a tangent by
    /// far less than GameCore's 1 in 16, so the curve still joins.
    public static func curve(from start: PlanPoint, leaving startTangent: PlanVector?, to end: PlanPoint, leaving endTangent: PlanVector?) -> TrackCurve? {
        let chord = PlanVector(dx: end.x - start.x, dy: end.y - start.y)
        guard chord.dx != 0 || chord.dy != 0 else { return nil }
        if let startTangent, !turnsAtMostRightAngle(startTangent, toward: chord) { return nil }
        if let endTangent, !turnsAtMostRightAngle(endTangent, toward: chord.reversed) { return nil }
        guard startTangent != nil || endTangent != nil else { return .straight }
        let third = (Double(chord.dx) * Double(chord.dx) + Double(chord.dy) * Double(chord.dy)).squareRoot() / 3
        return .cubic(
            offset(start, along: startTangent ?? chord, by: third),
            offset(end, along: endTangent ?? chord.reversed, by: third)
        )
    }

    /// Whether `direction` turns at most 90° from `chord`: their dot
    /// product is not negative.
    static func turnsAtMostRightAngle(_ direction: PlanVector, toward chord: PlanVector) -> Bool {
        direction.dx * chord.dx + direction.dy * chord.dy >= 0
    }

    /// `point` moved `distance` along `direction`, rounded to whole units.
    private static func offset(_ point: PlanPoint, along direction: PlanVector, by distance: Double) -> PlanPoint {
        let dx = Double(direction.dx), dy = Double(direction.dy)
        let scale = distance / (dx * dx + dy * dy).squareRoot()
        return PlanPoint(x: point.x + Int64((dx * scale).rounded()), y: point.y + Int64((dy * scale).rounded()))
    }
}

extension GameWorld {
    /// The node of the track network nearest `point` in plan, if one lies
    /// within `radius` world units; the lowest numbered of equally near.
    public func trackNode(near point: PlanPoint, within radius: Int64) -> TrackNode? {
        var best: (node: TrackNode, distance: Int64)?
        for node in network.nodes {
            let dx = node.position.x - point.x, dy = node.position.y - point.y
            let squared = dx * dx + dy * dy
            guard squared <= radius * radius else { continue }
            if best == nil || squared < best!.distance {
                best = (node, squared)
            }
        }
        return best?.node
    }

    /// The place on an edge of the track network nearest `point` in plan,
    /// if an edge passes within `radius` world units of it; the lowest
    /// numbered edge of equally near ones.
    public func trackEdgePoint(near point: PlanPoint, within radius: Int64) -> NetworkEdgePoint? {
        let px = Double(point.x), py = Double(point.y)
        let limit = Double(radius) * Double(radius)
        var best: (point: NetworkEdgePoint, distance: Double)?
        for edge in network.edges {
            guard let geometry = trackGeometry(of: edge.id) else { continue }
            for index in geometry.points.indices.dropLast() {
                let a = geometry.points[index], b = geometry.points[index + 1]
                let ax = Double(a.x), ay = Double(a.y)
                let dx = Double(b.x) - ax, dy = Double(b.y) - ay
                let span = dx * dx + dy * dy
                let t = span > 0 ? min(1, max(0, ((px - ax) * dx + (py - ay) * dy) / span)) : 0
                let ex = ax + t * dx - px, ey = ay + t * dy - py
                let squared = ex * ex + ey * ey
                guard squared <= limit, best == nil || squared < best!.distance else { continue }
                let start = geometry.distances[index], end = geometry.distances[index + 1]
                let distance = start + Int64((Double(end - start) * t).rounded())
                best = (NetworkEdgePoint(edge: edge.id, distance: distance), squared)
            }
        }
        return best?.point
    }

    /// Where a new edge must leave the node `id` to join the edges that end
    /// there, one direction per edge end (the opposite of the way it leaves),
    /// in the order of the ends. Empty for a node with no edges.
    func joiningDirections(at id: TrackNodeID) -> [PlanVector] {
        network.node(id)?.ends.map(\.direction.reversed) ?? []
    }

    /// Of the ways to join the track at node `id` (see
    /// ``joiningDirections(at:)``), the one pointing most nearly at
    /// `target`, if it turns at most 90° from it; the first of equally near.
    func joiningDirection(at id: TrackNodeID, toward target: PlanPoint) -> PlanVector? {
        guard let node = network.node(id) else { return nil }
        let chord = PlanVector(dx: target.x - node.position.x, dy: target.y - node.position.y)
        var best: (direction: PlanVector, cosine: Double)?
        for direction in joiningDirections(at: id) where NetworkBuilding.turnsAtMostRightAngle(direction, toward: chord) {
            let dx = Double(direction.dx), dy = Double(direction.dy)
            let cosine = (dx * Double(chord.dx) + dy * Double(chord.dy)) / (dx * dx + dy * dy).squareRoot()
            if best == nil || cosine > best!.cosine {
                best = (direction, cosine)
            }
        }
        return best?.direction
    }

    /// Where `anchor` lies, at `height` for a new point.
    func position(of anchor: NetworkAnchor, height: Int64) -> WorldCoordinate? {
        switch anchor {
        case .node(let id): network.node(id)?.position
        case .point(let point): WorldCoordinate(x: point.x, y: point.y, z: height)
        }
    }
}
