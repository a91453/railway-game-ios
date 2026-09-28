import GameCore

/// The whole GameCore kernel (Stages I–N) written a second time, straight
/// from the documented rules (ARCHITECTURE decisions 3, 5, 6, 10, 14–16 and
/// 18; the rules summary), for differential testing.
///
/// It shares no code with GameCore beyond the plain value types used for
/// inputs and outputs, and it is written differently on purpose:
///
/// - tiles live in a dictionary, not a row-major array;
/// - movement is worked out in closed form per step (whole links by
///   division), not by GameCore's link-by-link loop, and there is no
///   shortcut for steps where nothing moves: every minute is stepped;
/// - routes come from distances relaxed until nothing changes followed by a
///   greedy walk, not from a breadth-first search.
///
/// Only for small maps: routes cost O(states²).
struct ReferenceWorld: Equatable {
    enum Tile: Equatable {
        case track(UInt8)
        case station(Int)
    }

    struct Station: Equatable {
        var id: Int
        var name: String
        var position: GridPosition
    }

    struct Train: Equatable {
        var id: Int
        var name: String
        var position: TrainPosition?
        var rate: Int64 = 0
        var continuation: [GridPosition] = []
        var cursor = 0
    }

    let width: Int
    let height: Int
    var tiles: [GridPosition: Tile] = [:]
    var stations: [Station] = []
    var trains: [Train] = []
    var balance: Int64
    let costs: (track: Int64, station: Int64, train: Int64)
    var minutes: Int64
    var speed: GameSpeed
    var resumeSpeed: GameSpeed
    var nextStationID = 1
    var nextTrainID = 1

    static let linkLength: Int64 = 1024

    init(width: Int, height: Int, balance: Int64, costs: ConstructionCosts, minutes: Int64, speed: GameSpeed) {
        self.width = width
        self.height = height
        self.balance = balance
        self.costs = (costs.track.amount, costs.station.amount, costs.train.amount)
        self.minutes = minutes
        self.speed = speed
        self.resumeSpeed = speed == .paused ? .normal : speed
    }

