// Running curves under speed limits (ARCHITECTURE decision 217). Where a run
// passes curves (``CurveSpeedLimit``), its train may not keep to the one
// cruise speed of a ``RunningCurve``: it brakes, at its usual braking, to
// be at a limit when the limit begins, holds it, and accelerates again
// once past. The run is then a string of phases, each accelerating,
// cruising or braking at a constant rate; as with ``RunningCurve`` the
// cruise speed is the one that makes the run take its time, here a cap
// over the whole run, found by halving.
//
// The speed allowed at a point is the least of the cap, the limit there,
// how fast the train can have accelerated to since the last point it had
// to be slower (or since it set off), and how fast it can be and still
// brake down to the next limit (or to a stand at the end): the textbook
// minimum of the forward and backward envelopes. Within a stretch of one
// limit, v² follows three lines (acceleration, the limit, braking), so the
// phases are worked out exactly from v², without stepping.
//
// The references have no such curve (the Railway reference's
// `runSpeedZones` only spreads a run's time over measured zones); the rule
// is this project's. A run with limits does not coast: coasting is the
// high-speed line's, whose curves the limits barely touch.
//
// Scales: distance in world units × 2^16; time in milliseconds × 2^16;
// speed in world units per millisecond × 2^20 (so v² is × 2^40); rates in
// thousandths of a km/h per second, as ``TrainPerformance``'s.

/// The run of a train between two stops under speed limits (decision 217):
/// it covers ``length`` in ``duration`` or less, never faster than a limit
/// where it applies, braking at its braking ahead of each.
public struct LimitedRunningCurve: Hashable, Sendable {
    /// World units.
    public let length: Int64
    /// Milliseconds.
    public let duration: Int64

    /// One stretch of the run at a constant rate.
    struct Phase: Hashable, Sendable {
        /// Distance and time where it begins (× 2^16).
        let start: Int64
        let time: Int64
        /// How far and how long it lasts (× 2^16).
        let distance: Int64
        let elapsed: Int64
        /// Speed at its start (× 2^20).
        let speed: Int64
        /// Thousandths of a km/h per second: positive accelerating,
        /// negative braking, 0 cruising.
        let rate: Int64
    }

    let phases: [Phase]

    /// The highest speed a curve is built for, in km/h: every v² fits in 64
    /// bits below it.
    public static let maximumSpeed: Int64 = 2000
    /// 1 ÷ a in ms² per world unit is this ÷ the rate (see
    /// ``RunningCurve``).
    static let inverseRate: Int64 = 56_250_000

    /// The speed `kmh` km/h in world units per millisecond × 2^20.
    static func speed(kmh: Int64) -> Int64 {
        kmh * (4 << 20) / 225
    }

    /// The curve for a run of `length` world units in `duration`
    /// milliseconds at `acceleration` and `braking` (thousandths of a km/h
    /// per second), at most `topSpeed` km/h, and under `limits` (along the
    /// run, from its start; they may overlap, the lowest holds), or `nil`
    /// when the run cannot be done in that time (or a value is out of
    /// range).
    public init?(length: Int64, duration: Int64, acceleration: Int64, braking: Int64, topSpeed: Int64, limits: [TrackSpeedLimit]) {
        guard (1...RunningCurve.maximumLength).contains(length),
              (1...RunningCurve.maximumDuration).contains(duration),
              (1...RunningCurve.maximumRate).contains(acceleration),
              (1...RunningCurve.maximumRate).contains(braking),
              topSpeed >= 1 else { return nil }
        let zones = Self.zones(length: length, limits: limits)
        let top = Self.speed(kmh: min(topSpeed, Self.maximumSpeed))
        let whole = duration << 16
        func time(_ cap: Int64) -> Int64 {
            Self.phases(zones: zones, cap: cap, acceleration: acceleration, braking: braking).reduce(0) { $0 + $1.elapsed }
        }
        guard top >= 1, time(top) <= whole else { return nil }
        // The least cap that keeps to the time, to within 1/4096 of itself
        // (so the train arrives at most that share of its run early, a
        // fraction of a second on most runs): the train runs no faster than
        // it must. It is at least the average speed.
        var (low, high) = (min(top, max(1, (length << 20) / duration)), top)
        while high - low > max(1, low >> 12) {
            let middle = (low + high) / 2
            if time(middle) <= whole {
                high = middle
            } else {
                low = middle + 1
            }
        }
        self.length = length
        self.duration = duration
        self.phases = Self.phases(zones: zones, cap: high, acceleration: acceleration, braking: braking)
    }

