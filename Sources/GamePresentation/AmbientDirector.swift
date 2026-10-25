import GameCore

/// Decision 414: the idle mode's director (放空模式). Once the player turns
/// it on, the camera moves by itself between the player's own trains,
/// stations and lines, using the follow views the game already has (the
/// 2D map following a train, decision 219; the 3D map following one,
/// decisions 333, 337 and 403), while the music plays on and the controls
/// are put away. A tap anywhere ends it.
///
/// Ported from the owner's Taiwan rail site (`Railway/site_archive_clean/
/// index.html`, `#ambientBtn`): `pickTourTrain` picks a running train
/// weighted towards the rarer kinds and not one of the last five shown
/// (`TOUR_RECENT`), follows it for 60–120 s (`nextTourTrain`), and cuts to
/// the next through a dark veil (`fadeSwitch`, 0.7 s each way). The site
/// has no stations or lines of a player's to show; the shots of those are
/// this game's own.
///
/// Only view state, never part of the world: the app asks ``update(cast:now:allows3D:)``
/// about once a second with the wall clock (seconds), and cuts to the shot
/// it returns. It draws its choices from its own seeded generator, so a
/// test can replay them; the app seeds it from the clock.
public struct AmbientDirector: Equatable, Sendable {
    /// What a shot looks at.
    public enum Subject: Hashable, Sendable {
        case train(TrainID)
        case station(StationID)
        case line(LineID)
    }

    /// Where a shot is seen: the 2D map, or the 3D map following a train
    /// from one of its views.
    public enum Stage: Hashable, Sendable {
        case map2D
        case map3D(Map3DFollow.View)
    }

    /// One shot: what it looks at, where, and for how long (seconds of
    /// the wall clock).
    public struct Shot: Hashable, Sendable {
        public let subject: Subject
        public let stage: Stage
        public let seconds: Double

        public init(subject: Subject, stage: Stage, seconds: Double) {
            self.subject = subject
            self.stage = stage
            self.seconds = seconds
        }
    }

    /// What there is to show, read from the world each time
    /// (``init(world:)``): the trains on the track, the stations and the
    /// lines, each with what makes it more worth a look.
    public struct Cast: Equatable, Sendable {
        /// A train on the track and the line it runs for (`nil`: none).
        public struct Train: Equatable, Sendable {
            public let id: TrainID
            public let line: LineID?
            public init(id: TrainID, line: LineID?) {
                self.id = id
                self.line = line
            }
        }

        /// A station and how many wait there.
        public struct Station: Equatable, Sendable {
            public let id: StationID
            public let waiting: Int64
            public init(id: StationID, waiting: Int64) {
                self.id = id
                self.waiting = waiting
            }
        }

        /// A line of two stops or more and how many trains run on it.
        public struct Line: Equatable, Sendable {
            public let id: LineID
            public let trains: Int
            public init(id: LineID, trains: Int) {
                self.id = id
                self.trains = trains
            }
        }

        public let trains: [Train]
        public let stations: [Station]
        public let lines: [Line]

        public init(trains: [Train], stations: [Station], lines: [Line]) {
            self.trains = trains
            self.stations = stations
            self.lines = lines
        }

        /// The world's trains on the track (the ones a follow can hold:
        /// ``GameSession/followTrain(_:)`` needs a position), its stations
        /// apart from depots, and its lines of two stops or more, in ID
        /// order.
        public init(world: GameWorld) {
            let running = world.trains.filter { $0.position != nil }.sorted { $0.id < $1.id }
            trains = running.map { Train(id: $0.id, line: world.assignedLine(of: $0.id)) }
            stations = world.stations.filter { !$0.isDepot }.sorted { $0.id < $1.id }.map { station in
                Station(id: station.id, waiting: world.waitingPassengers(at: station.id).reduce(0) { $0 + $1.count })
            }
            lines = world.lines.filter { $0.stops.count >= 2 }.sorted { $0.id < $1.id }.map { line in
                Line(id: line.id, trains: running.reduce(0) { $0 + (line.trains.contains($1.id) ? 1 : 0) })
            }
        }

