import GameCore

/// The whole GameCore kernel (Stages I–S2) written a second time, straight
/// from the documented rules (ARCHITECTURE decisions 3, 5, 6, 14–16 and
/// 18–27; the rules summary), for differential testing. The track network
/// and the trains on it are in `ReferenceNetwork.swift` (Stage F3c removed
/// the grid's track, stations and movement, ARCHITECTURE decision 51).
///
/// It shares no code with GameCore beyond the plain value types used for
/// inputs and outputs, and it is written differently on purpose:
///
/// - there is no shortcut for steps where nothing moves: every second is
///   stepped;
/// - a service is a stop index, a flag and a cycle, not an enum; every
///   departure looks its route up again (no memory of routes that were not
///   found from one call to the next; within one `advance`, which cannot
///   change the map, Stage W2b keeps the routes it looked up, see
///   `routeMemo`), and a train already stopped at the next stop's station
///   is recognised by being stopped there, not by an empty route;
/// - Stage W2b: a dwell is worked out second by second from its times, with
///   the doors' and the least dwell's rules written as comparisons, not as
///   one event time;
/// - Stage W2c: a service's run is followed second by second, its share of
///   each second taken from the curve; the least second a curve is built
///   for is found by trying every second upward from a bound below it, and
///   the way left is read off the train's link or path (see
///   `ReferenceRuns.swift`);
/// - a repeating timetable is checked by adding the period to the first
///   arrival, not by subtracting, and a scheduled time is the stored time
///   plus the cycle times the period, recomputed at every use;
/// - a line's window is an optional pair (none for all day) checked as one
///   or two ranges of the day, and a leg's minutes are `(units - 1) / rate
///   + 1` rather than a quotient and a remainder;
/// - a line's targets are a dictionary by level, a headway is checked by
///   subtracting the last dispatch from the minute, and a trip's timetable
///   is built from dwells looked up per call;
/// - a line's patterns (decision 24) take room on each segment by summing
///   what every earlier service's plan puts there, recomputed per segment,
///   and find their trains by counting down, not by a binary search.
///
/// Only for small maps: routes cost O(states²).
struct ReferenceWorld: Equatable {
    struct Station: Equatable {
        var id: Int
        var name: String
        /// Decision 30: its platforms on the track network, in order.
        var trackPlatforms: [TrackPlatform] = []
        /// Stage F1: where it stands. Fares measure from it (Stage F3d).
        var point: PlanPoint
    }

    struct Train: Equatable {
        var id: Int
        var name: String
        var position: TrainPosition?
        var rate: Int64 = 0
        var cursor = 0
        var timetable: [ScheduledStop] = []
        /// Stage W2a: in seconds, like the times.
        var period: Int64?
        var service: Service?
        /// Decision 27: its cars.
        var cars = 1
        /// Decision 29: on the track network, the edges it enters next and
        /// the edges its body lies over behind its head's edge.
        var edges: [Int] = []
        var trailEdges: [Int] = []
        /// Decision 31: where on the last edge of its path it stops, `nil`
        /// at that edge's end.
        var end: Int64?
        /// Decision 32: the track it has reserved, in resource order.
        var reservation: [TrackResource] = []
        var trafficVisits: [TrafficVisit] = []
        /// Stage W2c: how it accelerates, brakes and coasts.
        var performance: TrainPerformance = .standard
    }

    /// Decision 20: the timetable entry a service is at or heading for.
    /// Decision 21: and the cycle of a repeating timetable it is in.
    /// Stage W2b: and its times, in seconds: when it reached the stop it
    /// waits at (or last waited at), when its exchange ends, when its
    /// doors started closing, and when it left the stop before. Stage W2c:
    /// and, travelling, the curve it runs on.
    struct Service: Equatable {
        var stop: Int
        var waiting: Bool
        var cycle: Int64 = 0
        var arrival: Int64
        var exchangeEnd: Int64?
        var closing: Int64?
        var departure: Int64?
        var run: CurveRun?

