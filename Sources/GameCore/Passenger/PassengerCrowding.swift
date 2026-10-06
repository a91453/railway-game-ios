// Crowding in route choice and the generalized cost's effect on demand
// (Phase 5F, network routing only).
//
// NATIVE RULES. The owner's reference has no implementation to port here:
// the `Ci/` snapshot reads its route shares (`choiceProb`) from a flow
// service that is not in the snapshot and only reports load factors
// (`metroEconomyCollectCrowdingMetrics`), and the RailwayCore pack
// (`Railway/railway_game_reference_clean/01_MIGRATION_MAP.md` §6) names the
// link graph's fields (travel time, frequency, offered and used capacity,
// transfer penalty) and asks for a shortest generalized cost with
// deterministic assignment, without a formula. The rules below are native
// and integer-only, so every platform plans the same:
//
// - Offered capacity: a service path's trains a day (each service level's
//   open minutes in the line's window divided by its headway at that
//   level) times a train's capacity (``Train/capacity``). A service with no
//   train counts ``PassengerCrowding/defaultTrainCapacity``.
// - Used capacity: the plan's daily trips, shared among each pair's route
//   choices by their uncrowded weights (largest remainder), added on every
//   ride segment they use. One plan's own loads, so a plan is a function of
//   the world alone: saving, loading and batching change nothing.
// - Crowding: each segment's ride time grows by the Bureau of Public Roads
//   link cost function, 0.15 × (used / offered)^4, the ratio capped at 2.
//   A choice's weight is then 10000 over its crowded cost (its whole-minute
//   cost plus the crowding seconds, in minutes), as the uncrowded weight is
//   10000 over its cost: one step of an incremental assignment. Without
//   crowding the weights are exactly the uncrowded ones.
// - Demand: a pair's daily trips stay whole while its fastest route takes
//   at most ``PassengerCrowding/fullDemandMinutes``, and fall in inverse
//   proportion beyond (twice as long, half the trips), rounded half up.

enum PassengerCrowding {
    /// Generalized minutes up to which a pair keeps all its trips (native).
    static let fullDemandMinutes: Int64 = 30

    /// What a service with no train assigned is counted to carry: six cars
    /// of ``Train/capacityPerCar`` (native default).
    static let defaultTrainCapacity: Int64 = 6 * Train.capacityPerCar

    /// The Bureau of Public Roads coefficient, in hundredths (0.15).
    static let bprCoefficientHundredths: Int64 = 15

    /// The highest load ratio, in thousandths, crowding counts (2).
    static let maximumLoad: Int64 = 2_000

    /// `trips` as a pair whose fastest route takes `minutes` keeps them.
    static func decayed(_ trips: Int64, minutes: Int64) -> Int64 {
        guard trips > 0, minutes > fullDemandMinutes else { return trips }
        let factor = 1_000 * fullDemandMinutes / minutes
        return (trips * factor + 500) / 1_000
    }

    /// The seconds crowding adds to a ride of `seconds` on a segment loaded
    /// `load` thousandths of its capacity: `seconds × 0.15 × (load/1000)^4`,
    /// the ratio capped at 2.
    static func crowdingSeconds(_ seconds: Int64, load: Int64) -> Int64 {
        let x = min(max(0, load), maximumLoad)
        let square = x * x / 1_000
        let fourth = square * square / 1_000
        return seconds * bprCoefficientHundredths * fourth / 100_000
    }

    /// Passengers a service carries a day each way: its trains a day at
    /// each level (the level's open minutes over its headway, `headways`
    /// giving the headway at a level, `nil` when it does not run) times
    /// `capacity`.
    static func dailyCapacity(window: ServiceWindow, day: ServiceDay, capacity: Int64,
                              headways: (ServiceLevel) -> Int64?) -> Int64 {
        var minutes: [ServiceLevel: Int64] = [:]
        for minute in 0..<1_440 where window.contains(minuteOfDay: minute) {
            minutes[day.level(atMinuteOfDay: minute), default: 0] += 1
        }
        var trains: Int64 = 0
        for level in ServiceLevel.allCases {
            guard let open = minutes[level], let headway = headways(level), headway > 0 else { continue }
            trains += open / headway
        }
        return trains * capacity
    }

    /// The weights of a pair's `choices` under the plan's daily loads
    /// `used` on `graph`'s ride segments.
    static func crowdedWeights(_ choices: [PassengerRouteChoice], used: [PassengerRouteGraph.Segment: Int64],
                               on graph: PassengerRouteGraph) -> [Int64] {
        choices.map { choice in
            var crowding: Int64 = 0
            for segment in graph.segments(of: choice.route) ?? [] {
                let offered = graph.paths[segment.path].dailyCapacity
                let load = offered > 0 ? (used[segment] ?? 0) * 1_000 / offered : maximumLoad
                crowding += crowdingSeconds(graph.paths[segment.path].runSeconds[segment.stop], load: load)
            }
            // 10000 over the crowded cost in minutes, worked in seconds:
            // exactly the uncrowded weight without crowding.
            let seconds = max(1, choice.route.totalMinutes) * GameTime.secondsPerMinute + crowding
            return max(1, 10_000 * GameTime.secondsPerMinute / seconds)
        }
    }
}

extension PassengerRouteGraph {
    /// A ride segment: a path's run from call `stop` to the next.
    struct Segment: Hashable {
        let path: Int
        let stop: Int
    }

    /// The ride segments `route` uses; `nil` if a leg is not on this graph.
    func segments(of route: PassengerRoute) -> [Segment]? {
        var result: [Segment] = []
        for leg in route.legs {
            guard let path = paths.indices.first(where: {
                paths[$0].line == leg.line && paths[$0].pattern == leg.pattern && paths[$0].direction == leg.direction
                    && paths[$0].stations.contains(leg.from)
            }), let from = paths[path].stations.firstIndex(of: leg.from),
                  let to = paths[path].stations[(from + 1)...].firstIndex(of: leg.to) else { return nil }
            for stop in from..<to {
                result.append(Segment(path: path, stop: stop))
            }
        }
        return result
    }
}
