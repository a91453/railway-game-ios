import GameCore

/// Decision 22, written a second time for ``ReferenceWorld``: service lines,
/// the service day, and what is derived from them. Written from the rules,
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
        let n = line.stops.count
        var best: LineJourney?
        for platform in platforms(of: line.stops[0]) {
            for heading in TrackDirection.allCases {
                let start = TrainPosition.atNode(platform, heading: heading)
                var position = start
                var legs: [LineLeg] = []
                var drivable = true
                // Out: 0 -> n-1, then back: n-1 -> 0, turning at the far end.
                var pairs: [(Int, Int)] = (0..<(n - 1)).map { ($0, $0 + 1) }
                pairs += (1..<n).reversed().map { ($0, $0 - 1) }
                for (from, to) in pairs {
                    if from == n - 1 { position = Self.turned(position) }
                    guard let route = route(from: position, toStation: line.stops[to]) else {
                        drivable = false
                        break
                    }
                    let units = Int64(route.count) * Self.linkLength
                    legs.append(LineLeg(from: from, to: to, route: route, minutes: units == 0 ? 0 : (units - 1) / line.rate + 1))
                    if route.count >= 1 {
                        let previous = route.count >= 2 ? route[route.count - 2] : Self.ahead(position).0
                        position = .atNode(route[route.count - 1], heading: stepDirection(from: previous, to: route[route.count - 1])!)
                    }
                }
                guard drivable else { continue }
                let total = legs.reduce(Int64(0)) { $0 + $1.minutes } + 2 * 2 + Int64(2 * (n - 2)) * 1
                if best.map({ total < $0.roundTripMinutes }) ?? true {
                    best = LineJourney(start: start, legs: legs, roundTripMinutes: total)
                }
            }
        }
        return best
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
            let wanted = line.trains[level]!
            let count = wanted < maximum ? wanted : maximum
            answers.trains[level] = count
            if count > 0 {
                let roundTrip = journey.roundTripMinutes
                answers.headways[level] = roundTrip == 0 ? 0 : (roundTrip - 1) / Int64(count) + 1
            }
        }
        return answers
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
