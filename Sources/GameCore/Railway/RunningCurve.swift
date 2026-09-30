// Running curves (Phase 4.7 Stage W1, ARCHITECTURE decision 33): how far a
// train has run, a given time after leaving a stop, on a run that must
// cover a given distance in a given time. A faithful port of the owner's
// Railway reference (`index.html`: `buildProfile`, `profTimeToProg`,
// `profProgToTime` and the `PERF_*` tables; `rail-3d/physical/timing.js`
// has the same two queries): acceleration, cruise, an optional coast and
// braking, with the cruise speed solved from the distance and the time.
//
// The only changes are the mechanical ones GameCore needs. Floating point
// becomes integers at stated scales:
//
// - distance: world units (1/64 m, 1024 to a tile);
// - time: milliseconds;
// - acceleration, braking and coasting deceleration: thousandths of a
//   km/h per second (the reference's values have at most three decimals);
// - top speed: km/h (the reference's values are whole);
// - the coasting speed ratio: thousandths, bisected over the denominator
//   1000 × 2^14, where the reference's fourteen halvings are exact.
//
// Square roots are integer square roots. Every other quantity is the exact
// floor of the reference's formula, given the cruise speed. Nothing here
// changes how trains run yet: W2 connects the curve to journeys and
// movement.

/// How a train accelerates, brakes and coasts, and how fast it may run
/// (Stage W1): the input of a ``RunningCurve``.
///
/// The presets are the owner's reference values (`PERF_DEFAULT`,
/// `PERF_HSR`, `PERF_DR1000`, `PERF_RULES` and `PERF_BY_TYPE` in the
/// Railway reference). Which preset a train uses is not decided yet: the
/// reference picks one from a real train's type and car name, which the
/// game's trains do not have.
public struct TrainPerformance: Hashable, Sendable {
    /// Coasting between cruising and braking (the reference's `coast`):
    /// the train rolls, slowing at ``deceleration``, down to
    /// ``speedRatio`` of its cruise speed before it brakes.
    public struct Coast: Hashable, Sendable {
        /// Thousandths of a km/h per second (`coast.c`).
        public let deceleration: Int64
        /// Thousandths of the cruise speed (`coast.rho`).
        public let speedRatio: Int64

        public init(deceleration: Int64, speedRatio: Int64) {
            self.deceleration = deceleration
            self.speedRatio = speedRatio
        }
    }

    /// Thousandths of a km/h per second (`a`).
    public let acceleration: Int64
    /// Thousandths of a km/h per second (`b`).
    public let braking: Int64
    /// km/h (`v`).
    public let topSpeed: Int64
    /// The acceleration to try, with ``alternativeBraking``, when no curve
    /// can be built with the usual values (`aAlt`).
    public let alternativeAcceleration: Int64?
    /// The braking to try when no curve can be built with the usual
    /// braking (`bAlt`).
    public let alternativeBraking: Int64?
    public let coast: Coast?

    public init(
        acceleration: Int64,
        braking: Int64,
        topSpeed: Int64,
        alternativeAcceleration: Int64? = nil,
        alternativeBraking: Int64? = nil,
        coast: Coast? = nil
    ) {
        self.acceleration = acceleration
        self.braking = braking
        self.topSpeed = topSpeed
        self.alternativeAcceleration = alternativeAcceleration
        self.alternativeBraking = alternativeBraking
        self.coast = coast
    }

