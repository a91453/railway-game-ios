// Crowding in route choice and the generalized cost's effect on demand
// (Phase 5F, network routing only).
//
// The owner's reference has no implementation to port here: the `Ci/`
// snapshot reads its route shares (`choiceProb`) from a flow service that
// is not in the snapshot and only reports load factors
// (`metroEconomyCollectCrowdingMetrics`), and the RailwayCore pack
// (`Railway/railway_game_reference_clean/01_MIGRATION_MAP.md` §6) names the
// link graph's fields (travel time, frequency, offered and used capacity,
// transfer penalty) and asks for a shortest generalized cost with
// deterministic assignment, without a formula. The rules below are native
// and integer-only, so every platform plans the same:
//
// - Offered capacity: a service path's trains a day (each service level's
//   open minutes in the line's window divided by its headway at that level)
//   times a train's operational capacity (``Train/capacity``, the
//   reference's rated load × 1.1). A line with no train assigned counts the
//   reference's six-car train.
// - Used capacity: the plan's daily trips, shared among each pair's route
//   choices by their uncrowded weights (largest remainder), added on every
//   ride segment they use. One plan's own loads, so a plan is a function of
//   the world alone: saving, loading and batching change nothing.
// - Crowding: each segment's ride time grows by the Bureau of Public Roads
//   link cost function, 0.15 × (used / offered)^4, the ratio capped at 2.
//   A choice's weight is then the inverse of its crowded cost, as the
//   uncrowded weight is of its uncrowded cost: one step of an incremental
//   assignment.
// - Demand: a pair's daily trips keep 1000‰ while its fastest route takes
//   at most ``PassengerCrowding/fullDemandMinutes``, and fall in inverse
//   proportion beyond (twice as long, half the trips), rounded half up.

enum PassengerCrowding {
    /// Generalized minutes up to which a pair keeps all its trips.
    static let fullDemandMinutes: Int64 = 30

    /// The reference's six-car train (`{cars: 6, cap: 1920}`) at its
    /// operational load: what a line with no train assigned is counted to
    /// carry.
    static let defaultTrainCapacity: Int64 = 6 * Train.capacityPerCar

    /// The highest load ratio, in thousandths, crowding counts.
    static let maximumLoad: Int64 = 2_000

    /// `trips` as a pair whose fastest route takes `minutes` keeps them.
    static func decayed(_ trips: Int64, minutes: Int64) -> Int64 {
        guard trips > 0, minutes > fullDemandMinutes else { return trips }
        let factor = 1_000 * fullDemandMinutes / minutes
        return (trips * factor + 500) / 1_000
    }

    /// The seconds crowding adds to a ride of `seconds` on a segment loaded
    /// `load` thousandths of its capacity: `seconds × 0.15 × (load/1000)^4`.
    static func crowdingSeconds(_ seconds: Int64, load: Int64) -> Int64 {
        let x = min(max(0, load), maximumLoad)
        let square = x * x / 1_000
        let fourth = square * square / 1_000
        return seconds * 15 * fourth / 100_000
    }

    /// Passengers `line`'s service `service` carries a day each way.
    static func dailyCapacity(of line: ServiceLine, service: Int, in world: GameWorld) -> Int64 {
        let pattern = service == 0 ? nil : service - 1
        var minutes: [ServiceLevel: Int64] = [:]
        for minute in 0..<1_440 where line.window.contains(minuteOfDay: minute) {
            minutes[world.serviceDay.level(atMinuteOfDay: minute), default: 0] += 1
        }
        var trains: Int64 = 0
        for level in ServiceLevel.allCases {
            guard let open = minutes[level], let headway = world.lineHeadway(line.id, at: level, pattern: pattern),
                  headway > 0 else { continue }
            trains += open / headway
        }
        let assigned = service == 0 ? line.trains : line.patterns[service - 1].trains
        let capacity = assigned.compactMap { world.train(id: $0)?.capacity }.max()
            ?? (line.trains + line.patterns.flatMap(\.trains)).compactMap { world.train(id: $0)?.capacity }.max()
            ?? defaultTrainCapacity
        return trains * capacity
    }
}

extension PassengerRouteGraph {
    /// The ride segments `route` uses, as the index of the call each one
    /// leaves (see ``offsets``), with its running seconds; `nil` if a leg
    /// is not on this graph.
    func segments(of route: PassengerRoute) -> [(segment: Int, seconds: Int64, path: Int)]? {
        var result: [(segment: Int, seconds: Int64, path: Int)] = []
        for leg in route.legs {
            guard let path = paths.indices.first(where: {
                paths[$0].line == leg.line && paths[$0].pattern == leg.pattern && paths[$0].direction == leg.direction
            }), let from = paths[path].stations.firstIndex(of: leg.from),
                  let to = paths[path].stations[(from + 1)...].firstIndex(of: leg.to) else { return nil }
            for stop in from..<to {
                result.append((offsets[path] + stop, paths[path].runSeconds[stop], path))
            }
        }
        return result
    }
}
