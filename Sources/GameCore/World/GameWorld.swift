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
    /// The land: empty ground and the tiles stations stand on. It holds no
    /// railway (Stage S3A): see ``network``.
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
    /// The railway (Phase 4.5 Stage S3): the one record of all track, the
    /// grid's track pieces and the continuous network's nodes and edges.
    /// Empty in a new world.
    public private(set) var network: RailwayNetwork

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
        self.network = RailwayNetwork()
        self.nextStationID = 1
        self.nextTrainID = 1
        self.nextLineID = 1
    }

    // MARK: - Queries

    /// The grid track at `position`, or `nil` if the tile holds no track
    /// (plain track, a turnout or a crossing). Read from the ``network``.
    public func track(at position: GridPosition) -> Track? {
        network.track(at: position)
    }

    /// Every grid track piece in row-major order.
    public var tracks: [Track] {
        network.tracks
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

        let track = Track(position: position, connections: connections)
        network.lay(track)
        return track
    }

    /// Lays a turnout on an empty tile and charges ``ConstructionCosts/track``
    /// (Phase 4.5 Stage S1). The `stem` joins every other exit; the others
    /// join only the stem, so a train cannot pass from one branch to
    /// another. Like any track piece it need not meet its neighbours.
    ///
    /// - Throws: ``GameError/invalidTrackConnections`` unless `connections`
    ///   has three exits or more, only the four directions, and the `stem`
    ///   among them; then ``GameError/outOfBounds(_:)``,
    ///   ``GameError/tileOccupied(_:)``, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func buildTurnout(
        at position: GridPosition,
        connections: TrackConnections,
        stem: TrackDirection
    ) throws(GameError) -> Track {
        guard Self.isTurnout(connections, stem: stem) else { throw .invalidTrackConnections }
        try requireEmptyTile(at: position)
        try economy.spend(economy.costs.track)

        let track = Track(position: position, connections: connections, layout: .turnout(stem: stem))
        network.lay(track)
        return track
    }

    /// Whether `connections` and `stem` make a turnout: three exits or more,
    /// only the four directions, the stem among them.
    static func isTurnout(_ connections: TrackConnections, stem: TrackDirection) -> Bool {
        connections.hasOnlyKnownDirections && connections.directions.count >= 3 && connections.contains(TrackConnections(stem))
    }

    /// Lays a level crossing on an empty tile and charges
    /// ``ConstructionCosts/track`` (Phase 4.5 Stage S1): exits in all four
    /// directions, each joining only the one opposite, so two straight
    /// tracks cross without trains changing from one to the other.
    ///
    /// - Throws: ``GameError/outOfBounds(_:)``,
    ///   ``GameError/tileOccupied(_:)``, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func buildCrossing(at position: GridPosition) throws(GameError) -> Track {
        try requireEmptyTile(at: position)
        try economy.spend(economy.costs.track)

        let track = Track(position: position, connections: [.north, .east, .south, .west], layout: .crossing)
        network.lay(track)
        return track
    }

    /// Removes the track piece at `position`. Removal is free and not refunded.
    ///
    /// Track that a placed train rests on (its node, either end of its
    /// link, or a node its body lies over) cannot be removed while the train
    /// is there; unplace the train first. Any other track can be removed, including track next to a train.
    /// Checking scans every train once (O(trains)); no occupancy index is kept.
    ///
    /// - Throws: ``GameError/outOfBounds(_:)``,
    ///   ``GameError/noTrackToRemove(_:)`` if the tile is empty or a station,
    ///   or ``GameError/trackInUse(_:)``. Turnouts and crossings are track
    ///   and are removed the same way.
    public mutating func removeTrack(at position: GridPosition) throws(GameError) {
        guard map.contains(position) else { throw .outOfBounds(position) }
        guard track(at: position) != nil else { throw .noTrackToRemove(position) }
        guard !trains.contains(where: { $0.position?.isSupported(by: position) == true || $0.trail.contains(position) }) else {
            throw .trackInUse(position)
        }

        network.removeTrack(at: position)
    }

    // MARK: - Track network

    /// Builds a node of the track network at `position` (Phase 4.5 Stage S3):
    /// a point where edges can end and meet. Free: track is paid for by its
    /// edges. Returns the new node's ID, ``TrackNodeID/node(_:)``, numbered
    /// in order from 1 and never reused.
    ///
    /// The node must lie on the map (`0 <= x < width × 1024` and
    /// `0 <= y < height × 1024`; see ``WorldCoordinate``), at a height in
    /// ``RailwayNetwork/heightRange`` (Stage S4; 0 is the ground), where no
    /// node stands yet. The network does not interact with the grid: a
    /// node can stand over any tile.
    ///
    /// - Throws, checked in this order: ``GameError/invalidTrackGeometry``
    ///   or ``GameError/idsExhausted``.
    @discardableResult
    public mutating func buildTrackNode(at position: WorldCoordinate) throws(GameError) -> TrackNodeID {
        guard isOnMap(position), !network.hasNode(at: position) else { throw .invalidTrackGeometry }
        let (_, next) = try Self.allocateID(from: network.nextNodeNumber)

        return network.addNode(at: position, next: next)
    }

    /// Builds an edge of the track network from node `from` to node `to`,
    /// shaped in plan by `curve` (Phase 4.5 Stage S3) and in height by
    /// `profile`, carried by `structure` (Stage S4), and charges
    /// ``ConstructionCosts/track`` times the structure's
    /// ``TrackStructure/costFactor`` for every tile of its length (1024
    /// units), rounded up. Returns the new edge's ID,
    /// ``TrackEdgeID/edge(_:)``, numbered in order from 1 and never reused.
    ///
    /// The edge's length, centre line and heights are worked out from its
    /// end nodes, curve and profile (see ``TrackGeometry``); its control
    /// points must lie on the map. Which edges it joins at each end follows
    /// from the way it leaves the node (see ``TrackNodeEnd``): an edge that
    /// meets others at an angle joins none of them there. Edges that cross
    /// in plan without a shared node never join, and must pass one over the
    /// other (see ``TrackClearance``). Several edges may join the same two
    /// nodes.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackNode(_:)``
    ///   for `from`, then for `to`; ``GameError/invalidTrackGeometry`` (the
    ///   same node twice, a control point off the map, or a curve or profile
    ///   that does not make an edge); ``GameError/trackTooSteep``;
    ///   ``GameError/invalidTrackStructure``;
    ///   ``GameError/trackConflict(_:)`` for the lowest numbered edge it
    ///   would meet without clearance; ``GameError/idsExhausted``; or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func buildTrackEdge(
        from: TrackNodeID, to: TrackNodeID, curve: TrackCurve = .straight, profile: TrackProfile = .uniform, structure: TrackStructure = .surface
    ) throws(GameError) -> TrackEdgeID {
        guard let start = network.node(from) else { throw .unknownTrackNode(from) }
        guard let end = network.node(to) else { throw .unknownTrackNode(to) }
        guard from != to, curve.controlPoints.allSatisfy(isOnMap),
              let geometry = TrackGeometry(from: start.position, to: end.position, curve: curve, profile: profile)
        else { throw .invalidTrackGeometry }
        guard geometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumGrade) else { throw .trackTooSteep }
        guard structure.allows(height: start.position.z), structure.allows(height: end.position.z) else { throw .invalidTrackStructure }
        if let other = network.firstConflict(from: from, to: to, curve: curve, geometry: geometry) {
            throw .trackConflict(other)
        }
        let (_, next) = try Self.allocateID(from: network.nextEdgeNumber)
        try economy.spend(try edgeCost(length: geometry.length, structure: structure))

        return network.addEdge(from: from, to: to, curve: curve, profile: profile, structure: structure, geometry: geometry, next: next)
    }

    /// Removes edge `id` of the track network (Stage S3). Removal is free and
    /// not refunded. Its nodes stay; the edges it joined there no longer join
    /// it. A train whose continuation names it stops at the node before it
    /// and waits there: IDs are never reused, so give that train a new
    /// continuation.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackEdge(_:)``;
    ///   ``GameError/trackEdgeInUse(_:)`` while a placed train's head or
    ///   body is on it (unplace the train first); or
    ///   ``GameError/trackEdgeHasPlatform(_:)`` while a station has a
    ///   platform on it (Stage S4).
    public mutating func removeTrackEdge(_ id: TrackEdgeID) throws(GameError) {
        guard network.edge(id) != nil else { throw .unknownTrackEdge(id) }
        guard !trains.contains(where: { train in
            if case .onEdge(let traversal, _)? = train.position, traversal.edge == id { return true }
            return train.trailEdges.contains(id)
        }) else { throw .trackEdgeInUse(id) }
        guard network.platforms(on: id).isEmpty else { throw .trackEdgeHasPlatform(id) }

        network.removeEdge(id)
    }

    /// Removes node `id` of the track network (Stage S3). Free. No edge may
    /// end at it, so no train can be there.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackNode(_:)`` or
    ///   ``GameError/trackNodeInUse(_:)`` while edges end at it.
    public mutating func removeTrackNode(_ id: TrackNodeID) throws(GameError) {
        guard let node = network.node(id) else { throw .unknownTrackNode(id) }
        guard node.ends.isEmpty else { throw .trackNodeInUse(id) }

        network.removeNode(id)
    }

    /// Adds a platform to the railway network for station `id`, along edge
    /// `edge` from `start` to `end` measured from the edge's `from` node
    /// (Phase 4.5 Stage S4). Free: the station has been paid for. A station
    /// may have any number of platforms, straight or curved, at different
    /// levels (surface, elevated, underground); each platform's level is its
    /// edge's height and structure there. Its ends cut the edge's resource
    /// spans (see ``trackSpans(of:)``).
    ///
    /// The stretch must lie within the edge (`0 <= start < end <= length`),
    /// be level (the edge's height at `start` and at `end` is the same, and
    /// heights never turn back along an edge), and not overlap another
    /// platform on the edge, of this station or another.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``;
    ///   ``GameError/unknownTrackEdge(_:)`` (a grid link has its own
    ///   platforms); or ``GameError/invalidPlatform``.
    public mutating func addTrackPlatform(_ id: StationID, on edge: TrackEdgeID, from start: Int64, to end: Int64) throws(GameError) {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard network.edge(edge) != nil else { throw .unknownTrackEdge(edge) }
        let platform = TrackPlatform(station: id, edge: edge, start: start, end: end)
        guard isValidPlatform(platform), !network.platforms.contains(where: { $0.overlaps(platform) }) else {
            throw .invalidPlatform
        }

        network.addPlatform(platform)
    }

    /// Removes station `id`'s platform on edge `edge` that starts at `start`
    /// (Stage S4). Free.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)`` or
    ///   ``GameError/invalidPlatform`` when the station has no such platform.
    public mutating func removeTrackPlatform(_ id: StationID, on edge: TrackEdgeID, from start: Int64) throws(GameError) {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard let index = network.platforms.firstIndex(where: { $0.station == id && $0.edge == edge && $0.start == start }) else {
            throw .invalidPlatform
        }

        network.removePlatform(at: index)
    }

    /// The platforms of station `id` on the track network, in order along
    /// the track (Stage S4); empty for none or an unknown station. Its grid
    /// platforms are ``platforms(of:)``.
    public func trackPlatforms(of id: StationID) -> [TrackPlatform] {
        network.platforms(of: id)
    }

    /// Whether `platform` fits its edge: the edge exists, the stretch lies
    /// within it and is level.
    private func isValidPlatform(_ platform: TrackPlatform) -> Bool {
        guard let geometry = network.geometry(of: platform.edge) else { return false }
        return 0 <= platform.start && platform.start < platform.end && platform.end <= geometry.length
            && geometry.height(at: platform.start) == geometry.height(at: platform.end)
    }

    /// Whether a node at `position` would lie on the map, at a height in
    /// ``RailwayNetwork/heightRange``.
    private func isOnMap(_ position: WorldCoordinate) -> Bool {
        RailwayNetwork.heightRange.contains(position.z) && isOnMap(position.plan)
    }

    /// Whether `point` lies over the map: `0 <= x < width × 1024` and
    /// `0 <= y < height × 1024`.
    private func isOnMap(_ point: PlanPoint) -> Bool {
        point.x >= 0 && point.y >= 0 && point.x < Int64(map.width) * WorldCoordinate.tileSize && point.y < Int64(map.height) * WorldCoordinate.tileSize
    }

    /// What an edge `length` long on `structure` costs:
    /// ``ConstructionCosts/track`` times the structure's
    /// ``TrackStructure/costFactor`` for every tile of its length, rounded
    /// up, and at least one.
    ///
    /// - Throws: ``GameError/insufficientFunds(required:available:)`` when
    ///   the price does not even fit in a ``Money``, so no balance could pay
    ///   it; `required` is then the largest amount there is.
    private func edgeCost(length: Int64, structure: TrackStructure) throws(GameError) -> Money {
        let tiles = max(1, (length + WorldCoordinate.tileSize - 1) / WorldCoordinate.tileSize)
        let (units, overflowFactor) = tiles.multipliedReportingOverflow(by: structure.costFactor)
        let (price, overflow) = economy.costs.track.amount.multipliedReportingOverflow(by: units)
        guard !overflowFactor, !overflow else { throw .insufficientFunds(required: Money(.max), available: economy.balance) }
        return Money(price)
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

    /// Grows station `id` onto the empty tile at `position`, beside one of
    /// its tiles, and charges ``ConstructionCosts/station`` (Phase 4.5
    /// Stage S2). Track beside the new tile becomes the station's platforms
    /// too (see ``platforms(of:)``), so a larger station has more and longer
    /// platforms.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``,
    ///   ``GameError/outOfBounds(_:)``, ``GameError/tileOccupied(_:)``,
    ///   ``GameError/invalidStationTile(_:)`` if the tile is not beside one
    ///   of the station's tiles, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    public mutating func extendStation(_ id: StationID, to position: GridPosition) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        try requireEmptyTile(at: position)
        guard stations[index].tiles.contains(where: { TrackDirection(from: $0, to: position) != nil }) else {
            throw .invalidStationTile(position)
        }
        try economy.spend(economy.costs.station)

        stations[index].annexes.append(position)
        map.setType(.station(id: id), at: position)
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
    /// On the track network (Stage S3) `position` is
    /// ``TrainPosition/onEdge(_:offset:)`` on an edge, `0 <= offset <=` its
    /// length; a train with a body stands at an offset above 0 (at a node,
    /// at the end of the edge it arrived along; see ``TrainPosition``). Its
    /// body is laid back from the start of its edge the way a train could
    /// have come, the lowest numbered edge first where the track branches.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainAlreadyPlaced(_:)`` (placement never moves a
    ///   train), or ``GameError/invalidTrainPosition``.
    public mutating func placeTrain(_ id: TrainID, at position: TrainPosition) throws(GameError) {
        let index = try trainIndex(of: id)
        guard trains[index].position == nil else { throw .trainAlreadyPlaced(id) }
        guard isOnTrack(position) else { throw .invalidTrainPosition }
        let length = trains[index].length
        if case .onEdge(let traversal, let offset) = position {
            guard length == 0 || offset > 0, let trail = networkTrailBehind(traversal, offset: offset, length: length) else {
                throw .invalidTrainPosition
            }
            trains[index].position = position
            trains[index].trailEdges = trail
            return
        }
        guard let trail = trailBehind(position, length: length) else { throw .invalidTrainPosition }

        trains[index].position = position
        trains[index].trail = trail
    }

    /// Sets how many cars an unplaced train has (Phase 4.5 Stage S2), one
    /// to a tile: ``Train/minimumCars`` to ``Train/maximumCars``. Free. A
    /// train of more than one car is placed with its body behind its head
    /// along the track it could have come by (see ``placeTrain(_:at:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/invalidTrainLength``, or
    ///   ``GameError/trainAlreadyPlaced(_:)`` (take it off the track first).
    public mutating func setTrainCars(_ id: TrainID, to cars: Int) throws(GameError) {
        let index = try trainIndex(of: id)
        guard (Train.minimumCars...Train.maximumCars).contains(cars) else { throw .invalidTrainLength }
        guard trains[index].position == nil else { throw .trainAlreadyPlaced(id) }

        trains[index].cars = cars
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
        trains[index].trail = []
        trains[index].trailEdges = []
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

        if case .onEdge(let traversal, let offset) = position {
            (trains[index].position, trains[index].trailEdges) = reversedOnNetwork(
                traversal, offset: offset, trail: trains[index].trailEdges, length: trains[index].length
            )
        } else {
            (trains[index].position, trains[index].trail) = Self.reversed(position, trail: trains[index].trail, length: trains[index].length)
        }
        trains[index].movement.continuation = []
        trains[index].movement.edges = []
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
    ///
    /// A train on the track network follows edges, not tiles: an empty list
    /// clears its continuation, and any other list is refused (see
    /// ``setTrainContinuation(_:along:)``).
    public mutating func setTrainContinuation(_ id: TrainID, to nodes: [GridPosition]) throws(GameError) {
        let (index, position) = try manuallyControlledTrain(id)
        guard let (node, heading) = position.ahead else {
            guard nodes.isEmpty else { throw .invalidContinuation }
            trains[index].movement.edges = []
            trains[index].movement.cursor = 0
            return
        }
        guard TrainMovement.isPath(nodes, from: node, heading: heading, mayPass: { canPass(from: $0, facing: $1, to: $2) }) else {
            throw .invalidContinuation
        }

        trains[index].movement.continuation = nodes
        trains[index].movement.cursor = 0
    }

    /// Replaces a placed train's continuation with the path `traversals`
    /// (Stage S3), for a train on the grid or on the track network alike: the
    /// form ``route(from:to:)`` returns for a ``TrackNodeID``. Each traversal
    /// must be one a train may take after the one before it (see
    /// ``transitions(after:)``): the first after the edge the train is on,
    /// or on the grid from the node ahead of it as
    /// ``setTrainContinuation(_:to:)`` requires. The whole list is checked
    /// against the current track, then replaces the old continuation, and
    /// the cursor goes back to 0; an empty list clears it. On the grid it is
    /// kept as the nodes the links lead to (``TrainMovement/continuation``),
    /// on the network as its edges (``TrainMovement/edges``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``,
    ///   ``GameError/trainServiceActive(_:)``, or
    ///   ``GameError/invalidContinuation`` (a step a train may not take, or
    ///   the other kind of track).
    public mutating func setTrainContinuation(_ id: TrainID, along traversals: [TrackTraversal]) throws(GameError) {
        let (index, position) = try manuallyControlledTrain(id)
        guard case .onEdge(let traversal, _) = position else {
            // On the grid: the node each link leads to, from the node ahead.
            var node = position.ahead!.node
            var nodes: [GridPosition] = []
            for next in traversals {
                guard case .link(let a, let b) = next.edge, TrackEdgeID.precedes(a, b) else { throw .invalidContinuation }
                let (from, to) = next.direction == .forward ? (a, b) : (b, a)
                guard from == node else { throw .invalidContinuation }
                nodes.append(to)
                node = to
            }
            try setTrainContinuation(id, to: nodes)
            return
        }
        var arrival = traversal
        for next in traversals {
            guard transitions(after: arrival).contains(next) else { throw .invalidContinuation }
            arrival = next
        }

        trains[index].movement.edges = traversals.map(\.edge)
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
    /// the timetable, and start the service again. A train assigned to a
    /// line gets its timetables from the line.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainOnLine(_:)``,
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
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
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
    /// runs, turns trains round and starts a timetable again). A train
    /// assigned to a line is sent out by the line.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainOnLine(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` if a service is already
    ///   running, ``GameError/noTimetable(_:)`` for an empty timetable,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/trainNotAtFirstStop(_:)``.
    public mutating func startTrainService(_ id: TrainID) throws(GameError) {
        let index = try trainIndex(of: id)
        let train = trains[index]
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
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
    /// brake; set the rate to 0 to hold the train. A line's train is taken
    /// off the line first (``unassignTrain(_:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainOnLine(_:)``, or
    ///   ``GameError/trainServiceNotActive(_:)``.
    public mutating func stopTrainService(_ id: TrainID) throws(GameError) {
        let index = try trainIndex(of: id)
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
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
    /// journey would take is derived by ``lineJourney(_:pattern:)``.
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

    /// Removes a line. Its ID is never handed out again. Its trains are no
    /// longer assigned to a line; a train on a round trip keeps its
    /// timetable and finishes the trip as an ordinary service.
    ///
    /// - Throws: ``GameError/unknownLine(_:)``.
    public mutating func removeLine(_ id: LineID) throws(GameError) {
        let index = try lineIndex(of: id)
        lines.remove(at: index)
    }

    /// Replaces a line's stops with `stops`, in order. Its patterns keep
    /// their calls, as indices into the new stops.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/invalidLineStops``, ``GameError/unknownStation(_:)``
    ///   naming the first stop whose station does not exist, or
    ///   ``GameError/invalidLinePattern`` if a pattern would call past the
    ///   new last stop (remove it first).
    public mutating func setLineStops(_ id: LineID, to stops: [StationID]) throws(GameError) {
        let index = try lineIndex(of: id)
        try requireLineStops(stops)
        guard lines[index].patterns.allSatisfy({ LinePattern.isCallList($0.calls, stopCount: stops.count) }) else {
            throw .invalidLinePattern
        }
        lines[index].stops = stops
    }

    /// Sets the rate, in logical units per game minute, that a line's
    /// journey times are worked out at (see ``lineJourney(_:pattern:)``).
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

    /// Sets how many trains a line's own service, or its pattern at index
    /// `pattern`, is to run at each service level. Any count of 0 or more
    /// is kept as it is; how many it can run is derived (see
    /// ``lineTrainsInService(_:at:pattern:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/unknownLinePattern(_:)``, or
    ///   ``GameError/invalidTrainsInService`` for a negative count.
    public mutating func setLineTrainsInService(_ id: LineID, to trains: TrainsInService, pattern: Int? = nil) throws(GameError) {
        let (index, service) = try lineService(id, pattern: pattern)
        guard trains.isValid else { throw .invalidTrainsInService }
        if service == 0 {
            lines[index].trainsInService = trains
        } else {
            lines[index].patterns[service - 1].trainsInService = trains
        }
    }

    /// Sets which service level each minute of the day has, for every line.
    ///
    /// - Throws: ``GameError/invalidServiceDay`` unless the bands start at
    ///   minute 0 and strictly increase within the day.
    public mutating func setServiceDay(_ day: ServiceDay) throws(GameError) {
        guard day.isValid else { throw .invalidServiceDay }
        serviceDay = day
    }

    /// Sets the minutes a line's own service, or its pattern at index
    /// `pattern`, aims to keep between its trains, at the levels with a
    /// target; the other levels run the count set by
    /// ``setLineTrainsInService(_:to:pattern:)`` (see ``TargetHeadways``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/unknownLinePattern(_:)``, or
    ///   ``GameError/invalidHeadway`` for a target outside `2...1440`.
    public mutating func setLineTargetHeadways(_ id: LineID, to headways: TargetHeadways, pattern: Int? = nil) throws(GameError) {
        let (index, service) = try lineService(id, pattern: pattern)
        guard headways.isValid else { throw .invalidHeadway }
        if service == 0 {
            lines[index].targetHeadways = headways
        } else {
            lines[index].patterns[service - 1].targetHeadways = headways
        }
    }

    /// Adds a pattern to a line, calling at `calls` (indices into the
    /// line's stops), after its other patterns, with no trains in service,
    /// no target headways and no trains; returns its index. Free.
    ///
    /// Calls that are a run of neighbouring stops make a short working;
    /// calls that leave stops out make an express, which passes them.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidLinePattern`` unless there are two calls or
    ///   more, strictly increasing, each an index of one of the line's
    ///   stops.
    @discardableResult
    public mutating func addLinePattern(_ id: LineID, calling calls: [Int]) throws(GameError) -> Int {
        let index = try lineIndex(of: id)
        guard LinePattern.isCallList(calls, stopCount: lines[index].stops.count) else { throw .invalidLinePattern }
        lines[index].patterns.append(LinePattern(calls: calls))
        return lines[index].patterns.count - 1
    }

    /// Removes a line's pattern at index `pattern`; the patterns after it
    /// move down one index. Its trains are no longer assigned to a line: a
    /// train on a round trip keeps its timetable and finishes the trip as
    /// an ordinary service, as when a line is removed.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/unknownLinePattern(_:)``.
    public mutating func removeLinePattern(_ id: LineID, at pattern: Int) throws(GameError) {
        let (index, service) = try lineService(id, pattern: pattern)
        lines[index].patterns.remove(at: service - 1)
    }

    /// The line train `id` is assigned to, or `nil` if it is on none (or
    /// does not exist).
    public func assignedLine(of id: TrainID) -> LineID? {
        lines.first { line in (0..<line.serviceCount).contains { line.trains(ofService: $0).contains(id) } }?.id
    }

    /// The index of the pattern train `id` is assigned to, or `nil` if it
    /// is assigned to a line's own service, or to no line.
    public func assignedPattern(of id: TrainID) -> Int? {
        for line in lines {
            if let pattern = line.patterns.firstIndex(where: { $0.trains.contains(id) }) { return pattern }
        }
        return nil
    }

    /// Assigns a train to a line's own service, or to its pattern at index
    /// `pattern`, which from then on runs the train's timetable and
    /// service: it sends the train out on round trips from its first call
    /// (see ``advance(ticks:)``). Free, and the train may be placed or not,
    /// anywhere; only a train stopped at the first call can be sent out.
    /// Nothing else changes until the service sends the train out.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/unknownLine(_:)``, ``GameError/unknownLinePattern(_:)``,
    ///   ``GameError/trainOnLine(_:)`` if it is on a line already (this one
    ///   included), or ``GameError/trainServiceActive(_:)`` while it runs a
    ///   service of its own (stop it first).
    public mutating func assignTrain(_ id: TrainID, to line: LineID, pattern: Int? = nil) throws(GameError) {
        let index = try trainIndex(of: id)
        let (target, service) = try lineService(line, pattern: pattern)
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }

        if service == 0 {
            lines[target].trains.insert(id, at: lines[target].trains.firstIndex { $0 > id } ?? lines[target].trains.count)
        } else {
            let roster = lines[target].patterns[service - 1].trains
            lines[target].patterns[service - 1].trains.insert(id, at: roster.firstIndex { $0 > id } ?? roster.count)
        }
    }

    /// Takes a train off its line, whichever of the line's services it is
    /// on. Only the assignment ends: a train on a round trip keeps its
    /// timetable and finishes the trip as an ordinary service, which can
    /// then be stopped like any other.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)`` or
    ///   ``GameError/trainNotOnLine(_:)``.
    public mutating func unassignTrain(_ id: TrainID) throws(GameError) {
        _ = try trainIndex(of: id)
        guard let index = lines.firstIndex(where: { $0.id == assignedLine(of: id) }) else { throw .trainNotOnLine(id) }

        lines[index].trains.removeAll { $0 == id }
        for pattern in lines[index].patterns.indices {
            lines[index].patterns[pattern].trains.removeAll { $0 == id }
        }
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
    /// basic step from minute `T` to `T + 1` has five phases, each taking
    /// the lines in ascending ``LineID`` order and the trains in ascending
    /// ``TrainID`` order:
    ///
    /// 0. **Dispatch at `T`.** Each line sends out at most one of its
    ///    trains on a round trip (see below).
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
    /// **Dispatch** (see ``assignTrain(_:to:pattern:)``). Each service of a
    /// line (its own, then its patterns in order) sends a train out at `T`
    /// when all of these hold:
    ///
    /// - `T` is minute 0 or later, the line's window is open, the
    ///   service's journey can be driven (see ``lineJourney(_:pattern:)``),
    ///   and at the level of `T` it runs trains beside the services before
    ///   it (see ``lineTrainsInService(_:at:pattern:)``);
    /// - that headway (see ``lineHeadway(_:at:pattern:)``) has passed since
    ///   the service last sent a train out;
    /// - fewer of its trains run a service than it runs then; and
    /// - one of its trains is ready: without a service, placed, with a rate
    ///   above 0, stopped at the first call's station (see
    ///   ``stationsStoppedAt(by:)``), and able to drive the whole round trip
    ///   from there as it faces or turned round, whichever is shorter (as it
    ///   faces when they are equal).
    ///
    /// The first ready train in ID order gets a timetable for one round trip
    /// leaving at `T`, and its service starts at the first call: it leaves
    /// in phase 1 of the same step. The times come from that trip at the
    /// line's rate, with the dwells of ``ServiceLine``: out to the last
    /// call, where it turns round, and back to the first, where it turns
    /// round and the service ends; stops a pattern does not call at are
    /// not in the timetable. The train then waits there until its service
    /// sends it out again. So a service never runs more trains than it runs
    /// at its level: when it runs fewer, the trains coming back wait at the
    /// first call; when it runs more, only trains waiting there can go. A
    /// train late back makes the next one leave late, never early.
    ///
    /// When a whole step changes nothing (no train moves, no service leaves,
    /// arrives or ends, and no line sends a train out), no later step of
    /// this call can change anything before the next scheduled departure of
    /// a waiting service, or the next minute at which a line's service with
    /// a ready train might send it out (the map and every train's inputs
    /// stay the same until the next command, a departure that found no
    /// route finds none later in the call, and a line's window, level and
    /// headways change only at known minutes), so the clock moves on at once to that minute,
    /// or to the end of the batch. This is an exact shortcut, not an
    /// approximation.
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
        var memo = DispatchMemo()
        while remaining > 0 {
            let dispatched = dispatchTrains(memo: &memo)
            let departed = departTrains(unroutable: &unroutable)
            let moved = moveTrainsOneStep()
            clock.advance(basicSteps: 1)
            let arrived = recordArrivals()
            remaining -= 1
            if !dispatched, !departed, !moved, !arrived {
                let wake = [basicStepsUntilNextDeparture(), basicStepsUntilNextDispatch(memo: &memo)].compactMap { $0 }.min()
                let idle = min(remaining, wake ?? remaining)
                clock.advance(basicSteps: idle)
                remaining -= idle
            }
        }
    }

    /// What dispatching works out once per call of ``advance(ticks:)``:
    /// no command can come within a call, so the map, the lines' stops,
    /// patterns and rates and an idle train's position stay the same, and
    /// so do these.
    private struct DispatchMemo {
        /// Each service's journey (see ``lineJourney(_:pattern:)``), by line
        /// and service (see ``ServiceLine/serviceCount``), once looked up.
        var journeys: [LineID: [Int: LineJourney?]] = [:]
        /// Each train's round trip from where it stood idle (its position
        /// and trail) when it was looked up, or `nil` if it had none.
        var trips: [TrainID: (from: TrainPosition, trail: [GridPosition], trip: LineTrip?)] = [:]
    }

    /// Phase 0 of a basic step: each line, in ascending ID order, and on it
    /// each service, its own first and then its patterns in order, sends
    /// out at most one of its trains (see ``advance(ticks:)``). Returns
    /// whether any did.
    private mutating func dispatchTrains(memo: inout DispatchMemo) -> Bool {
        let now = clock.now
        var dispatched = false
        for index in lines.indices {
            for service in 0..<lines[index].serviceCount where !lines[index].trains(ofService: service).isEmpty {
                let line = lines[index]
                guard isDispatchDue(line, service, at: now, memo: &memo),
                      let (ready, trip) = readyTrain(of: line, service, memo: &memo),
                      let timetable = trip.timetable(calling: line.stops, leavingAt: now)
                else { continue }
                trains[ready].timetable = timetable
                trains[ready].timetablePeriod = nil
                trains[ready].execution = .waitingAtStop(0)
                lines[index].recordDispatch(ofService: service, at: now)
                dispatched = true
            }
        }
        return dispatched
    }

    /// Whether `line`'s service `service` sends a train out at `now` if one
    /// is ready: not before minute 0; the line's window is open and the
    /// service runs trains then (see ``plannedService(of:_:at:memo:)``); a
    /// headway of that level has passed since the service's last dispatch;
    /// and fewer of its trains run a service than it runs then.
    private func isDispatchDue(_ line: ServiceLine, _ service: Int, at now: GameTime, memo: inout DispatchMemo) -> Bool {
        guard now.minutes >= 0, let planned = plannedService(of: line, service, at: now, memo: &memo) else { return false }
        if let last = line.lastDispatch(ofService: service) {
            let (due, overflow) = last.minutes.addingReportingOverflow(planned.headway)
            guard !overflow, due <= now.minutes else { return false }
        }
        let running = line.trains(ofService: service).count { id in train(id: id)?.execution != nil }
        return running < planned.trains
    }

    /// The trains `line`'s service `service` runs at `now` and the headway
    /// between them, beside the services before it (see
    /// ``ServiceLine/services(at:roundTrips:)``), or `nil` when the line's
    /// window is closed, or the service runs none then or its journey
    /// cannot be driven.
    private func plannedService(of line: ServiceLine, _ service: Int, at now: GameTime, memo: inout DispatchMemo) -> (trains: Int, headway: Int64)? {
        guard line.window.contains(minuteOfDay: now.minuteOfDay) else { return nil }
        var roundTrips: [Int64?] = []
        for earlier in 0...service {
            let journey: LineJourney?
            if let known = memo.journeys[line.id]?[earlier] {
                journey = known
            } else {
                journey = self.journey(of: line, service: earlier)
                memo.journeys[line.id, default: [:]][earlier] = journey
            }
            roundTrips.append(journey?.roundTripMinutes)
        }
        guard roundTrips[service] != nil else { return nil }
        return line.services(at: serviceDay.level(atMinuteOfDay: now.minuteOfDay), roundTrips: roundTrips).plans[service]
    }

    /// The first of the trains of `line`'s service `service`, in ID order,
    /// that it can send out: one without a service, placed, with a rate
    /// above 0, stopped at the first call's station, and able to drive the
    /// whole round trip from there (see ``trip(of:service:for:)``); with
    /// its index and that trip.
    private func readyTrain(of line: ServiceLine, _ service: Int, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        let first = line.stops[line.calls(ofService: service)[0]]
        for id in line.trains(ofService: service) {
            guard let index = trains.firstIndex(where: { $0.id == id }) else { continue }
            let train = trains[index]
            guard train.execution == nil, let position = train.position, train.movement.rate > 0,
                  isStopped(train, at: first)
            else { continue }
            let trip: LineTrip?
            if let known = memo.trips[id], known.from == position, known.trail == train.trail {
                trip = known.trip
            } else {
                trip = self.trip(of: line, service: service, for: train)
                memo.trips[id] = (position, train.trail, trip)
            }
            if let trip { return (index, trip) }
        }
        return nil
    }

    /// The basic steps from now until the first minute, at or after now,
    /// at which some service might send a train out, or `nil` if none can
    /// in this call.
    ///
    /// Only a service with a train ready counts: a train becomes ready only
    /// by arriving or finishing a service, which is a change, so after a
    /// step that changed nothing no other service can send one out before
    /// the next command. For such a service the answer is now if it is due
    /// now; otherwise the first of minute 0, the minute a headway since its
    /// last dispatch has passed, and the next minute its line's window
    /// opens or closes or the day's level changes. Until then nothing that
    /// decides whether it is due can change (what the services before it
    /// run changes only at those same minutes), so this is exact. A gap too
    /// large for an `Int64` is given as `Int64.max`.
    private func basicStepsUntilNextDispatch(memo: inout DispatchMemo) -> Int64? {
        let now = clock.now
        var soonest: Int64?
        for line in lines {
            for service in 0..<line.serviceCount where !line.trains(ofService: service).isEmpty {
                guard readyTrain(of: line, service, memo: &memo) != nil else { continue }
                var wake: Int64?
                if now.minutes < 0 {
                    wake = 0
                } else if isDispatchDue(line, service, at: now, memo: &memo) {
                    wake = now.minutes
                } else {
                    wake = line.nextChange(after: now, in: serviceDay)?.minutes
                    if let last = line.lastDispatch(ofService: service), let planned = plannedService(of: line, service, at: now, memo: &memo) {
                        let (due, overflow) = last.minutes.addingReportingOverflow(planned.headway)
                        if !overflow, due > now.minutes {
                            wake = min(wake ?? due, due)
                        }
                    }
                }
                guard let wake else { continue }
                let (gap, overflow) = wake.subtractingReportingOverflow(now.minutes)
                soonest = min(soonest ?? .max, overflow ? .max : gap)
            }
        }
        return soonest
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
                // left, so turning it round needs nothing else. A train of
                // several cars turns round with its head where its tail was,
                // at a node again (see reversed(_:trail:length:)).
                let (start, startTrail) = train.timetable[stop].reverses
                    ? Self.reversed(position, trail: train.trail, length: train.length)
                    : (position, train.trail)
                guard let next = train.call(after: stop, cycle: cycle) else {
                    // The last stop's departure: the service is complete.
                    trains[index].position = start
                    trains[index].trail = startTrail
                    trains[index].execution = nil
                    changed = true
                    break
                }
                guard let route = route(from: start, toStation: train.timetable[next.stop].station, length: train.length) else {
                    // Nothing changes: the train is not turned round either.
                    unroutable.insert(train.id)
                    break
                }
                changed = true
                trains[index].position = start
                trains[index].trail = startTrail
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
            if case .onEdge(let traversal, let offset) = position {
                // On the track network: the same rules, each edge as long as
                // it is (Stage S3).
                let travel = TrainMovement.travel(
                    along: traversal, offset: offset, length: network.edge(traversal.edge)!.length,
                    distance: movement.rate, edges: movement.edges, cursor: movement.cursor,
                    enter: { networkEntry(after: $0, into: $1) }
                )
                guard travel.position != position || travel.cursor != movement.cursor,
                      case .onEdge(_, let reached) = travel.position
                else { continue }
                trains[index].trailEdges = networkTrail(
                    after: traversal.edge, trail: trains[index].trailEdges,
                    entered: movement.edges[movement.cursor..<travel.cursor], offset: reached, length: trains[index].length
                )
                trains[index].position = travel.position
                if travel.cursor == movement.edges.count {
                    // Every edge has been entered: the continuation is spent.
                    trains[index].movement.edges = []
                    trains[index].movement.cursor = 0
                } else {
                    trains[index].movement.cursor = travel.cursor
                }
                moved = true
                continue
            }
            let travel = TrainMovement.travel(
                from: position,
                distance: movement.rate,
                continuation: movement.continuation,
                cursor: movement.cursor,
                mayPass: { canPass(from: $0, facing: $1, to: $2) }
            )
            guard travel.position != position || travel.cursor != movement.cursor else { continue }

            trains[index].trail = Self.trail(
                after: position, trail: trains[index].trail, to: travel.position,
                entered: movement.continuation[movement.cursor..<travel.cursor], length: trains[index].length
            )
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
        // Grid track and stations take a tile each (the rules of Stages
        // I–S2); the continuous network takes none.
        guard tile.type == .empty, track(at: position) == nil else { throw .tileOccupied(position) }
    }

    private static func isValidName(_ name: String) -> Bool {
        name.contains { !$0.isWhitespace }
    }

    /// The index of line `id` and the service `pattern` names on it (see
    /// ``ServiceLine/serviceCount``).
    private func lineService(_ id: LineID, pattern: Int?) throws(GameError) -> (index: Int, service: Int) {
        let index = try lineIndex(of: id)
        guard let service = lines[index].service(pattern) else { throw .unknownLinePattern(pattern ?? 0) }
        return (index, service)
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
    ///
    /// On the track network: the edge exists and the offset lies within it
    /// (see ``isOnNetwork(_:offset:)``).
    func isOnTrack(_ position: TrainPosition) -> Bool {
        guard position.isWellFormed else { return false }
        switch position {
        case .atNode(let tile, _):
            return track(at: tile) != nil
        case .onLink(let from, let to, _):
            return isConnected(from, to: to)
        case .onEdge(let traversal, let offset):
            return isOnNetwork(traversal, offset: offset)
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
        case map, stations, trains, lines, serviceDay, clock, economy, nextStationID, nextTrainID, nextLineID, network
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
    /// it travels to, as a route from the service would; every line's
    /// and patterns' trains must exist and be on that service only, none of
    /// them may run a repeating timetable, and no service may have sent a
    /// train out after the current minute, as ``assignTrain(_:to:pattern:)`` and dispatching require).
    ///
    /// A continuation's links are not required to exist: track ahead of a
    /// train may have been removed after the continuation was set, and a
    /// world where a train waits for that track to be rebuilt is valid.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Stage S3A: the saved tiles hold the land and the grid's track
        // together, as every save has since Stage I; the land goes to the
        // map and the track to the railway network, and nowhere else.
        let saved = try container.decode(SavedMap.self, forKey: .map)
        map = saved.land
        stations = try container.decode([Station].self, forKey: .stations)
        trains = try container.decode([Train].self, forKey: .trains)
        clock = try container.decode(GameClock.self, forKey: .clock)
        economy = try container.decode(GameEconomy.self, forKey: .economy)
        nextStationID = try container.decode(Int.self, forKey: .nextStationID)
        nextTrainID = try container.decode(Int.self, forKey: .nextTrainID)
        lines = container.contains(.lines) ? try container.decode([ServiceLine].self, forKey: .lines) : []
        nextLineID = container.contains(.nextLineID) ? try container.decode(Int.self, forKey: .nextLineID) : 1
        serviceDay = container.contains(.serviceDay) ? try container.decode(ServiceDay.self, forKey: .serviceDay) : .standard
        network = container.contains(.network) ? try container.decode(RailwayNetwork.self, forKey: .network) : RailwayNetwork()
        for track in saved.tracks {
            network.lay(track)
        }

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
    /// IDs from 1, with the standard day. Likewise a world whose track
    /// network never had a node or an edge has no `"network"` key (Stage
    /// S3), and a save without one reads as an empty network. An explicit
    /// `null` for any of them is rejected.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(SavedMap(land: map, tracks: network.tracks), forKey: .map)
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
        if !network.isPristine {
            try container.encode(network, forKey: .network)
        }
    }

    /// The map as a save holds it (Stage S3A): each tile's land or grid
    /// track, in the format every save has had since Stage I. It is only a
    /// way of writing the two down: the land is the ``GridMap``'s and the
    /// track the ``RailwayNetwork``'s, and neither is kept here.
    private struct SavedMap: Codable {
        /// A saved tile: the land, or a grid track piece on it. The cases and
        /// their labels are the saved form of the map's tiles before Stage
        /// S3A, so saves read and write byte for byte as before.
        private enum Tile: Codable, Equatable {
            case empty
            case track(connections: TrackConnections)
            case station(id: StationID)
            case turnout(connections: TrackConnections, stem: TrackDirection)
            case crossing
        }

        private enum CodingKeys: String, CodingKey {
            case width, height, tiles
        }

        let land: GridMap
        /// The grid's track pieces in row-major order.
        let tracks: [Track]

        init(land: GridMap, tracks: [Track]) {
            self.land = land
            self.tracks = tracks
        }

        /// Decodes `{"width", "height", "tiles"}`, the tiles in row-major
        /// order, rejecting a size the map cannot have, a tile count that
        /// does not match it, a track piece without exits and a turnout
        /// that is not one.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let width = try container.decode(Int.self, forKey: .width)
            let height = try container.decode(Int.self, forKey: .height)
            let tiles = try container.decode([Tile].self, forKey: .tiles)
            func corrupt(_ description: String) -> DecodingError {
                DecodingError.dataCorruptedError(forKey: .tiles, in: container, debugDescription: description)
            }
            guard let map = try? GridMap(width: width, height: height), tiles.count == width * height else {
                throw corrupt("Tile count \(tiles.count) does not match a valid \(width)x\(height) map.")
            }
            var land = map
            var tracks: [Track] = []
            for (index, tile) in tiles.enumerated() {
                let position = GridPosition(x: index % width, y: index / width)
                switch tile {
                case .empty:
                    break
                case .station(let id):
                    land.setType(.station(id: id), at: position)
                case .track(let connections):
                    guard !connections.isEmpty else { throw corrupt("Track tiles must have at least one connection.") }
                    tracks.append(Track(position: position, connections: connections))
                case .turnout(let connections, let stem):
                    guard GameWorld.isTurnout(connections, stem: stem) else {
                        throw corrupt("A turnout needs three exits or more, its stem among them.")
                    }
                    tracks.append(Track(position: position, connections: connections, layout: .turnout(stem: stem)))
                case .crossing:
                    tracks.append(Track(position: position, connections: [.north, .east, .south, .west], layout: .crossing))
                }
            }
            self.land = land
            self.tracks = tracks
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(land.width, forKey: .width)
            try container.encode(land.height, forKey: .height)
            var pieces: [GridPosition: Track] = [:]
            for track in tracks {
                pieces[track.position] = track
            }
            let tiles = land.tiles.map { tile -> Tile in
                if let track = pieces[tile.position] {
                    switch track.layout {
                    case .open: return .track(connections: track.connections)
                    case .turnout(let stem): return .turnout(connections: track.connections, stem: stem)
                    case .crossing: return .crossing
                    }
                }
                switch tile.type {
                case .empty: return .empty
                case .station(let id): return .station(id: id)
                }
            }
            try container.encode(tiles, forKey: .tiles)
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
        var assigned: Set<TrainID> = []
        for line in lines {
            guard Self.isValidName(line.name) else { return "Line \(line.id.rawValue) has an invalid name." }
            if let missing = line.stops.first(where: { station(id: $0) == nil }) {
                return "Line \(line.id.rawValue) calls at station \(missing.rawValue), which does not exist."
            }
            for service in 0..<line.serviceCount {
                for id in line.trains(ofService: service) {
                    guard let train = train(id: id) else { return "Line \(line.id.rawValue) has train \(id.rawValue), which does not exist." }
                    guard assigned.insert(id).inserted else { return "Train \(id.rawValue) is assigned to two lines or services." }
                    // A line sends its trains out on trips that run once, and
                    // no other service can start while a train is on a line.
                    guard train.execution == nil || train.timetablePeriod == nil else {
                        return "Line \(line.id.rawValue)'s train \(id.rawValue) runs a repeating timetable."
                    }
                }
                if let last = line.lastDispatch(ofService: service), last > clock.now {
                    return "Line \(line.id.rawValue) sent a train out after the current minute."
                }
            }
        }
        for station in stations {
            guard Self.isValidName(station.name) else { return "Station \(station.id.rawValue) has an invalid name." }
            guard station.tiles.allSatisfy({ map.tile(at: $0)?.type == .station(id: station.id) }) else {
                return "Station \(station.id.rawValue) does not match the map tile at \(station.position)."
            }
        }
        let stationTileCount = map.tiles.count { tile in
            if case .station = tile.type { return true }
            return false
        }
        guard stationTileCount == stations.reduce(0, { $0 + $1.tiles.count }) else {
            return "The map has station tiles without matching station records."
        }
        guard trains.allSatisfy({ Self.isValidName($0.name) }) else {
            return "A train has an invalid name."
        }
        // Stage S3A: grid track stands on the map's empty land, one piece a
        // tile (a station tile is not track).
        guard network.tracks.allSatisfy({ map.tile(at: $0.position)?.type == .empty }) else {
            return "Grid track lies off the map or on a station."
        }
        // Stage S3: the network lies over the map; Stage S4: at the heights
        // a world allows.
        guard network.nodes.allSatisfy({ isOnMap($0.position) }) else {
            return "A track node lies off the map or beyond the heights track may have."
        }
        guard network.edges.allSatisfy({ $0.curve.controlPoints.allSatisfy(isOnMap) }) else {
            return "A track edge's curve leaves the map."
        }
        if let problem = networkRuleProblem() {
            return problem
        }
        for train in trains {
            if let position = train.position, !isOnTrack(position) {
                return "Train \(train.id.rawValue) is not on this map's track."
            }
            if let position = train.position, !isTrailOnTrack(train.trail, behind: position) {
                return "Train \(train.id.rawValue)'s body is not on track it could have come along."
            }
            if case .onEdge(let traversal, let offset)? = train.position,
               !isNetworkTrail(train.trailEdges, behind: traversal, offset: offset, length: train.length) {
                return "Train \(train.id.rawValue)'s body is not on track it could have come along."
            }
            // IDs are never reused, so an edge that was built once is below
            // the next number even after it was removed.
            guard train.movement.edges.allSatisfy({ ($0.networkNumber ?? .max) < network.nextEdgeNumber }) else {
                return "Train \(train.id.rawValue)'s continuation names an edge that was never built."
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

    /// Why the track network breaks a Stage S4 rule, or `nil`: an edge
    /// steeper than the maximum grade or on a structure that cannot carry it
    /// at its heights, two edges meeting without clearance, or a platform
    /// that does not fit its edge or overlaps another.
    private func networkRuleProblem() -> String? {
        var geometries: [TrackGeometry] = []
        for edge in network.edges {
            guard let geometry = network.geometry(of: edge.id) else { return "Track edge \(edge.id) has no geometry." }
            geometries.append(geometry)
            guard geometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumGrade) else {
                return "Track edge \(edge.id) is steeper than the maximum grade."
            }
            guard edge.structure.allows(height: geometry.startHeight), edge.structure.allows(height: geometry.endHeight) else {
                return "Track edge \(edge.id)'s structure cannot carry it at its heights."
            }
        }
        if let (a, b) = network.firstConflictingPair(geometries: geometries) {
            return "Track edges \(a) and \(b) meet without clearance."
        }
        // The network's decoder has checked the platforms are in order and
        // do not overlap.
        for platform in network.platforms {
            guard station(id: platform.station) != nil else {
                return "A platform belongs to station \(platform.station.rawValue), which does not exist."
            }
            guard isValidPlatform(platform) else {
                return "Station \(platform.station.rawValue) has a platform that does not fit its edge."
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
            guard let ahead = position.ahead else { return "Train \(train.id.rawValue) runs a service on the track network." }
            let end = train.movement.continuation.last ?? ahead.node
            guard station.tiles.contains(where: { TrackDirection(from: end, to: $0) != nil }) else {
                return "Train \(train.id.rawValue)'s service travels on a journey that does not end at its next stop."
            }
        }
        return nil
    }

    private static func isStrictlyIncreasing(_ ids: [Int], below limit: Int) -> Bool {
        zip(ids, ids.dropFirst()).allSatisfy { $0 < $1 } && (ids.last ?? 0) < limit && (ids.first ?? 1) >= 1
    }
}
