/// Turns real elapsed time into whole, fixed-length simulation ticks.
///
/// The host measures real time; GameCore only ever receives whole ticks
/// through `GameWorld.advance(ticks:)`, so the simulation stays deterministic.
/// Time left over below one tick carries into the next call, so the tick rate
/// does not drift with the host's frame timing.
///
/// Each call counts at most ``maximumElapsed``: a stall (a busy main thread, a
/// debugger pause, a suspended app) cannot turn into a burst of catch-up ticks.
/// Speed is not handled here: 2× still means one tick per interval, and
/// GameCore decides what a tick does at each speed.
public struct TickAccumulator: Hashable, Sendable {
    public let tickInterval: Duration
    public let maximumElapsed: Duration
    /// Real time counted but not yet turned into a tick. Always below
    /// ``tickInterval`` between calls.
    public private(set) var pending: Duration = .zero

    public init(tickInterval: Duration, maximumElapsed: Duration) {
        precondition(tickInterval > .zero, "TickAccumulator requires a positive tick interval")
        precondition(maximumElapsed >= tickInterval, "maximumElapsed must cover at least one tick")
        self.tickInterval = tickInterval
        self.maximumElapsed = maximumElapsed
    }

    /// Adds `elapsed` real time and returns how many whole ticks are now due.
    /// Negative durations count as zero.
    public mutating func ticks(for elapsed: Duration) -> Int {
        pending += min(max(elapsed, .zero), maximumElapsed)
        // At most maximumElapsed / tickInterval + 1 iterations; exact, unlike
        // dividing durations as floating point.
        var count = 0
        while pending >= tickInterval {
            pending -= tickInterval
            count += 1
        }
        return count
    }

    /// Drops any partial tick, so time that passed while the game was paused
    /// or the app was inactive is never replayed.
    public mutating func reset() {
        pending = .zero
    }
}
