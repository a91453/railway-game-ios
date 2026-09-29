import GameCore

/// Decision 27, written a second time for ``ReferenceWorld``: train length,
/// the body behind the head, the pull along a station's platforms, and
/// platform tracks. Written from the rules, and differently where it can
/// be: the body is a list of points with their distance behind the head,
/// cut by walking those distances rather than by a count in closed form;
/// turning round finds the tail by walking the points; the pull counts the
/// tiles behind by adding tiles until they cover the body; platform tracks
/// come from labels spread until nothing changes, not a flood fill.
extension ReferenceWorld {
    static let carUnits: Int64 = 1024

    /// One car to a tile: a link from each car's centre to the next.
    static func length(_ train: Train) -> Int64 {
        Int64(train.cars - 1) * carUnits
    }

    static func length(cars: Int) -> Int64 {
        Int64(cars - 1) * carUnits
    }

    /// How far behind a train at `position` the first node behind its head
    /// is: a whole link at a node, its offset on a link.
    private static func firstDistance(_ position: TrainPosition) -> Int64 {
        switch position {
        case .atNode: linkLength
        case .onLink(_, _, let offset): offset
        case .onEdge: preconditionFailure("the grid reference is for positions on the grid")
        }
    }

    /// `nodes`, nearest first, as the body of a train `length` long at
    /// `position`: up to and including the first at or beyond its tail;
    /// `nil` if they run out first. Empty without length.
    static func cut(_ nodes: [GridPosition], at position: TrainPosition, length: Int64) -> [GridPosition]? {
        guard length > 0 else { return [] }
        var kept: [GridPosition] = []
        var distance = firstDistance(position)
        for node in nodes {
            kept.append(node)
            if distance >= length { return kept }
            distance += linkLength
        }
        return nil
    }

    /// The head's node (the `to` end on a link) and then the trail, each
    /// with its distance behind the head (the `to` end's is negative).
    static func points(_ position: TrainPosition, _ trail: [GridPosition]) -> [(node: GridPosition, distance: Int64)] {
        let head: (GridPosition, Int64)
        switch position {
        case .atNode(let tile, _): head = (tile, 0)
        case .onLink(_, let to, let offset): head = (to, offset - linkLength)
        case .onEdge: preconditionFailure("the grid reference is for positions on the grid")
        }
        var distance = firstDistance(position)
        var result = [head]
        for node in trail {
            result.append((node, distance))
            distance += linkLength
        }
        return result
    }

    /// Placing: back from the head the way a train could have come. At a
    /// node, from the tile behind it; then each node the first way north,
    /// east, south, west a train walking backward may take.
    func body(behind position: TrainPosition, length: Int64) -> [GridPosition]? {
        guard length > 0 else { return [] }
        var nodes: [GridPosition]
        var node: GridPosition
        var walking: TrackDirection
        switch position {
        case .atNode(let tile, let heading):
            let behind = step(tile, heading.opposite)
            guard joined(tile, behind) else { return nil }
            (nodes, node, walking) = ([behind], behind, heading.opposite)
        case .onLink(let from, let to, _):
            (nodes, node, walking) = ([from], from, stepDirection(from: to, to: from)!)
        case .onEdge:
            preconditionFailure("the grid reference is for positions on the grid")
        }
        while Self.cut(nodes, at: position, length: length) == nil {
            guard let way = TrackDirection.allCases.first(where: { joined(node, step(node, $0)) && mayTurn(at: node, facing: walking, to: $0) }) else {
                return nil
            }
            node = step(node, way)
            walking = way
            nodes.append(node)
        }
        return Self.cut(nodes, at: position, length: length)
    }

    /// Moving: the nodes the head went through, newest first, then the old
    /// body, cut for the new place. `passed` are the nodes it entered, in
    /// order, after the node ahead of it before.
    static func body(after old: TrainPosition, _ trail: [GridPosition], to new: TrainPosition, passed: [GridPosition], length: Int64) -> [GridPosition] {
        let path = [ahead(old).0] + passed
        // The last node of the path is the one the head stands at or heads for.
        let behind = Array(path.dropLast().reversed()) + trail
        return cut(behind, at: new, length: length)!
    }

