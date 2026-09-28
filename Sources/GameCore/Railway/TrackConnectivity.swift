// Track connectivity is derived from the map on every query. The map's track
// tiles are the only record of the network, so there is no graph, cache or
// index to keep in step with construction: after any command, the next query
// sees the new map.
//
// Two orthogonally adjacent track tiles are joined when each has an exit
// toward the other. An exit alone is not a link: exits toward an empty tile,
// a station, a track without the matching exit, or the map edge are dangling.
// Each track tile is one node, so every exit of a three- or four-exit piece
// joins all the others; crossings without a junction are not modelled.

extension GameWorld {
    /// The track tiles joined to the track at `position`, in north, east,
    /// south, west order.
    ///
    /// Every joined neighbour is listed, including the one a train would have
    /// come from; choosing among them is not part of this query. Returns an
    /// empty array when `position` is outside the map or holds no track (an
    /// empty tile or a station).
    ///
    /// Reads at most five tiles and never scans the map.
    public func connectedNeighbors(of position: GridPosition) -> [GridPosition] {
        guard let track = track(at: position) else { return [] }
        return track.connections.directions.compactMap { direction in
            guard let neighbor = map.neighbor(of: position, toward: direction),
                  let neighborTrack = self.track(at: neighbor),
                  neighborTrack.connections.contains(TrackConnections(direction.opposite))
            else { return nil }
            return neighbor
        }
    }

    /// Whether the tracks at `position` and `other` are joined: they are
    /// orthogonal neighbours and each has an exit toward the other.
    ///
    /// Symmetric in its arguments. `false` for the same tile, diagonal or more
    /// distant tiles, positions outside the map, and tiles without track.
    public func isConnected(_ position: GridPosition, to other: GridPosition) -> Bool {
        connectedNeighbors(of: position).contains(other)
    }
}
