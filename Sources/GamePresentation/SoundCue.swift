import GameCore

/// A sound the app plays for something that happened in the game: the
/// sounds of the first promo video, so the game sounds as the video does
/// (`tools/audio/`). Only what to play: the app plays it, and the player
/// can turn the sounds off. Never part of the world, never saved.
public enum SoundCue: Hashable, Sendable {
    /// A train in service arrived at a station: the station chime.
    case arrival
    /// Track was built: a rail joint.
    case track
    /// The player moved to another tool, or into or out of a game: a whoosh.
    case transition

    /// When each train in service last arrived at a call, as its service
    /// times record it (`ServiceTimes/arrival`), by train. Taken before the
    /// world advances and compared after it with ``arrived(since:in:)``.
    static func arrivals(in world: GameWorld) -> [TrainID: GameTime] {
        var arrivals: [TrainID: GameTime] = [:]
        for train in world.trains {
            if let times = train.times {
                arrivals[train.id] = times.arrival
            }
        }
        return arrivals
    }

    /// Whether a train in service arrived at a call in `world` since
    /// `before` (``arrivals(in:)`` of the same world earlier): one whose
    /// service times record an arrival they did not then.
    ///
    /// Starting a service, or a line sending a train out, counts as
    /// arriving at its first call in GameCore, but the train has not left
    /// a call of that service yet (`ServiceTimes/departure` is `nil`), so it
    /// does not chime. A train that arrives and leaves again within one
    /// step still chimes: its arrival time has changed.
    static func arrived(since before: [TrainID: GameTime], in world: GameWorld) -> Bool {
        world.trains.contains { train in
            guard let times = train.times, times.departure != nil else { return false }
            return before[train.id] != times.arrival
        }
    }
}
