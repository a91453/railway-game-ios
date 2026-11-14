// Taking turns on single track (decision 718). Under traffic control a
// service's departure took its route whenever the track was free for it,
// or followed the train ahead onto it (Stage U2), and of two due in the
// same step the lower numbered went first. So where trains wait at both
// ends of a single track, a later train could keep going in behind the one
// before it, and the train at the other end waited for as long as they
// kept coming.
//
// Now the trains go in the order they came to wait: a departure that could
// take its route does not, while a service that has waited longer needs
// track of that route the other way and nothing but trains on their way
// keeps it from going. Nothing is remembered: how long a service has
// waited is when its doors closed (see ``GameWorld/departureDue(of:)``),
// which the train already keeps.
//
// With realistic operation on too (PLATFORM-BOOK PB-1, decision 738), the
// same goes for a platform: a departure whose route ends at a platform does
// not take it while a service that has waited longer is bound for that
// platform of the same station, and nothing but trains on their way keeps
// it from going. First come, first served, as the owner's desktop game
// gives a station's platforms out in the order they were asked for.

extension GameWorld {
    /// Decision 718: the train that goes before train `id`, whose service
    /// is due to leave a stop and could take its route, but gives its turn
    /// to one that has waited longer for the same track the other way (see
    /// ``trainHoldingRoute(of:)``, which names it too); `nil` for any other
    /// train. Derived on every call, never saved.
    public func trainGoingFirst(before id: TrainID) -> TrainID? {
        var memo = questionMemo()
        guard isTrafficControlEnabled, let train = train(id: id), train.position != nil,
              let departing = departureRequest(of: train, memo: &memo),
              case .granted(let granted) = takingDeparture(departing, memo: &memo)
        else { return nil }
        return turnOwed(by: granted, memo: &memo)
    }

    /// PLATFORM-BOOK PB-1 (decision 738): the train that goes before train
    /// `id` because it has waited longer for the platform `id`'s route ends
    /// at, with that platform's station; `nil` when `id` gives its turn for
    /// track the other way (``trainGoingFirst(before:)``) or not at all.
    /// Derived on every call, never saved.
    public func trainGoingFirstToPlatform(before id: TrainID) -> (train: TrainID, station: StationID)? {
        var memo = questionMemo()
        guard isTrafficControlEnabled, let train = train(id: id), train.position != nil,
              let departing = departureRequest(of: train, memo: &memo),
              case .granted(let granted) = takingDeparture(departing, memo: &memo),
              let owed = turnOwedFor(granted, memo: &memo), let station = owed.platform
        else { return nil }
        return (owed.train, station)
    }

    /// Decision 718: the service `granted`, a departure that could take its
    /// route now, gives its turn to: the one that has waited longest of the
    /// services due to leave a stop that
    ///
    /// - have waited longer than it (their doors closed first; of two that
    ///   closed in the same second, the lower numbered),
    /// - would run over an edge of its route the other way, so only one of
    ///   the two can go, or, with realistic operation on (PLATFORM-BOOK
    ///   PB-1, decision 738), would end its route at the same platform of
    ///   the same station, and
    /// - could go now, or are kept from their route only by trains that are
    ///   on their way and will clear it: never by a train that stands or
    ///   waits itself, which may be waiting for this one.
    ///
    /// `nil` when there is none, with traffic control off, and for any
    /// departure but a service's from a stop it waits at with its doors
    /// closed (a line sending a train out, a train going on from a passing
    /// place): those have no time they came to wait from.
    ///
    /// It can keep no train for good: the longest waiting of them gives its
    /// turn to nobody, and it either goes at its next try or waits for
    /// trains that are moving, which come to the end of their routes.
    func turnOwed(by granted: Train, memo: inout DirectionMemo) -> TrainID? {
        turnOwedFor(granted, memo: &memo)?.train
    }

    /// ``turnOwed(by:memo:)`` with why: `platform` is the station whose
    /// platform the two routes end at when that is what they contest
    /// (decision 738), `nil` when it is track the other way (decision 718).
    func turnOwedFor(_ granted: Train, memo: inout DirectionMemo) -> (train: TrainID, platform: StationID?)? {
        guard isTrafficControlEnabled, let waiting = train(id: granted.id), case .waitingAtStop? = waiting.execution,
              let due = departureDue(of: waiting) else { return nil }
        let route = routeStretches(of: granted)
        guard route.moves else { return nil }
        var against: Set<TrackTraversal>?
        var stuck: Set<TrainID>?
        var first: (due: GameTime, id: TrainID, platform: StationID?)?
        // Decision 738: the platform its route ends at, under realistic
        // operation only.
        let platform = realisticOperation ? boundPlatform(of: granted, along: route.stretches) : nil
        for other in trains where other.id != granted.id && other.position != nil {
            guard case .waitingAtStop? = other.execution, let otherDue = departureDue(of: other), otherDue <= clock.now,
                  otherDue < due || (otherDue == due && other.id < granted.id)
            else { continue }
            // Only the longest waiting of them is named.
            if let first, first.due < otherDue || (first.due == otherDue && first.id < other.id) { continue }
            guard let request = departureRequest(of: other, memo: &memo) else { continue }
            let wanted = routeStretches(of: request)
            guard wanted.moves else { continue }
            if against == nil { against = Set(route.stretches.map(\.traversal.reversed)) }
            let contested: StationID?
            if wanted.stretches.contains(where: { against!.contains($0.traversal) }) {
                contested = nil
            } else if let platform, let theirs = boundPlatform(of: request, along: wanted.stretches),
                      theirs.station == platform.station, theirs.edge == platform.edge {
                contested = platform.station
            } else {
                continue
            }
            if case .held = takingDeparture(request, memo: &memo) {
                // Held by trains on their way only.
                let holders = trackHolders(memo: &memo)
                let envelope = envelopeCover(of: request)
                guard holder(of: envelope, except: other.id, holders: holders) != nil else { continue }
                if stuck == nil { stuck = Set(trains.filter { !isOnItsWay($0, memo: &memo) }.map(\.id)) }
                if blockedTrack(except: other.id, among: stuck, holders: holders).blocks(envelope, in: network) { continue }
            }
            first = (otherDue, other.id, contested)
        }
        return first.map { ($0.id, $0.platform) }
    }

    /// Decision 738: the station and platform edge where `train`'s route
    /// (`stretches`, see ``routeStretches(of:)``) ends, when it is bound for
    /// a stop and the route ends on a platform of that stop's station;
    /// `nil` otherwise.
    func boundPlatform(of train: Train, along stretches: [TrackStretch]) -> (station: StationID, edge: TrackEdgeID)? {
        guard case .travellingToStop(let stop, _)? = train.execution, train.timetable.indices.contains(stop),
              let last = stretches.last
        else { return nil }
        let station = train.timetable[stop].station
        guard network.platforms(of: station).contains(where: { $0.edge == last.traversal.edge }) else { return nil }
        return (station, last.traversal.edge)
    }

    /// Whether `train` is on its way along a route and can move on now: a
    /// service travelling to its call with track of its route still held
    /// ahead of it. A train following others (Stage U2) that has come as
    /// far as its reservation holds is not.
    func isOnItsWay(_ train: Train, memo: inout DirectionMemo) -> Bool {
        guard case .travellingToStop? = train.execution, !train.reservation.isEmpty else { return false }
        if let authority = authority(of: train, memo: &memo) { return authority.left > 0 }
        return routeStretches(of: train).moves
    }
}
