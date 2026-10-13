import GameCore

// A passing loop in one step (decision 204, NEXT_PRIORITIES §0 item 10):
// tap a single track, and a second track goes beside it, 5 m to one side,
// joined by a turnout at each end, as the platform track tool lays one
// (``GameSession/sidingPlan(on:from:to:spacing:reach:side:)``). With it
// comes a signal station (號誌站): a station closed to passengers with a
// platform on each track, so a timetable that calls there has its meets
// planned there, and a line that calls there may run a train each way on
// the single track (decision 61 counts a passing place only at a stop;
// ClosedStationMeetTests). The reference has no such tool, only the
// geometry of a crossover's reverse curve (`Simulator/` `Kw`): native.

/// A passing loop worked out from the world: the siding beside the
/// stretch of track from `start` to `end` on `edge`, and the signal
/// station that gets a platform on each.
public struct PassingLoopPlan: Hashable, Sendable {
    let edge: TrackEdgeID
    let start: Int64
    let end: Int64
    /// Where the stretch begins and ends: once the turnouts split the
    /// track, the stretch is found again by these.
    let stretchStart: WorldCoordinate
    let stretchEnd: WorldCoordinate
    let near: PlatformTrackTurnout
    let far: PlatformTrackTurnout
    let beside: PlatformTrackPlan.Beside
    let curves: PlatformTrackPlan.Curves
    let structure: TrackStructure
    /// The signal station's name and where it stands: the stretch's middle.
    let name: String
    let station: PlanPoint
}

extension PassingLoopPlan {
    /// How far apart the two tracks stand, centre to centre: 5 m, as a
    /// double track (``DoubleTrack/spacing``).
    public static let spacing = DoubleTrack.spacing
    /// How far each turnout stands from the loop's end: the S-curve out to
    /// the loop, as a side platform's (``PlatformTrackLayout/reach``).
    public static let reach = PlatformTrackLayout.side.reach
    /// The shortest loop: six cars (96 m).
    public static let minimumCars = 6
}

extension GameSession {
    /// How long a passing loop is: the longest train the company has, at
    /// least ``PassingLoopPlan/minimumCars`` cars.
    public var passingLoopLength: Int64 {
        max(world.trains.map(\.length).max() ?? 0, Int64(PassingLoopPlan.minimumCars) * Train.carLength)
    }

    /// The loop centred on `point` (moved along to stay on its edge), on
    /// `side` of the way the edge runs.
    func passingLoopPlan(at point: NetworkEdgePoint, side: PlatformTrackSide) -> Result<PassingLoopPlan, PlatformTrackProblem> {
        guard let edge = world.network.edge(point.edge), let geometry = world.trackGeometry(of: point.edge) else { return .failure(.missing) }
        let length = passingLoopLength
        guard length < edge.length else { return .failure(.noRoom) }
        let start = min(max(0, point.distance - length / 2), edge.length - length)
        let end = start + length
        return sidingPlan(on: point.edge, from: start, to: end, spacing: PassingLoopPlan.spacing, reach: PassingLoopPlan.reach, side: side).map { siding in
            let middle = geometry.location(at: (start + end) / 2).position.plan
            return PassingLoopPlan(
                edge: point.edge, start: start, end: end,
                stretchStart: geometry.location(at: start).position, stretchEnd: geometry.location(at: end).position,
                near: siding.near, far: siding.far, beside: siding.beside, curves: siding.curves, structure: siding.structure,
                name: signalStationName(), station: middle
            )
        }
    }

    /// "Signal 1", "號誌站 1": the next number after the closed stations'.
    func signalStationName() -> String {
        let closed = world.stations.filter { $0.operationMode == .closed }.count
        return language.text("Signal \(closed + 1)", "號誌站 \(closed + 1)")
    }