    /// `PERF_DEFAULT`: the reference's fallback.
    public static let standard = TrainPerformance(acceleration: 1500, braking: 2500, topSpeed: 110)
    /// `PERF_HSR`: high-speed trains, which coast before braking.
    public static let highSpeed = TrainPerformance(
        acceleration: 1400, braking: 1500, topSpeed: 300,
        alternativeAcceleration: 2000, alternativeBraking: 2700,
        coast: Coast(deceleration: 450, speedRatio: 450)
    )
    /// `PERF_DR1000`: branch-line diesel railcars.
    public static let dieselRailcar = TrainPerformance(acceleration: 1500, braking: 2448, topSpeed: 110)
    /// `PERF_RULES` `/阿里山號|祝山線|神木線|沼平線|觀日/`: the forest railway.
    public static let forestRailway = TrainPerformance(acceleration: 700, braking: 1100, topSpeed: 45)
    /// `PERF_RULES` `/普快車|普通車/`: ordinary trains.
    public static let ordinary = TrainPerformance(acceleration: 1300, braking: 2400, topSpeed: 100)
    /// `PERF_RULES` `/\(太/`: Taroko tilting trains.
    public static let tiltingTaroko = TrainPerformance(acceleration: 1880, braking: 3600, topSpeed: 135)
    /// `PERF_RULES` `/\(普/`: Puyuma tilting trains.
    public static let tiltingPuyuma = TrainPerformance(acceleration: 1840, braking: 3600, topSpeed: 135)
    /// `PERF_RULES` `/\(PP/`: push-pull expresses.
    public static let pushPull = TrainPerformance(acceleration: 1600, braking: 2800, topSpeed: 130)
    /// `PERF_RULES` `/\(3000|110[KM]/`: EMU3000 expresses.
    public static let emu3000 = TrainPerformance(acceleration: 2520, braking: 3600, topSpeed: 135)
    /// `PERF_RULES` `/\(D\d/`: diesel expresses.
    public static let dieselExpress = TrainPerformance(acceleration: 1500, braking: 2448, topSpeed: 110)
    /// `PERF_RULES` `/自強/` and `PERF_BY_TYPE` `自強`: Tze-Chiang expresses.
    public static let express = TrainPerformance(acceleration: 1800, braking: 2900, topSpeed: 130)
    /// `PERF_RULES` `/莒光|復興/` and `PERF_BY_TYPE` `莒光/復興`: Chu-Kuang and Fu-Hsing trains.
    public static let semiExpress = TrainPerformance(acceleration: 1500, braking: 2600, topSpeed: 120)
    /// `PERF_RULES` `/電車|區間/` and `PERF_BY_TYPE` `區間車`, `區間快`: local EMUs.
    public static let local = TrainPerformance(acceleration: 2500, braking: 3000, topSpeed: 120)
}

/// The run of a train between two stops (Stage W1): it covers ``length``
/// in ``duration``, accelerating, cruising, coasting when its performance
/// has a coast, and braking to a stand at the end.
///
/// A port of the reference's `buildProfile`: the cruise speed is the one
/// that makes the run take exactly ``duration``. There is no curve when the
/// run cannot be done in that time without passing the top speed, or with
/// an acceleration, braking or coast that do not fit in it; the reference
/// then runs the train at a constant speed.
public struct RunningCurve: Hashable, Sendable {
    /// World units.
    public let length: Int64
    /// Milliseconds.
    public let duration: Int64

    // The solved curve. Speeds are world units per millisecond × 2^32;
    // times are milliseconds × 2^16; distances are world units × 2^16.
    let acceleration: Int64
    let braking: Int64
    let coastDeceleration: Int64
    let cruiseSpeed: UInt64
    let brakingSpeed: UInt64
    let accelerationTime: Int64
    let cruiseTime: Int64
    let coastTime: Int64
    let brakingTime: Int64
    let accelerationDistance: Int64
    let cruiseDistance: Int64
    let coastDistance: Int64

    /// The longest run and the longest time a curve is built for: 2^40
    /// world units (about 17,000 km) and 2^32 milliseconds (about 50
    /// days). Every intermediate value stays inside 128 bits below them.
    public static let maximumLength: Int64 = 1 << 40
    public static let maximumDuration: Int64 = 1 << 32
    /// The largest acceleration, braking or coasting deceleration (in
    /// thousandths of a km/h per second) and top speed (in km/h) accepted.
    public static let maximumRate: Int64 = 1 << 20

    /// 1 ÷ a, in ms² per world unit, is this ÷ the acceleration in
    /// thousandths of a km/h per second: a thousandth of a km/h per second
    /// is 64 ÷ 3600 world units per s², or 1 ÷ 56,250,000 per ms².
    static let inverseAcceleration: Int64 = 56_250_000
    /// The coasting ratio's denominator: thousandths, halved fourteen times.
    static let ratioDenominator: Int64 = 1000 << 14

