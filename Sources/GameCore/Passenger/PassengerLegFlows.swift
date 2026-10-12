// A read-only view of the planned passenger flows (ARCHITECTURE decision
// 178): how many passengers each hour the cached passenger plan sends along
// each ride leg of each line, in each direction. The plan is worked out and
// kept by ``GameWorld/advance(ticks:)`` (see ``GameWorld/PassengerPlan``);
// this only reads it, so presentation never works out the paths of every
// origin-destination pair again (on the whole of Taiwan that is far too slow
// for a frame). Nothing here is state: it is never saved, and the world is
// not changed.

/// The passengers planned to ride one leg of a line: the same line, way and
/// pair of stations, in each hour of the day.
public struct PassengerLegFlow: Hashable, Sendable {
    public let line: LineID
    public let direction: LineDirection
    /// The stations the leg boards and gets off at (not necessarily
    /// neighbouring stops of the line: a leg runs over every stop between).
    public let from: StationID
    public let to: StationID
    /// Passengers in each hour of the day: 24 entries, hour 0 first.
    public let hourly: [Int64]
}

extension GameWorld {
    /// The planned passengers of every ride leg, by line, direction, then
    /// the stations of the leg, or `nil` when no plan is kept (before the
    /// first ``advance(ticks:)`` of a world, or after a change that forgets
    /// it) and an empty list when no pair has trips.
    ///
    /// Each origin-destination pair's trips in an hour are split among its
    /// route choices by the choices' weights (largest remainders, as
    /// ``passengerRouteAllocations(from:to:count:)`` splits a day), and every
    /// leg of a choice carries its share.
    public func plannedPassengerLegFlows() -> [PassengerLegFlow]? {
        guard case .some(let kept) = passengerPlan.plan else { return nil }
        guard let plan = kept else { return [] }
        struct Key: Hashable {
            let line: LineID
            let direction: LineDirection
            let from: StationID
            let to: StationID
        }
        var sums: [Key: [Int64]] = [:]
        for (index, flow) in plan.flows.enumerated() {
            let weights = flow.choices.map(\.weight)
            for hour in 0..<24 {
                let trips = plan.hourly[index * 24 + hour]
                guard trips > 0 else { continue }
                let shares = Self.apportion(trips, by: weights)
                for (choice, share) in zip(flow.choices, shares) where share > 0 {
                    for leg in choice.journey.legs {
                        let key = Key(line: leg.line, direction: leg.direction, from: leg.from, to: leg.to)
                        sums[key, default: Array(repeating: 0, count: 24)][hour] += share
                    }
                }
            }
        }
        return sums.keys.sorted {
            ($0.line, $0.direction.rawValue, $0.from, $0.to) < ($1.line, $1.direction.rawValue, $1.from, $1.to)
        }.map { key in
            PassengerLegFlow(line: key.line, direction: key.direction, from: key.from, to: key.to, hourly: sums[key]!)
        }
    }
}
