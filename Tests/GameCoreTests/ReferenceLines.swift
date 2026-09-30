import GameCore

/// Decisions 22 to 24, written a second time for ``ReferenceWorld``:
/// service lines and their patterns, the service day, what is derived from
/// them, and dispatch. Written from the rules,
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
        // Decision 24: the patterns keep their calls, which must still fit.
        if lines[index].patterns.contains(where: { $0.calls.contains { $0 >= stops.count } }) { return .invalidLinePattern }
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

    mutating func setLineTrains(_ id: LineID, _ trains: TrainsInService, pattern: Int? = nil) -> GameError? {
        guard let index = lineIndex(id) else { return .unknownLine(id) }
        if let pattern, !lines[index].patterns.indices.contains(pattern) { return .unknownLinePattern(pattern) }
        guard min(trains.peak, trains.offPeak, trains.low) >= 0 else { return .invalidTrainsInService }
        let counts: [ServiceLevel: Int] = [.peak: trains.peak, .offPeak: trains.offPeak, .low: trains.low]
        if let pattern {
            lines[index].patterns[pattern].trains = counts
        } else {
            lines[index].trains = counts
        }
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

    func lineJourney(_ id: LineID, pattern: Int? = nil) -> LineJourney? {
        guard let line = lines.first(where: { $0.id == id.rawValue }) else { return nil }
        if let pattern, !line.patterns.indices.contains(pattern) { return nil }
        return serviceJourney(line, pattern.map { $0 + 1 } ?? 0)
    }

    /// Service `k` of `line` driven from every platform of its first call
    /// facing every way; the shortest, the first found among equals.
    func serviceJourney(_ line: Line, _ k: Int) -> LineJourney? {
        let calls = line.service(k).calls
        var best: LineJourney?
        for platform in platforms(of: line.stops[calls[0]]) {
            for heading in TrackDirection.allCases {
                guard let journey = journey(of: line, calling: calls, from: .atNode(platform, heading: heading)) else { continue }
                if best.map({ journey.roundTripMinutes < $0.roundTripMinutes }) ?? true {
                    best = journey
                }
            }
        }
        // Decision 31: then from every berth on the network, a train of one car.
        for start in journeyStarts(onNetworkOf: line.stops[calls[0]]) {
            guard let journey = networkJourney(of: line, calling: calls, from: start, trailEdges: [], length: 0) else { continue }
            if best.map({ journey.roundTripMinutes < $0.roundTripMinutes }) ?? true {
                best = journey
            }
        }
        return best
    }

    /// The line driven once from `start`, calling at `calls` (indices of its
    /// stops): out along them, turning at the last, back along them in
    /// reverse; `nil` if a leg has no route. Decision 27: a train `length`
    /// long with body `trail` turns with its head at its tail and is pulled
    /// along the platforms.
    func journey(of line: Line, calling calls: [Int], from start: TrainPosition, trail: [GridPosition] = [], length: Int64 = 0) -> LineJourney? {
        let n = calls.count
        var position = start
        var body = trail
        var legs: [LineLeg] = []
        var pairs: [(Int, Int)] = (0..<(n - 1)).map { (calls[$0], calls[$0 + 1]) }
        pairs += (1..<n).reversed().map { (calls[$0], calls[$0 - 1]) }
        for (from, to) in pairs {
            if from == calls[n - 1] { (position, body) = Self.turnedWithBody(position, body, length: length) }
            guard let route = route(from: position, toStation: line.stops[to], length: length) else { return nil }
            let units = Int64(route.count) * Self.linkLength
            // Decision 31: a leg keeps its path as links from the node ahead.
            var node = Self.ahead(position).0
            let links = route.map { next -> TrackTraversal in
                defer { node = next }
                return TrackTraversal.link(from: node, to: next)
            }
            let path = TrainPath(traversals: links, end: nil, distance: units)
            legs.append(LineLeg(from: from, to: to, path: path, minutes: units == 0 ? 0 : (units - 1) / line.rate + 1))
            if route.count >= 1 {
                let previous = route.count >= 2 ? route[route.count - 2] : Self.ahead(position).0
                let arrived = TrainPosition.atNode(route[route.count - 1], heading: stepDirection(from: previous, to: route[route.count - 1])!)
                body = Self.body(after: position, body, to: arrived, passed: route, length: length)
                position = arrived
            }
        }
        let total = legs.reduce(Int64(0)) { $0 + $1.minutes } + 2 * 2 + Int64(2 * (n - 2)) * 1
        return LineJourney(start: start, legs: legs, roundTripMinutes: total)
    }

    /// Everything derived for one service of a line: `nil` parts where the
    /// line or pattern does not exist or cannot be driven.
    struct LineAnswers: Equatable {
        var journey: LineJourney?
        var maximum: Int?
        var trains: [ServiceLevel: Int]
        var headways: [ServiceLevel: Int64]
    }

    func lineAnswers(_ id: LineID, pattern: Int? = nil) -> LineAnswers {
        let none = LineAnswers(journey: nil, maximum: nil, trains: [:], headways: [:])
        guard let line = lines.first(where: { $0.id == id.rawValue }) else { return none }
        if let pattern, !line.patterns.indices.contains(pattern) { return none }
        let k = pattern.map { $0 + 1 } ?? 0
        let journeys = (0...k).map { serviceJourney(line, $0) }
        guard let journey = journeys[k] else { return none }
        var answers = LineAnswers(journey: journey, maximum: Self.maximumTrains(roundTrip: journey.roundTripMinutes), trains: [:], headways: [:])
        for level in ServiceLevel.allCases {
            let plan = Self.plans(line, at: level, journeys: journeys)[k]!
            answers.trains[level] = plan.trains
            answers.headways[level] = plan.headway
        }
        return answers
    }

    /// Everything derived for every service of line `id` (its own first,
    /// then its patterns) and the load on each segment at every level, from
    /// one drive of each service's journey; `nil` if the line does not
    /// exist.
    func allLineAnswers(_ id: LineID) -> (services: [LineAnswers], loads: [ServiceLevel: [Int]])? {
        guard let line = lines.first(where: { $0.id == id.rawValue }) else { return nil }
        let journeys = (0...line.patterns.count).map { serviceJourney(line, $0) }
        var services = journeys.map { journey in
            LineAnswers(journey: journey, maximum: journey.map { Self.maximumTrains(roundTrip: $0.roundTripMinutes) }, trains: [:], headways: [:])
        }
        var loads: [ServiceLevel: [Int]] = [:]
        for level in ServiceLevel.allCases {
            let plans = Self.plans(line, at: level, journeys: journeys)
            for (k, plan) in plans.enumerated() {
                guard let plan else { continue }
                services[k].trains[level] = plan.trains
                services[k].headways[level] = plan.headway
            }
            loads[level] = (0..<(line.stops.count - 1)).map { Self.loadBefore(line, plans, $0) }
        }
        return (services, loads)
    }

    /// Decisions 22 and 23: the trains a service runs at `level` on its own
    /// and the headway, `nil` without trains. With a target: enough trains
    /// that their share of the round trip is no longer than it (but no
    /// more than the maximum), and the target or that share, whichever is
    /// longer.
    static func plan(_ service: Pattern, at level: ServiceLevel, roundTrip: Int64, maximum: Int) -> (trains: Int, headway: Int64?) {
        let count: Int
        if let target = service.targets[level] {
            let enough = Int((roundTrip - 1) / target + 1)
            count = enough < maximum ? enough : maximum
        } else {
            let wanted = service.trains[level]!
            count = wanted < maximum ? wanted : maximum
        }
        guard count > 0 else { return (0, nil) }
        return (count, headway(count, roundTrip: roundTrip, target: service.targets[level]))
    }

    static func headway(_ count: Int, roundTrip: Int64, target: Int64?) -> Int64 {
        let share = (roundTrip - 1) / Int64(count) + 1
        guard let target else { return share }
        return share > target ? share : target
    }

    /// Decision 24: a day's trains at `headway`, rounded up.
    static func load(_ headway: Int64) -> Int {
        Int((1440 + headway - 1) / headway)
    }

    /// Decision 24: what each of the first `journeys.count` services of
    /// `line` runs at `level` (`nil` where its journey cannot be driven):
    /// in order, each takes what it would run alone, then counts down until
    /// a day's trains at its headway, added on every segment from its first
    /// call to its last to what the services before it put there, stays
    /// within 720.
    static func plans(_ line: Line, at level: ServiceLevel, journeys: [LineJourney?]) -> [(trains: Int, headway: Int64?)?] {
        var plans: [(trains: Int, headway: Int64?)?] = []
        for (k, journey) in journeys.enumerated() {
            guard let journey else {
                plans.append(nil)
                continue
            }
            let service = line.service(k)
            let alone = plan(service, at: level, roundTrip: journey.roundTripMinutes, maximum: maximumTrains(roundTrip: journey.roundTripMinutes))
            var count = alone.trains
            while count > 0 {
                let mine = load(headway(count, roundTrip: journey.roundTripMinutes, target: service.targets[level]))
                let fits = (service.calls.first!..<service.calls.last!).allSatisfy { segment in
                    loadBefore(line, plans, segment) + mine <= 720
                }
                if fits { break }
                count -= 1
            }
            plans.append(count == 0 ? (0, nil) : (count, headway(count, roundTrip: journey.roundTripMinutes, target: service.targets[level])))
        }
        return plans
    }

    /// What `plans` (of services 0, 1, ... of `line`) put on `segment`.
    static func loadBefore(_ line: Line, _ plans: [(trains: Int, headway: Int64?)?], _ segment: Int) -> Int {
        var total = 0
        for (k, plan) in plans.enumerated() {
            guard let headway = plan?.headway else { continue }
            let calls = line.service(k).calls
            if calls.first! <= segment, segment < calls.last! { total += load(headway) }
        }
        return total
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

    func lineMaximumTrains(_ id: LineID, pattern: Int? = nil) -> Int? {
        lineAnswers(id, pattern: pattern).maximum
    }

    func lineTrainsInService(_ id: LineID, at level: ServiceLevel, pattern: Int? = nil) -> Int? {
        lineAnswers(id, pattern: pattern).trains[level]
    }

    func lineHeadway(_ id: LineID, at level: ServiceLevel, pattern: Int? = nil) -> Int64? {
        lineAnswers(id, pattern: pattern).headways[level]
    }

    /// Decision 24: every segment's load, summed afresh from the plans.
    func lineSegmentLoads(_ id: LineID, at level: ServiceLevel) -> [Int]? {
        guard let line = lines.first(where: { $0.id == id.rawValue }) else { return nil }
        let journeys = (0...line.patterns.count).map { serviceJourney(line, $0) }
        let plans = Self.plans(line, at: level, journeys: journeys)
        return (0..<(line.stops.count - 1)).map { Self.loadBefore(line, plans, $0) }
    }
}

// MARK: - Dispatch (decisions 23 and 24)

extension ReferenceWorld {
    func onLine(_ id: TrainID) -> Bool {
        lines.contains { line in line.roster.contains(id.rawValue) || line.patterns.contains { $0.roster.contains(id.rawValue) } }
    }

    mutating func setLineTargets(_ id: LineID, _ targets: TargetHeadways, pattern: Int? = nil) -> GameError? {
        guard let index = lines.firstIndex(where: { $0.id == id.rawValue }) else { return .unknownLine(id) }
        if let pattern, !lines[index].patterns.indices.contains(pattern) { return .unknownLinePattern(pattern) }
        var byLevel: [ServiceLevel: Int64] = [:]
        for level in ServiceLevel.allCases {
            guard let target = targets[level] else { continue }
            guard target >= 2, target <= 1440 else { return .invalidHeadway }
            byLevel[level] = target
        }
        if let pattern {
            lines[index].patterns[pattern].targets = byLevel
        } else {
            lines[index].targets = byLevel
        }
        return nil
    }

    /// The train, then the line, then the pattern, then not on a line, then
    /// no service.
    mutating func assign(_ id: TrainID, to line: LineID, pattern: Int? = nil) -> GameError? {
        guard let train = trains.first(where: { $0.id == id.rawValue }) else { return .unknownTrain(id) }
        guard let index = lines.firstIndex(where: { $0.id == line.rawValue }) else { return .unknownLine(line) }
        if let pattern, !lines[index].patterns.indices.contains(pattern) { return .unknownLinePattern(pattern) }
        if onLine(id) { return .trainOnLine(id) }
        if train.service != nil { return .trainServiceActive(id) }
        if let pattern {
            lines[index].patterns[pattern].roster = (lines[index].patterns[pattern].roster + [id.rawValue]).sorted()
        } else {
            lines[index].roster = (lines[index].roster + [id.rawValue]).sorted()
        }
        return nil
    }

    mutating func unassign(_ id: TrainID) -> GameError? {
        guard trains.contains(where: { $0.id == id.rawValue }) else { return .unknownTrain(id) }
        guard onLine(id) else { return .trainNotOnLine(id) }
        for l in lines.indices {
            lines[l].roster.removeAll { $0 == id.rawValue }
            for p in lines[l].patterns.indices {
                lines[l].patterns[p].roster.removeAll { $0 == id.rawValue }
            }
        }
        return nil
    }

    /// Decision 24: two calls or more, each a stop of the line, rising.
    mutating func addPattern(_ id: LineID, _ calls: [Int]) -> GameError? {
        guard let index = lines.firstIndex(where: { $0.id == id.rawValue }) else { return .unknownLine(id) }
        guard calls.count >= 2, calls.allSatisfy({ (0..<lines[index].stops.count).contains($0) }),
              (1..<calls.count).allSatisfy({ calls[$0 - 1] < calls[$0] })
        else { return .invalidLinePattern }
        lines[index].patterns.append(Pattern(calls: calls))
        return nil
    }

    mutating func removePattern(_ id: LineID, _ pattern: Int) -> GameError? {
        guard let index = lines.firstIndex(where: { $0.id == id.rawValue }) else { return .unknownLine(id) }
        guard lines[index].patterns.indices.contains(pattern) else { return .unknownLinePattern(pattern) }
        lines[index].patterns.remove(at: pattern)
        return nil
    }

    struct ServiceKey: Hashable {
        var line: Int
        var service: Int
    }

    /// What stays the same within one call of `advance`.
    struct DispatchMemo {
        var journeys: [ServiceKey: LineJourney?] = [:]
        /// Trips found from a train's place and body: `(turned, journey)`,
        /// or none.
        var trips: [Place: [ServiceKey: (Bool, LineJourney)?]] = [:]
    }

    struct Place: Hashable {
        var position: TrainPosition
        var trail: [GridPosition]
        var trailEdges: [Int]
    }

    /// Every service of one line, its own first, dispatching at the current
    /// minute.
    mutating func dispatch(_ l: Int, memo: inout DispatchMemo) {
        for k in 0...lines[l].patterns.count {
            dispatch(l, service: k, memo: &memo)
        }
    }

    /// One service's dispatch at the current minute: from minute 0, window
    /// open, a level at which it runs trains beside the services before it
    /// on a drivable journey, a headway since its last dispatch, fewer of
    /// its trains in service than it runs; then the first of its trains, by
    /// ID, without a service, placed, moving at some rate and stopped at its
    /// first call, that can drive the round trip from there (turned round
    /// only if that is shorter or the only way) leaves on it now. Decision
    /// 32: under traffic control, only if its first departure can take its
    /// route; and it leaves at once.
    mutating func dispatch(_ l: Int, service k: Int, memo: inout DispatchMemo) {
        guard isDue(l, service: k, memo: &memo) else { return }
        for id in lines[l].service(k).roster {
            guard let i = trains.firstIndex(where: { $0.id == id }) else { continue }
            switch tripTimetable(i, l, service: k, memo: &memo) {
            case .notReady:
                continue
            case .overflow:
                return
            case .ready(let timetable):
                var sent = trains[i]
                sent.timetable = timetable
                sent.period = nil
                sent.service = Service(stop: 0, waiting: true)
                if trafficControl, let leaving = firstLeaving(sent), holder(of: needs(leaving).resources, except: sent.id) != nil { continue }
                trains[i] = sent
                if k == 0 {
                    lines[l].lastDispatch = minutes
                } else {
                    lines[l].patterns[k - 1].lastDispatch = minutes
                }
                depart(i)
                return
            }
        }
    }

    /// Whether service `k` of line `l` sends a train out now if one is
    /// ready.
    func isDue(_ l: Int, service k: Int, memo: inout DispatchMemo) -> Bool {
        let line = lines[l]
        let service = line.service(k)
        guard !service.roster.isEmpty, minutes >= 0,
              let level = serviceLevel(of: LineID(rawValue: line.id), at: GameTime(minutes: minutes))
        else { return false }
        var journeys: [LineJourney?] = []
        for earlier in 0...k {
            let key = ServiceKey(line: line.id, service: earlier)
            if memo.journeys[key] == nil {
                memo.journeys[key] = .some(serviceJourney(line, earlier))
            }
            journeys.append(memo.journeys[key]!)
        }
        guard journeys[k] != nil, let plan = Self.plans(line, at: level, journeys: journeys)[k], plan.trains > 0,
              let headway = plan.headway
        else { return false }
        if let last = service.lastDispatch, minutes - last < headway { return false }
        let busy = trains.filter { service.roster.contains($0.id) && $0.service != nil }.count
        return busy < plan.trains
    }

    enum TripTimetable {
        case notReady
        case overflow
        case ready([ScheduledStop])
    }

    /// The timetable train `i` would be sent out on by service `k` of line
    /// `l` now: none unless it has no service, is placed, moves at some
    /// rate, stands at the first call and can drive the round trip.
    func tripTimetable(_ i: Int, _ l: Int, service k: Int, memo: inout DispatchMemo) -> TripTimetable {
        let line = lines[l]
        let service = line.service(k)
        let first = line.stops[service.calls[0]]
        let train = trains[i]
        guard train.service == nil, let position = train.position, train.rate > 0,
              stationsStoppedAt(by: TrainID(rawValue: train.id)).contains(first)
        else { return .notReady }
        let place = Place(position: position, trail: train.trail, trailEdges: train.trailEdges)
        let length = Self.length(train)
        let key = ServiceKey(line: line.id, service: k)
        if memo.trips[place]?[key] == nil {
            let straight: LineJourney?
            let turned: LineJourney?
            if case .onEdge = position {
                // Decision 31: on the network, from its place and body.
                straight = networkJourney(of: line, calling: service.calls, from: position, trailEdges: train.trailEdges, length: length)
                let back = turnedOnNetwork(train)
                turned = networkJourney(of: line, calling: service.calls, from: back.position!, trailEdges: back.trailEdges, length: length)
            } else {
                straight = journey(of: line, calling: service.calls, from: position, trail: train.trail, length: length)
                let (back, backBody) = Self.turnedWithBody(position, train.trail, length: length)
                turned = journey(of: line, calling: service.calls, from: back, trail: backBody, length: length)
            }
            let pick: (Bool, LineJourney)? = switch (straight, turned) {
            case (let s?, let t?): t.roundTripMinutes < s.roundTripMinutes ? (true, t) : (false, s)
            case (let s?, nil): (false, s)
            case (nil, let t?): (true, t)
            case (nil, nil): nil
            }
            memo.trips[place, default: [:]][key] = .some(pick)
        }
        guard let (turn, trip) = memo.trips[place]![key]! else { return .notReady }
        // The timetable: leave now; each call the leg's minutes after
        // the one before; stay 1 between the ends, 2 at the far end
        // (turning), and finish on arrival back at the first call
        // (turning).
        var timetable = [ScheduledStop(station: first, arrival: GameTime(minutes: minutes), departure: GameTime(minutes: minutes), reverses: turn)]
        var clock = minutes
        for (n, leg) in trip.legs.enumerated() {
            let final = n == trip.legs.count - 1
            let far = leg.to == service.calls.last!
            let stay: Int64 = final ? 0 : far ? 2 : 1
            guard clock <= Int64.max - leg.minutes - stay else { return .overflow }
            let arrival = clock + leg.minutes
            clock = arrival + stay
            timetable.append(ScheduledStop(
                station: line.stops[leg.to], arrival: GameTime(minutes: arrival), departure: GameTime(minutes: clock), reverses: final || far
            ))
        }
        return .ready(timetable)
    }

    /// Decision 32: the timetable train `train` would be sent out on now by
    /// its line, if the line is due and the train ready (routes aside).
    func readyTrip(of train: Train, line l: Int, service k: Int) -> [ScheduledStop]? {
        var memo = DispatchMemo()
        guard isDue(l, service: k, memo: &memo), let i = trains.firstIndex(where: { $0.id == train.id }),
              case .ready(let timetable) = tripTimetable(i, l, service: k, memo: &memo)
        else { return nil }
        return timetable
    }
}
