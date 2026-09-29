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
    /// All service lines, ordered by ascending ``LineID``.
    public private(set) var lines: [ServiceLine]
    /// Which service level each minute of the day has, for every line.
    public private(set) var serviceDay: ServiceDay
    public private(set) var clock: GameClock
    public private(set) var economy: GameEconomy

    /// The next ID to hand out to a station, a train or a line (see
    /// `allocateID(from:)`).
    private var nextStationID: Int
    private var nextTrainID: Int
    private var nextLineID: Int

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
        self.lines = []
        self.serviceDay = .standard
        self.clock = clock
        self.economy = economy
        self.nextStationID = 1
        self.nextTrainID = 1
        self.nextLineID = 1
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
    /// timetable (and its period); its movement becomes ``TrainMovement/idle`` (rate 0, no
    /// continuation), so placing it again never resumes an old journey.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/trainServiceActive(_:)`` while the train runs its
    ///   timetable (stop the service first).
    public mutating func unplaceTrain(_ id: TrainID) throws(GameError) {
        let (index, _) = try manuallyControlledTrain(id)

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
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/trainServiceActive(_:)`` while the train runs its
    ///   timetable (stop the service first).
    public mutating func reverseTrain(_ id: TrainID) throws(GameError) {
        let (index, position) = try manuallyControlledTrain(id)

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
    /// Allowed while the train runs its timetable: a service never sets the
    /// rate, so the rate is how fast a scheduled train goes, and 0 holds it
    /// (a service still gives it a continuation when a departure comes).
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
    ///   ``GameError/trainNotPlaced(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` while the train runs its
    ///   timetable (the service owns the continuation; stop it first), or
    ///   ``GameError/invalidContinuation``.
    public mutating func setTrainContinuation(_ id: TrainID, to nodes: [GridPosition]) throws(GameError) {
        let (index, position) = try manuallyControlledTrain(id)
        let (node, heading) = position.ahead
        guard TrainMovement.isPath(nodes, from: node, heading: heading, isJoined: { isConnected($0, to: $1) }) else {
            throw .invalidContinuation
        }

        trains[index].movement.continuation = nodes
        trains[index].movement.cursor = 0
    }

    // MARK: - Timetables

    /// Replaces a train's timetable with `stops`, in order (see
    /// ``ScheduledStop``), running once or, with a `period`, repeating every
    /// `period` minutes (see ``Train/timetablePeriod``). An empty list
    /// without a period clears it. Free, and the train may be placed or not.
    ///
    /// The whole list is checked before anything changes: its times never go
    /// back in time, starting from minute 0 (`0 <= arrival <= departure` at
    /// every stop, and each departure no later than the next stop's
    /// arrival), and every stop names a station of this world. A repeating
    /// timetable also needs a stop and a period of at least one minute, and
    /// its times must not go back when it starts again: the last departure
    /// no later than the first arrival one period later. Equal times,
    /// repeated stations, stations without platforms, turning round at any
    /// stop and times the clock has already passed are all allowed; whether
    /// the train could keep to the timetable (a route between the stations,
    /// the travel time, where the train is now, the last stop leading back
    /// to the first) is not checked.
    ///
    /// Only the timetable and its period change. Setting one never places,
    /// moves, routes or stops the train, and never starts a service: only a
    /// service started with ``startTrainService(_:)`` reads the timetable.
    /// While a service runs, its timetable cannot be replaced: an index into
    /// the old timetable has no meaning in a new one. Stop the service, set
    /// the timetable, and start the service again.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainServiceActive(_:)``,
    ///   ``GameError/invalidTimetable`` (for the times or the period), or
    ///   ``GameError/unknownStation(_:)`` naming the first stop, in
    ///   timetable order, whose station does not exist.
    public mutating func setTrainTimetable(
        _ id: TrainID,
        to stops: [ScheduledStop],
        repeatingEvery period: Int64? = nil
    ) throws(GameError) {
        let index = try trainIndex(of: id)
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }
        guard ScheduledStop.isTimetable(stops, period: period) else { throw .invalidTimetable }
        if let stop = stops.first(where: { station(id: $0.station) == nil }) {
            throw .unknownStation(stop.station)
        }

        trains[index].timetable = stops
        trains[index].timetablePeriod = period
    }

    // MARK: - Timetable services

    /// Starts running the train's timetable as a service, stop by stop in
    /// timetable order, from the first stop to the last: once, or cycle
    /// after cycle for a repeating timetable (see ``Train/timetablePeriod``).
    ///
    /// The train must be stopped at the first stop's station (see
    /// ``stationsStoppedAt(by:)``; a platform shared with other stations is
    /// fine). It then waits there as if it had just arrived
    /// (``TimetableExecution/waitingAtStop(_:cycle:)`` with index 0). A
    /// service always starts from the first stop, however late it is. A
    /// timetable that runs once starts in its only cycle, so if its times
    /// have all passed it leaves every stop as soon as it can. A repeating
    /// timetable starts in the first cycle whose first departure is not
    /// before now, so the train leaves on time; a cycle that has begun
    /// already is not joined halfway. Starting changes nothing else; nothing
    /// moves until time passes (see ``advance(ticks:)`` for how a service
    /// runs, turns trains round and starts a timetable again).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` if a service is already
    ///   running, ``GameError/noTimetable(_:)`` for an empty timetable,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/trainNotAtFirstStop(_:)``.
    public mutating func startTrainService(_ id: TrainID) throws(GameError) {
        let index = try trainIndex(of: id)
        let train = trains[index]
        guard train.execution == nil else { throw .trainServiceActive(id) }
        guard let first = train.timetable.first else { throw .noTimetable(id) }
        guard train.position != nil else { throw .trainNotPlaced(id) }
        guard isStopped(train, at: first.station) else { throw .trainNotAtFirstStop(id) }

        trains[index].execution = .waitingAtStop(0, cycle: train.startingCycle(at: clock.now))
    }

    /// Stops the train's service, wherever it has got to. Only the
    /// automation ends: the train keeps its timetable, position, rate and
    /// continuation, so a train on its way to a stop carries on to it and
    /// stops there, now under manual control. Stopping a service is not a
    /// brake; set the rate to 0 to hold the train.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)`` or
    ///   ``GameError/trainServiceNotActive(_:)``.
    public mutating func stopTrainService(_ id: TrainID) throws(GameError) {
        let index = try trainIndex(of: id)
        guard trains[index].execution != nil else { throw .trainServiceNotActive(id) }

        trains[index].execution = nil
    }

    // MARK: - Service lines

    /// The line with `id`, or `nil` if there is none.
    public func line(id: LineID) -> ServiceLine? {
        lines.first { $0.id == id }
    }

    /// Creates a service line calling at `stops`, in order, with the
    /// standard window (06:00 to midnight), the default rate (one link a
    /// minute) and no trains in service. Free.
    ///
    /// A line is plan data: it never moves, routes or schedules a train.
    /// Whether its stations are joined by track is not checked; what its
    /// journey would take is derived by ``lineJourney(_:)``.
    ///
    /// - Throws, checked in this order: ``GameError/invalidName``,
    ///   ``GameError/invalidLineStops`` (fewer than two, or a station twice
    ///   in a row), ``GameError/unknownStation(_:)`` naming the first stop
    ///   whose station does not exist, or ``GameError/idsExhausted``.
    @discardableResult
    public mutating func createLine(named name: String, stops: [StationID]) throws(GameError) -> ServiceLine {
        guard Self.isValidName(name) else { throw .invalidName }
        try requireLineStops(stops)
        let (id, nextID) = try Self.allocateID(from: nextLineID)

        let line = ServiceLine(id: LineID(rawValue: id), name: name, stops: stops)
        nextLineID = nextID
        lines.append(line)
        return line
    }

    /// Removes a line. Its ID is never handed out again.
    ///
    /// - Throws: ``GameError/unknownLine(_:)``.
    public mutating func removeLine(_ id: LineID) throws(GameError) {
        let index = try lineIndex(of: id)
        lines.remove(at: index)
    }

    /// Replaces a line's stops with `stops`, in order.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/invalidLineStops``, or ``GameError/unknownStation(_:)``
    ///   naming the first stop whose station does not exist.
    public mutating func setLineStops(_ id: LineID, to stops: [StationID]) throws(GameError) {
        let index = try lineIndex(of: id)
        try requireLineStops(stops)
        lines[index].stops = stops
    }

    /// Sets the rate, in logical units per game minute, that a line's
    /// journey times are worked out at (see ``lineJourney(_:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidLineRate`` for a rate below 1.
    public mutating func setLineRate(_ id: LineID, to rate: Int64) throws(GameError) {
        let index = try lineIndex(of: id)
        guard rate >= 1 else { throw .invalidLineRate }
        lines[index].rate = rate
    }

    /// Sets when a line runs during the day (see ``ServiceWindow``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidServiceWindow``.
    public mutating func setLineServiceWindow(_ id: LineID, to window: ServiceWindow) throws(GameError) {
        let index = try lineIndex(of: id)
        guard window.isValid else { throw .invalidServiceWindow }
        lines[index].window = window
    }

    /// Sets how many trains a line is to run at each service level. Any
    /// count of 0 or more is kept as it is; how many the line can run is
    /// derived (see ``lineTrainsInService(_:at:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidTrainsInService`` for a negative count.
    public mutating func setLineTrainsInService(_ id: LineID, to trains: TrainsInService) throws(GameError) {
        let index = try lineIndex(of: id)
        guard trains.isValid else { throw .invalidTrainsInService }
        lines[index].trainsInService = trains
    }

    /// Sets which service level each minute of the day has, for every line.
    ///
    /// - Throws: ``GameError/invalidServiceDay`` unless the bands start at
    ///   minute 0 and strictly increase within the day.
    public mutating func setServiceDay(_ day: ServiceDay) throws(GameError) {
        guard day.isValid else { throw .invalidServiceDay }
        serviceDay = day
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
    /// A tick runs one basic step at 1x, two at 2x and none while paused. A
    /// basic step from minute `T` to `T + 1` has four phases, each taking
    /// the trains in ascending ``TrainID`` order:
    ///
    /// 1. **Departures at `T`.** Every train whose service waits at a stop
    ///    with a scheduled departure of `T` or earlier leaves it (see below).
    ///    Departures are those of the service's cycle: the timetable's
    ///    times shifted by whole periods.
    /// 2. **Movement.** Every train travels up to its rate (see
    ///    ``TrainMovement``).
    /// 3. The clock moves on to `T + 1`.
    /// 4. **Arrivals at `T + 1`.** Every train whose service is travelling to
    ///    a stop and that is now stopped at that stop's station (see
    ///    ``stationsStoppedAt(by:)``) waits at that stop.
    ///
    /// Trains do not interact, so the order only fixes when each is updated.
    /// A train moves at most once per step: one that arrives in phase 4
    /// leaves in phase 1 of the next step at the earliest, even when its
    /// scheduled departure is the minute it arrived. Whenever the clock can
    /// hold the whole batch, `advance(ticks: n)` is the same as `n` calls of
    /// `advance(ticks: 1)`, and one tick at 2x the same as two at 1x apart
    /// from the speed itself. (Near the clock's limit a batch is rejected
    /// whole, while single ticks may still fit one at a time.)
    ///
    /// A train that cannot enter the next link of its continuation (the track
    /// was removed after the continuation was set) waits at its node, and
    /// every later step tries that same link again; once it is rebuilt the
    /// train carries on with that step's distance. Distance a train cannot
    /// use is dropped, so a train never catches up.
    ///
    /// **Services** (see ``startTrainService(_:)``). A service never leaves a
    /// stop before its scheduled departure, and adds no dwell of its own: a
    /// train that arrives early waits for its departure, and one that
    /// arrives at or after its departure leaves in the next step. Leaving
    /// stop `i`:
    ///
    /// - A stop marked ``ScheduledStop/reverses`` first turns the train
    ///   round where it stands, as ``reverseTrain(_:)`` would, and the rest
    ///   of the departure starts from there.
    /// - At the last stop of a timetable that runs once, or of the last
    ///   cycle whose times fit, the service is complete: it ends, and the
    ///   train stays where it is, keeping its timetable and rate.
    /// - Otherwise the service gives the train the continuation
    ///   ``route(from:toStation:)`` finds to the station of the next call,
    ///   and the train travels there. The next call is stop `i + 1`; after
    ///   the last stop of a repeating timetable it is stop 0 of the next
    ///   cycle. The service never turns the train except at a stop marked
    ///   to, and never sets the rate: a train with rate 0 gets its
    ///   continuation and stays where it is.
    /// - An empty route means the train is already stopped at the next
    ///   call's station (a repeated station, a platform both share, or a
    ///   repeating timetable that ends where it starts). It arrives there at
    ///   once, and leaves it too in the same phase if that departure has
    ///   also come. In one phase a service leaves at most as many stops as
    ///   its timetable has: every stop of a timetable that runs once, and at
    ///   most one whole cycle of a repeating one, which carries on in the
    ///   next step.
    /// - Without a route the train waits at its stop, not turned round, and
    ///   later steps try again, turning it first again: after a command
    ///   changes the map, a route may appear. Within one call the map cannot
    ///   change, so the route is looked up at most once per call.
    ///
    /// A travelling train follows its continuation like any other; if track
    /// ahead is removed it waits for that track, and no new route is looked
    /// up. The timetable's arrival times are not read: they are the plan the
    /// train is measured against, not a limit.
    ///
    /// When a whole step changes nothing (no train moves, and no service
    /// leaves, arrives or ends), no later step of this call can change
    /// anything before the next scheduled departure of a waiting service
    /// (the map and every train's inputs stay the same until the next
    /// command, and a departure that found no route finds none later in the
    /// call), so the clock moves on at once to that minute, or to the end of
    /// the batch. This is an exact shortcut, not an approximation.
    ///
    /// - Throws: ``GameError/clockOverflow`` if game time would pass the
    ///   largest minute the clock can hold. This is checked before any train
    ///   or the clock changes, so a rejected call changes nothing.
    /// - Precondition: `ticks >= 0`.
    public mutating func advance(ticks: Int) throws(GameError) {
        var remaining = try clock.basicSteps(forTicks: ticks)
        // Services whose departure found no route in this call. Nothing can
        // change the map or move a waiting train before the call ends, so
        // looking again would give the same answer.
        var unroutable: Set<TrainID> = []
        while remaining > 0 {
            let departed = departTrains(unroutable: &unroutable)
            let moved = moveTrainsOneStep()
            clock.advance(basicSteps: 1)
            let arrived = recordArrivals()
            remaining -= 1
            if !departed, !moved, !arrived {
                let idle = min(remaining, basicStepsUntilNextDeparture() ?? remaining)
                clock.advance(basicSteps: idle)
                remaining -= idle
            }
        }
    }

    /// Phase 1 of a basic step: every waiting service whose scheduled
    /// departure has come leaves its stop, in ascending ID order. Returns
    /// whether any service changed.
    private mutating func departTrains(unroutable: inout Set<TrainID>) -> Bool {
        var changed = false
        let now = clock.now
        for index in trains.indices {
            // Every pass leaves one stop. A timetable that runs once ends
            // within its stops; a repeating one could go round forever when
            // it is late and calls at one station only, so each train leaves
            // at most one whole cycle of stops per phase.
            var passes = 0
            while passes < trains[index].timetable.count,
                  case .waitingAtStop(let stop, let cycle)? = trains[index].execution,
                  trains[index].scheduledDeparture(of: stop, cycle: cycle) <= now,
                  !unroutable.contains(trains[index].id),
                  let position = trains[index].position {
                passes += 1
                let train = trains[index]
                // A waiting train stands at a node with no continuation
                // left, so turning it round needs nothing else.
                let start = train.timetable[stop].reverses ? position.reversed : position
                guard let next = train.call(after: stop, cycle: cycle) else {
                    // The last stop's departure: the service is complete.
                    trains[index].position = start
                    trains[index].execution = nil
                    changed = true
                    break
                }
                guard let route = route(from: start, toStation: train.timetable[next.stop].station) else {
                    // Nothing changes: the train is not turned round either.
                    unroutable.insert(train.id)
                    break
                }
                changed = true
                trains[index].position = start
                if route.isEmpty {
                    // Already stopped at the next call's station.
                    trains[index].execution = .waitingAtStop(next.stop, cycle: next.cycle)
                } else {
                    trains[index].movement.continuation = route
                    trains[index].movement.cursor = 0
                    trains[index].execution = .travellingToStop(next.stop, cycle: next.cycle)
                }
            }
        }
        return changed
    }

    /// Phase 4 of a basic step: every travelling service whose train is now
    /// stopped at the station of the stop it travels to waits at that stop.
    /// Returns whether any service arrived.
    private mutating func recordArrivals() -> Bool {
        var arrived = false
        for index in trains.indices {
            guard case .travellingToStop(let stop, let cycle)? = trains[index].execution,
                  isStopped(trains[index], at: trains[index].timetable[stop].station)
            else { continue }
            trains[index].execution = .waitingAtStop(stop, cycle: cycle)
            arrived = true
        }
        return arrived
    }

    /// The basic steps from now until the earliest scheduled departure (in
    /// its service's cycle), at or after now, of a waiting service, or `nil`
    /// if there is none.
    /// Departures already past are left out: after a step that changed
    /// nothing, each of those found no route. The clock may be before minute
    /// 0, so a gap too large for an `Int64` is given as `Int64.max`, which
    /// is more steps than any batch can have left.
    private func basicStepsUntilNextDeparture() -> Int64? {
        let now = clock.now.minutes
        return trains.compactMap { train -> Int64? in
            guard case .waitingAtStop(let stop, let cycle)? = train.execution else { return nil }
            let departure = train.scheduledDeparture(of: stop, cycle: cycle).minutes
            guard departure >= now else { return nil }
            let (gap, overflow) = departure.subtractingReportingOverflow(now)
            return overflow ? .max : gap
        }.min()
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

    private func lineIndex(of id: LineID) throws(GameError) -> Int {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        return index
    }

    private func requireLineStops(_ stops: [StationID]) throws(GameError) {
        guard ServiceLine.isStopList(stops) else { throw .invalidLineStops }
        if let missing = stops.first(where: { station(id: $0) == nil }) {
            throw .unknownStation(missing)
        }
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

    /// A placed train that no service is running: the commands that change
    /// its continuation or take it off the track need one.
    private func manuallyControlledTrain(_ id: TrainID) throws(GameError) -> (index: Int, position: TrainPosition) {
        let (index, position) = try placedTrain(id)
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }
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
        case map, stations, trains, lines, serviceDay, clock, economy, nextStationID, nextTrainID, nextLineID
    }

    /// Decodes a world, rejecting data that breaks cross-object invariants
    /// (station tiles and station records must agree; IDs must be unique and
    /// below the next ID to allocate; every placed train must be on this
    /// map's track, as ``placeTrain(_:at:)`` requires; every continuation
    /// node must lie inside the map; every timetable stop must name one of
    /// this world's stations, as
    /// ``setTrainTimetable(_:to:repeatingEvery:)`` requires; a waiting
    /// service's train must be stopped at its stop's station, and a
    /// travelling service's journey must end beside the station of the stop
    /// it travels to, as a route from the service would).
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
        lines = container.contains(.lines) ? try container.decode([ServiceLine].self, forKey: .lines) : []
        nextLineID = container.contains(.nextLineID) ? try container.decode(Int.self, forKey: .nextLineID) : 1
        serviceDay = container.contains(.serviceDay) ? try container.decode(ServiceDay.self, forKey: .serviceDay) : .standard

        if let problem = invariantViolation() {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: problem)
            )
        }
    }

    /// Encodes the world. A world without lines has no `"lines"` key, one
    /// that never had a line no `"nextLineID"`, and one with the standard
    /// service day no `"serviceDay"`: such worlds save exactly as before
    /// lines existed, and those saves read as having none, handing out line
    /// IDs from 1, with the standard day. An explicit `null` for any of them
    /// is rejected.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(map, forKey: .map)
        try container.encode(stations, forKey: .stations)
        try container.encode(trains, forKey: .trains)
        if !lines.isEmpty {
            try container.encode(lines, forKey: .lines)
        }
        if serviceDay != .standard {
            try container.encode(serviceDay, forKey: .serviceDay)
        }
        try container.encode(clock, forKey: .clock)
        try container.encode(economy, forKey: .economy)
        try container.encode(nextStationID, forKey: .nextStationID)
        try container.encode(nextTrainID, forKey: .nextTrainID)
        if nextLineID != 1 {
            try container.encode(nextLineID, forKey: .nextLineID)
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
        guard Self.isStrictlyIncreasing(lines.map(\.id.rawValue), below: nextLineID) else {
            return "Line IDs must be unique, ascending and below nextLineID."
        }
        for line in lines {
            guard Self.isValidName(line.name) else { return "Line \(line.id.rawValue) has an invalid name." }
            if let missing = line.stops.first(where: { station(id: $0) == nil }) {
                return "Line \(line.id.rawValue) calls at station \(missing.rawValue), which does not exist."
            }
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
            if let problem = serviceProblem(of: train) {
                return problem
            }
        }
        return nil
    }

    /// Why a train's service does not fit this world's stations, or `nil`.
    /// ``Train``'s decoder has already checked that the service fits the
    /// timetable, position and movement.
    ///
    /// A waiting train is stopped at its stop's station. A travelling train
    /// ends its journey (the last node of its continuation, or the end of
    /// its link once that is spent) next to the station of the stop it
    /// travels to, as every route from the service does; stations never
    /// move, so it arrives there even if track on the way was removed and
    /// rebuilt. Being next to the station is checked rather than being on a
    /// platform, because that last track tile may be removed and rebuilt
    /// before the train gets there.
    private func serviceProblem(of train: Train) -> String? {
        guard let execution = train.execution, let position = train.position,
              let station = station(id: train.timetable[execution.stop].station)
        else { return nil }
        switch execution {
        case .waitingAtStop:
            guard isStopped(train, at: station.id) else {
                return "Train \(train.id.rawValue)'s service waits at a station the train is not stopped at."
            }
        case .travellingToStop:
            let end = train.movement.continuation.last ?? position.ahead.node
            guard TrackDirection(from: end, to: station.position) != nil else {
                return "Train \(train.id.rawValue)'s service travels on a journey that does not end at its next stop."
            }
        }
        return nil
    }

    private static func isStrictlyIncreasing(_ ids: [Int], below limit: Int) -> Bool {
        zip(ids, ids.dropFirst()).allSatisfy { $0 < $1 } && (ids.last ?? 0) < limit && (ids.first ?? 1) >= 1
    }
}
