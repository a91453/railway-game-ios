// Passenger routes worked out ahead, apart from the tick that needs them
// (decision 470). A network plan's routes are a pure function of the derived
// route graph (``PassengerRouteMemo``), so whoever works them out, on any
// thread and at any time, works out the same ones: a world given them plans
// exactly as one that works them out itself, only sooner.

/// Route choices worked out apart from a world's own ticks, to give it with
/// ``GameWorld/takePassengerRoutes(_:)``. Not game state.
public struct PassengerRouteCache: Sendable {
    var memo: PassengerRouteMemo

    /// How many station pairs' routes it holds.
    public var pairs: Int { memo.count }
}

/// The routes a world's next plan would work out afresh
/// (``GameWorld/passengerRoutesToWorkOut(forTicks:)``): from which
/// stations, on the route graph of which minute.
public struct PassengerRoutesToWorkOut: Equatable, Sendable {
    let time: GameTime
    /// The stations to work the routes out from, by ascending station.
    public let origins: [StationID]
}

extension GameWorld {
    /// The route choices this world has worked out so far.
    public var passengerRouteCache: PassengerRouteCache {
        PassengerRouteCache(memo: passengerRouteMemo)
    }

    /// The routes the network passenger plans of the next `ticks` calls
    /// of ``advance(ticks:)`` would work out afresh, the first ones only:
    /// the plan's now when the one kept is not current, or else the plan's
    /// at the first minute in those ticks whose service levels differ from
    /// now's (06:00, when the lines start running). `nil` when they are
    /// kept already, or when the game routes passengers by line only.
    public func passengerRoutesToWorkOut(forTicks ticks: Int = 1) -> PassengerRoutesToWorkOut? {
        guard passengerRoutingMode == .network else { return nil }
        var times: [GameTime] = []
        if passengerPlan.plan == nil || passengerPlan.key != passengerPlanKey() || passengerPlan.day != demandDay {
            times.append(clock.now)
        }
        if let steps = try? clock.basicSteps(forTicks: ticks), steps.seconds > 0 {
            let now = lines.map { serviceLevel(of: $0.id, at: clock.now) }
            let minute = GameTime.secondsPerMinute
            var time = (clock.now.seconds / minute + 1) * minute
            while time < clock.now.seconds + steps.seconds {
                if lines.map({ serviceLevel(of: $0.id, at: GameTime(seconds: time)) }) != now {
                    times.append(GameTime(seconds: time))
                    break
                }
                time += minute
            }
        }
        for time in times {
            let graph = PassengerRouteGraph(world: self, at: time)
            guard !graph.paths.isEmpty else { continue }
            var memo = passengerRouteMemo
            memo.use(graph)
            let origins = passengerRouteOrigins().filter { !memo.hasChoices(from: $0) }
            if !origins.isEmpty { return PassengerRoutesToWorkOut(time: time, origins: origins) }
        }
        return nil
    }

    /// The routes from each of `work`'s origins in `origins` (all of them
    /// when `nil`) to every station with passengers, on the route graph of
    /// `work`'s time, as a plan would ask them. Changes nothing, so several
    /// can be worked out at once.
    public func workingOutPassengerRoutes(_ work: PassengerRoutesToWorkOut, origins: [StationID]? = nil) -> PassengerRouteCache {
        let graph = PassengerRouteGraph(world: self, at: work.time)
        var memo = PassengerRouteMemo()
        memo.use(graph)
        var searches = PassengerRouteSearches(graph: graph)
        let destinations = passengers.filter { $0.demand != nil }.map(\.station)
        for origin in origins ?? work.origins {
            for destination in destinations {
                let pair = PassengerRouteMemo.Pair(origin: origin, destination: destination)
                if memo[pair] == nil {
                    memo[pair] = passengerRouteChoices(from: origin, to: destination, searches: &searches)
                }
            }
        }
        return PassengerRouteCache(memo: memo)
    }

    /// Keeps the routes in `cache` for the plans to come, for the parts of
    /// the route graph they were worked out on. Changes nothing a plan
    /// gives (``PassengerRouteMemo``).
    public mutating func takePassengerRoutes(_ cache: PassengerRouteCache) {
        passengerRouteMemo.absorb(cache.memo)
    }

    /// The stations a network plan asks routes from, by ascending station.
    private func passengerRouteOrigins() -> [StationID] {
        passengers.filter { $0.demand != nil && allowsEntry(at: $0.station) }.map(\.station).sorted()
    }
}