        var execution: TimetableExecution {
            waiting ? .waitingAtStop(stop, cycle: cycle) : .travellingToStop(stop, cycle: cycle)
        }

        var times: ServiceTimes {
            ServiceTimes(
                arrival: GameTime(seconds: arrival), exchangeEnd: exchangeEnd.map(GameTime.init(seconds:)),
                closing: closing.map(GameTime.init(seconds:)), departure: departure.map(GameTime.init(seconds:)),
                run: run.map { ServiceRun(start: GameTime(seconds: $0.start), length: $0.length, seconds: $0.seconds) }
            )
        }
    }

    /// Stage W2c: a run, set off at `start` (a second), `length` units long
    /// and `seconds` long.
    struct CurveRun: Equatable {
        var start: Int64
        var length: Int64
        var seconds: Int64
    }

    /// Stage F3d: how far the world reaches east and south, in world units.
    let width: Int64
    let height: Int64
    var stations: [Station] = []
    var trains: [Train] = []
    var balance: Int64
    let costs: (track: Int64, station: Int64, train: Int64, car: Int64)
    /// Stage W2a: the clock counts seconds, and ticks at 1x leave tenths
    /// of a second pending.
    var clockSeconds: Int64
    var pendingTenths: Int64 = 0
    var speed: GameSpeed
    var resumeSpeed: GameSpeed
    var nextStationID = 1
    var nextTrainID = 1
    var lines: [Line] = []
    var nextLineID = 1
    var serviceDay: [(start: Int, level: ServiceLevel)] = [(0, .low), (420, .peak), (600, .offPeak), (960, .peak), (1200, .offPeak), (1260, .low)]
    /// Decision 29: the track network, in dictionaries by number.
    var networkNodes: [Int: WorldCoordinate] = [:]
    var networkEdges: [Int: NetworkEdge] = [:]
    /// Decision 53 (Stage F2b): the fouling of the network as it last was
    /// asked for (see `fouling`), kept by the network it belongs to.
    let foulingMemo = ReferenceFoulingMemo()
    var nextNetworkNode = 1
    var nextNetworkEdge = 1
    /// Decision 32: traffic control.
    var trafficControl = false
    /// Decision 34: the stations' demand, queues and counts.
    var passengers = ReferencePassengers()
    /// Decision 36: the company's accounts.
    var accounts = ReferenceAccounts()
    /// Decision 36: how far the last departure took its train, `nil` when
    /// its service ended instead; set by the departures.
    var departedDistance: Int64?
    /// Stage W2b: routes worked out for departures within one `advance`,
    /// which cannot change the map. A departure is now tried every second,
    /// and this model's route search is slow (O(states²)), so its results
    /// are kept for the call: the same start, station and length give the
    /// same route. Not the model's state: `==` ignores it, and `advance`
    /// empties it before it returns.
    var routeMemo = RouteMemo()

    struct RouteMemo: Equatable {
        struct Key: Hashable {
            var start: TrainPosition
            var station: StationID
            var length: Int64
        }

        var network: [Key: TrainPath?] = [:]
        var scheduled: ScheduledPlan?
        struct Order: Hashable {
            var stations: [StationID]
            var turns: Set<Int>
            var length: Int64
            var repeats: Bool
        }
        var directions: [Order: Set<Run>] = [:]
        /// A running service's walk on from where it stands.
        struct Walk: Hashable {
            var order: Order
            var seed: ReferenceWorld.DirectionState
        }
        var walks: [Walk: Set<Run>] = [:]
        /// V1: only reused within one advance (unchanged network), and
        /// only while every blocking resource is exactly the same.
        struct BlockedKey: Hashable {
            var route: Key
            var track: Set<TrackResource>
            var forbidden: Set<Run>
        }
        var unblocked: [BlockedKey: TrainPath?] = [:]

        static func == (lhs: RouteMemo, rhs: RouteMemo) -> Bool { true }
    }

