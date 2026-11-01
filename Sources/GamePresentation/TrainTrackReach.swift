import GameCore

/// The track just past a train's two ends, where the map draws the halves
/// of its first and last cars that stand past its body (decision 538).
///
/// GameCore's body (``GameWorld/bodyPath(of:)``) runs from the first car's
/// centre to the last car's, so the map lays the front half of the first
/// car and the back half of the last (and the cars of a set drawn at its
/// own, longer lengths, decision 399) past it. They were laid straight on
/// (decision 205); on a sharp curve, Zhuzhong's viaduct platform on the
/// Liujia Line (104.1), the last car swung 9 m off the track, out over the
/// ground platform below. Now they follow the track: ahead of the head,
/// the way the train is to go, and behind the tail, the way it came (the
/// edges the network says a train could have come by past its trail).
/// Only drawing: nothing is written back into the world.
enum TrainTrackReach {
    /// How much track past its tail a train's cars are laid along, in
    /// world units: more than ``TrainCars/cars(body:heading:lengths:gaps:)``
    /// lays past it (a car and a half).
    static let behind = Int64(2 * TrainCars.drawnCarLength)
    /// How much track ahead of its head: more than its first car's front
    /// half, and the little more a set drawn at its own lengths lays.
    static let ahead = Int64(TrainCars.drawnCarLength)

    /// Train `train`'s centre line from its head back along its body and
    /// then ``behind`` further along the track it came by, head first, as
    /// ``GameWorld/bodyPath(of:)`` walks it: the same points over its body.
    /// Shorter where the track ends; empty for a train not placed.
    static func back(of train: Train, in world: GameWorld) -> [WorldCoordinate] {
        guard let position = train.position, let head = world.location(of: position),
              case .onEdge(var traversal, var start) = position else { return [] }
        var points = [head.position]
        var remaining = train.length + behind
        var trail = train.trailEdges.makeIterator()
        while remaining > 0, let geometry = world.trackGeometry(of: traversal.edge) {
            let end = max(0, start - remaining)
            walk(geometry, traversal.direction, from: start, to: end, into: &points)
            remaining -= start - end
            guard remaining > 0, let edge = world.network.edge(traversal.edge),
                  let node = world.network.node(edge.start(of: traversal.direction)) else { break }
            // Its trail first; past it, the lowest numbered edge a train
            // could have come by (GameCore's `networkTrailBehind`).
            guard let id = trail.next() ?? node.ends.first(where: { $0.exits.contains(traversal.edge) })?.edge,
                  let behindEdge = world.network.edge(id), let leaving = behindEdge.traversal(leaving: node.id) else { break }
            traversal = leaving.reversed
            start = behindEdge.length
        }
        return points
    }

    /// The track ahead of train `train`'s head, ``ahead`` long, head
    /// first: along the edge it is on, then the way it is to go
    /// (``GameWorld/pathAhead(of:)``), then the lowest numbered way on.
    /// Shorter where the track ends; empty for a train not placed.
    static func front(of train: Train, in world: GameWorld) -> [WorldCoordinate] {
        guard let position = train.position, let head = world.location(of: position),
              case .onEdge(var traversal, var start) = position else { return [] }
        var points = [head.position]
        var remaining = ahead
        var path = world.pathAhead(of: train.id).makeIterator()
        while remaining > 0, let geometry = world.trackGeometry(of: traversal.edge) {
            let end = min(geometry.length, start + remaining)
            walk(geometry, traversal.direction, from: start, to: end, into: &points)
            remaining -= end - start
            guard remaining > 0 else { break }
            let ways = world.transitions(after: traversal)
            guard let next = path.next().flatMap({ planned in ways.first { $0 == planned } }) ?? ways.first else { break }
            traversal = next
            start = 0
        }
        return points
    }

    /// Along `geometry` travelled `direction`, from offset `from` to
    /// offset `to` (either way): every sampled point strictly between,
    /// then the point at `to`, appended to `points`.
    private static func walk(_ geometry: TrackGeometry, _ direction: TrackEdgeDirection, from: Int64, to: Int64,
                             into points: inout [WorldCoordinate]) {
        let (a, b) = direction == .forward ? (from, to) : (geometry.length - from, geometry.length - to)
        let distances = geometry.distances
        let between = distances.indices.filter { a < b ? (distances[$0] > a && distances[$0] < b) : (distances[$0] < a && distances[$0] > b) }
        for index in a < b ? between : between.reversed() {
            points.append(geometry.points[index])
        }
        points.append(geometry.location(at: b).position)
    }
}
