import Foundation
import GameCore

/// Decision 470: the passenger routes a tick's plan is about to work out,
/// worked out first on every core. After a game is opened or the lines are
/// changed, the next network plan works out every route again, one origin
/// after another (92.1's game of 81 stations: 5–19 s on Linux, the trains
/// still all the while). The routes from each origin are a pure function of
/// the route graph, so they are split among tasks by origin and given to the
/// world before the tick: the tick then plans exactly as it would have, only
/// without working them out. Whatever the device's speed, the world after
/// the tick is the same.
enum PassengerRoutesAhead {
    /// Fewer origins than this are left to the tick: not worth the tasks.
    static let minimumOrigins = 8

    /// `world` with the routes its next plan would work out afresh, or
    /// `world` as it is when there are none or too few.
    static func given(to world: GameWorld, minimumOrigins: Int = Self.minimumOrigins) async -> GameWorld {
        guard let work = world.passengerRoutesToWorkOut(), work.origins.count >= minimumOrigins else { return world }
        let origins = work.origins
        // More tasks than cores: origins differ in cost.
        let tasks = min(origins.count, 4 * max(1, ProcessInfo.processInfo.activeProcessorCount))
        let caches = await withTaskGroup(of: PassengerRouteCache.self) { group in
            for task in 0..<tasks {
                let part = stride(from: task, to: origins.count, by: tasks).map { origins[$0] }
                group.addTask { world.workingOutPassengerRoutes(work, origins: part) }
            }
            var caches: [PassengerRouteCache] = []
            for await cache in group { caches.append(cache) }
            return caches
        }
        var given = world
        for cache in caches { given.takePassengerRoutes(cache) }
        return given
    }
}
