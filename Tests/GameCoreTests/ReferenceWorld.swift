import GameCore

/// The whole GameCore kernel (Stages I–S2) written a second time, straight
/// from the documented rules (ARCHITECTURE decisions 3, 5, 6, 10, 14–16 and
/// 18–27; the rules summary), for differential testing.
///
/// It shares no code with GameCore beyond the plain value types used for
/// inputs and outputs, and it is written differently on purpose:
///
/// - tiles live in a dictionary, not a row-major array;
/// - movement is worked out in closed form per step (whole links by
///   division), not by GameCore's link-by-link loop, and there is no
///   shortcut for steps where nothing moves: every minute is stepped;
/// - routes come from distances relaxed until nothing changes followed by a
///   greedy walk, not from a breadth-first search;
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
    enum Tile: Equatable {
        case track(UInt8)
        case station(Int)
        /// Decision 26: a turnout's exits and stem, and a level crossing.
        case turnout(UInt8, TrackDirection)
        case crossing
    }

    struct Station: Equatable {
        var id: Int
        var name: String
        var position: GridPosition
        /// Decision 27: the tiles it grew onto, in order.
        var annexes: [GridPosition] = []
        /// Decision 30: its platforms on the track network, in order.
        var trackPlatforms: [TrackPlatform] = []
        /// Stage F1: where a station built at a point stands; it takes no
        /// tile, and `position` is the tile under the point.
        var point: PlanPoint?

        var tiles: [GridPosition] {
            point == nil ? [position] + annexes : []
        }
    }

    struct Train: Equatable {
        var id: Int
        var name: String
        var position: TrainPosition?
        var rate: Int64 = 0
        var continuation: [GridPosition] = []
        var cursor = 0
        var timetable: [ScheduledStop] = []
        /// Stage W2a: in seconds, like the times.
        var period: Int64?
        var service: Service?
        /// Decision 27: its cars, and the nodes its body lies over.
        var cars = 1
        var trail: [GridPosition] = []
        /// Decision 29: on the track network, the edges it enters next and
        /// the edges its body lies over behind its head's edge.
        var edges: [Int] = []
        var trailEdges: [Int] = []
        /// Decision 31: where on the last edge of its path it stops, `nil`
        /// at that edge's end.
        var end: Int64?
        /// Decision 32: the track it has reserved, in resource order.
        var reservation: [TrackResource] = []
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

    let width: Int
    let height: Int
    var tiles: [GridPosition: Tile] = [:]
    var stations: [Station] = []
    var trains: [Train] = []
    var balance: Int64
    let costs: (track: Int64, station: Int64, train: Int64)
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

        var grid: [Key: [GridPosition]?] = [:]
        var network: [Key: TrainPath?] = [:]

        static func == (lhs: RouteMemo, rhs: RouteMemo) -> Bool { true }
    }

    /// Decision 22: a service line; `hours` is `nil` all day. Decision 23:
    /// its targets by level, the IDs of its trains and its last dispatch.
    /// Decision 24: its patterns.
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

        static func == (lhs: Line, rhs: Line) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs.stops == rhs.stops && lhs.performance == rhs.performance
                && lhs.hours?.open == rhs.hours?.open && lhs.hours?.close == rhs.hours?.close && lhs.trains == rhs.trains
                && lhs.targets == rhs.targets && lhs.roster == rhs.roster && lhs.lastDispatch == rhs.lastDispatch
                && lhs.patterns == rhs.patterns
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

    static let linkLength: Int64 = 1024

    init(width: Int, height: Int, balance: Int64, costs: ConstructionCosts, seconds: Int64, speed: GameSpeed) {
        self.width = width
        self.height = height
        self.balance = balance
        self.costs = (costs.track.amount, costs.station.amount, costs.train.amount)
        self.clockSeconds = seconds
        self.speed = speed
        self.resumeSpeed = speed == .paused ? .normal : speed
    }

    init(width: Int, height: Int, balance: Int64, costs: ConstructionCosts, minutes: Int64, speed: GameSpeed) {
        self.init(width: width, height: height, balance: balance, costs: costs, seconds: minutes * 60, speed: speed)
    }

    /// The minute the clock is in, rounded down: everything but travel
    /// happens at whole minutes, where it is the clock in minutes.
    var minutes: Int64 {
        clockSeconds >= 0 ? clockSeconds / 60 : -((-clockSeconds + 59) / 60)
    }

    static func == (lhs: ReferenceWorld, rhs: ReferenceWorld) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.tiles == rhs.tiles && lhs.stations == rhs.stations
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

    func inMap(_ p: GridPosition) -> Bool {
        p.x >= 0 && p.y >= 0 && p.x < width && p.y < height
    }

    /// The mask bit for a direction: north 1, east 2, south 4, west 8.
    static func bit(_ direction: TrackDirection) -> UInt8 {
        switch direction {
        case .north: 1
        case .east: 2
        case .south: 4
        case .west: 8
        }
    }

    func mask(at p: GridPosition) -> UInt8? {
        guard inMap(p) else { return nil }
        switch tiles[p] {
        case .track(let mask)?, .turnout(let mask, _)?: return mask
        case .crossing?: return 15
        case .station?, nil: return nil
        }
    }

    /// Decision 26, as a table: the (way in, way out) pairs a piece allows,
    /// written as the side a train entered by and the side it leaves by;
    /// `nil` for a piece that allows every pair but straight back.
    func allowedTurns(at p: GridPosition) -> Set<[TrackDirection]>? {
        switch tiles[p] {
        case .turnout(let mask, let stem)?:
            let branches = TrackDirection.allCases.filter { mask & Self.bit($0) != 0 && $0 != stem }
            return Set(branches.flatMap { [[stem, $0], [$0, stem]] })
        case .crossing?:
            return [[.north, .south], [.south, .north], [.east, .west], [.west, .east]]
        default:
            return nil
        }
    }

    /// Whether a train at `p` facing `facing` may leave toward `way`: never
    /// straight back, and on a turnout or crossing only by an allowed pair
    /// when it came in by one of the piece's exits.
    func mayTurn(at p: GridPosition, facing: TrackDirection, to way: TrackDirection) -> Bool {
        guard way != facing.opposite else { return false }
        guard let turns = allowedTurns(at: p), let mask = mask(at: p), mask & Self.bit(facing.opposite) != 0 else { return true }
        return turns.contains([facing.opposite, way])
    }

    /// Decision 10: both tiles are track, orthogonal neighbours, and each has
    /// an exit toward the other.
    func joined(_ p: GridPosition, _ q: GridPosition) -> Bool {
        guard let way = stepDirection(from: p, to: q), let a = mask(at: p), let b = mask(at: q) else { return false }
        return a & Self.bit(way) != 0 && b & Self.bit(way.opposite) != 0
    }

    func neighbors(of p: GridPosition) -> [GridPosition] {
        guard mask(at: p) != nil else { return [] }
        return TrackDirection.allCases.map { step(p, $0) }.filter { joined(p, $0) }
    }

    func isOnTrack(_ position: TrainPosition) -> Bool {
        switch position {
        case .atNode(let tile, _):
            return mask(at: tile) != nil
        case .onLink(let from, let to, let offset):
            return offset > 0 && offset < Self.linkLength && joined(from, to)
        case .onEdge(let traversal, let offset):
            return isOnNetwork(traversal, offset)
        }
    }

    // MARK: - Stations (decision 18)

    /// Decision 27: the track beside every tile of the station, tile by
    /// tile, each once.
    func platforms(of id: StationID) -> [GridPosition] {
        guard let station = stations.first(where: { $0.id == id.rawValue }) else { return [] }
        var found: [GridPosition] = []
        for tile in station.tiles {
            for p in TrackDirection.allCases.map({ step(tile, $0) }) where mask(at: p) != nil && !found.contains(p) {
                found.append(p)
            }
        }
        return found
    }

    /// The stations with a tile beside `tile`.
    func stations(beside tile: GridPosition) -> [StationID] {
        stations.filter { $0.tiles.contains { stepDirection(from: tile, to: $0) != nil } }.map { StationID(rawValue: $0.id) }
    }

    func stationsStoppedAt(by id: TrainID) -> [StationID] {
        guard let train = trains.first(where: { $0.id == id.rawValue }) else { return [] }
        if case .onEdge? = train.position {
            // Decision 31: see networkStops(of:).
            return networkStops(of: train)
        }
        guard case .atNode(let tile, _)? = train.position,
              train.cursor >= train.continuation.count
        else { return [] }
        return stations(beside: tile)
    }

    // MARK: - Commands

    private static func isValidName(_ name: String) -> Bool {
        name.contains { !$0.isWhitespace }
    }

    private func requireEmpty(_ p: GridPosition) -> GameError? {
        guard inMap(p) else { return .outOfBounds(p) }
        return tiles[p] == nil ? nil : .tileOccupied(p)
    }

    func funds(_ cost: Int64) -> GameError? {
        balance >= cost ? nil : .insufficientFunds(required: Money(cost), available: Money(balance))
    }

    mutating func buildTrack(at p: GridPosition, mask: UInt8) -> GameError? {
        guard mask != 0, mask & 0xF0 == 0 else { return .invalidTrackConnections }
        if let error = requireEmpty(p) ?? funds(costs.track) { return error }
        balance -= costs.track
        tiles[p] = .track(mask)
        return nil
    }

    /// Decision 26: three exits or more, only the four, the stem among them.
    mutating func buildTurnout(at p: GridPosition, mask: UInt8, stem: TrackDirection) -> GameError? {
        guard mask & 0xF0 == 0, mask & Self.bit(stem) != 0, TrackDirection.allCases.filter({ mask & Self.bit($0) != 0 }).count >= 3 else {
            return .invalidTrackConnections
        }
        if let error = requireEmpty(p) ?? funds(costs.track) { return error }
        balance -= costs.track
        tiles[p] = .turnout(mask, stem)
        return nil
    }

    mutating func buildCrossing(at p: GridPosition) -> GameError? {
        if let error = requireEmpty(p) ?? funds(costs.track) { return error }
        balance -= costs.track
        tiles[p] = .crossing
        return nil
    }

    mutating func removeTrack(at p: GridPosition) -> GameError? {
        guard inMap(p) else { return .outOfBounds(p) }
        guard mask(at: p) != nil else { return .noTrackToRemove(p) }
        let supports = trains.contains { train in
            // Decision 27: the body's nodes too.
            if train.trail.contains(p) { return true }
            switch train.position {
            case .atNode(let tile, _)?: return tile == p
            case .onLink(let from, let to, _)?: return from == p || to == p
            case .onEdge?, nil: return false
            }
        }
        guard !supports else { return .trackInUse(p) }
        // Decision 32: nor track a train has reserved.
        if trafficControl, let holder = reserves(tile: p) { return .trackReserved(TrainID(rawValue: holder)) }
        tiles[p] = nil
        return nil
    }

    mutating func buildStation(named name: String, at p: GridPosition) -> GameError? {
        guard Self.isValidName(name) else { return .invalidName }
        if let error = requireEmpty(p) { return error }
        guard nextStationID != Int.max else { return .idsExhausted }
        if let error = funds(costs.station) { return error }
        balance -= costs.station
        stations.append(Station(id: nextStationID, name: name, position: p))
        tiles[p] = .station(nextStationID)
        nextStationID += 1
        return nil
    }

    /// Stage F1: in the order name, point on the map (else the tile under
    /// it, rounding down, is out of bounds), ID, money. The station takes
    /// no tile.
    mutating func buildStation(named name: String, at point: PlanPoint) -> GameError? {
        guard Self.isValidName(name) else { return .invalidName }
        let tile = GridPosition(
            x: Int((Double(point.x) / 1_024).rounded(.down)), y: Int((Double(point.y) / 1_024).rounded(.down))
        )
        guard point.x >= 0, point.y >= 0, point.x < Int64(width) * 1_024, point.y < Int64(height) * 1_024 else { return .outOfBounds(tile) }
        guard nextStationID != Int.max else { return .idsExhausted }
        if let error = funds(costs.station) { return error }
        balance -= costs.station
        stations.append(Station(id: nextStationID, name: name, position: tile, point: point))
        nextStationID += 1
        return nil
    }

    /// Decision 27: in the order station, tile (on the map, empty), beside
    /// one of the station's tiles, money.
    mutating func extendStation(_ id: StationID, to p: GridPosition) -> GameError? {
        guard let i = stations.firstIndex(where: { $0.id == id.rawValue }) else { return .unknownStation(id) }
        if let error = requireEmpty(p) { return error }
        guard stations[i].tiles.contains(where: { stepDirection(from: $0, to: p) != nil }) else { return .invalidStationTile(p) }
        if let error = funds(costs.station) { return error }
        balance -= costs.station
        stations[i].annexes.append(p)
        tiles[p] = .station(stations[i].id)
        return nil
    }

    /// Decision 27: in the order train, 1 to 16 cars, off the track.
    mutating func setCars(_ id: TrainID, _ cars: Int) -> GameError? {
        switch index(id) {
        case .failure(let error): return error
        case .success(let i):
            guard cars >= 1, cars <= 16 else { return .invalidTrainLength }
            guard trains[i].position == nil else { return .trainAlreadyPlaced(id) }
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
    /// would take the continuation or the train away from a service.
    private func manual(_ id: TrainID) -> Result<Int, GameError> {
        placed(id).flatMap { trains[$0].service == nil ? .success($0) : .failure(.trainServiceActive(id)) }
    }

    mutating func placeTrain(_ id: TrainID, at position: TrainPosition) -> GameError? {
        switch index(id) {
        case .failure(let error): return error
        case .success(let i):
            guard trains[i].position == nil else { return .trainAlreadyPlaced(id) }
            guard isOnTrack(position) else { return .invalidTrainPosition }
            var placed = trains[i]
            if case .onEdge(let traversal, let offset) = position {
                let length = Self.length(trains[i])
                guard length == 0 || offset > 0, let body = networkBody(behind: traversal, offset: offset, length: length) else {
                    return .invalidTrainPosition
                }
                placed.position = position
                placed.trailEdges = body
            } else {
                guard let body = body(behind: position, length: Self.length(trains[i])) else { return .invalidTrainPosition }
                placed.position = position
                placed.trail = body
            }
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
            var turned = trains[i]
            if case .onEdge? = turned.position {
                turned = turnedOnNetwork(turned)
            } else {
                (turned.position, turned.trail) = Self.turnedWithBody(turned.position!, turned.trail, length: Self.length(turned))
            }
            turned.continuation = []
            turned.edges = []
            turned.cursor = 0
            turned.end = nil
            return admit(turned, at: i)
        }
    }

    /// Decision 14: the same place, facing the other way.
    static func turned(_ position: TrainPosition) -> TrainPosition {
        switch position {
        case .atNode(let tile, let heading): .atNode(tile, heading: heading.opposite)
        case .onLink(let from, let to, let offset): .onLink(from: to, to: from, offset: linkLength - offset)
        case .onEdge: preconditionFailure("turned(_:) is for positions on the grid")
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

    /// The node ahead of a placed train and the way it faces there.
    static func ahead(_ position: TrainPosition) -> (GridPosition, TrackDirection) {
        switch position {
        case .atNode(let tile, let heading): (tile, heading)
        case .onLink(let from, let to, _): (to, stepDirection(from: from, to: to)!)
        case .onEdge: preconditionFailure("ahead(_:) is for positions on the grid")
        }
    }

    /// The entries from `start` on that can be entered one after another from
    /// `node` facing `heading`: each a joined neighbour, none straight back.
    func passable(_ nodes: ArraySlice<GridPosition>, from node: GridPosition, heading: TrackDirection) -> [(GridPosition, TrackDirection)] {
        var result: [(GridPosition, TrackDirection)] = []
        var (current, facing) = (node, heading)
        for next in nodes {
            guard let way = stepDirection(from: current, to: next), mayTurn(at: current, facing: facing, to: way), joined(current, next) else { break }
            result.append((next, way))
            (current, facing) = (next, way)
        }
        return result
    }

    mutating func setContinuation(_ id: TrainID, _ nodes: [GridPosition]) -> GameError? {
        switch manual(id) {
        case .failure(let error): return error
        case .success(let i):
            var sent = trains[i]
            if case .onEdge? = trains[i].position {
                // Decision 29: a train on the network follows edges; an
                // empty list still clears (decision 31: where it stops too).
                guard nodes.isEmpty else { return .invalidContinuation }
                sent.edges = []
                sent.cursor = 0
                sent.end = nil
                return admit(sent, at: i)
            }
            let (node, heading) = Self.ahead(trains[i].position!)
            guard passable(nodes[...], from: node, heading: heading).count == nodes.count else { return .invalidContinuation }
            sent.continuation = nodes
            sent.cursor = 0
            // Decision 32: the whole of it, or nothing.
            return admit(sent, at: i)
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
            if second == 0 {
                // Decision 36: the hour and the day that ended are settled first.
                settle(memo: &memo)
                // Decision 34: passengers first, from the minute's demand.
                releasePassengers()
                for l in lines.indices {
                    dispatch(l, memo: &memo)
                }
            }
            for i in trains.indices {
                dwell(i, second: second)
                leave(i)
                resume(i)
            }
            for i in trains.indices where trains[i].position != nil {
                let distance = travel(i, second: second)
                guard distance > 0 else { continue }
                if case .onEdge? = trains[i].position {
                    trains[i] = steppedOnNetwork(trains[i], distance: distance)
                } else {
                    trains[i] = stepped(trains[i], distance: distance)
                }
                // Decision 32: a route that has come to its end is released.
                releaseIfArrived(i)
            }
            // Stage W2c: a train that fell behind its run drops it.
            for i in trains.indices {
                dropIfHeldUp(i)
            }
            clockSeconds += 1
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
    /// (42 s at either end or a turn, 36 s elsewhere) and reached its
    /// scheduled departure.
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
        let terminal = service.stop == 0 || service.stop == train.timetable.count - 1 || train.timetable[service.stop].reverses
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
        let leaving = service.stop
        departedDistance = nil
        _ = departOnce(i)
        guard trains[i].service != service else { return }
        refuseLeftBehind(i, stop: leaving)
        if trains[i].service != nil, let distance = departedDistance {
            countDeparture(i, distance: distance)
        }
    }

    /// One departure of train `i` from the stop its service waits at, on
    /// either kind of track; `true` when it arrived at once at the next
    /// stop, so the next one may be left too.
    mutating func departOnce(_ i: Int) -> Bool {
        if case .onEdge? = trains[i].position { return departOnNetwork(i) }
        return departOnGrid(i)
    }

    /// One departure on the grid: finish at the last stop, arrive at once
    /// where the train already is stopped at the next stop's station
    /// (decision 27: and needs no pull along its platforms), or set off
    /// along a route; wait if there is none. Decision 21: turn the train
    /// first at a stop marked to, but only if it then finishes, arrives at
    /// once or finds a route; after the last stop of a repeating timetable
    /// go on to the first stop of the next cycle while its times fit.
    /// Decision 32: under traffic control, only if the train can take what
    /// that needs.
    private mutating func departOnGrid(_ i: Int) -> Bool {
        let service = trains[i].service!
        let stop = trains[i].timetable[service.stop]
        // Decision 27: a train with cars turns round with its head at
        // its tail.
        let length = Self.length(trains[i])
        let (start, body) = stop.reverses
            ? Self.turnedWithBody(trains[i].position!, trains[i].trail, length: length)
            : (trains[i].position!, trains[i].trail)
        var leaving = trains[i]
        leaving.position = start
        leaving.trail = body
        var next = (stop: service.stop + 1, cycle: service.cycle)
        if next.stop == trains[i].timetable.count {
            next = (0, service.cycle + 1)
            if trains[i].period == nil || !Self.fits(trains[i], cycle: next.cycle) {
                leaving.service = nil
                _ = admit(leaving, at: i)
                return false
            }
        }
        let target = trains[i].timetable[next.stop].station
        // Decision 27: the route pulls a train with cars along the
        // platforms; one already stopped there that needs no pull is
        // there at once.
        let key = RouteMemo.Key(start: start, station: target, length: length)
        let route = routeMemo.grid[key] ?? route(from: start, toStation: target, length: length)
        routeMemo.grid[key] = .some(route)
        if case .atNode(let tile, _) = start, stations(beside: tile).contains(target), route == [] {
            leaving.service = Service(stop: next.stop, waiting: true, cycle: next.cycle, arrival: clockSeconds, departure: clockSeconds)
            departedDistance = 0
            return admit(leaving, at: i) == nil
        }
        guard let route else { return false }
        departedDistance = Int64(route.count) * 1024
        leaving.continuation = route
        leaving.cursor = 0
        leaving.service = Service(
            stop: next.stop, waiting: false, cycle: next.cycle, arrival: service.arrival, departure: clockSeconds,
            run: setOff(trains[i], length: Int64(route.count) * 1024, from: (service.stop, service.cycle), to: next)
        )
        _ = admit(leaving, at: i)
        return false
    }

    /// One basic step for one train, in closed form: the train first needs
    /// the rest of its link, then each whole link is 1024 units; with `q`
    /// whole links and `r` units over, it has entered `q` links and, if
    /// `r > 0` and another link can be entered, is `r` into the next one.
    private func stepped(_ train: Train, distance: Int64) -> Train {
        // Decision 27: the body follows the head over the nodes it passed.
        var (moved, passed) = steppedHead(train, distance: distance)
        moved.trail = Self.body(after: train.position!, train.trail, to: moved.position!, passed: passed, length: Self.length(train))
        return moved
    }

    /// The head's step, and the nodes it entered on the way, in order.
    func steppedHead(_ train: Train, distance: Int64) -> (Train, [GridPosition]) {
        var train = train
        let position = train.position!
        let (node, heading) = Self.ahead(position)
        var distance = distance
        if case .onLink(let from, let to, let offset) = position {
            let toEnd = Self.linkLength - offset
            if distance < toEnd {
                train.position = .onLink(from: from, to: to, offset: offset + distance)
                return (train, [])
            }
            distance -= toEnd
            train.position = .atNode(node, heading: heading)
        }
        let chain = passable(train.continuation[train.cursor...], from: node, heading: heading)
        let whole = distance / Self.linkLength
        let over = distance % Self.linkLength
        let entered: Int
        if whole >= Int64(chain.count) {
            entered = chain.count
            if let last = chain.last {
                train.position = .atNode(last.0, heading: last.1)
            }
        } else {
            let q = Int(whole)
            if q > 0 {
                train.position = .atNode(chain[q - 1].0, heading: chain[q - 1].1)
            }
            if over > 0 {
                let from = q == 0 ? node : chain[q - 1].0
                train.position = .onLink(from: from, to: chain[q].0, offset: over)
                entered = q + 1
            } else {
                entered = q
            }
        }
        train.cursor += entered
        if train.cursor == train.continuation.count {
            train.continuation = []
            train.cursor = 0
        }
        return (train, chain.prefix(entered).map(\.0))
    }

    // MARK: - Routes

    private struct State: Hashable {
        var node: GridPosition
        var heading: TrackDirection
    }

    /// Distances by relaxation, then the greedy walk in N, E, S, W order.
    func route(from start: TrainPosition, toAny destinations: Set<GridPosition>) -> [GridPosition]? {
        guard isOnTrack(start), !destinations.isEmpty else { return nil }
        let (node, heading) = Self.ahead(start)
        if destinations.contains(node) { return [] }
        func moves(_ s: State) -> [State] {
            neighbors(of: s.node).compactMap { n in
                let way = stepDirection(from: s.node, to: n)!
                return mayTurn(at: s.node, facing: s.heading, to: way) ? State(node: n, heading: way) : nil
            }
        }
        let trackTiles = tiles.keys.filter { mask(at: $0) != nil }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        let states = trackTiles.flatMap { tile in TrackDirection.allCases.map { State(node: tile, heading: $0) } }
        var distance: [State: Int] = [:]
        for s in states where destinations.contains(s.node) { distance[s] = 0 }
        var changed = true
        while changed {
            changed = false
            for s in states where !destinations.contains(s.node) {
                if let best = moves(s).compactMap({ distance[$0] }).min(), best + 1 < distance[s] ?? .max {
                    distance[s] = best + 1
                    changed = true
                }
            }
        }
        var state = State(node: node, heading: heading)
        guard var remaining = distance[state] else { return nil }
        var route: [GridPosition] = []
        while remaining > 0 {
            guard let next = moves(state).first(where: { distance[$0] == remaining - 1 }) else { return nil }
            route.append(next.node)
            state = next
            remaining -= 1
        }
        return route
    }

    func route(from start: TrainPosition, to destination: GridPosition) -> [GridPosition]? {
        mask(at: destination) == nil ? nil : route(from: start, toAny: [destination])
    }

}