    static func == (lhs: ReferenceWorld, rhs: ReferenceWorld) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.tiles == rhs.tiles && lhs.stations == rhs.stations
            && lhs.trains == rhs.trains && lhs.balance == rhs.balance && lhs.costs == rhs.costs && lhs.minutes == rhs.minutes
            && lhs.speed == rhs.speed && lhs.resumeSpeed == rhs.resumeSpeed && lhs.nextStationID == rhs.nextStationID
            && lhs.nextTrainID == rhs.nextTrainID
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
        guard inMap(p), case .track(let mask)? = tiles[p] else { return nil }
        return mask
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
        }
    }

    // MARK: - Stations (decision 18)

    func platforms(of id: StationID) -> [GridPosition] {
        guard let station = stations.first(where: { $0.id == id.rawValue }) else { return [] }
        return TrackDirection.allCases.map { step(station.position, $0) }.filter { mask(at: $0) != nil }
    }

    func stationsStoppedAt(by id: TrainID) -> [StationID] {
        guard let train = trains.first(where: { $0.id == id.rawValue }),
              case .atNode(let tile, _)? = train.position,
              train.cursor >= train.continuation.count
        else { return [] }
        return stations.filter { stepDirection(from: tile, to: $0.position) != nil }.map { StationID(rawValue: $0.id) }
    }

    // MARK: - Commands

    private static func isValidName(_ name: String) -> Bool {
        name.contains { !$0.isWhitespace }
    }

    private func requireEmpty(_ p: GridPosition) -> GameError? {
        guard inMap(p) else { return .outOfBounds(p) }
        return tiles[p] == nil ? nil : .tileOccupied(p)
    }

    private func funds(_ cost: Int64) -> GameError? {
        balance >= cost ? nil : .insufficientFunds(required: Money(cost), available: Money(balance))
    }

    mutating func buildTrack(at p: GridPosition, mask: UInt8) -> GameError? {
        guard mask != 0, mask & 0xF0 == 0 else { return .invalidTrackConnections }
        if let error = requireEmpty(p) ?? funds(costs.track) { return error }
        balance -= costs.track
        tiles[p] = .track(mask)
        return nil
    }

    mutating func removeTrack(at p: GridPosition) -> GameError? {
        guard inMap(p) else { return .outOfBounds(p) }
        guard mask(at: p) != nil else { return .noTrackToRemove(p) }
        let supports = trains.contains { train in
            switch train.position {
            case .atNode(let tile, _)?: tile == p
            case .onLink(let from, let to, _)?: from == p || to == p
            case nil: false
            }
        }
        guard !supports else { return .trackInUse(p) }
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

    mutating func purchaseTrain(named name: String) -> GameError? {
        guard Self.isValidName(name) else { return .invalidName }
        guard nextTrainID != Int.max else { return .idsExhausted }
        if let error = funds(costs.train) { return error }
        balance -= costs.train
        trains.append(Train(id: nextTrainID, name: name, position: nil))
        nextTrainID += 1
        return nil
    }

    private func index(_ id: TrainID) -> Result<Int, GameError> {
        guard let index = trains.firstIndex(where: { $0.id == id.rawValue }) else { return .failure(.unknownTrain(id)) }
        return .success(index)
    }

    private func placed(_ id: TrainID) -> Result<Int, GameError> {
        index(id).flatMap { trains[$0].position == nil ? .failure(.trainNotPlaced(id)) : .success($0) }
    }

    mutating func placeTrain(_ id: TrainID, at position: TrainPosition) -> GameError? {
        switch index(id) {
        case .failure(let error): return error
        case .success(let i):
            guard trains[i].position == nil else { return .trainAlreadyPlaced(id) }
            guard isOnTrack(position) else { return .invalidTrainPosition }
            trains[i].position = position
            return nil
        }
    }

    mutating func unplaceTrain(_ id: TrainID) -> GameError? {
        switch placed(id) {
        case .failure(let error): return error
        case .success(let i):
            trains[i] = Train(id: trains[i].id, name: trains[i].name, position: nil)
            return nil
        }
    }

    mutating func reverseTrain(_ id: TrainID) -> GameError? {
        switch placed(id) {
        case .failure(let error): return error
        case .success(let i):
            switch trains[i].position! {
            case .atNode(let tile, let heading):
                trains[i].position = .atNode(tile, heading: heading.opposite)
            case .onLink(let from, let to, let offset):
                trains[i].position = .onLink(from: to, to: from, offset: Self.linkLength - offset)
            }
            trains[i].continuation = []
            trains[i].cursor = 0
            return nil
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
        }
    }

    /// The entries from `start` on that can be entered one after another from
    /// `node` facing `heading`: each a joined neighbour, none straight back.
    func passable(_ nodes: ArraySlice<GridPosition>, from node: GridPosition, heading: TrackDirection) -> [(GridPosition, TrackDirection)] {
        var result: [(GridPosition, TrackDirection)] = []
        var (current, facing) = (node, heading)
        for next in nodes {
            guard let way = stepDirection(from: current, to: next), way != facing.opposite, joined(current, next) else { break }
            result.append((next, way))
            (current, facing) = (next, way)
        }
        return result
    }

    mutating func setContinuation(_ id: TrainID, _ nodes: [GridPosition]) -> GameError? {
        switch placed(id) {
        case .failure(let error): return error
        case .success(let i):
            let (node, heading) = Self.ahead(trains[i].position!)
            guard passable(nodes[...], from: node, heading: heading).count == nodes.count else { return .invalidContinuation }
            trains[i].continuation = nodes
            trains[i].cursor = 0
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

    /// Decision 3 and 15: checked first, then every minute is stepped.
    mutating func advance(ticks: Int) -> GameError? {
        let perTick: Int64 = switch speed {
        case .paused: 0
        case .normal: 1
        case .double: 2
        }
        let (steps, overflow) = Int64(ticks).multipliedReportingOverflow(by: perTick)
        guard !overflow, !minutes.addingReportingOverflow(steps).overflow else { return .clockOverflow }
        for _ in 0..<steps {
            for i in trains.indices where trains[i].position != nil && trains[i].rate > 0 {
                trains[i] = stepped(trains[i])
            }
            minutes += 1
        }
        return nil
    }

    /// One basic step for one train, in closed form: the train first needs
    /// the rest of its link, then each whole link is 1024 units; with `q`
    /// whole links and `r` units over, it has entered `q` links and, if
    /// `r > 0` and another link can be entered, is `r` into the next one.
    private func stepped(_ train: Train) -> Train {
        var train = train
        guard let position = train.position else { return train }
        let (node, heading) = Self.ahead(position)
        var distance = train.rate
        if case .onLink(let from, let to, let offset) = position {
            let toEnd = Self.linkLength - offset
            if distance < toEnd {
                train.position = .onLink(from: from, to: to, offset: offset + distance)
                return train
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
        return train
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
                return way == s.heading.opposite ? nil : State(node: n, heading: way)
            }
        }
        let trackTiles = tiles.compactMap { key, value -> GridPosition? in
            if case .track = value, inMap(key) { return key }
            return nil
        }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
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

    func route(from start: TrainPosition, toStation id: StationID) -> [GridPosition]? {
        route(from: start, toAny: Set(platforms(of: id)))
    }
}
