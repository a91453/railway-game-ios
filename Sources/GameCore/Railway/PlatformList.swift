// A leg's list of platforms (PLATFORM-BOOK PB-2, decision 740). A line
// could name one platform for a leg (decision 61); when that one was taken
// its trains went to whichever platform of the station was free (decision
// 57), the player's plan for the station or not. Now a leg may name up to
// four in order, as the owner's desktop game lets a train stop only at the
// platforms its list names: under traffic control a departure tries them
// in that order and waits when they are all taken; with traffic control
// off, a real timetable's train changes platform (decision 228) only to
// another of them. A deadlock the list keeps a train in is the one
// exception: the dispatcher lets that train stop, this once, at any
// platform (its look at deadlocks once a minute). A leg with one platform
// works as before.

extension GameWorld {
    /// Decision 740: the platform list the line of `candidate`, a service
    /// travelling to stop `stop` of its timetable, names for that leg (see
    /// ``LineRoutePreference/platformList``), with the preference; `nil`
    /// for a leg without one.
    func platformList(of candidate: Train, stop: Int, memo: inout PathMemo) -> (preference: LineRoutePreference, list: [TrackPlatform])? {
        guard candidate.timetable.indices.contains(stop) else { return nil }
        let from = stop == 0 ? candidate.timetable.count - 1 : stop - 1
        guard let preference = routePreference(for: candidate, from: from, to: stop, known: &memo.trainLines),
              let list = preference.platformList
        else { return nil }
        return (preference, list)
    }

    /// Decision 740: `candidate`, a service setting off for stop `stop` (of
    /// cycle `cycle`), along the way to each platform of its leg's list
    /// that is on the network and fits it, in the list's order: the first
    /// along the leg's walk, if it names one. `nil` for a leg without a
    /// list; empty when none of its platforms can be reached.
    func listedDepartures(of candidate: Train, stop: Int, cycle: Int64, memo: inout PathMemo) -> [Train]? {
        guard let position = candidate.position, let named = platformList(of: candidate, stop: stop, memo: &memo) else { return nil }
        var departures: [Train] = []
        for (index, platform) in named.list.enumerated() {
            let leg = index == 0 ? named.preference : LineRoutePreference(from: named.preference.from, to: named.preference.to, platform: platform)
            guard let path = preferredPath(from: position, preference: leg, length: candidate.length, memo: &memo) else { continue }
            departures.append(rerouted(candidate, along: path, stop: stop, cycle: cycle))
        }
        return departures
    }

    /// Decision 740: the departures of `candidate` its leg's list lets it
    /// make, as ``listedDepartures(of:stop:cycle:memo:)``, under traffic
    /// control; `nil` with traffic control off, for any train but a service
    /// setting off for a stop, for a leg without a list, and where none of
    /// the list's platforms can be reached (the leg then goes anywhere, as
    /// a preference whose track is gone does).
    func listedDepartures(of candidate: Train, memo: inout PathMemo) -> [Train]? {
        guard isTrafficControlEnabled, case .travellingToStop(let stop, let cycle)? = candidate.execution,
              let listed = listedDepartures(of: candidate, stop: stop, cycle: cycle, memo: &memo), !listed.isEmpty
        else { return nil }
        return listed
    }
}

