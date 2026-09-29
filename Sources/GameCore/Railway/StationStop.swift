// Station stops. A station is not track (see TrackConnectivity.swift), so
// trains stop beside it: on the track tiles next to the station's tile, its
// platforms. Like connectivity, platforms are derived from the map on every
// query and never stored, so the next query sees any track or station built
// or removed since.
//
// A train is stopped at a station when its journey ends at one of the
// station's platforms: it stands at the centre of the platform tile with no
// continuation left. The movement kernel never moves such a train by itself
// (see TrainMovement), so it stays stopped until a command gives it
// somewhere to go or takes it off the track, or its timetable service gives
// it a route when a departure comes. Being stopped is derived from
// the train's position and movement and the map, like being blocked; it is
// not stored.

extension GameWorld {
    /// The track tiles where trains stop for the station `id`: the track
    /// tiles directly north, east, south and west of each of the station's
    /// tiles (see ``Station/tiles``), in that order, each once.
    ///
    /// A platform runs alongside the track, so it needs no exit toward the
    /// station and need not be joined to other track. Diagonal tiles, empty
    /// tiles, other stations and tiles outside the map are not platforms. A
    /// track tile next to two stations is a platform of both. Empty for an
    /// unknown station and for a station with no track beside it.
    ///
    /// Reads at most five tiles per station tile once the station is
    /// found, and never scans the map.
    public func platforms(of id: StationID) -> [GridPosition] {
        guard let station = station(id: id) else { return [] }
        var platforms: [GridPosition] = []
        for stationTile in station.tiles {
            for direction in TrackDirection.allCases {
                guard let tile = map.neighbor(of: stationTile, toward: direction),
                      track(at: tile) != nil,
                      !platforms.contains(tile)
                else { continue }
                platforms.append(tile)
            }
        }
        return platforms
    }

    /// The station's platform tracks (Stage S2): its platforms (see
    /// ``platforms(of:)``) in groups joined to each other by track, each
    /// group in ``platforms(of:)`` order, the groups in the order of their
    /// first platform. A group's count is that track's platform length in
    /// tiles, the longest train (see ``Train/tileCount``) it holds beside
    /// the station if the track runs straight along it. Track on two sides
    /// of a station makes two platform tracks.
    ///
    /// Empty for an unknown station and for a station with no track
    /// beside it. Reads only the tiles around the station.
    public func platformTracks(of id: StationID) -> [[GridPosition]] {
        let platforms = platforms(of: id)
        var group = [Int?](repeating: nil, count: platforms.count)
        var groups: [[Int]] = []
        for start in platforms.indices where group[start] == nil {
            group[start] = groups.count
            var members = [start]
            var queue = [start]
            while let index = queue.popLast() {
                for other in platforms.indices where group[other] == nil && isConnected(platforms[index], to: platforms[other]) {
                    group[other] = groups.count
                    members.append(other)
                    queue.append(other)
                }
            }
            groups.append(members.sorted())
        }
        return groups.map { $0.map { platforms[$0] } }
    }

    /// The shortest continuation that takes a train at `start` to a platform
    /// of the station `id` (see ``platforms(of:)``), or `nil` if there is
    /// none.
    ///
    /// The same search as ``route(from:to:)``, with every platform of the
    /// station as a destination: the fewest links, and among the shortest the
    /// route whose exit directions come first in north, east, south, west
    /// order. So the result is the best of the routes ``route(from:to:)``
    /// gives to each platform. It ends at the first platform it reaches and
    /// passes no other platform of the station on the way. It can be passed
    /// to ``setTrainContinuation(_:to:)`` unchanged on this world, and a
    /// train that follows it to the end is stopped at the station (see
    /// ``stationsStoppedAt(by:)``). An empty list means the node ahead of the
    /// train (the node it stands on, or the `to` end of its link) is already
    /// a platform.
    ///
    /// Returns `nil` when `start` is not a valid position on this map's track
    /// (see ``placeTrain(_:at:)``), when there is no station `id` or it has
    /// no platform, or when no platform can be reached without turning
    /// straight back.
    ///
    /// A train `length` long (Stage S2) then pulls forward along the
    /// station's platforms until its whole body is beside the station, if
    /// the platform goes on that far: from where the route reaches the
    /// first platform, one tile further, the first way north, east, south,
    /// west that is a platform of the station, for every tile behind its
    /// head that its body would stand over (a tile per car after the
    /// first). For a train of one car (length 0) that is no further.
    ///
    /// Pure, and costs what ``route(from:to:)`` costs: it explores only track
    /// reachable from `start`.
    public func route(from start: TrainPosition, toStation id: StationID, length: Int64 = 0) -> [GridPosition]? {
        let platforms = platforms(of: id)
        guard isOnTrack(start), !platforms.isEmpty, let (node, heading) = start.ahead else { return nil }
        guard var route = TrainRoute.shortest(from: node, heading: heading, to: platforms.contains, exits: { exits(from: $0, facing: $1) }) else {
            return nil
        }
        var behind = Self.tilesBehind(length: length)
        var end = route.last ?? node
        var facing = route.count >= 2 ? TrackDirection(from: route[route.count - 2], to: end)! : route.isEmpty ? heading : TrackDirection(from: node, to: end)!
        while behind > 0, let next = exits(from: end, facing: facing).first(where: platforms.contains) {
            route.append(next)
            facing = TrackDirection(from: end, to: next)!
            end = next
            behind -= 1
        }
        return route
    }

