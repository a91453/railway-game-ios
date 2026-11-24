import GameCore

/// The platforms beside the player's track on the native 3D map (decision
/// 229, 392). Moved as they were out of `Map3DScene.swift` (TRACK-SPLIT),
/// whose builder these belong to.
extension Map3DScene.Builder {
    // MARK: Platforms

    /// Each platform beside its track: towards the other platform of
    /// its station across the next track within 15 m (an island
    /// between them), else on the side clear of other track, the left
    /// first; with a canopy. Decision 392: only where it stands clear
    /// of every other track, its edge as far from that one's middle as
    /// from its own, and at least ``narrowestPlatform`` wide; where
    /// there is no such room either side (the high-speed demo's through
    /// tracks between their loops, 5 m apart), none.
    mutating func addPlatforms(_ snapshot: RailwaySnapshot) {
        // Decision 860: those in tunnels, in their stations' boxes.
        addUndergroundPlatforms()
        let platforms = snapshot.platforms.filter { $0.points.count > 1 && $0.structure != .tunnel }
        let middles = platforms.map { point($0.points[$0.points.count / 2]) }
        let others = snapshot.edges.map { ($0.edge.id, $0.geometry.points.map(point)) }
        let fast = world.highSpeedStations
        // Decision 947: beside a guideway, level with its cars' doors
        // and clear of its widest car.
        let guided = guideways(of: snapshot).edges
        for (index, platform) in platforms.enumerated() {
            guard platform.points.contains(where: { contains(x: Double($0.x), y: Double($0.y)) }) else { continue }
            let line = platform.points.map { point($0) + Self.lifted }
            let across = Map3DMesh.acrossDirections(line)[line.count / 2]
            let middle = middles[index]
            let guideway = guided[platform.platform.edge]
            let edge = guideway?.platformEdge ?? (fast.contains(platform.platform.station) ? Self.highSpeedPlatformEdge : Self.platformEdge)
            let near = Self.nearestTracks(beside: line, others: others.filter { $0.0 != platform.platform.edge }.map(\.1))
            // The other platforms of its station across the nearest
            // track either side, far enough for an island between.
            // Decision 507: two islands with the double track between
            // them, the platform beside across it too near for one.
            let candidates: [(index: Int, lateral: Float)] = platforms.indices
                .filter { $0 != index && platforms[$0].platform.station == platform.platform.station && platforms[$0].platform.edge != platform.platform.edge }
                .map { (index: $0, lateral: (middles[$0] - middle).dot(across)) }
            let wide = Self.narrowestPlatform / 2 + edge
            let partner = candidates
                .filter { abs($0.lateral) < 15 && abs(abs($0.lateral) - near[$0.lateral >= 0 ? 1 : 0]) < 1 && abs($0.lateral) / 2 >= wide }
                .min { abs($0.lateral) < abs($1.lateral) }
            var side: Float = -1, width = Self.platformWidth
            // Decision 792's sequel: an island between two tracks that
            // run apart along it on a sharp curve (Zhongzhou's, 12 to
            // 17 m): half of it each side, as wide as the gap where it
            // stands.
            var curved: [Float]?
            if partner == nil, let island = Self.curvedIsland(
                beside: line, partners: candidates.map { platforms[$0.index].points.map { point($0) + Self.lifted } },
                near: near, wide: wide
            ) {
                side = island.side
                curved = island.gaps.map { $0 / 2 - edge }
                width = curved!.min()!
            } else if let partner {
                side = partner.lateral >= 0 ? 1 : -1
                width = abs(partner.lateral) / 2 - edge
            } else {
                func room(_ side: Float) -> Float { min(Self.platformWidth, near[side > 0 ? 1 : 0] - 2 * edge) }
                if room(-1) < Self.platformWidth, room(1) > room(-1) { side = 1 }
                width = room(side)
            }
            // Decision 947: what stands on a platform stands
            // ``platformHeight`` over its line, so a guideway's platform's
            // line is raised (or lowered) by the difference.
            let rise = guideway.map { $0.platformTop - Self.platformHeight } ?? 0
            let laid = rise == 0 ? line : line.map { $0 + Map3DPoint(0, rise, 0) }
            platformLines.append(laid) // Decision 263: no street over it.
            // An island's `width` is its half on this track's side: the
            // whole of it is held to the narrowest, as its partner was
            // picked (decision 856; before, an island 2 to 4 m wide
            // between tracks 5.2 to 7.2 m apart, the Xinbeitou Branch
            // Line's, was picked and then not drawn at all).
            let island = partner != nil || curved != nil
            guard (island ? 2 * width : width) >= Self.narrowestPlatform else { continue }
            let offset = side * (edge + width / 2)
            // Decision 259: its waiting crowd, and the station's
            // passengers outside.
            addStationLife(line: laid, offset: offset, width: width, station: platform.platform.station)
            mesh(at: middle) { mesh in
                mesh.addRibbon(along: laid, width: width, offset: offset, lift: Self.platformHeight, depth: Self.platformHeight + Self.bedDrop + rise,
                               top: Map3DPalette.platform, side: Map3DPalette.platform, topPaint: Self.paving, sidePaint: Self.concrete,
                               widths: curved, offsets: curved?.map { side * (edge + $0 / 2) })
                // Decision 721: its edge line lit after dark.
                let start = mesh.vertices.count
                mesh.addRibbon(along: laid, width: 0.3, offset: side * (edge + 0.35), lift: Self.platformHeight + 0.01,
                               top: Map3DPalette.platformEdge)
                mesh.makeNightLit(from: start)
            }
            addPlatformLight(laid, offset: offset)
            // Decision 321: its canopy and its station's building come
            // with the station kit (`addStations`).
            laidPlatforms.append(LaidPlatform(station: platform.platform.station, line: laid, offset: offset, width: width,
                                              structure: platform.structure, island: island,
                                              edge: platform.platform.edge))
        }
    }

