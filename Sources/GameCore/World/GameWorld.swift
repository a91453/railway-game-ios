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
    /// - Throws: ``GameError/outOfBounds(_:)``, or
    ///   ``GameError/noTrackToRemove(_:)`` if the tile is empty or a station.
    public mutating func removeTrack(at position: GridPosition) throws(GameError) {
        guard map.contains(position) else { throw .outOfBounds(position) }
        guard track(at: position) != nil else { throw .noTrackToRemove(position) }

        map.setType(.empty, at: position)
    }

    /// Builds a station on an empty tile and charges ``ConstructionCosts/station``.
    ///
    /// - Throws: ``GameError/invalidName``, ``GameError/outOfBounds(_:)``,
    ///   ``GameError/tileOccupied(_:)``, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func buildStation(named name: String, at position: GridPosition) throws(GameError) -> Station {
        guard Self.isValidName(name) else { throw .invalidName }
        try requireEmptyTile(at: position)
        try economy.spend(economy.costs.station)

        let station = Station(id: StationID(rawValue: nextStationID), name: name, position: position)
        nextStationID += 1
        stations.append(station)
        map.setType(.station(id: station.id), at: position)
        return station
    }

    /// Buys a new train and charges ``ConstructionCosts/train``.
    ///
    /// The train is not placed on the map; placement arrives with train
    /// simulation.
    ///
    /// - Throws: ``GameError/invalidName`` or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func purchaseTrain(named name: String) throws(GameError) -> Train {
        guard Self.isValidName(name) else { throw .invalidName }
        try economy.spend(economy.costs.train)

        let train = Train(id: TrainID(rawValue: nextTrainID), name: name)
        nextTrainID += 1
        trains.append(train)
        return train
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

    /// Advances the simulation by `ticks` fixed steps at the current speed.
    public mutating func advance(ticks: Int) {
        clock.advance(ticks: ticks)
    }

    // MARK: - Validation

    private func requireEmptyTile(at position: GridPosition) throws(GameError) {
        guard let tile = map.tile(at: position) else { throw .outOfBounds(position) }
        guard tile.type == .empty else { throw .tileOccupied(position) }
    }

    private static func isValidName(_ name: String) -> Bool {
        name.contains { !$0.isWhitespace }
    }
}

// MARK: - Codable

extension GameWorld: Codable {
    private enum CodingKeys: String, CodingKey {
        case map, stations, trains, clock, economy, nextStationID, nextTrainID
    }

    /// Decodes a world, rejecting data that breaks cross-object invariants
    /// (station tiles and station records must agree; IDs must be unique and
    /// below the next ID to allocate).
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
        return nil
    }

    private static func isStrictlyIncreasing(_ ids: [Int], below limit: Int) -> Bool {
        zip(ids, ids.dropFirst()).allSatisfy { $0 < $1 } && (ids.last ?? 0) < limit && (ids.first ?? 1) >= 1
    }
}
