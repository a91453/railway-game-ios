import GameCore

/// Decision 853 (decision 219, stage 2): the melody a line plays as a
/// train's doors start closing, for a train the player is looking at, at
/// 60× and slower. Six melodies written for the game
/// (`tools/audio/scores/departure-*.score.json`, played on the music's
/// sampled piano), in three pairs over the same accompanying instrument
/// (decision 868): each line has one pair, the same every time, and each
/// of its stations plays one of the two, so a line the player knows sounds
/// like itself without every station sounding alike, unless the station
/// the train leaves was set to play another (decision 866,
/// ``Station/departureMelody``). The cases are GameCore's (decision 866).
/// Worked out each time.
extension DepartureMelody {
    /// The slowest speed it plays at no longer: at 600× a train stands at a
    /// station for a second or less (the research note's §6).
    public static let upTo: GameSpeed = .x60

    /// The first melody of each pair (decision 853's three), which
    /// ``of(lineNamed:)`` picks among.
    static let firsts: [DepartureMelody] = [.a, .b, .c]

    /// The other melody of its pair (decision 868): the one over the same
    /// accompanying instrument, `a` and `d` over the harp, `b` and `e`
    /// over pizzicato strings, `c` and `f` over the harp and soft strings.
    public var companion: DepartureMelody {
        switch self {
        case .a: .d
        case .b: .e
        case .c: .f
        case .d: .a
        case .e: .b
        case .f: .c
        }
    }

    /// The FNV-1a hash of `text`, as the reference's `HsrAmbience` picks a
    /// station's variation (decision 219).
    private static func hash(_ text: String) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash
    }

    /// The melody of the line called `name`, the first of its pair: a hash
    /// of its name picks one, so a real line keeps its melody whatever
    /// order it was bought in (and the one it had before decision 868).
    public static func of(lineNamed name: String) -> DepartureMelody {
        firsts[Int(hash(name) % UInt32(firsts.count))]
    }

    /// The melody the line called `line` plays at the station called
    /// `station` (decision 868, the research note's §2.4): the line's
    /// melody or its companion, which of the two a hash of the station's
    /// name picks, so the stations along a line do not all sound alike and
    /// each keeps its own.
    public static func of(lineNamed line: String, atStationNamed station: String) -> DepartureMelody {
        let melody = of(lineNamed: line)
        return hash(station) % 2 == 0 ? melody : melody.companion
    }

    /// The melody train `id` plays leaving `station` in `world`: the one
    /// the player set the station to play (decision 866), or else the
    /// train's line's there (``of(lineNamed:atStationNamed:)``), or, for a
    /// train on no line (a timetable of its own) or at no station, the
    /// line's first, ``of(_:in:)``.
    public static func of(_ id: TrainID, at station: StationID?, in world: GameWorld) -> DepartureMelody {
        guard let station = station.flatMap({ world.station(id: $0) }) else { return of(id, in: world) }
        if let chosen = station.departureMelody { return chosen }
        guard let line = world.assignedLine(of: id).flatMap({ world.line(id: $0) }) else { return .a }
        return of(lineNamed: line.name, atStationNamed: station.name)
    }

    /// Decision 883: what train `id` plays leaving `station` in `world`:
    /// the notes of the player melody the station is set to, or else
    /// ``of(_:at:in:)``.
    public static func cue(_ id: TrainID, at station: StationID?, in world: GameWorld) -> SoundCue {
        if let melody = station.flatMap({ world.station(id: $0)?.playerMelody }).flatMap({ world.playerMelody(id: $0) }) {
            return .playerDeparture(melody.notes)
        }
        return .departure(of(id, at: station, in: world))
    }

    /// The melody of train `id`'s line in `world`, or, for a train on no
    /// line (a timetable of its own), the first melody.
    public static func of(_ id: TrainID, in world: GameWorld) -> DepartureMelody {
        guard let line = world.assignedLine(of: id).flatMap({ world.line(id: $0) }) else { return .a }
        return of(lineNamed: line.name)
    }

    /// A call whose doors started closing: the train and when it arrived
    /// there (which, with the train, names the call), and the station it
    /// stands at (decision 866: which melody plays is the station's).
    public struct Closing: Hashable, Sendable {
        public var train: TrainID
        public var arrival: GameTime
        public var station: StationID?
    }

    /// The calls of the trains `watched` whose doors started closing
    /// between `before` and `after`, in train order: a train whose doors
    /// are closing now, or one that stood with its doors still open
    /// before and has left since (at 60× the doors close within a tick or
    /// two, which a step can hold). Not the last call of a service: a
    /// train that ends there does not leave with its passengers.
    static func closings(from before: GameWorld, to after: GameWorld, watched: Set<TrainID>) -> [Closing] {
        func leaves(_ train: Train) -> Bool {
            guard case .waitingAtStop(let stop, _)? = train.execution else { return false }
            return stop < train.timetable.count - 1
        }
        func station(_ train: Train) -> StationID? {
            guard case .waitingAtStop(let stop, _)? = train.execution, train.timetable.indices.contains(stop) else { return nil }
            return train.timetable[stop].station
        }
        return watched.sorted().compactMap { id in
            let now = after.train(id: id)
            if let now, let times = now.times, times.closing != nil, leaves(now) {
                return Closing(train: id, arrival: times.arrival, station: station(now))
            }
            guard let earlier = before.train(id: id), let times = earlier.times, times.closing == nil,
                  leaves(earlier), times.exchangeEnd != nil, now?.execution != earlier.execution
            else { return nil }
            return Closing(train: id, arrival: times.arrival, station: station(earlier))
        }
    }
}
