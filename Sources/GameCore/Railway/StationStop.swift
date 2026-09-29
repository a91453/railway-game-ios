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
    /// tiles directly north, east, south and west of the station's tile, in
    /// that order.
    ///
    /// A platform runs alongside the track, so it needs no exit toward the
    /// station and need not be joined to other track. Diagonal tiles, empty
    /// tiles, other stations and tiles outside the map are not platforms. A
    /// track tile next to two stations is a platform of both. Empty for an
    /// unknown station and for a station with no track beside it.
    ///
    /// Reads at most five tiles once the station is found, and never scans
    /// the map.
    public func platforms(of id: StationID) -> [GridPosition] {
        guard let station = station(id: id) else { return [] }
        return TrackDirection.allCases.compactMap { direction in
            guard let tile = map.neighbor(of: station.position, toward: direction),
                  track(at: tile) != nil
            else { return nil }
            return tile
        }
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
    /// Pure, and costs what ``route(from:to:)`` costs: it explores only track
    /// reachable from `start`.
    public func route(from start: TrainPosition, toStation id: StationID) -> [GridPosition]? {
        let platforms = platforms(of: id)
        guard isOnTrack(start), !platforms.isEmpty else { return nil }
        let (node, heading) = start.ahead
        return TrainRoute.shortest(from: node, heading: heading, to: platforms.contains) { exits(from: $0, facing: $1) }
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
        return TrackDirection.allCases.compactMap { direction -> StationID? in
            guard let neighbor = map.neighbor(of: tile, toward: direction),
                  case .station(let station)? = map.tile(at: neighbor)?.type
            else { return nil }
            return station
        }.sorted()
    }

    /// Whether `train` is stopped at the station `id`: whether
    /// ``stationsStoppedAt(by:)`` would list `id` for it. Takes the train by
    /// value, so services can ask about the train they are updating.
    func isStopped(_ train: Train, at id: StationID) -> Bool {
        guard case .atNode(let tile, _)? = train.position,
              train.movement.remainingContinuation.isEmpty,
              let station = station(id: id)
        else { return false }
        return TrackDirection(from: tile, to: station.position) != nil
    }
}