        /// Whether there is anything to show: a station at least.
        public var isEmpty: Bool { stations.isEmpty }

        func holds(_ subject: Subject) -> Bool {
            switch subject {
            case .train(let id): trains.contains { $0.id == id }
            case .station(let id): stations.contains { $0.id == id }
            case .line(let id): lines.contains { $0.id == id }
            }
        }
    }

    // MARK: - The rules

    /// How long a train is followed: the site's 60–120 s.
    public static let trainSeconds: ClosedRange<Double> = 60...120
    /// How long a station or a line is looked at: long enough to see a
    /// train or two come and go at 1×, short beside a train's.
    public static let stillSeconds: ClosedRange<Double> = 20...30
    /// How many of the last shown are not shown again while there are
    /// others: the site's `TOUR_RECENT`.
    public static let recent = 5
    /// The order of the kinds of shot, round and round: trains most of
    /// the time, a station and a line between.
    public static let pattern: [Kind] = [.train, .train, .station, .train, .line]
    /// The 3D views a train is followed from, in turn, every other train
    /// shot: beside it first (the site's 9/7 change: "貼著車身的立體視角"),
    /// then behind, from the station ahead, above behind and from the cab.
    public static let views3D: [Map3DFollow.View] = [.side, .back, .station, .aboveBack, .cab]
    /// How far round a station its shot shows, each way (metres): the
    /// station, its platforms and the track either side.
    public static let stationReach = 600.0
    /// How far round a line's stops its shot shows past them (metres).
    public static let lineMargin = 400.0

    /// A kind of shot.
    public enum Kind: Hashable, Sendable {
        case train, station, line
    }

    // MARK: - State

    /// The shot on screen; `nil` before the first.
    public private(set) var shot: Shot?
    /// When it started (wall clock, seconds).
    public private(set) var startedAt: Double = 0
    private var shots = 0
    private var trainShots = 0
    private var recentTrains: [TrainID] = []
    private var recentStations: [StationID] = []
    private var recentLines: [LineID] = []
    private var random: SplitMix

    public init(seed: UInt64) {
        random = SplitMix(seed: seed)
    }

    /// Whether the idle mode can start: the world has a station to show.
    public static func isAvailable(in world: GameWorld) -> Bool {
        world.stations.contains { !$0.isDepot }
    }

    /// The next shot when it is time for one, else `nil` (keep the one on
    /// screen): at the start, when the shot's time is up, or when what it
    /// looks at has gone (the train left the track, the line was closed).
    /// `allows3D`: the 3D map may be used (it is on in Settings, and
    /// Reduce Motion is off: the 3D follow camera turns with the train and
    /// flies between views).
    public mutating func update(cast: Cast, now: Double, allows3D: Bool) -> Shot? {
        if let shot, now - startedAt < shot.seconds, cast.holds(shot.subject),
           allows3D || shot.stage == .map2D {
            return nil
        }
        guard let next = pick(cast: cast, allows3D: allows3D) else {
            shot = nil
            return nil
        }
        shot = next
        startedAt = now
        return next
    }

    private mutating func pick(cast: Cast, allows3D: Bool) -> Shot? {
        guard !cast.isEmpty else { return nil }
        // The pattern's kind, or the next of it there is something for.
        for step in 0..<Self.pattern.count {
            let kind = Self.pattern[(shots + step) % Self.pattern.count]
            if let shot = pick(kind, cast: cast, allows3D: allows3D) {
                shots += step + 1
                return shot
            }
        }
        return nil
    }

