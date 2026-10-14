import GameCore

/// Which of the official arrival chimes a station rings (decision 219,
/// stage 1): worked out from the world each time, never saved. Stage 2 lets
/// the player choose a station's chime; until then every station rings the
/// one its place in the network calls for.
public enum StationChime: String, CaseIterable, Hashable, Sendable {
    /// A small station: the two-note bell (`station-chime.wav`).
    case local
    /// An interchange: two passenger lines or more call there, or a high
    /// speed line does. The four-note bell of the reference's airport
    /// announcements, C5–E5–G5–C6.
    case metro
    /// An attraction is within the station's catchment (decision 174): a
    /// light plucked phrase on the C major pentatonic scale.
    case tourist

    /// The chime `station` rings in `world`: tourist before metro before
    /// local (tourist stations are fewer and their chime the easiest to
    /// remember). A station that no longer exists rings the local chime.
    public static func of(_ station: StationID, in world: GameWorld) -> StationChime {
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