    /// `buildProfile(L, T, a, b, v, coast)`: the curve for a run of
    /// `length` world units in `duration` milliseconds, or `nil` where the
    /// reference returns `null` (or where a value is not positive or is
    /// beyond the supported range).
    ///
    /// Without a coast, or with one whose deceleration is not below the
    /// braking, the train cruises until it brakes. With one, it first tries
    /// the coast's speed ratio; if that passes the top speed, it bisects the
    /// ratio fourteen times between it and 1 (no coast) and keeps the last
    /// ratio that fits.
    public init?(
        length: Int64,
        duration: Int64,
        acceleration: Int64,
        braking: Int64,
        topSpeed: Int64,
        coast: TrainPerformance.Coast? = nil
    ) {
        guard (1...Self.maximumLength).contains(length),
              (1...Self.maximumDuration).contains(duration),
              (1...Self.maximumRate).contains(acceleration),
              (1...Self.maximumRate).contains(braking),
              (1...Self.maximumRate).contains(topSpeed) else { return nil }
        let full = Self.ratioDenominator
        var deceleration: Int64 = 0
        var startRatio = full
        if let coast, (1...Self.maximumRate).contains(coast.deceleration), coast.deceleration < braking,
           (0..<1000).contains(coast.speedRatio) {
            deceleration = coast.deceleration
            startRatio = coast.speedRatio << 14
        }
        // `solve` also returns nil for a curve faster than the top speed,
        // which the reference checks after each solve (`vc <= vmax`).
        func solve(_ ratio: Int64) -> RunningCurve? {
            Self.solve(length: length, duration: duration, acceleration: acceleration, braking: braking,
                       coastDeceleration: deceleration, ratio: ratio, topSpeed: topSpeed)
        }
        guard var curve = solve(full) else { return nil }
        if startRatio < full {
            if let deep = solve(startRatio) {
                curve = deep
            } else {
                var low = startRatio
                var high = full
                for _ in 0..<14 {
                    let middle = (low + high) / 2
                    if let candidate = solve(middle) {
                        high = middle
                        curve = candidate
                    } else {
                        low = middle
                    }
                }
            }
        }
        self = curve
    }

    /// The curve `assignRunProfiles` gives a run: with the performance's
    /// acceleration and braking; failing that, with its alternative
    /// braking; failing that, with both alternatives. `nil` when none can be
    /// built.
    public init?(length: Int64, duration: Int64, performance: TrainPerformance) {
        if let curve = RunningCurve(length: length, duration: duration, acceleration: performance.acceleration,
                                    braking: performance.braking, topSpeed: performance.topSpeed,
                                    coast: performance.coast) {
            self = curve
            return
        }
        if let braking = performance.alternativeBraking,
           let curve = RunningCurve(length: length, duration: duration, acceleration: performance.acceleration,
                                    braking: braking, topSpeed: performance.topSpeed, coast: performance.coast) {
            self = curve
            return
        }
        if let acceleration = performance.alternativeAcceleration, let braking = performance.alternativeBraking,
           let curve = RunningCurve(length: length, duration: duration, acceleration: acceleration,
                                    braking: braking, topSpeed: performance.topSpeed, coast: performance.coast) {
            self = curve
            return
        }
        return nil
    }

    private init(
        length: Int64, duration: Int64, acceleration: Int64, braking: Int64, coastDeceleration: Int64,
        cruiseSpeed: UInt64, brakingSpeed: UInt64,
        accelerationTime: Int64, cruiseTime: Int64, coastTime: Int64, brakingTime: Int64,
        accelerationDistance: Int64, cruiseDistance: Int64, coastDistance: Int64
    ) {
        self.length = length
        self.duration = duration
        self.acceleration = acceleration
        self.braking = braking
        self.coastDeceleration = coastDeceleration
        self.cruiseSpeed = cruiseSpeed
        self.brakingSpeed = brakingSpeed
        self.accelerationTime = accelerationTime
        self.cruiseTime = cruiseTime
        self.coastTime = coastTime
        self.brakingTime = brakingTime
        self.accelerationDistance = accelerationDistance
        self.cruiseDistance = cruiseDistance
        self.coastDistance = coastDistance
    }

