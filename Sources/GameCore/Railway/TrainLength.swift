// Train length (Phase 4.5 Stage S2). A train's position is its head: the
// centre of its first car. Its cars stand one to a tile, centre to centre,
// so a train of more than one car has a body behind its head, a link per
// car after the first, lying over the track it came along. The body cannot
// be derived from the map where the track branches, so the nodes it lies
// over are stored with the train (its trail) and kept up by every command
// and step that moves the head. A train of one car (every train bought
// before Stage S2, and every new one) has no body and behaves exactly as
// before. Its length being whole links, a train at a node that turns round
// is at a node again.

extension Train {
    /// How far apart two cars' centres are, in logical units: a link.
    public static let carLength: Int64 = TrainPosition.linkLength
    /// The fewest and the most cars a train may have.
    public static let minimumCars = 1
    public static let maximumCars = 16

    /// The train's length, in logical units: from its first car's centre
    /// to its last car's, ``carLength`` for each car after the first. 0 for
    /// a train of one car.
    public var length: Int64 {
        Int64(cars - 1) * Self.carLength
    }

    /// How many tiles the train stands over when it stands at the centre
    /// of a tile: one per car. A platform track (see
    /// ``GameWorld/platformTracks(of:)``) at least this long holds it.
    public var tileCount: Int {
        1 + GameWorld.tilesBehind(length: length)
    }

    /// How many nodes a trail holds for a train `length` long at
    /// `position`: every node behind the head that the body reaches or
    /// passes, up to and including the first at or beyond its tail. The
    /// first node behind the head is the tile behind it for a train at a
    /// node, or the `from` end of its link for a train on a link.
    static func trailCount(length: Int64, at position: TrainPosition) -> Int {
        guard length > 0 else { return 0 }
        let link = TrainPosition.linkLength
        switch position {
        case .atNode:
            return Int((length + link - 1) / link)
        case .onLink(_, _, let offset):
            return length <= offset ? 1 : 1 + Int((length - offset + link - 1) / link)
        case .onEdge:
            // On the track network the body is kept as edges, not nodes.
            return 0
        }
    }

    /// The distance from the head to trail node `index` of a train at
    /// `position`.
    static func distanceBehind(_ index: Int, at position: TrainPosition) -> Int64 {
        switch position {
        case .atNode:
            return Int64(index + 1) * TrainPosition.linkLength
        case .onLink(_, _, let offset):
            return offset + Int64(index) * TrainPosition.linkLength
        case .onEdge:
            preconditionFailure("distanceBehind(_:at:) is for positions on the grid")
        }
    }

    /// Whether `trail` has the shape a trail of a train `length` long at
    /// `position` must have, judged without a map: the right count, each
    /// node beside the one before it, starting right behind the head (the
    /// tile behind it for a train at a node, the `from` end of its link for
    /// a train on a link), and never returning to the node two before.
    static func isTrail(_ trail: [GridPosition], length: Int64, at position: TrainPosition?) -> Bool {
        guard let position else { return trail.isEmpty }
        guard trail.count == trailCount(length: length, at: position) else { return false }
        guard let first = trail.first else { return true }
        let spine: [GridPosition]
        switch position {
        case .atNode(let tile, let heading):
            guard TrackDirection(from: tile, to: first) == heading.opposite else { return false }
            spine = [tile] + trail
        case .onLink(let from, let to, _):
            guard first == from else { return false }
            spine = [to] + trail
        case .onEdge:
            // No grid trail on the track network (the count above is 0).
            return false
        }
        for index in spine.indices.dropFirst() where TrackDirection(from: spine[index - 1], to: spine[index]) == nil {
            return false
        }
        for index in spine.indices.dropFirst(2) where spine[index] == spine[index - 2] {
            return false
        }
        return true
    }
}

extension GameWorld {
    /// The trail a train `length` long at `position` would have if placed
    /// there: walking back from the head along the track the way a train
    /// could have come, taking the first way north, east, south, west where
    /// the track branches (see ``exits(from:facing:)``). A train at a node
    /// came from the tile behind it, as one that drove there did, so its
    /// body leaves by that side and it never drives into its own body.
    /// `nil` when the track behind ends before the body does.
    func trailBehind(_ position: TrainPosition, length: Int64) -> [GridPosition]? {
        let count = Train.trailCount(length: length, at: position)
        guard count > 0 else { return [] }
        var trail: [GridPosition]
        var node: GridPosition
        var backward: TrackDirection
        switch position {
        case .atNode(let tile, let heading):
            guard let behind = map.neighbor(of: tile, toward: heading.opposite), isConnected(tile, to: behind) else { return nil }
            trail = [behind]
            node = behind
            backward = heading.opposite
        case .onLink(let from, let to, _):
            trail = [from]
            node = from
            backward = TrackDirection(from: to, to: from)!
        case .onEdge:
            return nil
        }
        while trail.count < count {
            guard let next = exits(from: node, facing: backward).first else { return nil }
            trail.append(next)
            backward = TrackDirection(from: node, to: next)!
            node = next
        }
        return trail
    }

