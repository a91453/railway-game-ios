import GameCore

/// Where one of a line's trains is along the line's stops, for the route
/// strip (ARCHITECTURE decision 113): the reference's line panel draws a
/// dot for each train on its station bar, placed by the train's progress
/// between the stations (`Ci/` `updateLineInfoTrainDots`, from the line's
/// `_stationProgress`).
public struct LineTrainDot: Hashable, Sendable {
    public let train: TrainID
    /// The place along ``ServiceLine/stops``: 0 at the first stop, 1 at
    /// the second, 1.5 halfway from the second to the third, up to
    /// `stops.count - 1` at the last.
    public let position: Double
    /// Whether the train is going towards the line's last stop; `false`
    /// when it is coming back.
    public let isOutbound: Bool

    public init(train: TrainID, position: Double, isOutbound: Bool) {
        self.train = train
        self.position = position
        self.isOutbound = isOutbound
    }
}

extension GameWorld {
    /// A dot for each train of line `id` that is running a trip, by train
    /// ID: at a stop while it calls there, and between two stops, as far
    /// as the time of its run (``ServiceRun``) has gone, while it travels.
    /// A train waiting for its next trip, or with no trip yet, has none.
    /// Empty for an unknown line. Read from the world each time; never
    /// stored.
    public func lineTrainDots(_ id: LineID) -> [LineTrainDot] {
        guard let line = line(id: id), line.stops.count > 1 else { return [] }
        let trainIDs = (line.trains + line.patterns.flatMap(\.trains)).sorted { $0.rawValue < $1.rawValue }
        return trainIDs.compactMap { trainID in
            guard let train = train(id: trainID), let execution = train.execution else { return nil }
            return dot(of: train, execution: execution, on: line)
        }
    }

    private func dot(of train: Train, execution: TimetableExecution, on line: ServiceLine) -> LineTrainDot? {
        let timetable = train.timetable
        guard timetable.indices.contains(execution.stop), let here = line.stops.firstIndex(of: timetable[execution.stop].station) else { return nil }
        func place(_ entry: Int) -> Int? {
            guard timetable.indices.contains(entry) else { return nil }
            return line.stops.firstIndex(of: timetable[entry].station)
        }
        switch execution {
        case .waitingAtStop(let stop, _):
            let isOutbound: Bool
            if let next = place(stop + 1), next != here {
                isOutbound = next > here
            } else if let previous = place(stop - 1), previous != here {
                isOutbound = here > previous
            } else {
                isOutbound = true
            }
            return LineTrainDot(train: train.id, position: Double(here), isOutbound: isOutbound)
        case .travellingToStop(let stop, _):
            // The entry it left: the last of the previous cycle when it is
            // heading for the first.
            guard let from = place(stop == 0 ? timetable.count - 1 : stop - 1), from != here else {
                return LineTrainDot(train: train.id, position: Double(here), isOutbound: true)
            }
            var progress = 0.0
            if let run = train.times?.run, run.seconds > 0 {
                let gone = clock.now.seconds - run.start.seconds
                progress = min(max(Double(gone) / Double(run.seconds), 0), 1)
            }
            // A ring's last stop runs on to its first, which the strip
            // does not draw: the train shows at the end it is nearer.
            if line.isRing, abs(here - from) == line.stops.count - 1 {
                return LineTrainDot(train: train.id, position: Double(progress < 0.5 ? from : here), isOutbound: true)
            }
            let position = Double(from) + Double(here - from) * progress
            return LineTrainDot(train: train.id, position: position, isOutbound: here > from)
        }
    }
}