    /// `solve(rho)` inside `buildProfile`, for the speed ratio
    /// `ratio ÷ ratioDenominator` (the whole denominator is no coast). With
    /// a = the acceleration, b = the braking, c = the coasting deceleration
    /// and ρ = the ratio:
    ///
    /// - D = 1/(2a) + (1 − ρ)²/(2c) (only when coasting) + ρ(2 − ρ)/(2b);
    /// - the cruise speed vc is the smaller root of D·v² − T·v + L = 0,
    ///   computed as 2L ÷ (T + √(T² − 4DL)), the same value as the
    ///   reference's (T − √(T² − 4DL)) ÷ (2D) without its cancellation;
    /// - vb = ρ·vc; tAcc = vc/a, tCoast = (vc − vb)/c, tDec = vb/b and
    ///   tCru = T − tAcc − tCoast − tDec, which must not be negative;
    /// - dAcc = vc²/(2a), dCru = vc·tCru, dCoast = (vc² − vb²)/(2c).
    ///
    /// D is kept × 2^24 and T² − 4DL × 2^24, so its square root is × 2^12.
    ///
    /// Every caller in the reference discards a solution faster than the
    /// top speed, so this returns `nil` for one as soon as vc is known; it
    /// also keeps every later product inside 128 bits.
    private static func solve(
        length: Int64, duration: Int64, acceleration: Int64, braking: Int64,
        coastDeceleration: Int64, ratio: Int64, topSpeed: Int64
    ) -> RunningCurve? {
        let full = ratioDenominator
        let coasting = ratio < full
        // 1/(2a) × 2^24 = 28,125,000 × 2^24 ÷ a.
        let half = UInt64(inverseAcceleration / 2) << 24
        let fullSquared = UInt64(full * full)
        var d = WideInteger(half).dividedRoundingDown(by: acceleration)
        d = d + WideInteger.product(half, UInt64(ratio * (2 * full - ratio)))
            .dividedRoundingDown(by: fullSquared).dividedRoundingDown(by: braking)
        if coasting {
            d = d + WideInteger.product(half, UInt64((full - ratio) * (full - ratio)))
                .dividedRoundingDown(by: fullSquared).dividedRoundingDown(by: coastDeceleration)
        }
        let squaredDuration = WideInteger.product(duration, duration).shiftedLeft(by: 24)
        let product = WideInteger.product(d.int64, length).multiplied(by: 4 as UInt64)
        guard product <= squaredDuration else { return nil }
        let root = (squaredDuration - product).squareRoot()
        let denominator = (UInt64(duration) << 12) + root
        let speed = WideInteger(UInt64(2 * length)).shiftedLeft(by: 44).dividedRoundingDown(by: denominator)
        // vc > 0, and vc ≤ vmax with vmax = v km/h = 4v ÷ 225 world units
        // per ms. So from here on vc × 2^32 < 2^47.
        guard speed > WideInteger(0 as UInt64),
              speed.multiplied(by: 225 as UInt64) <= WideInteger.product(UInt64(4 * topSpeed), 1 << 32) else { return nil }
        let cruiseSpeed = speed.low
        let brakingSpeed = WideInteger.product(cruiseSpeed, UInt64(ratio)).dividedRoundingDown(by: full).low
        func time(_ speed: UInt64, _ rate: Int64) -> WideInteger {
            WideInteger.product(speed, UInt64(inverseAcceleration)).dividedRoundingDown(by: rate).shiftedRight(by: 16)
        }
        let accelerationTime = time(cruiseSpeed, acceleration)
        let coastTime = coasting ? time(cruiseSpeed - brakingSpeed, coastDeceleration) : WideInteger(0 as UInt64)
        let brakingTime = time(brakingSpeed, braking)
        let whole = WideInteger(duration).shiftedLeft(by: 16)
        let moving = accelerationTime + coastTime + brakingTime
        guard moving <= whole else { return nil }
        let cruiseTime = (whole - moving).int64
        // vc × 2^32 < 2^47, so vc² × 2^64 × 28,125,000 < 2^119: the distances
        // below fit.
        func distance(_ squaredSpeeds: WideInteger, _ rate: Int64) -> Int64 {
            squaredSpeeds.multiplied(by: UInt64(inverseAcceleration / 2)).dividedRoundingDown(by: rate)
                .shiftedRight(by: 48).int64
        }
        let cruiseSquared = WideInteger.product(cruiseSpeed, cruiseSpeed)
        let accelerationDistance = distance(cruiseSquared, acceleration)
        let cruiseDistance = WideInteger.product(cruiseSpeed, UInt64(cruiseTime)).shiftedRight(by: 32).int64
        let coastDistance = coasting
            ? distance(cruiseSquared - WideInteger.product(brakingSpeed, brakingSpeed), coastDeceleration)
            : 0
        return RunningCurve(
            length: length, duration: duration, acceleration: acceleration, braking: braking,
            coastDeceleration: coasting ? coastDeceleration : 0,
            cruiseSpeed: cruiseSpeed, brakingSpeed: brakingSpeed,
            accelerationTime: accelerationTime.int64, cruiseTime: cruiseTime,
            coastTime: coastTime.int64, brakingTime: brakingTime.int64,
            accelerationDistance: accelerationDistance, cruiseDistance: cruiseDistance,
            coastDistance: coastDistance
        )
    }

