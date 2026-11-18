import GameCore

// SHARED-STATION-LEVEL (2026-11-18, the owner's screenshot of Rovaniemi on
// 138): the Kemijärvi line and the Muurola line both end at Rovaniemi. The
// one bought second was laid along the same real track as the first, met
// its station tracks, was refused, and was laid again with its Rovaniemi
// platforms raised (decision 809, through decision 462's
// ``RealLineLaying/StationRaising/viaductsAndShared``): its four platform
// tracks stood 16 m up on a viaduct, each within a metre (in plan) of one
// of the first line's three on the ground below. One station, two levels,
// the tracks stacked over each other.
//
// Now a line's end at a station another of the company's lines calls at
// (by the junction, or by its real name, as decision 400 joins them) whose
// track lies along the line's way is laid beside that track first: the
// way moved square to itself so the new line's nearest station track
// stands an island's width (decision 741's 11 m) past the outermost track
// there, on whichever side is the shorter move, from the end of the way
// back to past the last of the company's track along it, and over a
// further 200 m back onto the real line. Its station stands level at the
// height of the platforms already there on the ground
// (``sharedPlatformHeight(of:)``), so the station is one level, its tracks
// side by side and an island between the two lines. Where that is still
// refused, the raise of decision 809 is tried after it, as before.
// Taiwan's Zhuzhong too: the Liujia Line's platforms stay up on its real
// viaduct (decision 462), beside the Neiwan Line's, not over them. Track
// a removed line left (decision 528) is not laid beside: only a station
// another line calls at moves the way.
//
// Neither reference lays two bought lines into one station (decision 809's
// table): native. Decision 848.

extension RealLineLaying {
    /// How far a line's end station's tracks stand to either side of its
    /// way (positive on the right going up the line, as a loop's offset):
    /// its own track at 0 and its loops (``endStationSides(of:name:loops:layout:)``).
    static func endStationExtent(of line: RealBranchLine, name: String, tracks: Int, layout: RealLineLayout) -> ClosedRange<Double> {
        let offsets = endStationSides(of: line, name: name, loops: max(0, tracks - 1), layout: layout).prefix(max(0, tracks - 1)).map(\.0)
        return min(0, offsets.min() ?? 0)...max(0, offsets.max() ?? 0)
    }

    /// The loops of an end station, nearest first, each its offset, its
    /// level (how deep it lies) and whether it leaves the second track:
    /// an island end's (decision 748, decision 792) its first loop on the
    /// right the island's width out and the others beyond
    /// ``RealLineAcquisition/besideIslandOffset`` on the left; another
    /// end's one either side, level by level.
    static func endStationSides(of line: RealBranchLine, name: String, loops: Int, layout: RealLineLayout) -> [(Double, Int, Bool)] {
        let offset = layout.loopOffset
        let island = line.islandStations.contains(name) && (line.isUrban || loops <= 2)
        if island {
            let close = RealLineAcquisition.besideIslandOffset
            return [(RealLineAcquisition.islandSpacing, 1, false)]
                + (2...layout.endLevels + 2).map { level in (-(close + Double(level - 2) * offset), line.isUrban ? level : level - 1, false) }
        }
        return (1...layout.endLevels).flatMap { level -> [(Double, Int, Bool)] in
            [(Double(level) * offset, level, false), (-Double(level) * offset, level, false)]
        }
    }

    /// How far back from a shared end the way is held beside the
    /// company's track before it moves back onto the real line.
    static let sharedEndBlend = 200 * RealLineAcquisition.metre
    /// How near the way the company's track counts as lying along it.
    static let sharedEndReach = 60 * RealLineAcquisition.metre

    /// How far a station between a line's ends stands to either side of
    /// its way: the second track on the left (out to the island's width at
    /// an island station, decision 748), a loop on the right, and an
    /// overtaking station's second loop outside the second track (decision
    /// 605). SHARED-STATION-THROUGH.
    static func throughStationExtent(of line: RealBranchLine, name: String, tracks: Int, overtakes: Bool, layout: RealLineLayout) -> ClosedRange<Double> {
        let second = !line.isDoubleTrack ? 0 : line.islandStations.contains(name) ? RealLineAcquisition.islandSpacing : HighSpeedDemo.trackOffset
        let loops = overtakes ? 2 : tracks - (line.isDoubleTrack ? 2 : 1)
        let left = second + (overtakes ? layout.loopOffset : 0)
        return -left...(loops > 0 ? layout.loopOffset : 0)
    }