    /// Decision 22: a service line; `hours` is `nil` all day. Decision 23:
    /// its targets by level, the IDs of its trains and its last dispatch.
    /// Decision 24: its patterns. Decision 49: whether it is a ring, and
    /// when it last sent a train out the outer way.
    struct Line: Equatable {
        var id: Int
        var name: String
        var stops: [StationID]
        /// Stage W2c: what its legs are timed with.
        var performance: TrainPerformance = .standard
        var hours: (open: Int, close: Int)? = (360, 1440)
        var trains: [ServiceLevel: Int] = [.peak: 0, .offPeak: 0, .low: 0]
        var targets: [ServiceLevel: Int64] = [:]
        var roster: [Int] = []
        var lastDispatch: Int64?
        var patterns: [Pattern] = []
        var ring = false
        var outerLastDispatch: Int64?

        static func == (lhs: Line, rhs: Line) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs.stops == rhs.stops && lhs.performance == rhs.performance
                && lhs.hours?.open == rhs.hours?.open && lhs.hours?.close == rhs.hours?.close && lhs.trains == rhs.trains
                && lhs.targets == rhs.targets && lhs.roster == rhs.roster && lhs.lastDispatch == rhs.lastDispatch
                && lhs.patterns == rhs.patterns && lhs.ring == rhs.ring && lhs.outerLastDispatch == rhs.outerLastDispatch
        }

        var targetHeadways: TargetHeadways {
            TargetHeadways(peak: targets[.peak], offPeak: targets[.offPeak], low: targets[.low])
        }

        var window: ServiceWindow {
            hours.map { .hours(open: $0.open, close: $0.close) } ?? .allDay
        }

        var trainsInService: TrainsInService {
            TrainsInService(peak: trains[.peak]!, offPeak: trains[.offPeak]!, low: trains[.low]!)
        }