    /// `profTimeToProg(p, t) × L`: how far the train has run `time`
    /// milliseconds after leaving, in world units (rounded down). 0 up to
    /// the start and ``length`` from ``duration`` on. The reference returns
    /// the trapezoid's value unclamped; the integer value can be a unit
    /// beyond either end, so it is kept in `0...length`.
    public func distance(at time: Int64) -> Int64 {
        guard time > 0 else { return 0 }
        guard time < duration else { return length }
        let moment = time << 16
        let value: Int64
        if moment < accelerationTime {
            // ½·a·t² = a·t² ÷ 112,500,000, straight from the whole time.
            value = WideInteger.product(time, time).multiplied(by: acceleration)
                .dividedRoundingDown(by: 2 * Self.inverseAcceleration).int64 << 16
        } else if moment < accelerationTime + cruiseTime {
            value = accelerationDistance + run(cruiseSpeed, for: moment - accelerationTime)
        } else if moment < accelerationTime + cruiseTime + coastTime {
            let elapsed = moment - accelerationTime - cruiseTime
            value = accelerationDistance + cruiseDistance + run(cruiseSpeed, for: elapsed)
                - slowing(coastDeceleration, for: elapsed)
        } else {
            let elapsed = moment - accelerationTime - cruiseTime - coastTime
            value = accelerationDistance + cruiseDistance + coastDistance + run(brakingSpeed, for: elapsed)
                - slowing(braking, for: elapsed)
        }
        return min(max(value >> 16, 0), length)
    }

    /// `profProgToTime(p, distance ÷ L)`: how many milliseconds after
    /// leaving the train has run `distance` world units (rounded down). 0 up
    /// to the start and ``duration`` from ``length`` on.
    public func time(atDistance distance: Int64) -> Int64 {
        guard distance > 0 else { return 0 }
        guard distance < length else { return duration }
        let point = distance << 16
        let value: Int64
        if point < accelerationDistance {
            // √(2d/a) = √(d × 112,500,000 ÷ a), taken × 2^16.
            value = Int64(WideInteger.product(distance, 2 * Self.inverseAcceleration).shiftedLeft(by: 32)
                .dividedRoundingDown(by: acceleration).squareRoot())
        } else if point < accelerationDistance + cruiseDistance {
            value = accelerationTime + WideInteger(point - accelerationDistance).shiftedLeft(by: 32)
                .dividedRoundingDown(by: cruiseSpeed).int64
        } else if point < accelerationDistance + cruiseDistance + coastDistance {
            let rest = point - accelerationDistance - cruiseDistance
            value = accelerationTime + cruiseTime
                + (remainingSlowdown(from: cruiseSpeed, rate: coastDeceleration, over: rest) ?? coastTime)
        } else {
            let rest = max(0, point - accelerationDistance - cruiseDistance - coastDistance)
            value = accelerationTime + cruiseTime + coastTime
                + (remainingSlowdown(from: brakingSpeed, rate: braking, over: rest) ?? brakingTime)
        }
        return min(max(value >> 16, 0), duration)
    }

    /// v·τ × 2^16 world units for a speed × 2^32 and a time × 2^16.
    private func run(_ speed: UInt64, for elapsed: Int64) -> Int64 {
        WideInteger.product(speed, UInt64(elapsed)).shiftedRight(by: 32).int64
    }

    /// ½·r·τ² × 2^16 world units for a rate r in thousandths of a km/h per
    /// second and a time × 2^16: r·τ² ÷ (112,500,000 × 2^16).
    private func slowing(_ rate: Int64, for elapsed: Int64) -> Int64 {
        WideInteger.product(elapsed, elapsed).multiplied(by: rate)
            .dividedRoundingDown(by: 2 * Self.inverseAcceleration).shiftedRight(by: 16).int64
    }

    /// (v − √(v² − 2r·d)) ÷ r × 2^16 ms: the time to cover `rest` (world
    /// units × 2^16) while slowing from `speed` at `rate`, or `nil` where
    /// the reference's discriminant is not positive.
    private func remainingSlowdown(from speed: UInt64, rate: Int64, over rest: Int64) -> Int64? {
        // v² × 2^64, and 2r·d × 2^64 = r·d × 2^49 ÷ 56,250,000 for d × 2^16.
        let squared = WideInteger.product(speed, speed)
        let lost = WideInteger.product(rate, rest).shiftedLeft(by: 49).dividedRoundingDown(by: Self.inverseAcceleration)
        guard lost < squared else { return nil }
        let root = (squared - lost).squareRoot()
        return WideInteger.product(speed - root, UInt64(Self.inverseAcceleration)).dividedRoundingDown(by: rate)
            .shiftedRight(by: 16).int64
    }
}
