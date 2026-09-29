/// The authoritative game state and the only entry point for changing it.
///
/// `GameWorld` is a value type: every command validates its inputs before
/// touching any state, so a thrown ``GameError`` always leaves the world
/// exactly as it was. Copies are independent snapshots, which also gives
/// future undo/redo and background work a cheap starting point.
///
/// Presentation and rendering layers read from a world and send it commands;
/// they must not keep a separate copy of game state as the source of truth.
public struct GameWorld: Equatable, Sendable {
    public private(set) var map: GridMap
    /// All stations, ordered by ascending ``StationID``.
    public private(set) var stations: [Station]
    /// All trains, ordered by ascending ``TrainID``.
    public private(set) var trains: [Train]
    public private(set) var clock: GameClock
    public private(set) var economy: GameEconomy

    /// The next ID to hand out to a station or a train (see
    /// `allocateID(from:)`).
    private var nextStationID: Int
    private var nextTrainID: Int

    /// Creates an empty world.
    ///
    /// - Throws: ``GameError/invalidMapSize(width:height:)`` for unsupported
    ///   dimensions.
    public init(
        width: Int,
        height: Int,
        economy: GameEconomy,
        clock: GameClock = GameClock()
    ) throws(GameError) {
        self.map = try GridMap(width: width, height: height)
        self.stations = []
        self.trains = []
        self.clock = clock
        self.economy = economy
        self.nextStationID = 1
        self.nextTrainID = 1
    }

    // MARK: - Queries

    /// The track at `position`, or `nil` if the tile holds no track.
    public func track(at position: GridPosition) -> Track? {
        guard case .track(let connections)? = map.tile(at: position)?.type else { return nil }
        return Track(position: position, connections: connections)
    }

    /// Every track piece in row-major order.
    public var tracks: [Track] {
        map.tiles.compactMap { tile in
            guard case .track(let connections) = tile.type else { return nil }
            return Track(position: tile.position, connections: connections)
        }
    }

    public func station(id: StationID) -> Station? {
        stations.first { $0.id == id }
    }

    public func station(at position: GridPosition) -> Station? {
        guard case .station(let id)? = map.tile(at: position)?.type else { return nil }
        return station(id: id)
    }

    // MARK: - Construction