    /// Decision 792's sequel: the side (1 right, -1 left) of `line` on
    /// which one of `partners` (the other platforms' tracks of its
    /// station) runs alongside it 2 × `narrowest` to 18 m away all the
    /// way, with no other track between (`near`, as
    /// ``nearestTracks(beside:others:)`` gives it), and how far away
    /// it runs at each point of `line`; the nearest such, `nil` where
    /// none does. For the islands ``addPlatforms(_:)``'s middle-to-
    /// middle test misses: tracks running apart on a sharp curve.
    static func curvedIsland(beside line: [Map3DPoint], partners: [[Map3DPoint]], near: [Float], wide: Float)
        -> (side: Float, gaps: [Float])? {
        let across = Map3DMesh.acrossDirections(line)
        var best: (side: Float, gaps: [Float])?
        for other in partners where other.count > 1 {
            // How far across `line` the other runs at each point, where
            // it runs beside that point (not past either of its ends).
            let laterals: [Float?] = line.indices.map { index in
                var closest: (point: Map3DPoint, distance: Float, end: Bool)?
                for (k, (a, b)) in zip(other, other.dropFirst()).enumerated() {
                    let ab = b - a, length = ab.dot(ab)
                    let t = length > 0 ? min(1, max(0, (line[index] - a).dot(ab) / length)) : 0
                    let at = a + ab * t, distance = (at - line[index]).length
                    let end = (k == 0 && t == 0) || (k == other.count - 2 && t == 1)
                    if closest == nil || distance < closest!.distance { closest = (at, distance, end) }
                }
                guard let closest else { return nil }
                let offset = closest.point - line[index], lateral = across[index].dot(offset)
                // Past its end: much further than straight across.
                guard !closest.end || closest.distance - abs(lateral) < 0.5, abs(offset.y) < 3 else { return nil }
                return lateral
            }
            let found = laterals.compactMap { $0 }
            guard found.count * 2 >= line.count, let first = found.first else { continue }
            let side: Float = first >= 0 ? 1 : -1
            let gaps = found.map { $0 * side }
            guard let low = gaps.min(), let high = gaps.max(), low < 15, low / 2 >= wide, high <= 18,
                  near[side > 0 ? 1 : 0] > low - 1 else { continue }
            // Where it does not run beside a point, the gap at the
            // nearest point it does.
            var filled: [Float] = []
            for index in line.indices {
                if let lateral = laterals[index] { filled.append(lateral * side); continue }
                let nearest = line.indices.filter { laterals[$0] != nil }.min { abs($0 - index) < abs($1 - index) }!
                filled.append(laterals[nearest]! * side)
            }
            if best == nil || low < best!.gaps.min()! { best = (side, filled) }
        }
        return best
    }

