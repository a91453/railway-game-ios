import GameCore

/// Decisions 22 and 23, written a second time for ``ReferenceWorld``:
/// service lines, the service day, what is derived from them, and dispatch. Written from the rules,
/// not from GameCore, and differently where it can be: windows as one or
/// two ranges of the day, levels found by scanning the day's bands from the
/// start, leg minutes as `(units - 1) / rate + 1`, and every start of a
/// journey driven before the shortest is kept.
extension ReferenceWorld {
    private func lineIndex(_ id: LineID) -> Int? {
        lines.firstIndex { $0.id == id.rawValue }
    }

    /// Two stops or more, never one twice in a row; then every station known.
    private func stopsProblem(_ stops: [StationID]) -> GameError? {
        guard stops.count >= 2 else { return .invalidLineStops }
        for index in 1..<stops.count where stops[index] == stops[index - 1] {
            return .invalidLineStops
        }
        let known = Set(stations.map(\.id))
        if let missing = stops.first(where: { !known.contains($0.rawValue) }) {
            return .unknownStation(missing)
        }
        return nil
    }

    mutating func createLine(named name: String, stops: [StationID]) -> GameError? {
        guard name.contains(where: { !$0.isWhitespace }) else { return .invalidName }
        if let problem = stopsProblem(stops) { return problem }
        guard nextLineID != Int.max else { return .idsExhausted }
        lines.append(Line(id: nextLineID, name: name, stops: stops))
        nextLineID += 1
        return nil
    }

    mutating func removeLine(_ id: LineID) -> GameError? {
        guard let index = lineIndex(id) else { return .unknownLine(id) }
        lines.remove(at: index)
        return nil
    }

    mutating func setLineStops(_ id: LineID, _ stops: [StationID]) -> GameError? {
        guard let index = lineIndex(id) else { return .unknownLine(id) }
        if let problem = stopsProblem(stops) { return problem }
        lines[index].stops = stops
        return nil
    }

    mutating func setLineRate(_ id: LineID, _ rate: Int64) -> GameError? {
        guard let index = lineIndex(id) else { return .unknownLine(id) }
        guard rate > 0 else { return .invalidLineRate }
        lines[index].rate = rate
        return nil
    }

    mutating func setLineWindow(_ id: LineID, _ window: ServiceWindow) -> GameError? {
        guard let index = lineIndex(id) else { return .unknownLine(id) }
        switch window {
        case .allDay:
            lines[index].hours = nil
        case .hours(let open, let close):
            guard open >= 0, open < 1440, close > open, close <= 1800 else { return .invalidServiceWindow }
            lines[index].hours = (open, close)
        }
        return nil
    }

    mutating func setLineTrains(_ id: LineID, _ trains: TrainsInService) -> GameError? {
        guard let index = lineIndex(id) else { return .unknownLine(id) }
        guard min(trains.peak, trains.offPeak, trains.low) >= 0 else { return .invalidTrainsInService }
        lines[index].trains = [.peak: trains.peak, .offPeak: trains.offPeak, .low: trains.low]
        return nil
    }

    mutating func setServiceDay(_ day: ServiceDay) -> GameError? {
        let starts = day.bands.map(\.start)
        guard starts.first == 0, starts.allSatisfy({ $0 < 1440 }), zip(starts, starts.dropFirst()).allSatisfy({ $0 < $1 }) else {
            return .invalidServiceDay
        }
        serviceDay = day.bands.map { ($0.start, $0.level) }
        return nil
    }

    // MARK: - Derived

    func serviceLevel(of id: LineID, at time: GameTime) -> ServiceLevel? {
        guard let line = lines.first(where: { $0.id == id.rawValue }) else { return nil }
        let minute = Int(((time.minutes % 1440) + 1440) % 1440)
        if let (open, close) = line.hours {
            // One range, or, past midnight, the evening and the next morning.
            let inService = close <= 1440 ? (open..<close).contains(minute) : minute >= open || minute < close - 1440
            guard inService else { return nil }
        }
        var level = serviceDay[0].level
        for band in serviceDay where band.start <= minute {
            level = band.level
        }
        return level
    }

    func lineJourney(_ id: LineID) -> LineJourney? {
        guard let line = lines.first(where: { $0.id == id.rawValue }) else { return nil }
        var best: LineJourney?
        for platform in platforms(of: line.stops[0]) {
            for heading in TrackDirection.allCases {
                guard let journey = journey(of: line, from: .atNode(platform, heading: heading)) else { continue }
                if best.map({ journey.roundTripMinutes < $0.roundTripMinutes }) ?? true {
                    best = journey
                }
            }
        }
        return best
    }