    /// Lays a track piece on an empty tile and charges ``ConstructionCosts/track``.
    ///
    /// The piece does not have to meet any neighbouring track: isolated
    /// pieces and exits toward empty tiles, stations, mismatched track or the
    /// map edge are all allowed, and neighbouring tiles are never changed.
    /// Whether tiles are joined is derived by ``connectedNeighbors(of:)``.
    ///
    /// - Throws: ``GameError/invalidTrackConnections`` if `connections` is
    ///   empty or has bits other than the four directions,
    ///   ``GameError/outOfBounds(_:)``, ``GameError/tileOccupied(_:)``, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func buildTrack(
        at position: GridPosition,
        connections: TrackConnections
    ) throws(GameError) -> Track {
        guard !connections.isEmpty, connections.hasOnlyKnownDirections else { throw .invalidTrackConnections }
        try requireEmptyTile(at: position)
        try economy.spend(economy.costs.track)

        map.setType(.track(connections: connections), at: position)
        return Track(position: position, connections: connections)
    }

    /// Removes the track piece at `position`. Removal is free and not refunded.
    ///
    /// Track that a placed train rests on (its node, or either end of its
    /// link) cannot be removed while the train is there; unplace the train
    /// first. Any other track can be removed, including track next to a train.
    /// Checking scans every train once (O(trains)); no occupancy index is kept.
    ///
    /// - Throws: ``GameError/outOfBounds(_:)``,
    ///   ``GameError/noTrackToRemove(_:)`` if the tile is empty or a station,
    ///   or ``GameError/trackInUse(_:)``.
    public mutating func removeTrack(at position: GridPosition) throws(GameError) {
        guard map.contains(position) else { throw .outOfBounds(position) }
        guard track(at: position) != nil else { throw .noTrackToRemove(position) }
        guard !trains.contains(where: { $0.position?.isSupported(by: position) == true }) else {
            throw .trackInUse(position)
        }

        map.setType(.empty, at: position)
    }

    /// Builds a station on an empty tile and charges ``ConstructionCosts/station``.
    ///
    /// - Throws: ``GameError/invalidName``, ``GameError/outOfBounds(_:)``,
    ///   ``GameError/tileOccupied(_:)``, ``GameError/idsExhausted``, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func buildStation(named name: String, at position: GridPosition) throws(GameError) -> Station {
        guard Self.isValidName(name) else { throw .invalidName }
        try requireEmptyTile(at: position)
        let (id, nextID) = try Self.allocateID(from: nextStationID)
        try economy.spend(economy.costs.station)

        let station = Station(id: StationID(rawValue: id), name: name, position: position)
        nextStationID = nextID
        stations.append(station)
        map.setType(.station(id: station.id), at: position)
        return station
    }

    /// Buys a new train and charges ``ConstructionCosts/train``.
    ///
    /// The new train is unplaced (its ``Train/position`` is `nil`); put it on
    /// the track with ``placeTrain(_:at:)``.
    ///
    /// - Throws: ``GameError/invalidName``, ``GameError/idsExhausted``, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func purchaseTrain(named name: String) throws(GameError) -> Train {
        guard Self.isValidName(name) else { throw .invalidName }
        let (id, nextID) = try Self.allocateID(from: nextTrainID)
        try economy.spend(economy.costs.train)

        let train = Train(id: TrainID(rawValue: id), name: name)
        nextTrainID = nextID
        trains.append(train)
        return train
    }

    // MARK: - Trains

    /// The train with `id`, or `nil` if there is none.
    public func train(id: TrainID) -> Train? {
        trains.first { $0.id == id }
    }

    /// Puts an unplaced train on the track at `position`. Placement is free.
    ///
    /// `position` must be on this map's track:
    /// ``TrainPosition/atNode(_:heading:)`` on a track tile, with any heading
    /// (whether or not the track continues that way), or
    /// ``TrainPosition/onLink(from:to:offset:)`` between two joined track
    /// tiles with `0 < offset < TrainPosition.linkLength`. A train at either
    /// end of a link must be placed at that node instead. Other trains at the
    /// same place do not matter. The train starts idle: rate 0 and no
    /// continuation.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainAlreadyPlaced(_:)`` (placement never moves a
    ///   train), or ``GameError/invalidTrainPosition``.
    public mutating func placeTrain(_ id: TrainID, at position: TrainPosition) throws(GameError) {
        let index = try trainIndex(of: id)
        guard trains[index].position == nil else { throw .trainAlreadyPlaced(id) }
        guard isOnTrack(position) else { throw .invalidTrainPosition }

        trains[index].position = position
    }

    /// Takes a placed train off the track. The train keeps its ID, name and
    /// timetable; its movement becomes ``TrainMovement/idle`` (rate 0, no
    /// continuation), so placing it again never resumes an old journey.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)`` or
    ///   ``GameError/trainNotPlaced(_:)``.
    public mutating func unplaceTrain(_ id: TrainID) throws(GameError) {
        let (index, _) = try placedTrain(id)

        trains[index].position = nil
        trains[index].movement = .idle
    }

    /// Turns a placed train around where it stands, without moving it.
    ///
    /// At a node the heading becomes its opposite. On a link the ends swap
    /// and the offset becomes `TrainPosition.linkLength - offset`, measured
    /// from the new `from`, which is the same point. Reversing twice restores
    /// the original position exactly.
    ///
    /// The continuation is cleared, because it was a path for the other
    /// direction; the rate is kept. A reversed train on a link therefore runs
    /// to the end of that link (now its `to`) and stops there until it is
    /// given a new continuation.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)`` or
    ///   ``GameError/trainNotPlaced(_:)``.
    public mutating func reverseTrain(_ id: TrainID) throws(GameError) {
        let (index, position) = try placedTrain(id)

        trains[index].position = position.reversed
        trains[index].movement.continuation = []
        trains[index].movement.cursor = 0
    }

    // MARK: - Train movement

    /// Sets how many logical units a placed train may travel in each basic
    /// step (one game minute). 0 holds the train where it is and keeps its
    /// continuation, so setting a rate again resumes the same journey. Any
    /// non-negative `Int64` is accepted: travel adds distance to an offset
    /// only after checking that it is shorter than the rest of the link, so
    /// no rate can overflow.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/invalidMovementRate`` for a negative rate.
    public mutating func setTrainMovementRate(_ id: TrainID, to rate: Int64) throws(GameError) {
        let (index, _) = try placedTrain(id)
        guard rate >= 0 else { throw .invalidMovementRate }

        trains[index].movement.rate = rate
    }

    /// Replaces a placed train's continuation with `nodes`, the nodes to
    /// enter in order after the node the train is at, or after the end of
    /// the link it is on (that node is not listed). An empty list clears the
    /// continuation.
    ///
    /// The whole list is checked against the current map before anything
    /// changes: starting from that node, each entry must be joined to the one
    /// before it (see ``isConnected(_:to:)``) and must not lead straight
    /// back, including back past the train's heading. Loops and revisits are
    /// allowed; stations, empty or off-map tiles, and gaps are not. The train
    /// never picks a way itself, and clearing the continuation does not move
    /// it: a train on a link still runs to the end of that link at its rate
    /// (set the rate to 0 to hold it where it is).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/invalidContinuation``.
    public mutating func setTrainContinuation(_ id: TrainID, to nodes: [GridPosition]) throws(GameError) {
        let (index, position) = try placedTrain(id)
        let (node, heading) = position.ahead
        guard TrainMovement.isPath(nodes, from: node, heading: heading, isJoined: { isConnected($0, to: $1) }) else {
            throw .invalidContinuation
        }

        trains[index].movement.continuation = nodes
        trains[index].movement.cursor = 0
    }

    // MARK: - Timetables

    /// Replaces a train's timetable with `stops`, in order (see
    /// ``ScheduledStop``). An empty list clears it. Free, and the train may
    /// be placed or not.
    ///
    /// The whole list is checked before anything changes: its times never go
    /// back in time, starting from minute 0 (`0 <= arrival <= departure` at
    /// every stop, and each departure no later than the next stop's
    /// arrival), and every stop names a station of this world. Equal times,
    /// repeated stations, stations without platforms and times the clock has
    /// already passed are all allowed; whether the train could keep to the
    /// timetable (a route between the stations, the travel time, where the
    /// train is now) is not checked.
    ///
    /// Only the timetable changes. Setting one never places, moves, routes
    /// or stops the train: nothing in the simulation reads a timetable yet.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/invalidTimetable``, or ``GameError/unknownStation(_:)``
    ///   naming the first stop, in timetable order, whose station does not
    ///   exist.
    public mutating func setTrainTimetable(_ id: TrainID, to stops: [ScheduledStop]) throws(GameError) {
        let index = try trainIndex(of: id)
        guard ScheduledStop.isTimetable(stops) else { throw .invalidTimetable }
        if let stop = stops.first(where: { station(id: $0.station) == nil }) {
            throw .unknownStation(stop.station)
        }

        trains[index].timetable = stops
    }

    // MARK: - Time

    public mutating func pause() {
        clock.pause()
    }

    public mutating func resume() {
        clock.resume()
    }

    public mutating func setSpeed(_ speed: GameSpeed) {
        clock.setSpeed(speed)
    }

    /// Advances the simulation by `ticks` ticks at the current speed.
    ///
    /// A tick runs one basic step at 1x, two at 2x and none while paused. In
    /// each basic step every train, in ascending ``TrainID`` order, travels up
    /// to its rate (see ``TrainMovement``), and then the clock moves on one
    /// game minute. Trains do not interact, so the order only fixes when
    /// each is updated. Whenever the clock can hold the whole batch,
    /// `advance(ticks: n)` is the same as `n` calls of `advance(ticks: 1)`,
    /// and one tick at 2x the same as two at 1x apart from the speed itself.
    /// (Near the clock's limit a batch is rejected whole, while single ticks
    /// may still fit one at a time.)
    ///
    /// A train that cannot enter the next link of its continuation (the track
    /// was removed after the continuation was set) waits at its node, and
    /// every later step tries that same link again; once it is rebuilt the
    /// train carries on with that step's distance. Distance a train cannot
    /// use is dropped, so a train never catches up.
    ///
    /// Timetables play no part: a train at a scheduled stop does not wait
    /// or leave because of it, and time passing never changes a timetable.
    ///
    /// When a whole step changes no train, no later step of this call can
    /// either (the map and every train's inputs stay the same until the next
    /// command), so the clock moves the remaining minutes at once. This is an
    /// exact shortcut, not an approximation.
    ///
    /// - Throws: ``GameError/clockOverflow`` if game time would pass the
    ///   largest minute the clock can hold. This is checked before any train
    ///   or the clock changes, so a rejected call changes nothing.
    /// - Precondition: `ticks >= 0`.
    public mutating func advance(ticks: Int) throws(GameError) {
        var remaining = try clock.basicSteps(forTicks: ticks)
        while remaining > 0 {
            let moved = moveTrainsOneStep()
            clock.advance(basicSteps: 1)
            remaining -= 1
            if !moved {
                clock.advance(basicSteps: remaining)
                remaining = 0
            }
        }
    }

    /// One basic step of travel for every placed train with a rate, in
    /// ascending ID order. Returns whether any train changed.
    private mutating func moveTrainsOneStep() -> Bool {
        var moved = false
        for index in trains.indices {
            let movement = trains[index].movement
            guard let position = trains[index].position, movement.rate > 0 else { continue }
            let travel = TrainMovement.travel(
                from: position,
                distance: movement.rate,
                continuation: movement.continuation,
                cursor: movement.cursor,
                isJoined: { isConnected($0, to: $1) }
            )
            guard travel.position != position || travel.cursor != movement.cursor else { continue }

            trains[index].position = travel.position
            if travel.cursor == movement.continuation.count {
                // Every entry has been entered: the continuation is spent.
                trains[index].movement.continuation = []
                trains[index].movement.cursor = 0
            } else {
                trains[index].movement.cursor = travel.cursor
            }
            moved = true
        }
        return moved
    }

    // MARK: - Validation

    private func requireEmptyTile(at position: GridPosition) throws(GameError) {
        guard let tile = map.tile(at: position) else { throw .outOfBounds(position) }
        guard tile.type == .empty else { throw .tileOccupied(position) }
    }

    private static func isValidName(_ name: String) -> Bool {
        name.contains { !$0.isWhitespace }
    }

    private func trainIndex(of id: TrainID) throws(GameError) -> Int {
        guard let index = trains.firstIndex(where: { $0.id == id }) else { throw .unknownTrain(id) }
        return index
    }

    private func placedTrain(_ id: TrainID) throws(GameError) -> (index: Int, position: TrainPosition) {
        let index = try trainIndex(of: id)
        guard let position = trains[index].position else { throw .trainNotPlaced(id) }
        return (index, position)
    }

    /// Whether `position` is well formed and lies on this map's track: a node
    /// on a track tile, or a link between two joined track tiles.
    func isOnTrack(_ position: TrainPosition) -> Bool {
        guard position.isWellFormed else { return false }
        switch position {
        case .atNode(let tile, _):
            return track(at: tile) != nil
        case .onLink(let from, let to, _):
            return isConnected(from, to: to)
        }
    }
}

