import GameCore

// Double track in one stretch (decision 204, NEXT_PRIORITIES §0 item 10):
// with ``GameSession/networkBuildsDouble`` on, each stretch the network
// tool lays gets a second track beside it, ``DoubleTrack/spacing`` (5 m)
// centre to centre, as one command. Which of the two each direction runs
// on is GameCore's keep-left rule (decision 202), not the tool's.
//
// The parallel's ends stand beside the stretch's, along the normal of the
// way the stretch leaves and arrives; its curve is worked out as the
// stretch's own (``NetworkBuilding/curve(from:leaving:to:leaving:)``,
// handles a third of the chord along the same directions), so the two
// stay about 5 m apart round a curve. An end beside an existing node joins
// it: drawing on from the last stretch, the parallel carries on from the
// last parallel. The reference has the offset only as rendering
// (`Railway/site_archive_clean/rail-3d/integration/rail-structures.js`,
// `edge(p, ux, uy)`, the normal (-dy, dx) of each segment); the tool is
// this project's own.

/// The double-track tool's layout.
public enum DoubleTrack {
    /// Centre to centre, 5 m, as a side-platform track
    /// (``PlatformTrackLayout/side``): more than GameCore's least spacing
    /// (``RailwayNetwork/trackSpacing``, 4 m), so a curve's small error
    /// still clears it.
    public static let spacing: Int64 = PlatformTrackLayout.side.spacing
    /// How near a parallel's end must be to an existing node to join it:
    /// 1 m.
    public static let joinReach: Int64 = WorldCoordinate.unitsPerMetre

    /// `point` moved `distance` to the `side` of `way` (y grows south: left
    /// of (dx, dy) is (dy, -dx)), rounded to whole units.
    static func beside(_ point: WorldCoordinate, way: PlanVector, side: PlatformTrackSide, distance: Int64) -> WorldCoordinate {
        let dx = Double(way.dx), dy = Double(way.dy)
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return point }
        let scale = (side == .left ? 1 : -1) * Double(distance) / length
        return WorldCoordinate(x: point.x + Int64((dy * scale).rounded()), y: point.y + Int64((-dx * scale).rounded()), z: point.z)
    }
}

extension GameSession {
    /// `plan` and the track beside it (``parallelPlan(beside:in:)``). Decision
    /// 164 eases a grade only where it fits under the steepest; the track on
    /// the inside of a curve is shorter and so steeper, so where it would not
    /// fit eased, both keep the steady grade, as the stretch alone would.
    func doublePlans(_ plan: EdgePlan, in world: GameWorld) -> (main: EdgePlan, parallel: EdgePlan?) {
        let parallel = parallelPlan(beside: plan, in: world)
        guard plan.profile != .uniform, let geometry = parallel?.geometry,
              !geometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumGrade)
        else { return (plan, parallel) }
        let steady = EdgePlan(
            start: plan.start, end: plan.end, from: plan.from, to: plan.to, curve: plan.curve, profile: .uniform,
            geometry: TrackGeometry(from: plan.from, to: plan.to, curve: plan.curve),
            joinsStart: plan.joinsStart, joinsEnd: plan.joinsEnd
        )
        return (steady, parallelPlan(beside: steady, in: world))
    }

    /// The track beside `plan`, on ``networkDoubleSide`` of the way it is
    /// drawn, ``DoubleTrack/spacing`` from it; `nil` when `plan` makes no
    /// edge or the parallel's ends would fall on each other.
    func parallelPlan(beside plan: EdgePlan, in world: GameWorld) -> EdgePlan? {
        guard let geometry = plan.geometry else { return nil }
        let leaving = geometry.location(at: 0).direction
        let arriving = geometry.location(at: geometry.length).direction
        func end(_ position: WorldCoordinate, way: PlanVector) -> (anchor: NetworkAnchor, position: WorldCoordinate) {
            let beside = DoubleTrack.beside(position, way: way, side: networkDoubleSide, distance: DoubleTrack.spacing)
            if let found = world.trackNode(near: beside.plan, within: DoubleTrack.joinReach) {
                return (.node(found.id), found.position)
            }
            return (.point(beside.plan), beside)
        }
        let start = end(plan.from, way: leaving)
        let finish = end(plan.to, way: arriving)
        guard start.position.plan != finish.position.plan else { return nil }
        let curve: TrackCurve
        if case .straight = plan.curve, leaving == arriving {
            curve = .straight
        } else {
            guard let found = NetworkBuilding.curve(from: start.position.plan, leaving: leaving, to: finish.position.plan, leaving: arriving.reversed) else {
                return nil
            }
            curve = found
        }
        return EdgePlan(
            start: start.anchor, end: finish.anchor, from: start.position, to: finish.position, curve: curve, profile: plan.profile,
            geometry: TrackGeometry(from: start.position, to: finish.position, curve: curve, profile: plan.profile),
            joinsStart: false, joinsEnd: false
        )
    }
}
