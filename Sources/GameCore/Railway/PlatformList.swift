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
