import GameCore

/// V3's independent fixed-point buildProfile. Native UInt128 replaces the
/// production WideInteger implementation. Inversion brackets exponentially, and
/// never calls RunningCurve or any GameCore simulation function.
struct ReferenceTrafficCurve {
    var length: Int64
    var seconds: Int64
    var acceleration: Int64
    var braking: Int64
    var coast: Int64
    var speed: UInt128
    var brakeSpeed: UInt128
    var ta: UInt128
    var tc: UInt128
    var tg: UInt128
    var da: UInt128
    var dc: UInt128
    var dg: UInt128

    static func root(_ x: UInt128) -> UInt128 {
        var answer: UInt128 = 0
        var bit: UInt128 = 1 << 126
        while bit > x { bit >>= 2 }
        var remainder = x
        while bit > 0 {
            if remainder >= answer + bit { remainder -= answer + bit; answer = (answer >> 1) + bit }
            else { answer >>= 1 }
            bit >>= 2
        }
        return answer
    }

    static func build(_ length: Int64, _ seconds: Int64, _ perf: TrainPerformance) -> Self? {
        guard length > 0, length <= 1 << 40, seconds > 0, seconds <= (1 << 32) / 1000 else { return nil }
        let rates = [(perf.acceleration, perf.braking)]
            + (perf.alternativeBraking.map { [(perf.acceleration, $0)] } ?? [])
            + (perf.alternativeAcceleration.flatMap { a in perf.alternativeBraking.map { [(a, $0)] } } ?? [])
        let full: UInt128 = 1000 << 14
        for (a, b) in rates {
            let c = perf.coast?.deceleration ?? 0
            func solve(_ ratio: UInt128) -> Self? {
                let t = UInt128(seconds * 1000), l = UInt128(length)
                let h: UInt128 = 28_125_000 << 24
                var d = h / UInt128(a) + h * ratio * (2 * full - ratio) / (full * full) / UInt128(b)
                if ratio < full { d += h * (full - ratio) * (full - ratio) / (full * full) / UInt128(c) }
                let squared = t * t << 24
                guard squared >= 4 * d * l else { return nil }
                let v = (2 * l << 44) / ((t << 12) + root(squared - 4 * d * l))
                guard v > 0, 225 * v <= UInt128(4 * perf.topSpeed) << 32 else { return nil }
                let vb = v * ratio / full
                let ta = (v * 56_250_000 / UInt128(a)) >> 16
                let tg: UInt128 = ratio < full ? ((v - vb) * 56_250_000 / UInt128(c)) >> 16 : 0
                let tb = (vb * 56_250_000 / UInt128(b)) >> 16
                guard ta + tg + tb <= t << 16 else { return nil }
                let tc = (t << 16) - ta - tg - tb
                return Self(length: length, seconds: seconds, acceleration: a, braking: b, coast: c,
                            speed: v, brakeSpeed: vb, ta: ta, tc: tc, tg: tg,
                            da: (v * v * 28_125_000 / UInt128(a)) >> 48,
                            dc: (v * tc) >> 32,
                            dg: ratio < full ? ((v * v - vb * vb) * 28_125_000 / UInt128(c)) >> 48 : 0)
            }
            guard var result = solve(full) else { continue }
            if let coast = perf.coast, coast.deceleration < b, coast.speedRatio < 1000 {
                let ratio = UInt128(coast.speedRatio) << 14
                if let deep = solve(ratio) { result = deep }
                else {
                    var low = ratio, high = full
                    for _ in 0..<14 {
                        let middle = (low + high) / 2
                        if let candidate = solve(middle) { high = middle; result = candidate } else { low = middle }
                    }
                }
            }
            return result
        }
        return nil
    }

    func distance(_ second: Int64) -> Int64 {
        if second <= 0 { return 0 }
        if second >= seconds { return length }
        let ms = UInt128(second * 1000), t = ms << 16
        let value: UInt128
        if t < ta { value = (UInt128(acceleration) * ms * ms / 112_500_000) << 16 }
        else if t < ta + tc { value = da + ((speed * (t - ta)) >> 32) }
        else {
            let glide = t < ta + tc + tg
            let dt = t - ta - tc - (glide ? 0 : tg)
            let base = da + dc + (glide ? 0 : dg)
            let rolling = ((glide ? speed : brakeSpeed) * dt) >> 32
            let lost = (UInt128(glide ? coast : braking) * dt * dt / 112_500_000) >> 16
            value = base + rolling >= lost ? base + rolling - lost : 0
        }
        return min(length, Int64(value >> 16))
    }

    func firstSecond(at distance: Int64) -> Int64 {
        guard distance > 0 else { return 0 }
        var upper: Int64 = 1
        while upper < seconds && self.distance(upper) < distance { upper = min(seconds, upper * 2) }
        var lower = upper / 2
        while lower + 1 < upper {
            let second = lower + (upper - lower) / 2
            if self.distance(second) >= distance { upper = second } else { lower = second }
        }
        return upper
    }
}
