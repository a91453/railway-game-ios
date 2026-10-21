import GameCore

/// A sound the app plays for something that happened in the game: the
/// sounds of the first promo video, so the game sounds as the video does
/// (`tools/audio/`). Only what to play: the app plays it, and the player
/// can turn the sounds off. Never part of the world, never saved.
public enum SoundCue: Hashable, Sendable {
    /// A train in service arrived at a station: the station's chime.
    /// `watched` when one of the trains is one the player is looking at
    /// (``GameSession/watchedTrainIDs``); the app rings the others quieter
    /// and less often, so a busy network does not ring all the time.
    ///
    /// Decision 219: for a watched train, `chime` is the station's
    /// (``StationChime``), and `motif` plays only its first notes, at 600×
    /// and faster (``arrivalCue(for:watched:speed:in:)``).
    case arrival(watched: Bool, chime: StationChime = .local, motif: Bool = false)
    /// Track was built: a rail joint.
    case track
    /// The player moved to another tool, or into or out of a game: a whoosh.
    case transition
    /// The player put up a building or a platform (decision 117): a
    /// rising pluck over a soft thud.
    case built
    /// Fares or rent came in (decision 117): a bright double ding.
    case income
    /// The game refused what the player asked (a failure message,
    /// decision 184): two soft low plucks, falling.
    case refused
    /// A new worry in the news log (decision 184: debt, a deadline, a
    /// typhoon, a town short of materials): two short bells.
    case warning
    /// A challenge's goal or a city's request was met (decision 256): a
    /// short rising tune on the metro chime's phrase.
    case goalMet
    /// A real line was bought (decision 315): the local station chime's
    /// two notes, a cadence onto the tonic and a low stamp.
    case lineAcquired

    /// When each train in service last arrived at a call, as its service
    /// times record it (`ServiceTimes/arrival`), and whether it stands at
    /// its timetable's last call, by train. Taken before the world advances
    /// and compared after it with ``trainsArrived(since:in:)``.
    static func arrivals(in world: GameWorld) -> [TrainID: Arrival] {
        var arrivals: [TrainID: Arrival] = [:]
        for train in world.trains {
            if let times = train.times {
                let atLastCall = if case .waitingAtStop(let stop, _) = train.execution { stop == train.timetable.count - 1 } else { false }
                arrivals[train.id] = Arrival(time: times.arrival, atLastCall: atLastCall, lastCall: train.timetable.last?.station)
            }
        }
        return arrivals
    }

    /// A train's last arrival before a step (``arrivals(in:)``).
    struct Arrival: Hashable, Sendable {
        var time: GameTime
        var atLastCall: Bool
        /// The station of its timetable's last call: where a service that
        /// completes within the step arrived last (decision 219).
        var lastCall: StationID?
    }

    /// A train that arrived within a step, and at which station, when it
    /// is known (decision 219).
    struct ArrivedTrain: Hashable, Sendable {
        var train: TrainID
        var station: StationID?
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
    ///
    /// Decision 219: each with the station it arrived at. A train standing
    /// at a call arrived at that call's station; one already on its way
    /// again (it arrived and left within the step) arrived at the call it
    /// left, the one before the call it heads for; one that completed its
    /// service arrived at its last call.
    static func trainsArrived(since before: [TrainID: Arrival], in world: GameWorld) -> [ArrivedTrain] {
        world.trains.compactMap { train in
            guard let times = train.times, let departure = times.departure else {
                guard let earlier = before[train.id], !earlier.atLastCall else { return nil }
                // Still the same send-out, not left yet: no arrival.
                return train.times?.arrival == earlier.time ? nil : ArrivedTrain(train: train.id, station: earlier.lastCall)
            }
            let arrived: Bool
            if let earlier = before[train.id] {
                arrived = earlier.time != times.arrival
            } else {
                arrived = times.arrival >= departure
            }
            return arrived ? ArrivedTrain(train: train.id, station: station(arrivedAtBy: train)) : nil
        }
    }

    /// The station of the call a train in service last arrived at: the one
    /// it stands at, or the one before the call it heads for.
    private static func station(arrivedAtBy train: Train) -> StationID? {
        let timetable = train.timetable
        switch train.execution {
        case .waitingAtStop(let stop, _)?:
            return timetable.indices.contains(stop) ? timetable[stop].station : nil
        case .travellingToStop(let stop, _)?:
            let left = stop > 0 ? stop - 1 : timetable.count - 1
            return timetable.indices.contains(left) ? timetable[left].station : nil
        case nil:
            return nil
        }
    }

    /// The one sound for the trains that arrived within a step, or `nil`
    /// (decision 219, the research note's §6). The station's chime
    /// (``StationChime``) and its motif are for a watched train only:
    ///
    /// - a watched train rings its station's whole chime at 60× and
    ///   slower, and its motif, the first two or three notes, at 600× and
    ///   faster (stations are a second or two apart);
    /// - the others ring the local chime, quieter, at every speed, as
    ///   before (the app rings them at most every few seconds).
    ///
    /// A station not known rings the local chime.
    static func arrivalCue(for arrived: [ArrivedTrain], watched: Set<TrainID>, speed: GameSpeed, in world: GameWorld) -> SoundCue? {
        guard !arrived.isEmpty else { return nil }
        guard let seen = arrived.first(where: { watched.contains($0.train) }) else { return .arrival(watched: false) }
        let chime = seen.station.map { StationChime.of($0, in: world) } ?? .local
        return .arrival(watched: true, chime: chime, motif: speed.tenthsPerTick >= GameSpeed.normal.tenthsPerTick)
    }

    /// The file the app plays for the cue, in its bundle's `Audio`
    /// resources (made by `tools/audio/make_game_audio.py`, listed in
    /// `tools/audio/manifest.json`).
    public var resource: (name: String, extension: String) {
        switch self {
        case .arrival(_, let chime, true): ("chime-\(chime.rawValue)-motif", "wav")
        case .arrival(_, .local, false): ("station-chime", "wav")
        case .arrival(_, let chime, false): ("chime-\(chime.rawValue)", "wav")
        case .track: ("rail-joint", "wav")
        case .transition: ("whoosh", "wav")
        case .built: ("build-done", "wav")
        case .income: ("coins", "wav")
        case .refused: ("refused", "wav")
        case .warning: ("warning", "wav")
        case .goalMet: ("goal-met", "wav")
        case .lineAcquired: ("line-acquired", "wav")
        }
    }
}
