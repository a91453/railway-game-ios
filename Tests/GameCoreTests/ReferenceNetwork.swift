import GameCore

/// The track network of Stage S3 (ARCHITECTURE decision 29) written a second
/// time, straight from the documented rules, for differential testing. It
/// shares no code with GameCore beyond the plain value types used for inputs
/// and outputs, and is written differently on purpose:
///
/// - nodes and edges live in dictionaries by number, not sorted arrays, and
///   a node keeps no list of its ends: they are found by scanning every edge;
/// - a curve is sampled by de Casteljau's construction on integers scaled by
///   the sample count (not by summing Bernstein weights), rounded by floor
///   division (not by a shift), and square roots are found by binary search;
/// - which edges join at a node is decided on every query, with the
///   tolerance written as a product rather than a quotient;
/// - a train moves one unit at a time;
/// - a train's body is a stretch of absolute distance along the path it came
///   by: the path is rebuilt from its trail edges each time, and the trail,
///   turning round and the track occupied are all read off that stretch;
/// - routes come from distances to the destination relaxed until nothing
///   changes, followed by a greedy walk.
///
/// Only for maps of a few tiles: coordinates must stay within the map, so
/// every product here stays far inside an `Int64`.
extension ReferenceWorld {
    /// An edge of the network with its centre line, worked out here.
    struct NetworkEdge: Equatable {
        var from: Int
        var to: Int
        var curve: TrackCurve
        var points: [PlanPoint]
        /// The distance along the line to each point.
        var distances: [Int64]
        /// The way the edge leaves its `from` node, and its `to` node.
        var leavesFrom: PlanVector
        var leavesTo: PlanVector

        var length: Int64 {
            distances[distances.count - 1]
        }
    }

    /// A traversal as the reference keeps it: an edge number and whether it
    /// runs from the edge's `from` node to its `to` node.
    struct Run: Hashable {
        var edge: Int
        var forward: Bool

        init(edge: Int, forward: Bool) {
            self.edge = edge
            self.forward = forward
        }

        init?(_ traversal: TrackTraversal) {
            guard case .edge(let number) = traversal.edge else { return nil }
            self.init(edge: number, forward: traversal.direction == .forward)
        }

        var traversal: TrackTraversal {
            TrackTraversal(edge: .edge(edge), direction: forward ? .forward : .backward)
        }

        var flipped: Run {
            Run(edge: edge, forward: !forward)
        }
    }

    // MARK: - Integer geometry, written again

