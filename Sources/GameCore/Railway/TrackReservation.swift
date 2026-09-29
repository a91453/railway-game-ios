// Route reservation (Phase 4.6 Stage T). Under traffic control a train
// holds the track it needs: what it stands on (see occupiedResources(of:)),
// the node ahead of it, and every link and node of the rest of its
// continuation, which is the way to its next stop. No two trains may hold
// the same resource, so no two trains ever stand on the same track. A
// command that would give a train track another train holds is refused
// (trackReserved), and a service whose route is held waits at its stop and
// tries again at every step, as it does without a route.
//
// The reservation is all of a train's route at once (the minimal rule
// against deadlock this stage takes): a train sets off only when its whole
// way to the next stop is free, and it keeps all of it until the
// continuation is spent or replaced. Two trains that each wait for track
// the other stands on still wait for ever; choosing where trains wait for
// each other is the dispatcher's (Stage V). The reservation is derived from
// each train's position, body and continuation, all of which are saved, so
// it adds nothing to the state; Stage U, which releases track as a train
// passes it, will make it partial.

extension GameWorld {
    /// Turns traffic control on or off (see ``trafficControl``). Turning
    /// it off always succeeds, and trains then pass through each other as
    /// before; turning it on needs every two trains' track apart.
    ///
    /// - Throws: ``GameError/trainsShareTrack(_:_:)`` when two trains hold
    ///   the same resource (see ``reservedResources(of:)``): the train of
    ///   the lowest ID that shares with an earlier one, and the earliest it
    ///   shares with.
    public mutating func setTrafficControl(_ enabled: Bool) throws(GameError) {
        if enabled, let (earlier, later) = firstSharedTrack() {
            throw .trainsShareTrack(earlier, later)
        }
        trafficControl = enabled
    }

    /// The track train `id` holds under traffic control, in resource order:
    /// what it stands on (see ``occupiedResources(of:)``), the node ahead of
    /// it (the node it stands on, or the far end of its link), and each
    /// link and node of the rest of its continuation. Empty for an unplaced
    /// train or an unknown ID. Derived whether or not traffic control is on.
    public func reservedResources(of id: TrainID) -> [TrackResource] {
        guard let train = train(id: id) else { return [] }
        return reservation(of: train).sorted()
    }

    /// The train that holds track on the route train `id`'s service waits
    /// to take, under traffic control: for a service still waiting at a
    /// stop after its departure time, with a route to its next stop (from where
    /// it would stand after turning round, if the stop says so), the lowest
    /// ID of the trains holding track on that route. `nil` when traffic
    /// control is off, for a train not waiting at a stop, not yet due, with
    /// no next stop or no route, whose route is free, and for an unknown
    /// ID.
    public func trainHoldingRoute(of id: TrainID) -> TrainID? {
        guard trafficControl, let train = train(id: id), let position = train.position,
              case .waitingAtStop(let stop, let cycle)? = train.execution,
              train.scheduledDeparture(of: stop, cycle: cycle) < clock.now,
              let next = train.call(after: stop, cycle: cycle)
        else { return nil }
        let (start, trail) = train.timetable[stop].reverses
            ? Self.reversed(position, trail: train.trail, length: train.length)
            : (position, train.trail)
        guard let route = route(from: start, toStation: train.timetable[next.stop].station, length: train.length) else { return nil }
        return reservationHolder(of: reservation(at: start, trail: trail, length: train.length, ahead: route[...]), except: id)
    }

    /// The track `train` holds (see ``reservedResources(of:)``).
    func reservation(of train: Train) -> Set<TrackResource> {
        guard let position = train.position else { return [] }
        return reservation(at: position, trail: train.trail, length: train.length, ahead: train.movement.remainingContinuation)
    }

    /// The track a train `length` long at `position` with `trail` would
    /// hold with `ahead` left to run.
    func reservation(at position: TrainPosition, trail: [GridPosition], length: Int64, ahead: ArraySlice<GridPosition>) -> Set<TrackResource> {
        var held = Set(occupiedResources(at: position, trail: trail, length: length))
        var node = position.ahead.node
        held.insert(.node(node))
        for next in ahead {
            held.insert(.link(between: node, and: next))
            held.insert(.node(next))
            node = next
        }
        return held
    }

    /// The lowest ID of the trains other than `id` that hold any of
    /// `resources`, or `nil`.
    func reservationHolder(of resources: Set<TrackResource>, except id: TrainID) -> TrainID? {
        trains.first { $0.id != id && !reservation(of: $0).isDisjoint(with: resources) }?.id
    }

    /// Under traffic control, refuses track another train holds.
    func requireTrackFree(_ resources: Set<TrackResource>, for id: TrainID) throws(GameError) {
        guard trafficControl, let holder = reservationHolder(of: resources, except: id) else { return }
        throw .trackReserved(holder)
    }

    /// The first two trains, in ID order, that hold the same track: the
    /// first train sharing with an earlier one, and the earliest of those.
    func firstSharedTrack() -> (TrainID, TrainID)? {
        var held: [(TrainID, Set<TrackResource>)] = []
        for train in trains {
            let resources = reservation(of: train)
            if let earlier = held.first(where: { !$0.1.isDisjoint(with: resources) }) {
                return (earlier.0, train.id)
            }
            held.append((train.id, resources))
        }
        return nil
    }
}