    /// How many tiles behind the one its head stands at a train `length`
    /// long reaches into: its body runs back `length` from the centre of the
    /// head's tile, and each tile is ``TrainPosition/linkLength`` wide. For
    /// a train's length (whole links) that is a tile per car after the
    /// first.
    static func tilesBehind(length: Int64) -> Int {
        Int((length + TrainPosition.linkLength / 2 + TrainPosition.linkLength - 1) / TrainPosition.linkLength) - 1
    }

    /// The stations train `id` stands beside with its whole length (Stage
    /// S2): the stations it is stopped at (see ``stationsStoppedAt(by:)``)
    /// for which every tile its body stands over is a platform. A stopped
    /// train is at a node, so those tiles are its trail's nodes (see
    /// ``Train/trail``). The same as ``stationsStoppedAt(by:)`` for a train
    /// of one car.
    ///
    /// A train of several cars that turns round where it stands beside a
    /// station with its whole length has its head at a platform of the
    /// station again; one whose platform is too short has its head off it.
    public func stationsBesideWholeTrain(_ id: TrainID) -> [StationID] {
        guard let train = train(id: id) else { return [] }
        return stationsStoppedAt(by: id).filter { station in
            let platforms = platforms(of: station)
            return train.trail.allSatisfy(platforms.contains)
        }
    }

    /// The stations the train `id` is stopped at, in ascending ID order.
    ///
    /// A train is stopped at a station when it stands at the centre of one
    /// of the station's platforms (``TrainPosition/atNode(_:heading:)``,
    /// facing either way) with no continuation left, whatever its rate. Its
    /// journey ends there, and it stays until a command changes that, or
    /// its timetable service gives it a route when a departure comes (see
    /// ``advance(ticks:)``):
    ///
    /// - A train that passes a platform, one given a new continuation there
    ///   (even while its rate is 0), and one waiting there for removed track
    ///   still has a continuation, so it is not stopped.
    /// - A train on a link is not stopped, even with an empty continuation.
    ///   It is stopped only once it has reached the end of the link (which
    ///   takes a rate above 0), and only if that end is a platform.
    /// - Reversing a train, or clearing its continuation, at a platform stops
    ///   it there; so does placing a train on a platform.
    /// - A station built beside a stopped train is one it is stopped at.
    ///
    /// Several stations share a platform when their tiles are all next to
    /// it. Empty for an unknown or unplaced train and for a train that is not
    /// stopped at any station. Reads at most five tiles.
    public func stationsStoppedAt(by id: TrainID) -> [StationID] {
        guard let train = train(id: id),
              case .atNode(let tile, _)? = train.position,
              train.movement.remainingContinuation.isEmpty
        else { return [] }
        let stations = TrackDirection.allCases.compactMap { direction -> StationID? in
            guard let neighbor = map.neighbor(of: tile, toward: direction),
                  case .station(let station)? = map.tile(at: neighbor)?.type
            else { return nil }
            return station
        }
        // A platform beside two tiles of one station is one stop.
        return Set(stations).sorted()
    }

    /// Whether `train` is stopped at the station `id`: whether
    /// ``stationsStoppedAt(by:)`` would list `id` for it. Takes the train by
    /// value, so services can ask about the train they are updating.
    func isStopped(_ train: Train, at id: StationID) -> Bool {
        guard case .atNode(let tile, _)? = train.position,
              train.movement.remainingContinuation.isEmpty,
              let station = station(id: id)
        else { return false }
        return station.tiles.contains { TrackDirection(from: tile, to: $0) != nil }
    }
}
