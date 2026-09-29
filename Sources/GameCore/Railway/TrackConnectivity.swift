// Track connectivity is derived from the map on every query. The map's track
// tiles are the only record of the network, so there is no graph, cache or
// index to keep in step with construction: after any command, the next query
// sees the new map.
//
// Two orthogonally adjacent track tiles are joined when each has an exit
// toward the other. An exit alone is not a link: exits toward an empty tile,
// a station, a track without the matching exit, or the map edge are dangling.
// Each track tile is one node. On a plain piece every exit joins all the
// others; a turnout joins its stem to each branch but not the branches to
// each other, and a crossing joins each exit only to the one opposite (Stage
// S1). Which way a train may go on is therefore a question of where it came
// from as well as where it is: see exits(from:facing:).

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

    /// The joined tiles a train at `node` facing `heading` may go on to, in
    /// north, east, south, west order: never straight back (toward the
    /// opposite of `heading`), and only where the piece at `node` joins the
    /// side the train came in by (behind it) to that exit (see
    /// ``TrackLayout``). On a plain piece that is every joined tile but the
    /// one behind. When no exit is behind the train (it was placed facing
    /// away from one), the piece's own rule does not apply.
    ///
    /// Empty when `node` holds no track. Reads at most five tiles.
    public func exits(from node: GridPosition, facing heading: TrackDirection) -> [GridPosition] {
        guard let track = track(at: node) else { return [] }
        let behind = heading.opposite
        let entry = track.connections.contains(TrackConnections(behind)) ? behind : nil
        return connectedNeighbors(of: node).filter { neighbor in
            guard let direction = TrackDirection(from: node, to: neighbor) else { return false }
            return direction != behind && track.layout.joins(entry, to: direction)
        }
    }

    /// Whether a train at `node` facing `heading` may go on to `next` (see
    /// ``exits(from:facing:)``).
    func canPass(from node: GridPosition, facing heading: TrackDirection, to next: GridPosition) -> Bool {
        exits(from: node, facing: heading).contains(next)
    }
}