extension GameWorld {
    /// Decision 755 (PLATFORM-BOOK PB-3): where train `id`, under traffic
    /// control, is bound for or stands at a platform outside its leg's
    /// list (decision 740), as the dispatcher lets a train stop once when
    /// the list keeps it in a deadlock: the station and that platform's
    /// edge, so its card can say every platform of the list was taken.
    /// `nil` with traffic control off, for a train not on a service's leg
    /// with a list, at a platform of the list, and where none of the
    /// list's platforms is on the network and fits the train (the leg then
    /// goes anywhere, as no list does).
    public func offListPlatform(of id: TrainID) -> (station: StationID, platform: TrackPlatform)? {
        guard isTrafficControlEnabled, let train = train(id: id), let execution = train.execution,
              case .onEdge(let traversal, let offset)? = train.position else { return nil }
        var memo = PathMemo()
        guard let named = platformList(of: train, stop: execution.stop, memo: &memo) else { return nil }
        let station = named.preference.platform.station
        guard named.list.contains(where: { network.platforms.contains($0) && $0.length >= train.length }) else { return nil }
        let platforms = trackPlatforms(of: station)
        let at: [TrackPlatform]
        switch execution {
        case .travellingToStop:
            // Where its path ends: a platform's far end the way it runs.
            let edgeID = train.movement.remainingEdges.last ?? traversal.edge
            guard let edge = network.edge(edgeID) else { return nil }
            let end = train.movement.end ?? edge.length
            at = platforms.filter { $0.edge == edgeID && ($0.end == end || $0.start == edge.length - end) }
        case .waitingAtStop:
            guard let edge = network.edge(traversal.edge) else { return nil }
            let chainage = traversal.direction == .forward ? offset : edge.length - offset
            at = platforms.filter { $0.edge == traversal.edge && $0.start <= chainage && chainage <= $0.end }
        }
        guard let platform = at.first, !at.contains(where: named.list.contains) else { return nil }
        return (station, platform)
    }
}

extension GameWorld {
    /// Decision 755 (PLATFORM-BOOK PB-3): the most trains of line `id`'s
    /// service (its own for `pattern` `nil`) that its timetables have at
    /// station `station` at once, counting a train from its arrival to its
    /// departure, and at a terminus a repeating timetable turns it round at
    /// from its last arrival to its next first departure. Repeating
    /// timetables of one period are laid over one another, so trains on
    /// different cycles count; 0 when none of its trains runs a timetable
    /// calling there. What a leg's list of platforms (decision 740) is
    /// measured against: a list of fewer platforms keeps a train waiting.
    public func mostTrainsAtOnce(at station: StationID, line id: LineID, pattern: Int? = nil) -> Int {
        guard let line = line(id: id) else { return 0 }
        let ids = pattern.map { line.patterns.indices.contains($0) ? line.patterns[$0].trains : [] } ?? line.trains
        var spans: [(start: Int64, end: Int64)] = []
        var periods: Set<Int64?> = []
        for trainID in ids {
            guard let train = train(id: trainID), train.execution != nil, !train.timetable.isEmpty else { continue }
            let timetable = train.timetable, period = train.timetablePeriod
            periods.insert(period)
            let turnsRound = period != nil && timetable.count > 1 && timetable[0].station == station && timetable[timetable.count - 1].station == station
            for (index, stop) in timetable.enumerated() where stop.station == station {
                if turnsRound, index == 0 { continue }
                let start = stop.arrival.seconds
                var end = stop.departure.seconds
                if turnsRound, index == timetable.count - 1, let period {
                    let (next, overflow) = timetable[0].departure.seconds.addingReportingOverflow(period)
                    end = overflow ? end : max(end, next)
                }
                spans.append((start, max(end, start &+ 1)))
            }
        }
        if periods.count == 1, let only = periods.first, let period = only, period > 0 {
            spans = spans.flatMap { span -> [(start: Int64, end: Int64)] in
                let length = min(span.end - span.start, period)
                let start = ((span.start % period) + period) % period
                let end = start + length
                return end <= period ? [(start, end)] : [(start, period), (Int64(0), end - period)]
            }
        }
        // Ends before starts at the same second: one leaving as another comes.
        var events: [(second: Int64, change: Int)] = []
        for span in spans {
            events.append((span.start, 1))
            events.append((span.end, -1))
        }
        events.sort { $0.second != $1.second ? $0.second < $1.second : $0.change < $1.change }
        var now = 0, most = 0
        for event in events {
            now += event.change
            most = max(most, now)
        }
        return most
    }
}
