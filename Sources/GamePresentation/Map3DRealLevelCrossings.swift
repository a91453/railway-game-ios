import GameCore

// Decision 941 (later, LEVEL-CROSSING-REAL-MAP; the owner's IMG_5594 of
// 2026-11-25, 146: 「已經是最新版 但遊戲還是沒有鋪平交道」): decisions 263
// and 941 laid a level crossing only where a seeded street of a map with
// no base map crosses the track. On a real-world map the base map's roads
// (and the player's own, decision 438) ran on under the track's bed where
// they crossed it on the level (decision 391's `.level`, "平交道照舊",
// which drew nothing), the player's track and the real lines' alike. They
// get the seeded streets' crossing now: its deck, ramps, hatching, stop
// lines, barriers and booms, and the traffic over it.

extension Map3DScene.Builder {
    /// The most a level crossing's deck may stand over its road, metres:
    /// the track's bed on the ground (``Map3DScene/railLift`` and the
    /// deck's own ``Map3DLevelCrossing/deckRise``) with a little to
    /// spare. Higher, the track is on a bank the road goes over or under
    /// (decision 391), not a level crossing.
    static let levelCrossingMostRise: Float = 1.6

    /// The most apart, metres along a road, the tracks one level crossing
    /// covers on a real map: a double track's two and a siding or two, as
    /// a crossing at a station's end has. Further apart, the road is taken
    /// as crossing each on a deck of its own.
    static let realCrossingMostSpread: Float = 16

    /// Decision 941 (later): a level crossing wherever a road on the ground
    /// (``groundRoadLines``) crosses track laid on the ground: the player's
    /// (``trackLines`` on the surface, not a guideway's) or a real line's
    /// (``realSurfaceLines``), more than 30° off it, the track's bed no
    /// higher over the road than ``levelCrossingMostRise``, not where the
    /// road ends at the track or is lifted over it (decision 391). Each in
    /// the region once; laid as a seeded street's is, its traffic and
    /// walkers lifted over its deck.
    mutating func addRealLevelCrossings() {
        var segments: [(p: Map3DPoint, q: Map3DPoint)] = []
        for (number, line) in state.track.trackLines.enumerated() where line.kind == .surface && !state.track.guidedTrackLines.contains(number) {
            for (p, q) in zip(line.points, line.points.dropFirst()) { segments.append((p, q)) }
        }
        for line in state.realTrains.realSurfaceLines {
            for (p, q) in zip(line, line.dropFirst()) { segments.append((p, q)) }
        }
        guard !segments.isEmpty, !state.baseMap.groundRoadLines.isEmpty else { return }
        var index: [Int64: [Int]] = [:]
        for (number, segment) in segments.enumerated() {
            let (p, q) = segment
            for key in Self.trackCells(low: (min(p.x, q.x), min(p.z, q.z)), high: (max(p.x, q.x), max(p.z, q.z))) {
                index[key, default: []].append(number)
            }
        }
        var found: [Map3DLevelCrossing] = []
        for road in state.baseMap.groundRoadLines where road.points.count >= 2 {
            let line = road.points
            // Each track crossed: how far along the road, where (at the
            // rails' height), the track's way and the road's.
            var hits: [(d: Float, point: Map3DPoint, way: Map3DPoint, along: Map3DPoint)] = []
            var travelled: Float = 0
            for (a, b) in zip(line, line.dropFirst()) {
                let length = Map3DPoint(b.x - a.x, 0, b.z - a.z).length
                defer { travelled += length }
                guard length > 0.01, let along = Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized else { continue }
                var seen = Set<Int>()
                for key in Self.trackCells(low: (min(a.x, b.x), min(a.z, b.z)), high: (max(a.x, b.x), max(a.z, b.z))) {
                    for number in index[key] ?? [] where seen.insert(number).inserted {
                        let (p, q) = segments[number]
                        guard let hit = Self.intersection(a, b, p, q),
                              let way = Map3DPoint(q.x - p.x, 0, q.z - p.z).normalized,
                              abs(way.x * along.z - way.z * along.x) >= 0.5 else { continue }
                        let d = travelled + Map3DPoint(hit.x - a.x, 0, hit.z - a.z).length
                        // A piece's end shared with the next: one place.
                        if hits.contains(where: { abs($0.d - d) < 1 }) { continue }
                        let span = Map3DPoint(q.x - p.x, 0, q.z - p.z).length
                        let t = span > 0 ? min(max(Map3DPoint(hit.x - p.x, 0, hit.z - p.z).length / span, 0), 1) : 0
                        hits.append((d, Map3DPoint(hit.x, p.y + (q.y - p.y) * t, hit.z), way, along))
                    }
                }
            }
            hits.sort { $0.d < $1.d }
            var first = 0
            while first < hits.count {
                // The tracks crossed one after another, each within
                // ``Map3DLevelCrossing/mostSpread`` of the last.
                var last = first
                while last + 1 < hits.count, hits[last + 1].d - hits[last].d <= Map3DLevelCrossing.mostSpread { last += 1 }
                defer { first = last + 1 }
                let group = hits[first...last]
                guard let low = group.first, let high = group.last,
                      high.d - low.d <= Self.realCrossingMostSpread,
                      // Not where the road ends: it meets the track there.
                      low.d > 2, high.d < travelled - 2 else { continue }
                let middle = (low.d + high.d) / 2
                let at = Map3DPoint(low.point.x, 0, low.point.z) + low.along * (middle - low.d)
                let height = group.map(\.point.y).reduce(0, +) / Float(group.count)
                let crossing = Map3DLevelCrossing(point: Map3DPoint(at.x, height, at.z), along: low.along, kind: road.kind,
                                                  trackWay: low.way, spread: high.d - low.d)
                guard contains(x: originX + Double(at.x) * Self.metre, y: originY + Double(at.z) * Self.metre),
                      !found.contains(where: { abs($0.point.x - at.x) < 2 && abs($0.point.z - at.z) < 2 }),
                      !state.streets.crossings.contains(where: { abs($0.point.x - at.x) < 2 && abs($0.point.z - at.z) < 2 }) else { continue }
                // On the level: the deck just over the road, which is not
                // lifted over the track there.
                let surface = drawnGround(x: at.x, z: at.z) + Self.lift(of: road.kind)
                let rise = crossing.deckTop - surface
                guard rise >= 0, rise <= Self.levelCrossingMostRise,
                      !roadRise(at: Map3DBaseMap.Point(x: Double(at.x), z: Double(at.z)), along: (Double(low.along.x), Double(low.along.z)),
                                onDeck: false).onBridge else { continue }
                found.append(crossing)
            }
        }
        guard !found.isEmpty else { return }
        let start = state.streets.crossings.count
        state.streets.crossings += found
        for number in start..<state.streets.crossings.count { state.streets.crossings[number].gateFeet = addLevelCrossing(state.streets.crossings[number]) }
        streetLife.lift(over: found)
    }
}

