// Mountain track (decision 515): track steeper than the game's 40 in 1000,
// up to 70, laid only where the network tool traces a real line whose ground
// climbs that steeply (the Alishan Forest Railway's 62.5 in 1000), on which
// only a mountain train runs, and no faster than its grade allows.
//
// The owner's references give the forest railway's running (`PERF_RULES`
// `/阿里山號|祝山線|神木線|沼平線|觀日/`: 0.7 km/h a second to start, 1.1 to
// brake, 45 km/h at most, ``TrainPerformance/forestRailway``; the
// Railway reference's `rail-3d/physical/afr-timing.js` the same) but no
// grade or speed rule, and GameCore's running has no grade resistance:
// grades never move a train (Stage S4). The grade limit is this project's
// (gap): 85 km/h less the grade in thousandths, posted in steps of 5 km/h
// rounded down (``CurveSpeedLimit/step``), never below
// ``CurveSpeedLimit/lowest``: 40 in 1000 gives 45 km/h, the forest
// railway's top speed; 50 gives 35; 62.5 gives 20; 70 gives 15.

/// The rules of mountain track (decision 515).
public enum MountainTrack {
    /// The speed a grade of nothing would allow, in km/h, from which each
    /// thousandth of grade takes 1 km/h.
    public static let levelSpeed: Int64 = 85

    /// The speed limit, in km/h, on mountain track whose steepest grade is
    /// `grade`, up or down.
    public static func speed(grade: TrackGrade) -> Int64 {
        // The grade in thousandths, rounded up.
        let (scaled, overflow) = grade.rise.magnitude.multipliedReportingOverflow(by: 1_000)
        guard !overflow else { return CurveSpeedLimit.lowest }
        let permille = (scaled + grade.run.magnitude - 1) / grade.run.magnitude
        guard permille < UInt64(levelSpeed) else { return CurveSpeedLimit.lowest }
        let raw = levelSpeed - Int64(permille)
        return max(CurveSpeedLimit.lowest, raw / CurveSpeedLimit.step * CurveSpeedLimit.step)
    }

    /// The speed limits along an edge of `geometry` shaped by `curve`: its
    /// curve limits (``CurveSpeedLimit/limits(of:curve:)``) and, on
    /// mountain track, its grade's limit over the whole of it, merged.
    static func speedLimits(of geometry: TrackGeometry, curve: TrackCurve, mountain: Bool) -> [TrackSpeedLimit] {
        let curves = CurveSpeedLimit.limits(of: geometry, curve: curve)
        guard mountain, geometry.length > 0 else { return curves }
        let climb = TrackSpeedLimit(start: 0, end: geometry.length, speed: speed(grade: geometry.steepestGrade))
        return CurveSpeedLimit.merged(curves + [climb], within: geometry.length)
    }
}

extension GameWorld {
    /// Whether `line` runs on mountain track (decision 515): one of its
    /// services' journeys (each way round a ring) starts on, runs along or
    /// stops on a mountain edge. Pure; a world with no mountain track
    /// answers at once.
    func runsOnMountainTrack(_ line: ServiceLine) -> Bool {
        guard network.edges.contains(where: \.mountain) else { return false }
        func mountain(_ edge: TrackEdgeID) -> Bool { network.edge(edge)?.mountain ?? false }
        let directions: [RingDirection] = line.isRing ? RingDirection.allCases : [.inner]
        for service in 0..<line.serviceCount {
            for direction in directions {
                guard let journey = journey(of: line, service: service, direction: direction) else { continue }
                if case .onEdge(let traversal, _) = journey.start, mountain(traversal.edge) { return true }
                if journey.legs.contains(where: { $0.path.traversals.contains { mountain($0.edge) } }) { return true }
            }
        }
        return false
    }

    /// Whether line `id` runs on mountain track (decision 515), so that
    /// only a mountain train (``TrainType/climbsMountains``) may be
    /// assigned to it; `false` for a line the world does not have. Pure.
    public func lineRunsOnMountainTrack(_ id: LineID) -> Bool {
        line(id: id).map(runsOnMountainTrack) ?? false
    }
}
