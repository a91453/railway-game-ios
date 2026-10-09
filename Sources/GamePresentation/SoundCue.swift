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
    /// The player put up a building or a platform (decision 117): a
    /// rising pluck over a soft thud.
    case built
    /// Fares or rent came in (decision 117): a bright double ding.
    case income

    /// When each train in service last arrived at a call, as its service
    /// times record it (`ServiceTimes/arrival`), and whether it stands at
    /// its timetable's last call, by train. Taken before the world advances
    /// and compared after it with ``trainsArrived(since:in:)``.
    static func arrivals(in world: GameWorld) -> [TrainID: Arrival] {
        var arrivals: [TrainID: Arrival] = [:]
        for train in world.trains {
            if let times = train.times {
                let atLastCall = if case .waitingAtStop(let stop, _) = train.execution { stop == train.timetable.count - 1 } else { false }
                arrivals[train.id] = Arrival(time: times.arrival, atLastCall: atLastCall)
            }
        }
        return arrivals
    }

    /// A train's last arrival before a step (``arrivals(in:)``).
    struct Arrival: Hashable, Sendable {
        var time: GameTime
        var atLastCall: Bool
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
    ///
    /// A train in service before the step that now has no service times
    /// (or another service that has left no call yet) completed its
    /// service within the step (and a line may have sent it out again).
    /// Completing means leaving the last call, so unless it already stood
    /// there before the step, it arrived there within the step: that
    /// arrival counts too. GameCore keeps no times of a completed service,
    /// and a loop step can hold several ticks
    /// (``GameSession/maximumStepDuration``).
    static func trainsArrived(since before: [TrainID: Arrival], in world: GameWorld) -> [TrainID] {
        world.trains.compactMap { train in
            guard let times = train.times, let departure = times.departure else {
                guard let earlier = before[train.id], !earlier.atLastCall else { return nil }
                // Still the same send-out, not left yet: no arrival.
                return train.times?.arrival == earlier.time ? nil : train.id
            }
            if let earlier = before[train.id] {
                return earlier.time != times.arrival ? train.id : nil
            }
            return times.arrival >= departure ? train.id : nil
        }
    }
}