    /// The line driven once from `start`: out 0 -> n-1, turning at the far
    /// end, back n-1 -> 0; `nil` if a leg has no route.
    func journey(of line: Line, from start: TrainPosition) -> LineJourney? {
        let n = line.stops.count
        var position = start
        var legs: [LineLeg] = []
        var pairs: [(Int, Int)] = (0..<(n - 1)).map { ($0, $0 + 1) }
        pairs += (1..<n).reversed().map { ($0, $0 - 1) }
        for (from, to) in pairs {
            if from == n - 1 { position = Self.turned(position) }
            guard let route = route(from: position, toStation: line.stops[to]) else { return nil }
            let units = Int64(route.count) * Self.linkLength
            legs.append(LineLeg(from: from, to: to, route: route, minutes: units == 0 ? 0 : (units - 1) / line.rate + 1))
            if route.count >= 1 {
                let previous = route.count >= 2 ? route[route.count - 2] : Self.ahead(position).0
                position = .atNode(route[route.count - 1], heading: stepDirection(from: previous, to: route[route.count - 1])!)
            }
        }
        let total = legs.reduce(Int64(0)) { $0 + $1.minutes } + 2 * 2 + Int64(2 * (n - 2)) * 1
        return LineJourney(start: start, legs: legs, roundTripMinutes: total)
    }

    /// Everything derived for a line, from one drive of its journey:
    /// `nil` parts where the line does not exist or cannot be driven.
    struct LineAnswers: Equatable {
        var journey: LineJourney?
        var maximum: Int?
        var trains: [ServiceLevel: Int]
        var headways: [ServiceLevel: Int64]
    }

    func lineAnswers(_ id: LineID) -> LineAnswers {
        guard let line = lines.first(where: { $0.id == id.rawValue }), let journey = lineJourney(id) else {
            return LineAnswers(journey: nil, maximum: nil, trains: [:], headways: [:])
        }
        let maximum = Self.maximumTrains(roundTrip: journey.roundTripMinutes)
        var answers = LineAnswers(journey: journey, maximum: maximum, trains: [:], headways: [:])
        for level in ServiceLevel.allCases {
            let (count, headway) = Self.plan(line, at: level, roundTrip: journey.roundTripMinutes, maximum: maximum)
            answers.trains[level] = count
            answers.headways[level] = headway
        }
        return answers
    }

    /// Decisions 22 and 23: the trains a line runs at `level` and the
    /// headway, `nil` without trains. With a target: enough trains that
    /// their share of the round trip is no longer than it (but no more than
    /// the maximum), and the target or that share, whichever is longer.
    static func plan(_ line: Line, at level: ServiceLevel, roundTrip: Int64, maximum: Int) -> (trains: Int, headway: Int64?) {
        let count: Int
        if let target = line.targets[level] {
            let enough = Int((roundTrip - 1) / target + 1)
            count = enough < maximum ? enough : maximum
        } else {
            let wanted = line.trains[level]!
            count = wanted < maximum ? wanted : maximum
        }
        guard count > 0 else { return (0, nil) }
        let share = (roundTrip - 1) / Int64(count) + 1
        guard let target = line.targets[level] else { return (count, share) }
        return (count, share > target ? share : target)
    }

