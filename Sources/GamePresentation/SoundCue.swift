import GameCore

/// A sound the app plays for something that happened in the game: the
/// sounds of the first promo video, so the game sounds as the video does
/// (`tools/audio/`). Only what to play: the app plays it, and the player
/// can turn the sounds off. Never part of the world, never saved.
public enum SoundCue: Hashable, Sendable {
    /// A train in service arrived at a station: the station chime.
    /// `watched` when one of the trains is one the player is looking at
    /// (``GameSession/watchedTrainIDs``); the app rings the others quieter
    /// and less often, so a busy network does not ring all the time.
    case arrival(watched: Bool)
    /// Track was built: a rail joint.
    case track
    /// The player moved to another tool, or into or out of a game: a whoosh.
    case transition

    /// When each train in service last arrived at a call, as its service
    /// times record it (`ServiceTimes/arrival`), by train. Taken before the
    /// world advances and compared after it with ``trainsArrived(since:in:)``.
    static func arrivals(in world: GameWorld) -> [TrainID: GameTime] {
        var arrivals: [TrainID: GameTime] = [:]
        for train in world.trains {
            if let times = train.times {
                arrivals[train.id] = times.arrival
            }
        }
        return arrivals
    }

    /// The trains in service that arrived at a call in `world` since
    /// `before` (``arrivals(in:)`` of the same world earlier), in train
    /// order.
    ///
    /// Starting a service, or a line sending a train out, counts as
    /// arriving at its first call in GameCore, and the train has left no
    /// call of that service yet (`ServiceTimes/departure` is `nil`): that
    /// is not an arrival. For a train already in service before, a new
    /// arrival time is an arrival, even one it has left again within the
    /// same step. A train whose service started within the step arrived
    /// somewhere only if it now stands at a later call, reached no earlier
    /// than it left the one before (`arrival >= departure`); one still on
    /// its way from its first call has `arrival < departure`. (At 600× a
    /// line sends a train out at a minute and it leaves 42 s later, within
    /// the same tick.)
    static func trainsArrived(since before: [TrainID: GameTime], in world: GameWorld) -> [TrainID] {
        world.trains.compactMap { train in
            guard let times = train.times, let departure = times.departure else { return nil }
            if let earlier = before[train.id] {
                return earlier != times.arrival ? train.id : nil
            }
            return times.arrival >= departure ? train.id : nil
        }
    }
}
