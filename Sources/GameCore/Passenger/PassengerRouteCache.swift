// Kept route graphs and route choices for network passenger demand.
//
// Network demand needs every OD pair's route choices whenever its release
// plan is worked out. Before this cache the plan was worked out again at
// the start of every `advance(ticks:)` call, and each pair built the whole
// service graph again. Here the graph and each pair's choices are kept,
// keyed by everything the graph reads: the lines, stations, track network,
// traffic control, train lengths (a controlled single-track line's
// capacity reads its longest train) and each line's service level at the
// current minute (its window and the service day). The service level is
// the only time-of-day input, so a key per level keeps a day's few service
// periods without working them out again.
//
// The cache is derived, never saved, and two worlds compare equal whatever
// their caches hold (like `PassengerPlanCache`). A kept graph is used only
// when its key equals the world's, so the result is the one a fresh graph
// gives: `PassengerRouteCacheTests` checks the kept and fresh plans agree.

/// What ``PassengerRouteGraph/init(world:)`` reads from a world.
struct PassengerRouteGraphKey: Equatable, Sendable {
    let lines: [ServiceLine]
    let stations: [Station]
    let network: RailwayNetwork
    let trafficControl: Bool
    let trains: [TrainID]
    let trainLengths: [Int64]
    let levels: [ServiceLevel?]
}

/// What a network release plan reads besides its graph: the stations'
/// records (whose order gives a flow's record index) and demands, and the
/// fare rules that scale demand.
struct PassengerPlanKey: Equatable, Sendable {
    let graph: PassengerRouteGraphKey
    let records: [StationID]
    let demands: [StationDemand?]
    let economyMode: EconomyMode
    let fareRules: FareRules?
    let fareBaseline: Money
}

struct PassengerODPair: Hashable, Sendable {
    let origin: StationID
    let destination: StationID
}

struct PassengerRouteCache: Equatable, Sendable {
    struct Entry: Sendable {
        let key: PassengerRouteGraphKey
        let graph: PassengerRouteGraph
        /// Each pair's route choices on ``graph``, worked out when first
        /// asked for. Looked up by pair only, never iterated.
        var choices: [PassengerODPair: [PassengerRouteChoice]]

        /// The pair's route choices. The first pair asked for from an
        /// origin works out the choices to every station the graph serves.
        mutating func choices(from origin: StationID, to destination: StationID) -> [PassengerRouteChoice] {
            let pair = PassengerODPair(origin: origin, destination: destination)
            if let kept = choices[pair] { return kept }
            guard graph.stopsAt[origin] != nil, graph.stopsAt[destination] != nil else { return [] }
            let stations = graph.stopsAt.keys.sorted()
            let found = graph.choices(from: origin, to: stations)
            for station in stations where station != origin {
                choices[PassengerODPair(origin: origin, destination: station)] = found[station] ?? []
            }
            return found[destination] ?? []
        }
    }

    /// At most this many graphs are kept, the least recently used dropped
    /// first: enough for every service period of a day (three levels, the
    /// nightly closure and lines with their own windows).
    static let capacity = 8

    /// Least recently used first.
    private(set) var entries: [Entry] = []

    static func == (_: Self, _: Self) -> Bool {
        true
    }

    /// The kept entry for `key`, taken out of the cache, or `nil`.
    mutating func take(_ key: PassengerRouteGraphKey) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        return entries.remove(at: index)
    }

    /// Keeps `entry` as the most recently used.
    mutating func keep(_ entry: Entry) {
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }
}

extension GameWorld {
    /// The key of the graph ``PassengerRouteGraph/init(world:)`` builds now.
    func passengerRouteGraphKey() -> PassengerRouteGraphKey {
        PassengerRouteGraphKey(
            lines: lines, stations: stations, network: network, trafficControl: isTrafficControlEnabled,
            trains: trains.map(\.id), trainLengths: trains.map(\.length),
            levels: lines.map { serviceLevel(of: $0.id, at: clock.now) }
        )
    }

    /// The key of the network release plan ``makePassengerPlan()`` works
    /// out now.
    func passengerPlanKey() -> PassengerPlanKey {
        PassengerPlanKey(
            graph: passengerRouteGraphKey(), records: passengers.map(\.station), demands: passengers.map(\.demand),
            economyMode: accounts.mode, fareRules: accounts.fareRules, fareBaseline: accounts.fareBaseline
        )
    }

    /// The route graph of the world as it is now, with the route choices
    /// kept for it, taken out of the cache (built if none is kept); give it
    /// back with ``PassengerRouteCache/keep(_:)``.
    mutating func takePassengerRouteGraph() -> PassengerRouteCache.Entry {
        let key = passengerRouteGraphKey()
        return passengerRouteCache.take(key)
            ?? PassengerRouteCache.Entry(key: key, graph: PassengerRouteGraph(world: self), choices: [:])
    }
}