        /// Service `k`: the line's own (every stop) for 0, pattern `k - 1`
        /// after it, as one shape.
        func service(_ k: Int) -> Pattern {
            k == 0 ? Pattern(calls: Array(0..<stops.count), trains: trains, targets: targets, roster: roster, lastDispatch: lastDispatch) : patterns[k - 1]
        }
    }

    /// Decision 24: a further service of a line.
    struct Pattern: Equatable {
        var calls: [Int]
        var trains: [ServiceLevel: Int] = [.peak: 0, .offPeak: 0, .low: 0]
        var targets: [ServiceLevel: Int64] = [:]
        var roster: [Int] = []
        var lastDispatch: Int64?

        var targetHeadways: TargetHeadways {
            TargetHeadways(peak: targets[.peak], offPeak: targets[.offPeak], low: targets[.low])
        }

        var trainsInService: TrainsInService {
            TrainsInService(peak: trains[.peak]!, offPeak: trains[.offPeak]!, low: trains[.low]!)
        }
    }

    /// One car from the next, centre to centre (decision 46).
    static let carLength: Int64 = 1024

    init(width: Int64, height: Int64, balance: Int64, costs: ConstructionCosts, seconds: Int64, speed: GameSpeed) {
        self.width = width
        self.height = height
        self.balance = balance
        self.costs = (costs.track.amount, costs.station.amount, costs.train.amount, costs.car.amount)
        self.clockSeconds = seconds
        self.speed = speed
        self.resumeSpeed = speed == .paused ? .normal : speed
    }

    init(width: Int64, height: Int64, balance: Int64, costs: ConstructionCosts, minutes: Int64, speed: GameSpeed) {
        self.init(width: width, height: height, balance: balance, costs: costs, seconds: minutes * 60, speed: speed)
    }

    /// The minute the clock is in, rounded down: everything but travel
    /// happens at whole minutes, where it is the clock in minutes.
    var minutes: Int64 {
        clockSeconds >= 0 ? clockSeconds / 60 : -((-clockSeconds + 59) / 60)
    }

    static func == (lhs: ReferenceWorld, rhs: ReferenceWorld) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.stations == rhs.stations
            && lhs.trains == rhs.trains && lhs.balance == rhs.balance && lhs.costs == rhs.costs
            && lhs.clockSeconds == rhs.clockSeconds && lhs.pendingTenths == rhs.pendingTenths
            && lhs.speed == rhs.speed && lhs.resumeSpeed == rhs.resumeSpeed && lhs.nextStationID == rhs.nextStationID
            && lhs.nextTrainID == rhs.nextTrainID && lhs.lines == rhs.lines && lhs.nextLineID == rhs.nextLineID
            && lhs.serviceDay.map(\.start) == rhs.serviceDay.map(\.start) && lhs.serviceDay.map(\.level) == rhs.serviceDay.map(\.level)
            && lhs.networkNodes == rhs.networkNodes && lhs.networkEdges == rhs.networkEdges
            && lhs.nextNetworkNode == rhs.nextNetworkNode && lhs.nextNetworkEdge == rhs.nextNetworkEdge
            && lhs.trafficControl == rhs.trafficControl && lhs.passengers == rhs.passengers && lhs.accounts == rhs.accounts
    }

    // MARK: - Geometry

    /// Stage F3d: whether `point` lies in the world, `0 <= x < width` and
    /// `0 <= y < height`.
    func inWorld(_ point: PlanPoint) -> Bool {
        point.x >= 0 && point.y >= 0 && point.x < width && point.y < height
    }

    func isOnTrack(_ position: TrainPosition) -> Bool {
        switch position {
        case .onEdge(let traversal, let offset):
            return isOnNetwork(traversal, offset)
        }
    }

    // MARK: - Stations (decision 18)

    /// Decision 31: see networkStops(of:).
    func stationsStoppedAt(by id: TrainID) -> [StationID] {
        guard let train = trains.first(where: { $0.id == id.rawValue }), train.position != nil else { return [] }
        return networkStops(of: train)
    }

    // MARK: - Commands

    private static func isValidName(_ name: String) -> Bool {
        name.contains { !$0.isWhitespace }
    }

    func funds(_ cost: Int64) -> GameError? {
        balance >= cost ? nil : .insufficientFunds(required: Money(cost), available: Money(balance))
    }

    /// Stage F1: in the order name, point in the world (Stage F3d: else
    /// that point is out of bounds), ID, money.
    mutating func buildStation(named name: String, at point: PlanPoint) -> GameError? {
        guard Self.isValidName(name) else { return .invalidName }
        guard inWorld(point) else { return .outOfBounds(point) }
        guard nextStationID != Int.max else { return .idsExhausted }
        if let error = funds(costs.station) { return error }
        balance -= costs.station
        stations.append(Station(id: nextStationID, name: name, point: point))
        nextStationID += 1
        return nil
    }

    /// Decision 27: in the order train, 1 to 16 cars, off the track.
    mutating func setCars(_ id: TrainID, _ cars: Int) -> GameError? {
        switch index(id) {
        case .failure(let error): return error
        case .success(let i):
            guard cars >= 1, cars <= 16 else { return .invalidTrainLength }
            guard trains[i].position == nil else { return .trainAlreadyPlaced(id) }
            // Each car added is paid for; one taken off is not paid back.
            if cars > trains[i].cars {
                let price = costs.car * Int64(cars - trains[i].cars)
                // Free cars are added in the red too.
                if price > 0 {
                    if let error = funds(price) { return error }
                    balance -= price
                }
            }
            trains[i].cars = cars
            return nil
        }
    }

    mutating func purchaseTrain(named name: String) -> GameError? {
        guard Self.isValidName(name) else { return .invalidName }
        guard nextTrainID != Int.max else { return .idsExhausted }
        if let error = funds(costs.train) { return error }
        balance -= costs.train
        trains.append(Train(id: nextTrainID, name: name, position: nil))
        nextTrainID += 1
        return nil
    }

    func index(_ id: TrainID) -> Result<Int, GameError> {
        guard let index = trains.firstIndex(where: { $0.id == id.rawValue }) else { return .failure(.unknownTrain(id)) }
        return .success(index)
    }

    private func placed(_ id: TrainID) -> Result<Int, GameError> {
        index(id).flatMap { trains[$0].position == nil ? .failure(.trainNotPlaced(id)) : .success($0) }
    }

    /// Decision 20: a placed train without a service, for the commands that
    /// would take the path or the train away from a service.
    private func manual(_ id: TrainID) -> Result<Int, GameError> {
        placed(id).flatMap { trains[$0].service == nil ? .success($0) : .failure(.trainServiceActive(id)) }
    }

    mutating func placeTrain(_ id: TrainID, at position: TrainPosition) -> GameError? {
        switch index(id) {
        case .failure(let error): return error
        case .success(let i):
            guard trains[i].position == nil else { return .trainAlreadyPlaced(id) }
            guard isOnTrack(position), case .onEdge(let traversal, let offset) = position else { return .invalidTrainPosition }
            var placed = trains[i]
            let length = Self.length(trains[i])
            guard length == 0 || offset > 0, let body = networkBody(behind: traversal, offset: offset, length: length) else {
                return .invalidTrainPosition
            }
            placed.position = position
            placed.trailEdges = body
            // Decision 32: and what it would stand on and run on to.
            return admit(placed, at: i)
        }
    }

    mutating func unplaceTrain(_ id: TrainID) -> GameError? {
        switch manual(id) {
        case .failure(let error): return error
        case .success(let i):
            // Position and movement go; the timetable is plan data and stays.
            // Decision 27: so do the cars. Stage W2c: and the performance.
            trains[i] = Train(
                id: trains[i].id, name: trains[i].name, position: nil, timetable: trains[i].timetable, period: trains[i].period,
                cars: trains[i].cars, performance: trains[i].performance
            )
            return nil
        }
    }

    mutating func reverseTrain(_ id: TrainID) -> GameError? {
        switch manual(id) {
        case .failure(let error): return error
        case .success(let i):
            var turned = turnedOnNetwork(trains[i])
            turned.edges = []
            turned.cursor = 0
            turned.end = nil
            return admit(turned, at: i)
        }
    }

    mutating func setRate(_ id: TrainID, _ rate: Int64) -> GameError? {
        switch placed(id) {
        case .failure(let error): return error
        case .success(let i):
            guard rate >= 0 else { return .invalidMovementRate }
            trains[i].rate = rate
            return nil
        }
    }

    /// Decision 19: the train must exist; then all the times, arrival and
    /// departure of each stop in turn, must be non-negative and never fall;
    /// then every station must exist, the first missing one in timetable
    /// order being reported. Placement does not matter. Decision 20: not
    /// while a service runs, checked right after the train. Decision 21: a
    /// period needs a stop, is a second or more (Stage W2a: periods and
    /// times are seconds), and the first arrival one period later is no
    /// earlier than the last departure; checked with the times.
    mutating func setTimetable(_ id: TrainID, _ stops: [ScheduledStop], period: Int64? = nil) -> GameError? {
        switch index(id) {
        case .failure(let error): return error
        case .success(let i):
            // Decision 23: a line's train takes its timetables from the line.
            if onLine(id) { return .trainOnLine(id) }
            guard trains[i].service == nil else { return .trainServiceActive(id) }
            let times = stops.flatMap { [$0.arrival.seconds, $0.departure.seconds] }
            guard times.allSatisfy({ $0 >= 0 }), zip(times, times.dropFirst()).allSatisfy({ $0 <= $1 }) else {
                return .invalidTimetable
            }
            if let period {
                guard period >= 1, let first = stops.first, let last = stops.last else { return .invalidTimetable }
                let (again, overflow) = first.arrival.seconds.addingReportingOverflow(period)
                // Past the largest second is later than any departure.
                guard overflow || last.departure.seconds <= again else { return .invalidTimetable }
            }
            let known = Set(stations.map(\.id))
            if let missing = stops.first(where: { !known.contains($0.station.rawValue) }) {
                return .unknownStation(missing.station)
            }
            trains[i].trafficVisits = []
            trains[i].timetable = stops
            trains[i].period = period
            return nil
        }
    }

    /// Decision 21: the scheduled departure from entry `stop` in `cycle`, in
    /// seconds, or `nil` if it does not fit in a game second.
    static func departure(_ train: Train, stop: Int, cycle: Int64) -> Int64? {
        let (shift, overflow) = cycle.multipliedReportingOverflow(by: train.period ?? 0)
        guard !overflow else { return nil }
        let (time, late) = train.timetable[stop].departure.seconds.addingReportingOverflow(shift)
        return late ? nil : time
    }

    /// Decision 21: whether every time of `cycle` fits in a game second.
    static func fits(_ train: Train, cycle: Int64) -> Bool {
        departure(train, stop: train.timetable.count - 1, cycle: cycle) != nil
    }

    /// Decision 20: in the order train, no service yet, a timetable, placed,
    /// stopped at the first stop's station; then waiting at stop 0.
    mutating func startService(_ id: TrainID) -> GameError? {
        switch index(id) {
        case .failure(let error): return error
        case .success(let i):
            let train = trains[i]
            if onLine(id) { return .trainOnLine(id) }
            if train.service != nil { return .trainServiceActive(id) }
            if train.timetable.isEmpty { return .noTimetable(id) }
            if train.position == nil { return .trainNotPlaced(id) }
            if !stationsStoppedAt(by: id).contains(train.timetable[0].station) { return .trainNotAtFirstStop(id) }
            // Stage W2b: starting is arriving.
            trains[i].trafficVisits = []
            trains[i].service = Service(stop: 0, waiting: true, cycle: startingCycle(train), arrival: clockSeconds)
            return nil
        }
    }

    /// Decision 21: 0 without a period; otherwise the first cycle that
    /// leaves the first stop at the current second or later, but never past
    /// the last cycle that fits.
    private func startingCycle(_ train: Train) -> Int64 {
        guard let period = train.period else { return 0 }
        let first = train.timetable[0].departure.seconds
        let last = (Int64.max - train.timetable[train.timetable.count - 1].departure.seconds) / period
        guard clockSeconds > first else { return 0 }
        let wanted = (clockSeconds - first - 1) / period + 1
        return min(wanted, last)
    }

    mutating func stopService(_ id: TrainID) -> GameError? {
        switch index(id) {
        case .failure(let error): return error
        case .success(let i):
            if onLine(id) { return .trainOnLine(id) }
            if trains[i].service == nil { return .trainServiceNotActive(id) }
            trains[i].service = nil
            trains[i].trafficVisits = []
            abandonRiders(i)
            return nil
        }
    }

    mutating func setSpeed(_ newSpeed: GameSpeed) {
        speed = newSpeed
        if newSpeed != .paused { resumeSpeed = newSpeed }
    }

    mutating func pause() {
        speed = .paused
    }

    mutating func resume() {
        speed = resumeSpeed
    }

    /// Decisions 3, 15 and 20: checked first, then every second is
    /// stepped (Stage W2a): at a whole minute, the accounts, passengers and
    /// dispatch (decision 23); every service's dwell and departure (Stage
    /// W2b), and a travelling one held up on its run setting off again
    /// (Stage W2c); travel, each train its share of its run's curve or of
    /// its rate per minute for the second; the clock; then arrivals.
    mutating func advance(ticks: Int) -> GameError? {
        let tenthsPerTick: Int64 = switch speed {
        case .paused: 0
        case .x1: 1
        case .x10: 10
        case .x60: 60
        case .normal: 600
        case .double: 1200
        }
        // The tenths in full width: ticks × tenths per tick + pending.
        let product = Int64(ticks).multipliedFullWidth(by: tenthsPerTick)
        let (low, carry) = product.low.addingReportingOverflow(UInt64(pendingTenths))
        let total = (high: product.high + (carry ? 1 : 0), low: low)
        // Too many seconds for an Int64 once divided by 10.
        guard total.high < 5 else { return .clockOverflow }
        let (seconds, tenths) = Int64(10).dividingFullWidth(total)
        guard !clockSeconds.addingReportingOverflow(seconds).overflow else { return .clockOverflow }
        pendingTenths = tenths
        // Decision 23: within one call the map cannot change, so a line's
        // journey, and a trip from an idle train's place, stay the same.
        var memo = DispatchMemo()
        routeMemo = RouteMemo()
        defer { routeMemo = RouteMemo() }
        for _ in 0..<seconds {
            let second = clockSeconds - minutes * 60
            // Decision 56: following trains take what has freed first.
            extendFollowing()
            if second == 0 {
                // Decision 36: the hour and the day that ended are settled first.
                settle(memo: &memo)
                // Decision 34: passengers first, from the minute's demand.
                releasePassengers()
                for l in lines.indices {
                    dispatch(l, memo: &memo)
                }
            }
            if routeMemo.scheduled == nil { routeMemo.scheduled = scheduledPlan() }
            recordScheduledVisits(routeMemo.scheduled!, before: nil)
            for i in trains.indices {
                dwell(i, second: second)
                leave(i)
                resume(i)
                // Decision 58: from a passing place, on to the call.
                goOn(i)
            }
            // Decision 58: once a minute, a way out of a deadlock.
            if second == 0 {
                resolveDeadlock()
            }
            // Decision 56: no farther than its authority, all moving at once
            // from where the second found them.
            let beforeTraffic = trains
            let limits = trains.map(authority)
            for i in trains.indices where trains[i].position != nil {
                let distance = min(travel(i, second: second), limits[i] ?? .max)
                guard distance > 0 else { continue }
                trains[i] = steppedOnNetwork(trains[i], distance: distance)
                // Decisions 32 and 55: the track behind the train is
                // released, and all of it at the end of its route.
                releaseBehind(i)
            }
            // Stage W2c: a train that fell behind its run drops it.
            for i in trains.indices {
                dropIfHeldUp(i)
            }
            clockSeconds += 1
            recordScheduledVisits(routeMemo.scheduled!, before: beforeTraffic)
            for i in trains.indices {
                guard let service = trains[i].service, !service.waiting else { continue }
                let target = trains[i].timetable[service.stop].station
                if stationsStoppedAt(by: TrainID(rawValue: trains[i].id)).contains(target) {
                    trains[i].service = Service(
                        stop: service.stop, waiting: true, cycle: service.cycle, arrival: clockSeconds, departure: service.departure
                    )
                }
            }
        }
        return nil
    }

    /// Stage W2a: the units a train with `rate` units a minute travels in
    /// second `second` (from 0) of a minute, `⌊rate·(second + 1)/60⌋ −
    /// ⌊rate·second/60⌋`, in full-width arithmetic.
    static func share(of rate: Int64, inSecond second: Int64) -> Int64 {
        func covered(_ seconds: Int64) -> Int64 {
            Int64(60).dividingFullWidth(rate.multipliedFullWidth(by: seconds)).quotient
        }
        return covered(second + 1) - covered(second)
    }

    /// Stage W2b: second `second` of a minute of train `i`'s dwell at the
    /// stop its service waits at. 8 s after it arrived its doors are open:
    /// those for the stop get off and those waiting get on, 8 a second a
    /// car either way, the larger number setting how long. While the doors
    /// stay open, at each whole minute, newcomers get on after those still
    /// getting on. The doors start closing at the first second when the
    /// exchange is over and, 9 s later, the train will have dwelt its least
    /// (42 s at either end or a turn, 36 s elsewhere; a ring's train has no
    /// ends, decision 49) and reached its scheduled departure.
    mutating func dwell(_ i: Int, second: Int64) {
        guard var service = trains[i].service, service.waiting else { return }
        let now = clockSeconds
        let perSecond = 8 * Int64(trains[i].cars)
        if let end = service.exchangeEnd {
            if second == 0, service.closing == nil {
                let boarded = board(i, stop: service.stop)
                if boarded > 0 { service.exchangeEnd = Self.capped(max(end, now), (boarded + perSecond - 1) / perSecond) }
            }
        } else {
            guard now >= Self.capped(service.arrival, 8) else { return }
            let busy = exchange(i, stop: service.stop)
            service.exchangeEnd = Self.capped(now, (busy + perSecond - 1) / perSecond)
        }
        let train = trains[i]
        let ends = service.stop == 0 || service.stop == train.timetable.count - 1
        let onRing = lines.contains { $0.ring && $0.roster.contains(train.id) }
        let terminal = train.timetable[service.stop].reverses || (ends && !onRing)
        // A scheduled departure is never negative, so 9 s before it is a time.
        if service.closing == nil, now >= service.exchangeEnd!, now >= Self.capped(service.arrival, (terminal ? 42 : 36) - 9),
           now >= Self.departure(train, stop: service.stop, cycle: service.cycle)! - 9 {
            service.closing = now
        }
        trains[i].service = service
    }

    /// `time + seconds`, or the last second there is when that is later.
    static func capped(_ time: Int64, _ seconds: Int64) -> Int64 {
        time > Int64.max - seconds ? .max : time + seconds
    }

    /// Stage W2b: how late train `id`'s service is, in seconds, negative
    /// when early. Waiting: the seconds past its scheduled departure, or,
    /// before that, how much sooner than scheduled it arrived (never
    /// late). Travelling: the later of how late it left the call before
    /// and how far past its scheduled arrival the clock is (never early).
    func lateness(of id: Int) -> Int64? {
        guard let train = trains.first(where: { $0.id == id }), let service = train.service else { return nil }
        func scheduled(_ stop: Int, _ cycle: Int64) -> (arrival: Int64, departure: Int64) {
            let shift = cycle * (train.period ?? 0)
            return (train.timetable[stop].arrival.seconds + shift, train.timetable[stop].departure.seconds + shift)
        }
        let here = scheduled(service.stop, service.cycle)
        if service.waiting {
            return clockSeconds > here.departure ? clockSeconds - here.departure : min(0, service.arrival - here.arrival)
        }
        var late = max(0, clockSeconds - here.arrival)
        let before: (Int, Int64)? = service.stop > 0 ? (service.stop - 1, service.cycle)
            : service.cycle > 0 ? (train.timetable.count - 1, service.cycle - 1) : nil
        if let left = service.departure, let (stop, cycle) = before {
            late = max(late, left - scheduled(stop, cycle).departure)
        }
        return late
    }

    /// Stage W2b: train `i` leaves the stop its service waits at once its
    /// doors have closed, if it can; a full train counts those it leaves
    /// behind as refused (decision 35), and a line's train counts its
    /// departure (decision 36).
    mutating func leave(_ i: Int) {
        guard let service = trains[i].service, service.waiting, let closing = service.closing,
              clockSeconds >= Self.capped(closing, 9)
        else { return }
        if waitingScheduled(trains[i], plan: routeMemo.scheduled ?? scheduledPlan()) != nil { return }
        let leaving = service.stop
        departedDistance = nil
        _ = departOnce(i)
        guard trains[i].service != service else { return }
        refuseLeftBehind(i, stop: leaving)
        if trains[i].service != nil, let distance = departedDistance {
            countDeparture(i, distance: distance)
        }
    }

    /// One departure of train `i` from the stop its service waits at (see
    /// departOnNetwork(_:)); `true` when it arrived at once at the next
    /// stop, so the next one may be left too.
    mutating func departOnce(_ i: Int) -> Bool {
        departOnNetwork(i)
    }
}