    /// The curve for `performance` as ``RunningCurve/init(length:duration:performance:)``
    /// tries it: its rates, then its alternative braking, then both
    /// alternatives (its coast is not used).
    public init?(length: Int64, duration: Int64, performance: TrainPerformance, limits: [TrackSpeedLimit]) {
        for (acceleration, braking) in Self.rates(of: performance) {
            if let curve = LimitedRunningCurve(length: length, duration: duration, acceleration: acceleration, braking: braking,
                                               topSpeed: performance.topSpeed, limits: limits) {
                self = curve
                return
            }
        }
        return nil
    }

    /// The rates ``init(length:duration:performance:limits:)`` tries, in
    /// order.
    static func rates(of performance: TrainPerformance) -> [(Int64, Int64)] {
        var rates = [(performance.acceleration, performance.braking)]
        if let braking = performance.alternativeBraking {
            rates.append((performance.acceleration, braking))
            if let acceleration = performance.alternativeAcceleration {
                rates.append((acceleration, braking))
            }
        }
        return rates
    }

    /// The least whole second in which `performance` builds a curve for a
    /// run of `length` world units under `limits`, or `nil` if it builds
    /// none in up to ``RunningCurve/maximumSeconds``: its fastest run with
    /// each pair of rates it tries, rounded up, the least of them.
    public static func leastSeconds(length: Int64, performance: TrainPerformance, limits: [TrackSpeedLimit]) -> Int64? {
        guard let fastest = fastest(length: length, performance: performance, limits: limits) else { return nil }
        let least = (fastest + (1000 << 16) - 1) / (1000 << 16)
        guard least <= RunningCurve.maximumSeconds else { return nil }
        return max(1, least)
    }

    /// The time of the fastest run (milliseconds × 2^16) with any pair of
    /// rates ``init(length:duration:performance:limits:)`` tries: a curve is
    /// built for exactly the durations from it on.
    static func fastest(length: Int64, performance: TrainPerformance, limits: [TrackSpeedLimit]) -> Int64? {
        guard (1...RunningCurve.maximumLength).contains(length), performance.topSpeed >= 1 else { return nil }
        let zones = zones(length: length, limits: limits)
        let top = speed(kmh: min(performance.topSpeed, maximumSpeed))
        guard top >= 1 else { return nil }
        return rates(of: performance).compactMap { acceleration, braking -> Int64? in
            guard (1...RunningCurve.maximumRate).contains(acceleration), (1...RunningCurve.maximumRate).contains(braking) else { return nil }
            return phases(zones: zones, cap: top, acceleration: acceleration, braking: braking).reduce(0) { $0 + $1.elapsed }
        }.min()
    }

    // MARK: - Building

    /// A stretch of the run under one limit (× 2^16), with its speed (×
    /// 2^20), or the top speed's where there is none.
    struct Zone {
        let start: Int64
        let end: Int64
        let limit: Int64?
    }