    /// Builds `plan` in `world`: the siding, then the signal station, closed,
    /// with a platform along the loop and one along the track beside it.
    /// Returns the station.
    func build(_ plan: PassingLoopPlan, in world: inout GameWorld) throws(GameError) -> Station {
        let edges = try buildSiding(near: plan.near, far: plan.far, beside: plan.beside, curves: plan.curves, structure: plan.structure, in: &world)
        let station = try world.buildStation(named: plan.name, at: plan.station)
        try world.setStationOperationMode(station.id, to: .closed)
        let loop = world.network.edge(edges[1])?.length ?? 0
        try world.addTrackPlatform(station.id, on: edges[1], from: 0, to: loop)
        // The turnouts split the track: the stretch beside the loop now
        // lies on the part between them.
        guard let first = world.trackEdgePoint(near: plan.stretchStart.plan, within: 16),
              let last = world.trackEdgePoint(near: plan.stretchEnd.plan, within: 16), first.edge == last.edge
        else { throw .invalidTrackGeometry }
        try world.addTrackPlatform(station.id, on: first.edge, from: min(first.distance, last.distance), to: max(first.distance, last.distance))
        return world.station(id: station.id) ?? station
    }

    /// What a passing loop at ``networkEdgePoint`` on ``networkLoopSide``
    /// would cost, or why it cannot be built, and where it would run;
    /// worked out once for each place, side and world, as the track
    /// preview is (the map reads it many times a frame).
    public var networkLoopPreview: PassingLoopPreview? {
        guard networkMode == .passingLoop, let point = networkEdgePoint else { return nil }
        _ = world
        let key = PassingLoopMemo.Key(point: point, side: networkLoopSide, worldRevision: worldRevision)
        if let memo = passingLoopMemo, memo.key == key { return memo.preview }
        let preview = passingLoopPreview(at: point, side: networkLoopSide)
        passingLoopMemo = PassingLoopMemo(key: key, preview: preview)
        return preview
    }

    func passingLoopPreview(at point: NetworkEdgePoint, side: PlatformTrackSide) -> PassingLoopPreview {
        switch passingLoopPlan(at: point, side: side) {
        case .failure(let problem):
            return PassingLoopPreview(cost: nil, problem: problem.text(in: language), points: [])
        case .success(let plan):
            let ends = [plan.near.position, plan.beside.near, plan.beside.far, plan.far.position]
            let curves = [plan.curves.out, plan.curves.along, plan.curves.back]
            let points = curves.indices.flatMap { index in
                TrackGeometry(from: ends[index], to: ends[index + 1], curve: curves[index])?.points ?? [ends[index], ends[index + 1]]
            }
            var draft = world
            do throws(GameError) {
                _ = try build(plan, in: &draft)
                return PassingLoopPreview(cost: Money(world.economy.balance.amount - draft.economy.balance.amount), problem: nil, points: points)
            } catch {
                return PassingLoopPreview(cost: nil, problem: error.playerMessage(in: language), points: points)
            }
        }
    }

    /// Builds a passing loop at ``networkEdgePoint`` on ``networkLoopSide``
    /// (see the file's header), all or nothing.
    public func addPassingLoop() {
        let side = networkLoopSide
        guard let point = networkEdgePoint else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Tap the single track where the passing loop goes.", "請點選要加待避線的單線軌道。"
            ))
            return
        }
        let plan: PassingLoopPlan
        switch passingLoopPlan(at: point, side: side) {
        case .success(let found): plan = found
        case .failure(let problem):
            message = StatusMessage(kind: .failure, text: problem.text(in: language))
            return
        }
        let balance = world.economy.balance
        let length = NetworkBuilding.lengthText(plan.end - plan.start, in: language)
        let built = perform(.addPassingLoop(plan)) { _, _, world in
            let cost = Money(balance.amount - world.economy.balance.amount)
            return language.text(
                "\(plan.name): a \(length) passing loop, for \(cost.moneyText). Add it to a line's stops for its trains to pass there.",
                "\(plan.name)：已加上 \(length) 的待避線，花費 \(cost.moneyText)。把它加進路線的停靠站，列車就能在這裡交會。"
            )
        }
        if built != nil {
            networkEdgePoint = nil
            playSound?(.track)
        }
    }
}

/// What the passing-loop mode shows: the cost or why not, and the loop's
/// line on the map.
public struct PassingLoopPreview: Sendable {
    public let cost: Money?
    public let problem: String?
    public let points: [WorldCoordinate]
}

struct PassingLoopMemo {
    struct Key: Equatable {
        let point: NetworkEdgePoint
        let side: PlatformTrackSide
        let worldRevision: Int
    }

    let key: Key
    let preview: PassingLoopPreview
}