    /// `path`, with each end at a station of the company's (`shared`, by
    /// the stop's index) whose track lies along it moved beside that track
    /// (SHARED-STATION-LEVEL); with `through`, each station between the
    /// ends too (SHARED-STATION-THROUGH), held beside the company's track
    /// either way along the line as far as it runs along the way; `nil`
    /// where no stop is moved. `extent` is how far the stop's own tracks
    /// will stand to either side of the way.
    func sharedEnds(
        of path: WorldPath, points: [WorldVector], through: Bool = false, shared: (Int) -> StationID?, extent: (Int) -> ClosedRange<Double>
    ) -> (path: WorldPath, moved: [Int])? {
        guard points.count >= 2 else { return nil }
        // The company's track near the way, sampled as the network tool
        // surveys it.
        let reach = Self.sharedEndReach, gap = RealLineAcquisition.islandSpacing
        let last = points.count - 1
        // Each move: the stop, where it is along the way, and how far it
        // is held toward the way's start (`before`) and its end (`after`);
        // `nil` for all the way past an end.
        var moves: [(stop: Int, at: Double, before: Double?, after: Double?, by: Double)] = []
        for stop in through ? Array(0...last) : [0, last] {
            // Only a station another line calls at: track a line left
            // when it was removed is taken up and laid again (decision 528),
            // not laid beside.
            guard let station = shared(stop), world.station(id: station) != nil,
                  world.lines.contains(where: { $0.stops.contains(station) }) else { continue }
            let at = path.nearest(points[stop]).along
            // Every point of the company's track beside the way within
            // reach of this stop: for an end, from the end of the way back
            // past its station toward the line's middle; for a station
            // between the ends, either way along the line.
            var across: [Double] = [], toward: [Double] = [], away: [Double] = []
            let box = RealLineAcquisition.runOn + RealLineAcquisition.junctionReach
            let stopPoint = points[stop]
            for edge in world.network.edges {
                guard let from = world.network.node(edge.from), let to = world.network.node(edge.to) else { continue }
                let a = WorldVector(from.position.plan), b = WorldVector(to.position.plan)
                guard min((a - stopPoint).length, (b - stopPoint).length) < box + Double(edge.length) else { continue }
                guard let geometry = TrackGeometry(from: from.position, to: to.position, curve: edge.curve) else { continue }
                for plan in NetworkBuilding.surveyedPoints(of: geometry) + [from.position.plan, to.position.plan] {
                    let point = WorldVector(plan)
                    let near = path.nearest(point)
                    guard near.away < reach else { continue }
                    let side = (point - path.point(at: near.along)).dot(path.tangent(at: near.along).normal)
                    // How far toward the way's start (negative) or end
                    // (positive) of the stop.
                    let along = near.along - at
                    if stop == 0 || stop == last {
                        // Behind the stop (toward the line's middle) as far
                        // as the company's track runs on along the way.
                        let behind = stop == 0 ? along : -along
                        guard behind < box else { continue }
                        across.append(side)
                        if stop == 0 { away.append(behind) } else { toward.append(behind) }
                    } else {
                        guard abs(along) < box else { continue }
                        across.append(side)
                        if along < 0 { toward.append(-along) } else { away.append(along) }
                    }
                }
            }
            guard let low = across.min(), let high = across.max() else { continue }
            let own = extent(stop)
            // Clear already, an island's width or more off its tracks.
            guard high > own.lowerBound - gap, low < own.upperBound + gap else { continue }
            let right = high + gap - own.lowerBound, left = low - gap - own.upperBound
            let by = abs(right) <= abs(left) ? right : left
            // Held past the furthest of the company's track from the stop
            // in one run (gaps under 50 m), and at least past its station.
            func hold(_ distances: [Double]) -> Double {
                var hold = RealLineAcquisition.runOn
                for distance in distances.sorted() where distance > 0 {
                    guard distance <= hold + 50 * RealLineAcquisition.metre else { break }
                    hold = max(hold, distance)
                }
                return hold
            }
            moves.append((stop, at, stop == 0 ? nil : hold(toward), stop == last ? nil : hold(away), by))
        }
        guard !moves.isEmpty else { return nil }
        let spacing = 5 * RealLineAcquisition.metre, count = max(2, Int((path.length / spacing).rounded()))
        let blend = Self.sharedEndBlend
        let moved = (0...count).map { step -> WorldVector in
            let distance = path.length * Double(step) / Double(count)
            var point = path.point(at: distance)
            for move in moves {
                let held = distance < move.at ? move.before : move.after
                let share: Double
                if let held {
                    let t = min(max((abs(distance - move.at) - held) / blend, 0), 1)
                    share = 1 - t * t * (3 - 2 * t)
                } else {
                    share = 1
                }
                guard share > 0 else { continue }
                point = point + path.tangent(at: distance).normal * (move.by * share)
            }
            return point
        }
        return (WorldPath(moved).smoothed(), moves.map(\.stop))
    }
}

extension RealLineLaying {
    /// The height of the platforms of `station` not raised on a viaduct
    /// (on the ground, in a cutting or under it), the middle one where
    /// they differ; `nil` for none. SHARED-STATION-THROUGH: Fukuoka's
    /// subway stations stand a few metres down, and were not counted
    /// (only those within half a crossing's clearance of the ground were).
    func sharedPlatformHeight(of station: StationID) -> Double? {
        let heights = world.network.platforms(of: station).compactMap { platform -> Int64? in
            guard let edge = world.network.edge(platform.edge), edge.structure == .automatic || edge.structure == .surface,
                  let geometry = world.trackGeometry(of: platform.edge) else { return nil }
            let middle = geometry.location(at: (platform.start + platform.end) / 2).position
            // Not one raised on its line's viaduct (decision 462).
            guard let ground = world.groundHeight(at: middle.plan), middle.z - ground < TrackStructure.clearance / 2 else { return nil }
            return middle.z
        }.sorted()
        return heights.isEmpty ? nil : Double(heights[heights.count / 2])
    }
}