    /// The run cut where a limit begins or ends, each piece with the lowest
    /// limit over it (see ``CurveSpeedLimit/merged(_:within:)``), and the
    /// pieces between without.
    static func zones(length: Int64, limits: [TrackSpeedLimit]) -> [Zone] {
        var zones: [Zone] = []
        var reached: Int64 = 0
        for limit in CurveSpeedLimit.merged(limits, within: length) {
            if limit.start > reached {
                zones.append(Zone(start: reached << 16, end: limit.start << 16, limit: nil))
            }
            zones.append(Zone(start: limit.start << 16, end: limit.end << 16, limit: Self.speed(kmh: min(limit.speed, maximumSpeed))))
            reached = limit.end
        }
        if reached < length {
            zones.append(Zone(start: reached << 16, end: length << 16, limit: nil))
        }
        return zones
    }

    /// v² gained over `distance` (× 2^16) at `rate`: 2·r·d, in (× 2^20)².
    /// With r in world units per ms² = rate ÷ 56,250,000 and d ÷ 2^16 world
    /// units, that is rate·d·2^25 ÷ 56,250,000. Saturates at 2^62.
    static func gain(_ distance: Int64, rate: Int64) -> Int64 {
        let value = WideInteger.product(distance, rate).shiftedLeft(by: 25).dividedRoundingDown(by: inverseRate)
        return value < WideInteger(Int64(1) << 62) ? value.int64 : 1 << 62
    }

    /// The distance (× 2^16) over which v² changes by `squares` at `rate`.
    static func reach(_ squares: Int64, rate: Int64) -> Int64 {
        WideInteger.product(squares, inverseRate).dividedRoundingDown(by: rate).shiftedRight(by: 25).int64
    }

    /// The phases of the run through `zones` with every speed capped at
    /// `cap` (× 2^20).
    static func phases(zones: [Zone], cap: Int64, acceleration: Int64, braking: Int64) -> [Phase] {
        let caps = zones.map { min(cap, $0.limit ?? cap) }
        let count = zones.count
        // v² allowed where each zone begins: accelerating from a stand at
        // the start (forward) and braking to a stand at the end (backward).
        var forward = [Int64](repeating: 0, count: count + 1)
        var backward = [Int64](repeating: 0, count: count + 1)
        for k in 0..<count {
            let squared = caps[k] * caps[k]
            let reached = k == 0 ? 0 : min(forward[k], squared)
            forward[k] = reached
            let next = min(squared, reached + gain(zones[k].end - zones[k].start, rate: acceleration))
            forward[k + 1] = next
        }
        for k in stride(from: count - 1, through: 0, by: -1) {
            let squared = caps[k] * caps[k]
            let left = k == count - 1 ? 0 : min(backward[k + 1], squared)
            backward[k + 1] = left
            backward[k] = min(squared, left + gain(zones[k].end - zones[k].start, rate: braking))
        }
        var phases: [Phase] = []
        var time: Int64 = 0
        func add(from start: Int64, to end: Int64, squares first: Int64, _ last: Int64, rate: Int64) {
            guard end > start else { return }
            let v0 = FixedPoint.squareRoot(first), v1 = FixedPoint.squareRoot(last)
            let elapsed: Int64
            if rate == 0 {
                elapsed = v0 > 0 ? WideInteger.product(end - start, 1 << 20).dividedRoundingDown(by: v0).int64 : 0
            } else {
                // (v1 − v0) ÷ r ms × 2^16 = |v1 − v0| × 56,250,000 ÷ (rate × 16).
                elapsed = WideInteger.product(abs(v1 - v0), inverseRate).dividedRoundingDown(by: abs(rate) * 16).int64
            }
            phases.append(Phase(start: start, time: time, distance: end - start, elapsed: elapsed, speed: v0, rate: rate))
            time += elapsed
        }
        for k in 0..<count {
            let (start, end) = (zones[k].start, zones[k].end)
            let length = end - start
            let squared = caps[k] * caps[k]
            let entry = min(forward[k], backward[k])
            let exit = min(forward[k + 1], backward[k + 1])
            // v² rises from `entry` at the acceleration, holds at the cap,
            // and falls to `exit` at the braking; where the two slopes meet
            // below the cap, there is no cruise.
            let rising = reach(squared - entry, rate: acceleration)
            let falling = reach(squared - exit, rate: braking)
            if rising + falling <= length {
                add(from: start, to: start + rising, squares: entry, squared, rate: acceleration)
                add(from: start + rising, to: end - falling, squares: squared, squared, rate: 0)
                add(from: end - falling, to: end, squares: squared, exit, rate: -braking)
            } else {
                // entry + 2a·x = exit + 2b·(L − x): x = (exit − entry + 2b·L) ÷ (2a + 2b),
                // worked out as the share of L where the gains balance.
                let up = gain(length, rate: braking) + exit - entry
                let meet = up <= 0 ? 0
                    : min(length, WideInteger.product(up, length)
                        .dividedRoundingDown(by: gain(length, rate: acceleration) + gain(length, rate: braking)).int64)
                let peak = min(squared, max(entry + gain(meet, rate: acceleration), exit))
                add(from: start, to: start + meet, squares: entry, peak, rate: acceleration)
                add(from: start + meet, to: end, squares: peak, exit, rate: -braking)
            }
        }
        return phases
    }