// MARK: - ID allocation

extension GameWorld {
    /// The ID a counter hands out, and the counter's value afterwards.
    ///
    /// A counter holds the next ID to hand out, and every ID is below it, so
    /// handing out `next` needs `next + 1` to fit in an `Int`: the last ID is
    /// `Int.max - 1`, leaving the counter at `Int.max`, where it stays. Only
    /// reads the counter, so a command can check before changing anything.
    ///
    /// - Throws: ``GameError/idsExhausted`` once the counter is at `Int.max`.
    private static func allocateID(from next: Int) throws(GameError) -> (id: Int, next: Int) {
        let (following, overflow) = next.addingReportingOverflow(1)
        guard !overflow else { throw .idsExhausted }
        return (next, following)
    }
}

// MARK: - Codable

extension GameWorld: Codable {
    private enum CodingKeys: String, CodingKey {
        case map, stations, trains, clock, economy, nextStationID, nextTrainID
    }

    /// Decodes a world, rejecting data that breaks cross-object invariants
    /// (station tiles and station records must agree; IDs must be unique and
    /// below the next ID to allocate; every placed train must be on this
    /// map's track, as ``placeTrain(_:at:)`` requires; every continuation
    /// node must lie inside the map; every timetable stop must name one of
    /// this world's stations, as ``setTrainTimetable(_:to:)`` requires).
    ///
    /// A continuation's links are not required to exist: track ahead of a
    /// train may have been removed after the continuation was set, and a
    /// world where a train waits for that track to be rebuilt is valid.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        map = try container.decode(GridMap.self, forKey: .map)
        stations = try container.decode([Station].self, forKey: .stations)
        trains = try container.decode([Train].self, forKey: .trains)
        clock = try container.decode(GameClock.self, forKey: .clock)
        economy = try container.decode(GameEconomy.self, forKey: .economy)
        nextStationID = try container.decode(Int.self, forKey: .nextStationID)
        nextTrainID = try container.decode(Int.self, forKey: .nextTrainID)