extension Map3DStreetLife {
    /// Decision 941 (later): the traffic's lanes and the pavements'
    /// walkers, laid before level crossings `found`, lifted over their
    /// decks and ramps: looked at every 2 m near one (each level distance
    /// along them as it was, so their stops and crossings keep their
    /// places). Each from its path on the road as laid (``Lane/ground``),
    /// so a scene built again in part, lifting the lanes it keeps over
    /// all its crossings, has them as the scene built whole: over the
    /// crossings there now, not those the track taken up left.
    mutating func lift(over found: [Map3DLevelCrossing]) {
        func lifted(_ path: Map3DStreetLife.Path) -> Map3DStreetLife.Path? {
            let near = found.filter { crossing in
                let reach = crossing.rampEnd + crossing.halfWidth + 1
                return crossing.point.x + reach >= path.minimum.x && crossing.point.x - reach <= path.maximum.x
                    && crossing.point.z + reach >= path.minimum.z && crossing.point.z - reach <= path.maximum.z
            }
            guard !near.isEmpty else { return nil }
            func over(_ p: Map3DPoint) -> Map3DPoint {
                let rise = near.map { $0.rise(x: p.x, z: p.z, road: p.y - 0.02) }.max() ?? 0
                return Map3DPoint(p.x, p.y + rise, p.z)
            }
            func touches(_ a: Map3DPoint, _ b: Map3DPoint) -> Bool {
                near.contains { crossing in
                    Map3DScene.Builder.distance(crossing.point, crossing.point, a, b) <= crossing.rampEnd + crossing.halfWidth + 1
                }
            }
            var points = [over(path.points[0])]
            var changed = points[0].y != path.points[0].y
            for (a, b) in zip(path.points, path.points.dropFirst()) {
                let steps = touches(a, b) ? max(1, Int((Map3DPoint(b.x - a.x, 0, b.z - a.z).length / 2).rounded(.up))) : 1
                for step in 1...steps {
                    let point = over(a + (b - a) * (Float(step) / Float(steps)))
                    changed = changed || steps > 1 || point.y != b.y
                    points.append(point)
                }
            }
            return changed ? Map3DStreetLife.Path(points) : nil
        }
        for number in lanes.indices {
            let ground = lanes[number].ground ?? lanes[number].path
            let path = lifted(ground)
            lanes[number].path = path ?? ground
            lanes[number].ground = path == nil ? nil : ground
        }
        for number in spots.indices where spots[number].kind == .sidewalk {
            let ground = spots[number].ground ?? spots[number].path
            let path = lifted(ground)
            spots[number].path = path ?? ground
            spots[number].ground = path == nil ? nil : ground
        }
    }
}