    /// ⌊√n⌋ by binary search. Only for `0 <= n < 2^62`.
    static func floorRoot(_ n: Int64) -> Int64 {
        var low: Int64 = 0
        var high: Int64 = 1 << 31
        while low < high {
            let middle = (low + high + 1) / 2
            if middle * middle <= n {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// √n to the nearest integer: ⌊√n⌋ + 1 exactly when √n ≥ ⌊√n⌋ + ½,
    /// that is when 4n ≥ (2⌊√n⌋ + 1)² (never equal for an integer n).
    static func nearestRoot(_ n: Int64) -> Int64 {
        let root = floorRoot(n)
        return 4 * n >= (2 * root + 1) * (2 * root + 1) ? root + 1 : root
    }

    static func distance(_ a: PlanPoint, _ b: PlanPoint) -> Int64 {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        return nearestRoot(dx * dx + dy * dy)
    }

    /// ⌊a / b⌋ for `b > 0`.
    static func floorDivide(_ a: Int64, _ b: Int64) -> Int64 {
        let quotient = a / b
        return a % b != 0 && a < 0 ? quotient - 1 : quotient
    }

    /// `a / b` rounded to the nearest integer, halves up, for `b > 0`.
    static func nearestQuotient(_ a: Int64, _ b: Int64) -> Int64 {
        floorDivide(2 * a + b, 2 * b)
    }

    /// The sampled line of an edge from `p0` to `p3` with `curve`, and
    /// the distance to each point, or `nil` if it doubles back (a cusp) or a
    /// control point sits on its end.
    static func centreLine(_ p0: PlanPoint, _ p3: PlanPoint, _ curve: TrackCurve) -> (points: [PlanPoint], distances: [Int64])? {
        var points: [PlanPoint]
        switch curve {
        case .straight:
            points = [p0, p3]
        case .cubic(let c1, let c2):
            guard c1 != p0, c2 != p3 else { return nil }
            let polygon = distance(p0, c1) + distance(c1, c2) + distance(c2, p3)
            let count = Int64([8, 16, 32, 64, 128, 256, 512, 1024].first { 64 * $0 >= polygon } ?? 1024)
            let scale = count * count * count
            points = []
            for i in 0...count {
                // De Casteljau, each level scaled by `count` more.
                func blend(_ u: Int64, _ v: Int64) -> Int64 { u * (count - i) + v * i }
                func coordinate(_ a: Int64, _ b: Int64, _ c: Int64, _ d: Int64) -> Int64 {
                    let first = (blend(a, b), blend(b, c), blend(c, d))
                    let second = (blend(first.0, first.1), blend(first.1, first.2))
                    return nearestQuotient(blend(second.0, second.1), scale)
                }
                let point = PlanPoint(x: coordinate(p0.x, c1.x, c2.x, p3.x), y: coordinate(p0.y, c1.y, c2.y, p3.y))
                if points.last != point { points.append(point) }
            }
        }
        var distances: [Int64] = [0]
        for k in 1..<points.count {
            if k >= 2 {
                let (ax, ay) = (points[k - 1].x - points[k - 2].x, points[k - 1].y - points[k - 2].y)
                let (bx, by) = (points[k].x - points[k - 1].x, points[k].y - points[k - 1].y)
                if ax * bx + ay * by <= 0 { return nil }
            }
            distances.append(distances[k - 1] + distance(points[k - 1], points[k]))
        }
        return (points, distances)
    }

    // MARK: - Topology

    /// Whether `point` lies over the map.
    func overMap(_ point: PlanPoint) -> Bool {
        point.x >= 0 && point.y >= 0 && point.x < Int64(width) * 1024 && point.y < Int64(height) * 1024
    }

    /// The way edge `number` leaves node `node`, or `nil` if it does not end
    /// there.
    func way(of number: Int, at node: Int) -> PlanVector? {
        guard let edge = networkEdges[number] else { return nil }
        if edge.from == node { return edge.leavesFrom }
        if edge.to == node { return edge.leavesTo }
        return nil
    }

    func endNode(_ run: Run) -> Int {
        let edge = networkEdges[run.edge]!
        return run.forward ? edge.to : edge.from
    }

    func startNode(_ run: Run) -> Int {
        let edge = networkEdges[run.edge]!
        return run.forward ? edge.from : edge.to
    }

    /// The runs a train may go on to after `run`, by ascending edge: every
    /// other edge at the node that leaves it the opposite way to within 1 in
    /// 16, that is with a negative dot product and sixteen times the cross
    /// product no larger than it.
    func runs(after run: Run) -> [Run] {
        guard networkEdges[run.edge] != nil else { return [] }
        let node = endNode(run)
        let arriving = way(of: run.edge, at: node)!
        return networkEdges.keys.sorted().compactMap { number -> Run? in
            guard number != run.edge, let leaving = way(of: number, at: node) else { return nil }
            let dot = arriving.dx * leaving.dx + arriving.dy * leaving.dy
            let cross = arriving.dx * leaving.dy - arriving.dy * leaving.dx
            guard dot < 0, 16 * abs(cross) <= -dot else { return nil }
            return Run(edge: number, forward: networkEdges[number]!.from == node)
        }
    }

    func isOnNetwork(_ traversal: TrackTraversal, _ offset: Int64) -> Bool {
        guard let run = Run(traversal), let edge = networkEdges[run.edge] else { return false }
        return offset >= 0 && offset <= edge.length
    }

    // MARK: - Commands

    mutating func buildNetworkNode(at position: WorldCoordinate) -> GameError? {
        guard position.z == 0, overMap(position.plan), !networkNodes.values.contains(position) else { return .invalidTrackGeometry }
        guard nextNetworkNode != Int.max else { return .idsExhausted }
        networkNodes[nextNetworkNode] = position
        nextNetworkNode += 1
        return nil
    }

    mutating func buildNetworkEdge(from: TrackNodeID, to: TrackNodeID, curve: TrackCurve) -> GameError? {
        guard case .node(let a) = from, let start = networkNodes[a] else { return .unknownTrackNode(from) }
        guard case .node(let b) = to, let end = networkNodes[b] else { return .unknownTrackNode(to) }
        let controls: [PlanPoint]
        switch curve {
        case .straight: controls = []
        case .cubic(let c1, let c2): controls = [c1, c2]
        }
        guard a != b, controls.allSatisfy(overMap), let line = Self.centreLine(start.plan, end.plan, curve) else { return .invalidTrackGeometry }
        guard nextNetworkEdge != Int.max else { return .idsExhausted }
        let tiles = max(1, (line.distances.last! + 1023) / 1024)
        if let error = funds(costs.track * tiles) { return error }
        balance -= costs.track * tiles
        let (leavesFrom, leavesTo): (PlanVector, PlanVector)
        switch curve {
        case .straight:
            leavesFrom = PlanVector(dx: end.x - start.x, dy: end.y - start.y)
            leavesTo = PlanVector(dx: start.x - end.x, dy: start.y - end.y)
        case .cubic(let c1, let c2):
            leavesFrom = PlanVector(dx: c1.x - start.x, dy: c1.y - start.y)
            leavesTo = PlanVector(dx: c2.x - end.x, dy: c2.y - end.y)
        }
        networkEdges[nextNetworkEdge] = NetworkEdge(
            from: a, to: b, curve: curve, points: line.points, distances: line.distances, leavesFrom: leavesFrom, leavesTo: leavesTo
        )
        nextNetworkEdge += 1
        return nil
    }

    mutating func removeNetworkEdge(_ id: TrackEdgeID) -> GameError? {
        guard case .edge(let number) = id, networkEdges[number] != nil else { return .unknownTrackEdge(id) }
        let used = trains.contains { train in
            if case .onEdge(let traversal, _)? = train.position, traversal.edge == id { return true }
            return train.trailEdges.contains(number)
        }
        guard !used else { return .trackEdgeInUse(id) }
        networkEdges[number] = nil
        return nil
    }

    mutating func removeNetworkNode(_ id: TrackNodeID) -> GameError? {
        guard case .node(let number) = id, networkNodes[number] != nil else { return .unknownTrackNode(id) }
        guard !networkEdges.values.contains(where: { $0.from == number || $0.to == number }) else { return .trackNodeInUse(id) }
        networkNodes[number] = nil
        return nil
    }

    /// A continuation of traversals: on the network each must be a run the
    /// train may take after the one before; on the grid, links from the node
    /// ahead, each checked as a grid continuation.
    mutating func setContinuation(_ id: TrainID, along traversals: [TrackTraversal]) -> GameError? {
        guard let i = trains.firstIndex(where: { $0.id == id.rawValue }) else { return .unknownTrain(id) }
        guard let position = trains[i].position else { return .trainNotPlaced(id) }
        guard trains[i].service == nil else { return .trainServiceActive(id) }
        guard case .onEdge(let traversal, _) = position else {
            var node = Self.ahead(position).0
            var nodes: [GridPosition] = []
            for next in traversals {
                guard case .link(let a, let b) = next.edge, (a.y, a.x) < (b.y, b.x) else { return .invalidContinuation }
                let (from, to) = next.direction == .forward ? (a, b) : (b, a)
                guard from == node else { return .invalidContinuation }
                nodes.append(to)
                node = to
            }
            return setContinuation(id, nodes)
        }
        var run = Run(traversal)!
        var numbers: [Int] = []
        for next in traversals {
            guard let wanted = Run(next), runs(after: run).contains(wanted) else { return .invalidContinuation }
            numbers.append(wanted.edge)
            run = wanted
        }
        trains[i].edges = numbers
        trains[i].cursor = 0
        return nil
    }

    // MARK: - Trains

    /// The runs of a train's path, far end first, ending with its head's run:
    /// its trail edges walked back from the start of the head's edge.
    func path(of train: Train) -> [Run] {
        guard case .onEdge(let traversal, _)? = train.position else { return [] }
        var runs = [Run(traversal)!]
        var node = startNode(runs[0])
        for number in train.trailEdges {
            let edge = networkEdges[number]!
            let run = Run(edge: number, forward: edge.to == node)
            runs.insert(run, at: 0)
            node = startNode(run)
        }
        return runs
    }

    /// Where each run of `path` starts, measured along it, and its length.
    func spans(_ path: [Run]) -> [(start: Int64, end: Int64)] {
        var result: [(start: Int64, end: Int64)] = []
        var at: Int64 = 0
        for run in path {
            let length = networkEdges[run.edge]!.length
            result.append((at, at + length))
            at += length
        }
        return result
    }

    /// The trail of a train whose head is on the last run of `path` at
    /// `offset`: every earlier run that ends beyond the tail, nearest first.
    func trail(on path: [Run], offset: Int64, length: Int64) -> [Int] {
        let spans = spans(path)
        let head = spans[spans.count - 1].start + offset
        return path.indices.dropLast().reversed().filter { spans[$0].end > head - length }.map { path[$0].edge }
    }

    /// Decision 29: the body a placed train gets, walking back from the start
    /// of its edge, the lowest numbered edge that joins first.
    func networkBody(behind traversal: TrackTraversal, offset: Int64, length: Int64) -> [Int]? {
        var trail: [Int] = []
        var covered = offset
        var ahead = Run(traversal)!
        while covered < length {
            let node = startNode(ahead)
            let candidates = networkEdges.keys.sorted().compactMap { number -> Run? in
                guard number != ahead.edge, way(of: number, at: node) != nil else { return nil }
                let run = Run(edge: number, forward: networkEdges[number]!.to == node)
                return runs(after: run).contains(ahead) ? run : nil
            }
            guard let behind = candidates.first else { return nil }
            trail.append(behind.edge)
            covered += networkEdges[behind.edge]!.length
            ahead = behind
        }
        return trail
    }

    /// One basic step on the network, a unit at a time.
    func steppedOnNetwork(_ train: Train) -> Train {
        var train = train
        guard case .onEdge(let traversal, let start) = train.position else { return train }
        let before = path(of: train)
        var run = Run(traversal)!
        var offset = start
        var remaining = train.rate
        var entered: [Run] = []
        while remaining > 0 {
            if offset < networkEdges[run.edge]!.length {
                offset += 1
                remaining -= 1
                continue
            }
            guard train.cursor < train.edges.count else { break }
            let next = train.edges[train.cursor]
            guard let taken = runs(after: run).first(where: { $0.edge == next }) else { break }
            train.cursor += 1
            entered.append(taken)
            run = taken
            offset = 0
        }
        train.position = .onEdge(run.traversal, offset: offset)
        train.trailEdges = trail(on: before + entered, offset: offset, length: Self.length(train))
        if train.cursor == train.edges.count {
            train.edges = []
            train.cursor = 0
        }
        return train
    }

    /// Decision 29: turned round where it stands, by flipping the path it
    /// came along.
    func turnedOnNetwork(_ train: Train) -> Train {
        var train = train
        guard case .onEdge(let traversal, let offset) = train.position else { return train }
        let length = Self.length(train)
        let edgeLength = networkEdges[Run(traversal)!.edge]!.length
        guard length > 0 else {
            train.position = .onEdge(traversal.reversed, offset: edgeLength - offset)
            return train
        }
        let path = path(of: train)
        let spans = spans(path)
        let total = spans[spans.count - 1].end
        let head = spans[spans.count - 1].start + offset
        // Flipped: a point at x along the path is at total − x.
        let flipped = path.reversed().map(\.flipped)
        let flippedSpans = self.spans(flipped)
        let newHead = total - (head - length)
        let k = flippedSpans.indices.first { flippedSpans[$0].start < newHead && newHead <= flippedSpans[$0].end }!
        train.position = .onEdge(flipped[k].traversal, offset: newHead - flippedSpans[k].start)
        train.trailEdges = trail(on: Array(flipped[...k]), offset: newHead - flippedSpans[k].start, length: length)
        return train
    }

    /// Decision 29: every node within the train's stretch of its path, and
    /// every edge with a point of the stretch strictly inside it.
    func networkResources(of train: Train) -> [TrackResource] {
        guard case .onEdge(_, let offset)? = train.position else { return [] }
        let path = path(of: train)
        let spans = spans(path)
        let head = spans[spans.count - 1].start + offset
        let tail = head - Self.length(train)
        var found: Set<TrackResource> = []
        for (run, span) in zip(path, spans) {
            if tail <= span.start && span.start <= head { found.insert(.node(.node(startNode(run)))) }
            if tail <= span.end && span.end <= head { found.insert(.node(.node(endNode(run)))) }
            if tail < span.end && head > span.start { found.insert(.edge(.edge(run.edge))) }
        }
        return found.sorted()
    }

    // MARK: - Queries

    func networkLength(of id: TrackEdgeID) -> Int64? {
        guard case .edge(let number) = id else { return nil }
        return networkEdges[number]?.length
    }

    /// The point `offset` along a run and the way it goes, by a linear scan
    /// of the samples.
    func networkLocation(_ traversal: TrackTraversal, offset: Int64) -> TrackLocation? {
        guard let run = Run(traversal), let edge = networkEdges[run.edge], offset >= 0, offset <= edge.length else { return nil }
        let along = run.forward ? offset : edge.length - offset
        var k = 0
        while k + 2 < edge.points.count, edge.distances[k + 1] <= along {
            k += 1
        }
        let (a, b) = (edge.points[k], edge.points[k + 1])
        let piece = edge.distances[k + 1] - edge.distances[k]
        let into = along - edge.distances[k]
        let point = WorldCoordinate(x: a.x + Self.nearestQuotient((b.x - a.x) * into, piece), y: a.y + Self.nearestQuotient((b.y - a.y) * into, piece))
        let way = run.forward ? PlanVector(dx: b.x - a.x, dy: b.y - a.y) : PlanVector(dx: a.x - b.x, dy: a.y - b.y)
        return TrackLocation(position: point, direction: way)
    }

    /// Decision 29: the least total length from the end of the train's edge
    /// to `node`, the first edge in ascending order at each node among
    /// equals: distances to the destination relaxed until nothing changes,
    /// then a greedy walk.
    func networkRoute(from start: TrainPosition, to node: TrackNodeID) -> [TrackTraversal]? {
        guard case .node(let target) = node, networkNodes[target] != nil else { return nil }
        return networkRoute(from: start, using: distancesToNode(target))
    }

    /// For every run of the network, the least total length of the edges
    /// after it that reach `target`, 0 for the runs ending there: relaxed
    /// until nothing changes. The runs each leads to are listed once.
    func distancesToNode(_ target: Int) -> (remaining: [Run: Int64], next: [Run: [Run]]) {
        let all = networkEdges.keys.sorted().flatMap { [Run(edge: $0, forward: true), Run(edge: $0, forward: false)] }
        var next: [Run: [Run]] = [:]
        for run in all {
            next[run] = runs(after: run)
        }
        var remaining: [Run: Int64] = [:]
        for run in all where endNode(run) == target {
            remaining[run] = 0
        }
        var changed = true
        while changed {
            changed = false
            for run in all where endNode(run) != target {
                let best = next[run]!.compactMap { after in remaining[after].map { $0 + networkEdges[after.edge]!.length } }.min()
                if let best, best < remaining[run] ?? .max {
                    remaining[run] = best
                    changed = true
                }
            }
        }
        return (remaining, next)
    }

    /// The greedy walk from the train's run by the distances of
    /// ``distancesToNode(_:)``: the first run in ascending order that keeps
    /// to the least total length.
    func networkRoute(from start: TrainPosition, using table: (remaining: [Run: Int64], next: [Run: [Run]])) -> [TrackTraversal]? {
        guard case .onEdge(let traversal, let offset) = start, isOnNetwork(traversal, offset) else { return nil }
        var run = Run(traversal)!
        guard var left = table.remaining[run] else { return nil }
        var route: [TrackTraversal] = []
        while left > 0 {
            let next = table.next[run]!.first { after in table.remaining[after].map { $0 + networkEdges[after.edge]!.length } == left }!
            route.append(next.traversal)
            left = table.remaining[next]!
            run = next
        }
        return route
    }

    func networkTransitions(after traversal: TrackTraversal) -> [TrackTraversal] {
        guard let run = Run(traversal) else { return [] }
        return runs(after: run).map(\.traversal)
    }
}

extension ReferenceWorld {
    /// Decision 29: the points a train's cars stand along, head to tail: by
    /// absolute distance along the path it came, every sampled point strictly
    /// between head and tail (each place once), then the tail.
    func networkBodyPath(of train: Train) -> [WorldCoordinate] {
        guard case .onEdge(let traversal, let offset)? = train.position, let head = networkLocation(traversal, offset: offset)?.position else { return [] }
        let path = path(of: train)
        let spans = spans(path)
        let headAt = spans[spans.count - 1].start + offset
        let tailAt = headAt - Self.length(train)
        guard tailAt < headAt else { return [head] }
        var between: [Int64: WorldCoordinate] = [:]
        for (run, span) in zip(path, spans) {
            let edge = networkEdges[run.edge]!
            for (point, distance) in zip(edge.points, edge.distances) {
                let at = span.start + (run.forward ? distance : edge.length - distance)
                if at > tailAt, at < headAt { between[at] = WorldCoordinate(x: point.x, y: point.y) }
            }
        }
        let tailRun = spans.indices.first { spans[$0].start <= tailAt && tailAt < spans[$0].end }!
        let tail = networkLocation(path[tailRun].traversal, offset: tailAt - spans[tailRun].start)!.position
        return [head] + between.keys.sorted(by: >).map { between[$0]! } + [tail]
    }
}