    /// Decision 721: a platform's lamps on the ground round it after
    /// dark, a pool every ``Map3DNight/platformPool``'s `every` metres
    /// along it (drawn with the street lights' pools).
    mutating func addPlatformLight(_ line: [Map3DPoint], offset: Float) {
        guard let path = Map3DStreetLife.Path(line) else { return }
        let pool = Map3DNight.platformPool
        let count = max(1, Int((path.length / pool.every).rounded()))
        for index in 0..<count {
            let at = path.at(path.length * (Float(index) + 0.5) / Float(count))
            let middle = at.point + at.right * offset
            let centre = onGround([middle])[0], ring = onGround(Map3DProp.poolRing.map { middle + $0 * pool.radius })
            shadow(at: key(of: middle), size: 4 * pool.radius) {
                $0.addPool(centre: centre, ring: ring, colour: Map3DProp.lampLight, strength: pool.strength)
            }
        }
    }

    /// Decision 392: how far beside `line` the nearest of `others`'
    /// middles runs within 15 m (beyond 1.5 m), on its left (across
    /// it, negative) and its right, alongside it and at its level;
    /// `.infinity` where none does.
    static func nearestTracks(beside line: [Map3DPoint], others: [[Map3DPoint]]) -> [Float] {
        let reach: Float = 15, step: Float = 2
        let across = Map3DMesh.acrossDirections(line)
        let minX = line.map(\.x).min()! - reach, maxX = line.map(\.x).max()! + reach
        let minZ = line.map(\.z).min()! - reach, maxZ = line.map(\.z).max()! + reach
        var nearest: [Float] = [.infinity, .infinity]
        func consider(_ point: Map3DPoint) {
            guard point.x > minX, point.x < maxX, point.z > minZ, point.z < maxZ,
                  let index = line.indices.min(by: { (line[$0] - point).length < (line[$1] - point).length })
            else { return }
            let offset = point - line[index], forward = Map3DPoint(across[index].z, 0, -across[index].x)
            let beyond = forward.dot(offset)
            guard abs(offset.y) < 3, !(index == 0 && beyond < -1), !(index == line.count - 1 && beyond > 1) else { return }
            let lateral = across[index].dot(offset)
            // Closer than any other track could be: the platform's own,
            // past a node.
            guard abs(lateral) < reach, abs(lateral) > 1.5 else { return }
            let side = lateral >= 0 ? 1 : 0
            nearest[side] = min(nearest[side], abs(lateral))
        }
        for points in others {
            for (a, b) in zip(points, points.dropFirst()) {
                guard max(a.x, b.x) > minX, min(a.x, b.x) < maxX, max(a.z, b.z) > minZ, min(a.z, b.z) < maxZ else { continue }
                let pieces = max(1, Int(((b - a).length / step).rounded(.up)))
                for piece in 0...pieces { consider(a + (b - a) * (Float(piece) / Float(pieces))) }
            }
        }
        return nearest
    }

    /// The middle `share` of `line`, by length.
    static func middle(of line: [Map3DPoint], share: Float) -> [Map3DPoint] {
        guard let path = Map3DStreetLife.Path(line) else { return line }
        let from = path.length * (1 - share) / 2, to = path.length - from
        var points = [path.at(from).point]
        for (point, distance) in zip(path.points, path.distances) where distance > from && distance < to { points.append(point) }
        points.append(path.at(to).point)
        return points
    }
}