    /// Whether `trail`, with the shape ``Train/isTrail(_:length:at:)``
    /// checks, lies on this map's track the way a train could have come
    /// along it to `position`: each node joined to the one before it, and
    /// each turn one a train may take (see ``exits(from:facing:)``). Track
    /// under a train's body cannot be removed, so this stays true.
    func isTrailOnTrack(_ trail: [GridPosition], behind position: TrainPosition) -> Bool {
        guard !trail.isEmpty else { return true }
        let spine: [GridPosition]
        switch position {
        case .atNode(let tile, _): spine = [tile] + trail
        case .onLink(_, let to, _): spine = [to] + trail
        case .onEdge: return false
        }
        for index in spine.indices.dropFirst() where !isConnected(spine[index - 1], to: spine[index]) {
            return false
        }
        // Driving forward, the train came from spine[index + 1] through
        // spine[index] to spine[index - 1].
        for index in spine.indices.dropFirst().dropLast() {
            let heading = TrackDirection(from: spine[index + 1], to: spine[index])!
            guard canPass(from: spine[index], facing: heading, to: spine[index - 1]) else { return false }
        }
        return true
    }

    /// The trail after the head moved from `old` (with trail `trail`) to
    /// `new`, entering `entered` on the way (the continuation entries it
    /// began to enter in this move): the nodes it now has behind it, nearest
    /// first, cut to the count its length needs.
    static func trail(after old: TrainPosition, trail: [GridPosition], to new: TrainPosition, entered: ArraySlice<GridPosition>, length: Int64) -> [GridPosition] {
        let count = Train.trailCount(length: length, at: new)
        guard count > 0 else { return [] }
        // The nodes from far behind to the head's newest node.
        var history = Array(trail.reversed())
        history.append(old.ahead!.node)
        history.append(contentsOf: entered)
        // The last one is the node the head stands at or is heading for.
        history.removeLast()
        return Array(history.reversed().prefix(count))
    }

    /// The position and trail of a train `length` long at `position`
    /// with trail `trail` after it turns round where it stands: its head
    /// goes to where its tail was, facing away from where its head was, and
    /// its body lies back over the same track toward where its head was.
    ///
    /// - Precondition: `trail` fits `length` and `position`.
    static func reversed(_ position: TrainPosition, trail: [GridPosition], length: Int64) -> (position: TrainPosition, trail: [GridPosition]) {
        guard length > 0, let last = trail.indices.last else { return (position.reversed, []) }
        let link = TrainPosition.linkLength
        // The nodes from the tail's node back to the head: the trail's far
        // end first, then toward the head, then the head's own node or the
        // `to` end of its link.
        var toward = Array(trail.reversed())
        let headEnd: GridPosition
        switch position {
        case .atNode(let tile, _): headEnd = tile
        case .onLink(_, let to, _): headEnd = to
        case .onEdge: preconditionFailure("reversed(_:trail:length:) is for positions on the grid")
        }
        toward.append(headEnd)
        let tailNode = trail[last]
        let tailDistance = Train.distanceBehind(last, at: position)
        let newPosition: TrainPosition
        if tailDistance == length {
            // The tail is at a node: the head goes there, facing on past it.
            newPosition = .atNode(tailNode, heading: TrackDirection(from: toward[1], to: tailNode)!)
        } else if last == 0, case .onLink(let from, let to, let offset) = position {
            // The tail is on the head's own link, between it and `from`.
            precondition(from == tailNode)
            newPosition = .onLink(from: to, to: from, offset: link - offset + length)
        } else {
            // The tail is on the link from the node before it to its node.
            let before = toward[1]
            let beforeDistance = last == 0 ? 0 : Train.distanceBehind(last - 1, at: position)
            newPosition = .onLink(from: before, to: tailNode, offset: length - beforeDistance)
        }
        // Behind the new head: every node from the one before the tail's
        // node back to the head's.
        let count = Train.trailCount(length: length, at: newPosition)
        return (newPosition, Array(toward.dropFirst().prefix(count)))
    }

    /// The track a train covers beyond its head's own tile or link: the
    /// links its body lies over, and the nodes it passes or reaches.
    func bodyResources(of train: Train) -> [TrackResource] {
        guard let position = train.position, !train.trail.isEmpty else { return [] }
        let length = train.length
        var resources: [TrackResource] = []
        var previous: GridPosition
        switch position {
        case .atNode(let tile, _):
            previous = tile
        case .onLink(let from, _, _):
            previous = from
        case .onEdge:
            return []
        }
        for (index, node) in train.trail.enumerated() {
            let distance = Train.distanceBehind(index, at: position)
            if case .onLink = position, index == 0 {
                // The head's own link is already its resource.
            } else {
                resources.append(.link(between: previous, and: node))
            }
            if distance <= length {
                resources.append(.tile(node))
            }
            previous = node
        }
        return resources
    }
}
