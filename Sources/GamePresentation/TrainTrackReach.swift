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
    /// lays past it (a car and a half), and than a train with real car
    /// lengths lays past it (one car, decision 565: its nose at its head).
    static let behind = Int64(2 * TrainCars.drawnCarLength)
    /// How much track ahead of its head: more than its first car's front
    /// half, and the little more a set drawn at its own lengths lays;
    /// since TURNBACK (2026-11-27) more than a whole car, the longest (a
    /// high-speed car's 25 m), which a train turned round at a terminus
    /// lays ahead of its head (``turnRoom(of:in:)``).
    static let ahead = Int64(1.5 * TrainCars.drawnCarLength)

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
    /// Decision 686: or `ahead` world units of it, for a run driven by
    /// hand (``ManualDriveTrack``).
    static func front(of train: Train, in world: GameWorld, ahead: Int64 = Self.ahead) -> [WorldCoordinate] {
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

    /// TURNBACK (the owner's report of 2026-11-27: the maglev, monorail
    /// and suspended monorail standing a car past the end of their
    /// terminus, into the buildings beyond): GameCore turns a train round
    /// at a stop with its head where its tail was (``GameWorld/reverseTrain(_:)``),
    /// and the maps draw its first car's nose at its head (decision 565),
    /// so its cars, a car longer than its head-to-tail length, were laid a
    /// car past the platform's end it had stopped at. For a train pulling
    /// out of the stop where it was turned round (its timetable's last
    /// stop reverses it and it is on its way to the next, or it stands at
    /// the end of its service), with its tail on a platform of that stop's
    /// station: how far its tail is from that platform's end behind it, in
    /// world units. 0 once turned round, more as it pulls out;
    /// ``TrainCars`` lays ahead of its head what does not fit there.
    /// `nil` for any other train.
    static func turnRoom(of train: Train, in world: GameWorld) -> Int64? {
        let timetable = train.timetable
        let left: Int
        switch train.execution {
        case .travellingToStop(let stop, let cycle)?:
            if stop > 0 {
                left = stop - 1
            } else if cycle > 0 {
                left = timetable.count - 1
            } else {
                return nil
            }
        case nil:
            left = timetable.count - 1
        case .waitingAtStop?:
            return nil
        }
        guard timetable.indices.contains(left), timetable[left].reverses, let (traversal, offset) = tail(of: train, in: world),
              let edge = world.network.edge(traversal.edge) else { return nil }
        let at = traversal.direction == .forward ? offset : edge.length - offset
        let rooms = world.network.platforms(on: edge.id)
            .filter { $0.station == timetable[left].station && $0.start <= at && at <= $0.end }
            .map { traversal.direction == .forward ? at - $0.start : $0.end - at }
        return rooms.min()
    }

    /// Where train `train`'s tail is: the traversal it is on, facing the
    /// way the train does, and how far along it. Its head for a train of
    /// one car; `nil` for a train not placed or a body that cannot be
    /// followed.
    static func tail(of train: Train, in world: GameWorld) -> (traversal: TrackTraversal, offset: Int64)? {
        guard case .onEdge(var traversal, var offset)? = train.position else { return nil }
        var remaining = train.length
        var trail = train.trailEdges.makeIterator()
        while remaining > offset {
            remaining -= offset
            guard let edge = world.network.edge(traversal.edge), let node = world.network.node(edge.start(of: traversal.direction)),
                  let id = trail.next(), let behind = world.network.edge(id), let leaving = behind.traversal(leaving: node.id)
            else { return nil }
            traversal = leaving.reversed
            offset = behind.length
        }
        return (traversal, offset - remaining)
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