    /// As the web reference finds it: one if even a single train is closer
    /// than two minutes to itself, else a binary search for the largest
    /// count whose share of the round trip is still two minutes or more.
    static func maximumTrains(roundTrip: Int64) -> Int {
        guard roundTrip >= 2 else { return 1 }
        var (low, high, best) = (Int64(1), roundTrip, Int64(1))
        while low <= high {
            let middle = low + (high - low) / 2
            if roundTrip - middle >= middle {
                best = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return Int(best)
    }

    func lineMaximumTrains(_ id: LineID) -> Int? {
        lineAnswers(id).maximum
    }

    func lineTrainsInService(_ id: LineID, at level: ServiceLevel) -> Int? {
        lineAnswers(id).trains[level]
    }

    func lineHeadway(_ id: LineID, at level: ServiceLevel) -> Int64? {
        lineAnswers(id).headways[level]
    }
}

// MARK: - Dispatch (decision 23)

extension ReferenceWorld {
    func onLine(_ id: TrainID) -> Bool {
        lines.contains { $0.roster.contains(id.rawValue) }
    }

    mutating func setLineTargets(_ id: LineID, _ targets: TargetHeadways) -> GameError? {
        guard let index = lines.firstIndex(where: { $0.id == id.rawValue }) else { return .unknownLine(id) }
        var byLevel: [ServiceLevel: Int64] = [:]
        for level in ServiceLevel.allCases {
            guard let target = targets[level] else { continue }
            guard target >= 2, target <= 1440 else { return .invalidHeadway }
            byLevel[level] = target
        }
        lines[index].targets = byLevel
        return nil
    }

    /// The train, then the line, then not on a line, then no service.
    mutating func assign(_ id: TrainID, to line: LineID) -> GameError? {
        guard let train = trains.first(where: { $0.id == id.rawValue }) else { return .unknownTrain(id) }
        guard let index = lines.firstIndex(where: { $0.id == line.rawValue }) else { return .unknownLine(line) }
        if onLine(id) { return .trainOnLine(id) }
        if train.service != nil { return .trainServiceActive(id) }
        lines[index].roster = (lines[index].roster + [id.rawValue]).sorted()
        return nil
    }

    mutating func unassign(_ id: TrainID) -> GameError? {
        guard trains.contains(where: { $0.id == id.rawValue }) else { return .unknownTrain(id) }
        guard let index = lines.firstIndex(where: { $0.roster.contains(id.rawValue) }) else { return .trainNotOnLine(id) }
        lines[index].roster.removeAll { $0 == id.rawValue }
        return nil
    }

    /// What stays the same within one call of `advance`.
    struct DispatchMemo {
        var journeys: [Int: LineJourney?] = [:]
        /// Trips found from a train's place: `(turned, journey)`, or none.
        var trips: [TrainPosition: [Int: (Bool, LineJourney)?]] = [:]
    }

    /// One line's dispatch at the current minute: from minute 0, window
    /// open, a level with trains on a drivable journey, a headway since the
    /// last dispatch, fewer trains in service than the level runs; then
    /// the first of its trains, by ID, without a service, placed, moving at
    /// some rate and stopped at the first stop, that can drive the round
    /// trip from there (turned round only if that is shorter or the only
    /// way) leaves on it now.
    mutating func dispatch(_ l: Int, memo: inout DispatchMemo) {
        let line = lines[l]
        guard !line.roster.isEmpty, minutes >= 0,
              let level = serviceLevel(of: LineID(rawValue: line.id), at: GameTime(minutes: minutes))
        else { return }
        if memo.journeys[line.id] == nil {
            memo.journeys[line.id] = .some(lineJourney(LineID(rawValue: line.id)))
        }
        guard let journey = memo.journeys[line.id]! else { return }
        let maximum = Self.maximumTrains(roundTrip: journey.roundTripMinutes)
        let (count, headway) = Self.plan(line, at: level, roundTrip: journey.roundTripMinutes, maximum: maximum)
        guard count > 0, let headway else { return }
        if let last = line.lastDispatch, minutes - last < headway { return }
        let busy = trains.filter { line.roster.contains($0.id) && $0.service != nil }.count
        guard busy < count else { return }
        for id in line.roster {
            guard let i = trains.firstIndex(where: { $0.id == id }) else { continue }
            let train = trains[i]
            guard train.service == nil, let position = train.position, train.rate > 0,
                  stationsStoppedAt(by: TrainID(rawValue: id)).contains(line.stops[0])
            else { continue }
            if memo.trips[position]?[line.id] == nil {
                let straight = self.journey(of: line, from: position)
                let turned = self.journey(of: line, from: Self.turned(position))
                let pick: (Bool, LineJourney)? = switch (straight, turned) {
                case (let s?, let t?): t.roundTripMinutes < s.roundTripMinutes ? (true, t) : (false, s)
                case (let s?, nil): (false, s)
                case (nil, let t?): (true, t)
                case (nil, nil): nil
                }
                memo.trips[position, default: [:]][line.id] = .some(pick)
            }
            guard let (turn, trip) = memo.trips[position]![line.id]! else { continue }
            // The timetable: leave now; each call the leg's minutes after
            // the one before; stay 1 between the ends, 2 at the far end
            // (turning), and finish on arrival back at the first stop
            // (turning).
            var timetable = [ScheduledStop(station: line.stops[0], arrival: GameTime(minutes: minutes), departure: GameTime(minutes: minutes), reverses: turn)]
            var clock = minutes
            for (k, leg) in trip.legs.enumerated() {
                let final = k == trip.legs.count - 1
                let far = leg.to == line.stops.count - 1
                let stay: Int64 = final ? 0 : far ? 2 : 1
                guard clock <= Int64.max - leg.minutes - stay else { return }
                let arrival = clock + leg.minutes
                clock = arrival + stay
                timetable.append(ScheduledStop(
                    station: line.stops[leg.to], arrival: GameTime(minutes: arrival), departure: GameTime(minutes: clock), reverses: final || far
                ))
            }
            trains[i].timetable = timetable
            trains[i].period = nil
            trains[i].service = Service(stop: 0, waiting: true)
            lines[l].lastDispatch = minutes
            return
        }
    }
}