    private mutating func pick(_ kind: Kind, cast: Cast, allows3D: Bool) -> Shot? {
        switch kind {
        case .train:
            // Each line as often as another, whatever trains it runs, as the
            // site weights its rarer kinds of train up; a train on no line
            // counts as a line of its own.
            var perLine: [LineID?: Int] = [:]
            for train in cast.trains { perLine[train.line, default: 0] += 1 }
            guard let train = choose(cast.trains, avoiding: recentTrains, id: \.id, weight: { 1 / Double(perLine[$0.line] ?? 1) })
            else { return nil }
            remember(train.id, in: &recentTrains)
            let stage: Stage = allows3D && trainShots % 2 == 0
                ? .map3D(Self.views3D[(trainShots / 2) % Self.views3D.count]) : .map2D
            trainShots += 1
            return Shot(subject: .train(train.id), stage: stage, seconds: seconds(in: Self.trainSeconds))
        case .station:
            // The busier, the likelier: where people wait, trains come.
            guard let station = choose(cast.stations, avoiding: recentStations, id: \.id, weight: { 1 + Double($0.waiting).squareRoot() })
            else { return nil }
            remember(station.id, in: &recentStations)
            return Shot(subject: .station(station.id), stage: .map2D, seconds: seconds(in: Self.stillSeconds))
        case .line:
            guard let line = choose(cast.lines, avoiding: recentLines, id: \.id, weight: { 1 + Double($0.trains) }) else { return nil }
            remember(line.id, in: &recentLines)
            return Shot(subject: .line(line.id), stage: .map2D, seconds: seconds(in: Self.stillSeconds))
        }
    }

    /// One of `items`, by `weight`, not one of the `recent` while there are
    /// others; `nil` for none.
    private mutating func choose<Item, ID: Equatable>(
        _ items: [Item], avoiding recent: [ID], id: (Item) -> ID, weight: (Item) -> Double
    ) -> Item? {
        let fresh = items.filter { !recent.contains(id($0)) }
        let candidates = fresh.isEmpty ? items : fresh
        guard !candidates.isEmpty else { return nil }
        let weights = candidates.map(weight)
        var left = random.unit() * weights.reduce(0, +)
        for (item, weight) in zip(candidates, weights) {
            left -= weight
            if left < 0 { return item }
        }
        return candidates.last
    }

    private func remember<ID>(_ id: ID, in list: inout [ID]) {
        list.append(id)
        if list.count > Self.recent { list.removeFirst(list.count - Self.recent) }
    }

    private mutating func seconds(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + random.unit() * (range.upperBound - range.lowerBound)
    }

    // MARK: - Where a still shot looks

    /// The part of the map a station's or a line's shot shows: the station
    /// and ``stationReach`` round it; the line's stops and ``lineMargin``
    /// past them. `nil` for a train (followed instead) or one gone.
    public static func region(of subject: Subject, in world: GameWorld) -> WorldRegion? {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        switch subject {
        case .train:
            return nil
        case .station(let id):
            guard let station = world.station(id: id) else { return nil }
            let reach = stationReach * metre
            let x = Double(station.location.x), y = Double(station.location.y)
            return WorldRegion(minX: x - reach, minY: y - reach, maxX: x + reach, maxY: y + reach)
        case .line(let id):
            guard let line = world.lines.first(where: { $0.id == id }) else { return nil }
            let stops = line.stops.compactMap { world.station(id: $0) }.map { WorldCoordinate(x: $0.location.x, y: $0.location.y) }
            return WorldRegion(enclosing: stops)?.expanded(by: lineMargin * metre)
        }
    }

    /// What the shot shows, for the line under it: the train's name and
    /// its line's, the station's name, or the line's.
    public static func caption(of subject: Subject, in world: GameWorld, language: DisplayLanguage) -> String? {
        switch subject {
        case .train(let id):
            guard let train = world.train(id: id) else { return nil }
            guard let line = world.assignedLine(of: id).flatMap({ id in world.lines.first { $0.id == id } }) else { return train.name }
            return language.text("\(line.name) · \(train.name)", "\(line.name)・\(train.name)")
        case .station(let id):
            return world.station(id: id)?.name
        case .line(let id):
            return world.lines.first { $0.id == id }?.name
        }
    }
}

/// A small seeded generator (SplitMix64), for the director's choices to
/// replay in a test. Not the world's: the world draws nothing at random.
struct SplitMix: Equatable, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
