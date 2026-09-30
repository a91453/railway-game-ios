import GameCore

/// Decision 26, written a second time for ``ReferenceWorld``: what trains
/// occupy, sections and parallel tracks. Written from the rules, not from
/// GameCore, and differently where it can be: sections come from a
/// union-find of links that share a plain two-way tile, then each is laid
/// out and ordered; parallel tracks come from depth-first augmenting paths
/// rather than breadth-first ones (the most paths is the same either way).
extension ReferenceWorld {
    func occupiedResources(of id: TrainID) -> [TrackResource] {
        guard let train = trains.first(where: { $0.id == id.rawValue }) else { return [] }
        return occupied(train)
    }

    func occupied(_ train: Train) -> [TrackResource] {
        guard let position = train.position else { return [] }
        let head: TrackResource
        switch position {
        case .atNode(let tile, _):
            head = .node(.tile(tile))
        case .onLink(let from, let to, _):
            let first = (from.y, from.x) < (to.y, to.x)
            head = .wholeLink(.link(first ? from : to, first ? to : from))
        case .onEdge:
            return networkResources(of: train)
        }
        // Decision 27: and the body's.
        return Set([head] + bodyResources(of: train)).sorted()
    }

    func occupancyConflicts() -> [TrackConflict] {
        let occupied = trains.flatMap { train in occupiedResources(of: TrainID(rawValue: train.id)).map { ($0, train.id) } }
        let resources = Set(occupied.map(\.0)).sorted()
        return resources.compactMap { resource in
            let ids = occupied.filter { $0.0 == resource }.map(\.1).sorted()
            return ids.count > 1 ? TrackConflict(resource: resource, trains: ids.map(TrainID.init(rawValue:))) : nil
        }
    }

    private static func rowMajor(_ a: GridPosition, _ b: GridPosition) -> Bool {
        (a.y, a.x) < (b.y, b.x)
    }

    private func isBranch(_ p: GridPosition) -> Bool {
        if case .track? = tiles[p] { return neighbors(of: p).count != 2 }
        return mask(at: p) != nil
    }

    func trackSections() -> [TrackSection] {
        let trackTiles = tiles.keys.filter { mask(at: $0) != nil }.sorted(by: Self.rowMajor)
        // Every link once, as (first, second) in row-major order.
        var links: [[GridPosition]] = []
        for p in trackTiles {
            for q in neighbors(of: p) where Self.rowMajor(p, q) {
                links.append([p, q])
            }
        }
        // Union-find: links sharing a plain tile joined to exactly two
        // others are in the same section.
        var parent = Array(links.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { i = parent[i] }
            return i
        }
        for p in trackTiles where !isBranch(p) {
            let touching = links.indices.filter { links[$0].contains(p) }
            for i in touching.dropFirst() {
                parent[root(i)] = root(touching[0])
            }
        }
        var groups: [Int: [[GridPosition]]] = [:]
        for i in links.indices {
            groups[root(i), default: []].append(links[i])
        }
        var branchSections: [(start: GridPosition, step: Int, section: TrackSection)] = []
        var rings: [(start: GridPosition, section: TrackSection)] = []
        for group in groups.values {
            let tilesInGroup = Set(group.flatMap { $0 })
            let ends = tilesInGroup.filter { isBranch($0) }.sorted(by: Self.rowMajor)
            // Lay the chain out by walking its links from a start.
            func walk(from start: GridPosition, first: GridPosition) -> [GridPosition] {
                var nodes = [start, first]
                var used: Set<[GridPosition]> = [[start, first].sorted(by: Self.rowMajor)]
                while true {
                    let here = nodes[nodes.count - 1]
                    if isBranch(here) || (here == start && nodes.count > 1) { break }
                    guard let next = group.first(where: { $0.contains(here) && !used.contains($0) }) else { break }
                    used.insert(next)
                    let other = next[0] == here ? next[1] : next[0]
                    nodes.append(other)
                }
                return nodes
            }
            func stepIndex(_ from: GridPosition, _ to: GridPosition) -> Int {
                TrackDirection.allCases.firstIndex(of: stepDirection(from: from, to: to)!)!
            }
            if let start = ends.first {
                // From the first end in row-major order, by its first step
                // north, east, south, west among the group's links there.
                let firsts = group.compactMap { link -> GridPosition? in
                    link[0] == start ? link[1] : link[1] == start ? link[0] : nil
                }.sorted { stepIndex(start, $0) < stepIndex(start, $1) }
                let nodes = walk(from: start, first: firsts[0])
                branchSections.append((start, stepIndex(start, firsts[0]), TrackSection(nodes: nodes, isLoop: false)))
            } else {
                let start = tilesInGroup.sorted(by: Self.rowMajor)[0]
                let first = neighbors(of: start).sorted { stepIndex(start, $0) < stepIndex(start, $1) }[0]
                var nodes = walk(from: start, first: first)
                nodes.removeLast()
                rings.append((start, TrackSection(nodes: nodes, isLoop: true)))
            }
        }
        // Branch points joined to nothing are sections of one tile.
        for p in trackTiles where isBranch(p) && neighbors(of: p).isEmpty {
            branchSections.append((p, -1, TrackSection(nodes: [p], isLoop: false)))
        }
        branchSections.sort { $0.start == $1.start ? $0.step < $1.step : Self.rowMajor($0.start, $1.start) }
        rings.sort { Self.rowMajor($0.start, $1.start) }
        return branchSections.map(\.section) + rings.map(\.section)
    }

    /// The most link-disjoint paths between the stations' platforms, by
    /// depth-first augmenting paths on unit capacities each way.
    func parallelTracks(between a: StationID, and b: StationID) -> Int {
        let sources = Set(platforms(of: a))
        let sinks = Set(platforms(of: b)).subtracting(sources)
        guard !sources.isEmpty, !sinks.isEmpty else { return 0 }
        var used: [String: Int] = [:]
        func key(_ p: GridPosition, _ q: GridPosition) -> String { "\(p.x),\(p.y)>\(q.x),\(q.y)" }
        func augment(_ here: GridPosition, _ visited: inout Set<GridPosition>) -> Bool {
            if sinks.contains(here) { return true }
            for next in neighbors(of: here) where !visited.contains(next) && used[key(here, next), default: 0] < 1 {
                visited.insert(next)
                if augment(next, &visited) {
                    used[key(here, next), default: 0] += 1
                    used[key(next, here), default: 0] -= 1
                    return true
                }
            }
            return false
        }
        var count = 0
        while true {
            var visited = sources
            var found = false
            for source in sources.sorted(by: Self.rowMajor) where augment(source, &visited) {
                found = true
                break
            }
            guard found else { return count }
            count += 1
        }
    }
}