    /// Turning round: the head goes to the tail, found by walking the
    /// points, facing on the way the body ran; the body is then the points
    /// back toward the old head.
    static func turnedWithBody(_ position: TrainPosition, _ trail: [GridPosition], length: Int64) -> (TrainPosition, [GridPosition]) {
        guard length > 0 else { return (turned(position), []) }
        let points = points(position, trail)
        let k = points.firstIndex { $0.distance >= length }!
        let (b, atB) = points[k]
        let (a, atA) = points[k - 1]
        let head: TrainPosition = atB == length
            ? .atNode(b, heading: stepDirection(from: a, to: b)!)
            : .onLink(from: a, to: b, offset: length - atA)
        return (head, cut(points[..<k].reversed().map(\.node), at: head, length: length)!)
    }

    /// Decision 27: to the station, then as many tiles further along its
    /// platforms as the body reaches behind the head's tile, while one
    /// ahead (the first way north, east, south, west) is a platform.
    func route(from start: TrainPosition, toStation id: StationID, length: Int64 = 0) -> [GridPosition]? {
        let targets = Set(platforms(of: id))
        guard var route = route(from: start, toAny: targets) else { return nil }
        var behind = 0
        while Int64(behind) * Self.linkLength + Self.linkLength / 2 < length {
            behind += 1
        }
        var (node, heading) = Self.ahead(start)
        for next in route {
            heading = stepDirection(from: node, to: next)!
            node = next
        }
        for _ in 0..<behind {
            guard let way = TrackDirection.allCases.first(where: { way in
                let next = step(node, way)
                return targets.contains(next) && joined(node, next) && mayTurn(at: node, facing: heading, to: way)
            }) else { break }
            node = step(node, way)
            heading = way
            route.append(node)
        }
        return route
    }

    /// Decision 27: stopped there, with every tile the body reaches into a
    /// platform of the station.
    func stationsBesideWholeTrain(_ id: TrainID) -> [StationID] {
        guard let train = trains.first(where: { $0.id == id.rawValue }) else { return [] }
        let length = Self.length(train)
        var reached: [GridPosition] = []
        var distance = Self.linkLength
        for node in train.trail {
            // The node's tile starts half a link nearer the head.
            if distance - Self.linkLength / 2 < length { reached.append(node) }
            distance += Self.linkLength
        }
        return stationsStoppedAt(by: id).filter { station in
            let platforms = platforms(of: station)
            return reached.allSatisfy(platforms.contains)
        }
    }

    /// Decision 27: platforms labelled by the first platform they are
    /// joined to through other platforms.
    func platformTracks(of id: StationID) -> [[GridPosition]] {
        let platforms = platforms(of: id)
        var label = Array(platforms.indices)
        var changed = true
        while changed {
            changed = false
            for i in platforms.indices {
                for j in platforms.indices where joined(platforms[i], platforms[j]) && label[j] != label[i] {
                    let low = min(label[i], label[j])
                    label[i] = low
                    label[j] = low
                    changed = true
                }
            }
        }
        return Set(label).sorted().map { first in platforms.indices.filter { label[$0] == first }.map { platforms[$0] } }
    }

    /// Decision 27: every node the body reaches, and every link it lies
    /// over.
    func bodyResources(of train: Train) -> [TrackResource] {
        guard let position = train.position else { return [] }
        let length = Self.length(train)
        let points = Self.points(position, train.trail)
        var found: [TrackResource] = []
        for k in points.indices.dropFirst() {
            if points[k].distance <= length { found.append(.node(.tile(points[k].node))) }
            if points[k - 1].distance < length {
                let (p, q) = (points[k - 1].node, points[k].node)
                found.append(.wholeLink((p.y, p.x) < (q.y, q.x) ? .link(p, q) : .link(q, p)))
            }
        }
        return found
    }
}