        if let problem = invariantViolation() {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: problem)
            )
        }
    }

    private func invariantViolation() -> String? {
        let stationIDs = stations.map(\.id.rawValue)
        guard Self.isStrictlyIncreasing(stationIDs, below: nextStationID) else {
            return "Station IDs must be unique, ascending and below nextStationID."
        }
        guard Self.isStrictlyIncreasing(trains.map(\.id.rawValue), below: nextTrainID) else {
            return "Train IDs must be unique, ascending and below nextTrainID."
        }
        for station in stations {
            guard Self.isValidName(station.name) else { return "Station \(station.id.rawValue) has an invalid name." }
            guard map.tile(at: station.position)?.type == .station(id: station.id) else {
                return "Station \(station.id.rawValue) does not match the map tile at \(station.position)."
            }
        }
        let stationTileCount = map.tiles.count { tile in
            if case .station = tile.type { return true }
            return false
        }
        guard stationTileCount == stations.count else {
            return "The map has station tiles without matching station records."
        }
        guard trains.allSatisfy({ Self.isValidName($0.name) }) else {
            return "A train has an invalid name."
        }
        for train in trains {
            if let position = train.position, !isOnTrack(position) {
                return "Train \(train.id.rawValue) is not on this map's track."
            }
            // The map's size never changes, so a node that was on the map
            // when the continuation was set still is.
            guard train.movement.continuation.allSatisfy(map.contains) else {
                return "Train \(train.id.rawValue)'s continuation leaves the map."
            }
            if let stop = train.timetable.first(where: { station(id: $0.station) == nil }) {
                return "Train \(train.id.rawValue)'s timetable names station \(stop.station.rawValue), which does not exist."
            }
        }
        return nil
    }

    private static func isStrictlyIncreasing(_ ids: [Int], below limit: Int) -> Bool {
        zip(ids, ids.dropFirst()).allSatisfy { $0 < $1 } && (ids.last ?? 0) < limit && (ids.first ?? 1) >= 1
    }
}