    // MARK: - Queries

    /// The index of the phase under way at `value` of `key` (its time or its
    /// start): the last that begins at or before it.
    private func phase(at value: Int64, by key: (Phase) -> Int64) -> Int {
        var (low, high) = (0, phases.count - 1)
        while low < high {
            let middle = (low + high + 1) / 2
            if key(phases[middle]) <= value {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// How far the train has run `time` milliseconds after leaving, in
    /// world units (rounded down): 0 up to the start, ``length`` once it
    /// has arrived (at the latest ``duration``).
    public func distance(at time: Int64) -> Int64 {
        guard time > 0, !phases.isEmpty else { return 0 }
        guard time < duration else { return length }
        let moment = time << 16
        let phase = phases[phase(at: moment, by: \.time)]
        let elapsed = min(moment - phase.time, phase.elapsed)
        // v0·τ, and ½·r·τ² = r·τ² ÷ (112,500,000 × 2^16), in world units × 2^16.
        let run = WideInteger.product(phase.speed, elapsed).shiftedRight(by: 20).int64
        let change = WideInteger.product(elapsed, elapsed).multiplied(by: abs(phase.rate))
            .dividedRoundingDown(by: 2 * Self.inverseRate).shiftedRight(by: 16).int64
        let covered = phase.rate >= 0 ? run + change : max(0, run - change)
        return min(length, (phase.start + min(phase.distance, covered)) >> 16)
    }

    /// How many milliseconds after leaving the train has run `distance`
    /// world units (rounded down): 0 up to the start, and at most
    /// ``duration``.
    public func time(atDistance distance: Int64) -> Int64 {
        guard distance > 0, !phases.isEmpty else { return 0 }
        guard distance < length else { return min(duration, (phases.reduce(0) { $0 + $1.elapsed } >> 16)) }
        let point = distance << 16
        let phase = phases[phase(at: point, by: \.start)]
        let along = min(point - phase.start, phase.distance)
        let elapsed: Int64
        if phase.rate == 0 {
            elapsed = phase.speed > 0 ? WideInteger.product(along, 1 << 20).dividedRoundingDown(by: phase.speed).int64 : 0
        } else {
            let squared = phase.speed * phase.speed
            let change = Self.gain(along, rate: abs(phase.rate))
            let speed = FixedPoint.squareRoot(phase.rate > 0 ? squared + change : max(0, squared - change))
            elapsed = WideInteger.product(abs(speed - phase.speed), Self.inverseRate)
                .dividedRoundingDown(by: abs(phase.rate) * 16).int64
        }
        return min(duration, (phase.time + min(elapsed, phase.elapsed)) >> 16)
    }

    /// The train's speed `time` milliseconds after leaving, in km/h,
    /// rounded down: 0 before it leaves and once it has arrived.
    public func speed(at time: Int64) -> Int64 {
        guard time > 0, !phases.isEmpty else { return 0 }
        let moment = time << 16
        let index = phase(at: moment, by: \.time)
        let phase = phases[index]
        let elapsed = moment - phase.time
        guard elapsed <= phase.elapsed || index < phases.count - 1 else { return 0 }
        let change = WideInteger.product(abs(phase.rate), min(elapsed, phase.elapsed)).shiftedLeft(by: 4)
            .dividedRoundingDown(by: Self.inverseRate).int64
        let speed = phase.rate >= 0 ? phase.speed + change : max(0, phase.speed - change)
        return speed * 225 / (4 << 20)
    }
}

/// The curve a service's run follows (decision 217): a ``RunningCurve``
/// where it meets no speed limit below its top speed, as every run did
/// before, and a ``LimitedRunningCurve`` where it does.
public enum RunCurve: Hashable, Sendable {
    case plain(RunningCurve)
    case limited(LimitedRunningCurve)

    /// The curve `performance` builds for a run of `length` world units in
    /// `duration` milliseconds under `limits` (along the run), or `nil` if
    /// it builds none. Limits at or above the top speed change nothing.
    public init?(length: Int64, duration: Int64, performance: TrainPerformance, limits: [TrackSpeedLimit]) {
        let binding = Self.binding(limits, below: performance)
        if binding.isEmpty {
            guard let curve = RunningCurve(length: length, duration: duration, performance: performance) else { return nil }
            self = .plain(curve)
        } else {
            guard let curve = LimitedRunningCurve(length: length, duration: duration, performance: performance, limits: binding) else { return nil }
            self = .limited(curve)
        }
    }

    /// The least whole second in which `performance` builds a curve for a
    /// run of `length` under `limits` (see
    /// ``RunningCurve/leastSeconds(length:performance:)`` and
    /// ``LimitedRunningCurve/leastSeconds(length:performance:limits:)``).
    public static func leastSeconds(length: Int64, performance: TrainPerformance, limits: [TrackSpeedLimit]) -> Int64? {
        let binding = binding(limits, below: performance)
        return binding.isEmpty
            ? RunningCurve.leastSeconds(length: length, performance: performance)
            : LimitedRunningCurve.leastSeconds(length: length, performance: performance, limits: binding)
    }

    /// Whether `performance` builds a curve for a run of `length` in
    /// `duration` milliseconds under `limits`, without building it: the
    /// fastest run fits in the time.
    public static func fits(length: Int64, duration: Int64, performance: TrainPerformance, limits: [TrackSpeedLimit]) -> Bool {
        let binding = binding(limits, below: performance)
        guard !binding.isEmpty else { return RunningCurve(length: length, duration: duration, performance: performance) != nil }
        return LimitedRunningCurve.fastest(length: length, performance: performance, limits: binding).map { $0 <= duration << 16 } ?? false
    }

    /// The limits below `performance`'s top speed.
    static func binding(_ limits: [TrackSpeedLimit], below performance: TrainPerformance) -> [TrackSpeedLimit] {
        limits.filter { $0.speed < performance.topSpeed }
    }

    /// World units.
    public var length: Int64 {
        switch self {
        case .plain(let curve): curve.length
        case .limited(let curve): curve.length
        }
    }

    /// Milliseconds.
    public var duration: Int64 {
        switch self {
        case .plain(let curve): curve.duration
        case .limited(let curve): curve.duration
        }
    }

    /// How far the train has run `time` milliseconds after leaving.
    public func distance(at time: Int64) -> Int64 {
        switch self {
        case .plain(let curve): curve.distance(at: time)
        case .limited(let curve): curve.distance(at: time)
        }
    }

    /// How long after leaving the train has run `distance`.
    public func time(atDistance distance: Int64) -> Int64 {
        switch self {
        case .plain(let curve): curve.time(atDistance: distance)
        case .limited(let curve): curve.time(atDistance: distance)
        }
    }
}
