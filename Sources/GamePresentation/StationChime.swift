import GameCore

/// Which of the official arrival chimes a station rings (decision 219,
/// stage 1; the cases are GameCore's, decision 866). Worked out from the
/// world each time: the chime the player set the station to ring
/// (``Station/chime``), or else the one its place in the network calls for.
extension StationChime {
    /// The chime `station` rings in `world`: the one the player set it to
    /// ring, or else ``automatic(_:in:)``'s.
    public static func of(_ station: StationID, in world: GameWorld) -> StationChime {
        world.station(id: station)?.chime ?? automatic(station, in: world)
    }

    /// The chime a station's place in the network calls for, which it
    /// rings unless the player set another: tourist before metro before
    /// local (tourist stations are fewer and their chime the easiest to
    /// remember). A station that no longer exists rings the local chime.
    public static func automatic(_ station: StationID, in world: GameWorld) -> StationChime {
        guard let point = world.station(id: station)?.point else { return .local }
        if let attractions = world.tourism?.attractions {
            let reach = Tourism.reach
            let near = attractions.contains { attraction in
                let dx = attraction.point.x - point.x, dy = attraction.point.y - point.y
                return dx * dx + dy * dy <= reach * reach
            }
            if near { return .tourist }
        }
        var lines = 0
        for line in world.lines where !line.isFreight && line.stops.contains(station) {
            if line.isHighSpeed { return .metro }
            lines += 1
        }
        return lines >= 2 ? .metro : .local
    }
}
