// Flexible dispatch (ARCHITECTURE decision 172). A line used to send a train
// out only from its first stop; a train that ended a trip anywhere else was
// never sent out again, and the whole line stood still without a word. Now a
// train is sent out from either end of its line, on a ring from any of its
// stops, and one that stands elsewhere runs empty to the nearer end first.
// The rules are in ``GameWorld/readyTrip(of:on:_:memo:)``; this file is what
// the player is told about them.

/// Where a line's train will be sent out from (decision 172).
public enum TrainDispatchPlan: Hashable, Sendable {
    /// From the line's first stop, or on a ring from the stop it stands at:
    /// the way every train was sent out before.
    case fromFirstStop
    /// From the line's last stop: its trip goes back along the line first.
    case fromLastStop
    /// It stands at a station that is not an end of the line: it runs empty,
    /// without passengers, to this end, and is sent out from there.
    case runsEmpty(to: StationID)
    /// It cannot be sent out: it is not stopped at a station, or no end of
    /// the line can be reached from where it stands.
    case stranded
}

/// What becomes of one of a line's trains (decision 172).
public struct TrainDispatchOutlook: Hashable, Sendable {
    public let train: TrainID
    /// Whether the train runs a service now: its plan is then for once the
    /// service has ended, where its timetable ends.
    public let isRunning: Bool
    public let plan: TrainDispatchPlan
}

extension GameWorld {
    /// For each train assigned to line `id`, in ascending ID order, where
    /// it is sent out from next (decision 172): where it stands, or for a
    /// train running a service where that ends. A running train that will
    /// end at neither end of the line is given the nearer end by straight
    /// line, as its place on the track at the end is not known yet. Empty
    /// for an unknown line and for a line with runs (decision 133), which
    /// are sent out where each run starts; a train not placed on the track
    /// is left out.
    ///
    /// Pure.
    public func lineDispatchOutlook(_ id: LineID) -> [TrainDispatchOutlook] {
        guard let line = line(id: id), !line.hasRuns else { return [] }
        var outlook: [TrainDispatchOutlook] = []
        for trainID in line.assignedTrains {
            guard let train = train(id: trainID), let service = line.dispatchStream(of: trainID)?.service else { continue }
            let calls = line.calls(ofService: service)
            let first = line.stops[calls[0]], last = line.stops[calls[calls.count - 1]]
            let plan: TrainDispatchPlan
            if train.execution != nil {
                guard let end = train.timetable.last?.station else { continue }
                if line.isRing || end == first {
                    plan = .fromFirstStop
                } else if end == last {
                    plan = .fromLastStop
                } else {
                    plan = .runsEmpty(to: nearerEnd(to: end, first: first, last: last))
                }
            } else if train.placement == nil {
                // Not on the track yet: nothing is planned for it.
                continue
            } else if isStopped(train, at: first) || line.isRing && line.stops.contains(where: { isStopped(train, at: $0) }) {
                plan = .fromFirstStop
            } else if isStopped(train, at: last) {
                plan = .fromLastStop
            } else {
                if let end = deadheadTrip(of: line, service: service, for: train)?.deadhead?.to {
                    plan = .runsEmpty(to: end)
                } else {
                    plan = .stranded
                }
            }
            outlook.append(TrainDispatchOutlook(train: trainID, isRunning: train.execution != nil, plan: plan))
        }
        return outlook
    }

    /// The end of the two, `first` or `last`, nearer to `station` by
    /// straight line (the first among equals).
    private func nearerEnd(to station: StationID, first: StationID, last: StationID) -> StationID {
        guard let toFirst = squaredDistance(from: station, to: first), let toLast = squaredDistance(from: station, to: last) else { return first }
        return toLast < toFirst ? last : first
    }

    /// How far, in world units, the trains of line `id` have driven empty
    /// to one of its ends (decision 172); each such run costs the hour's
    /// train distance like any other (42 a train kilometre), and no fare.
    /// `nil` for an unknown line.
    public func lineDeadheadDistance(_ id: LineID) -> Int64? {
        line(id: id)?.deadheadDistance
    }
}
