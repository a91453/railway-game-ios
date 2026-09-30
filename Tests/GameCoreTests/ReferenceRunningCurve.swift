/// The owner's Railway reference (`index.html`: `buildProfile`,
/// `profTimeToProg`, `profProgToTime`), transliterated line by line in
/// `Double`, the way the JavaScript computes it, for the Stage W1
/// differential tests. Units are the reference's: metres, seconds, m/s and
/// m/s². Only the tests use floating point; GameCore's ``RunningCurve`` is
/// integers.
struct ReferenceRunningProfile {
    let T: Double
    let L: Double
    let a: Double
    let b: Double
    let c: Double
    let vc: Double
    let vb: Double
    let tAcc: Double
    let tCru: Double
    let tCoast: Double
    let tDec: Double
    let dAcc: Double
    let dCru: Double
    let dCoast: Double
    let rho: Double

    /// `buildProfile(Lkm, T, aK, bK, vK, coast)`, and how close any of its
    /// decisions came to going the other way, relative to its scale: a case
    /// that close is too close to call for a comparison with integers.
    static func build(
        Lkm: Double, T: Double, aK: Double, bK: Double, vK: Double, coast: (c: Double, rho: Double)?
    ) -> (profile: ReferenceRunningProfile?, margin: Double) {
        let L = Lkm * 1000, a = aK / 3.6, b = bK / 3.6, vmax = vK / 3.6
        guard L > 0, T > 0, a > 0, b > 0 else { return (nil, .infinity) }
        let cc = coast.map { $0.c > 0 ? $0.c / 3.6 : 0 } ?? 0
        let rho0 = coast.map { cc > 0 && cc < b && $0.rho >= 0 && $0.rho < 1 ? $0.rho : 1 } ?? 1
        var closest = Double.infinity
        func solve(_ rho: Double) -> ReferenceRunningProfile? {
            let glide = rho < 1
            let D = 1 / (2 * a) + (glide ? (1 - rho) * (1 - rho) / (2 * cc) : 0) + rho * (2 - rho) / (2 * b)
            let disc = T * T - 4 * D * L
            closest = min(closest, abs(disc) / (T * T))
            if disc < 0 { return nil }
            let vc = (T - disc.squareRoot()) / (2 * D)
            if !(vc > 0) { return nil }
            let vb = rho * vc
            let tAcc = vc / a, tCoast = glide ? (vc - vb) / cc : 0, tDec = vb / b
            let dAcc = vc * vc / (2 * a), dCoast = glide ? (vc * vc - vb * vb) / (2 * cc) : 0
            let tCru = T - tAcc - tCoast - tDec
            closest = min(closest, abs(tCru) / T)
            if !(tCru >= 0) { return nil }
            closest = min(closest, abs(vc - vmax) / vmax)
            return ReferenceRunningProfile(
                T: T, L: L, a: a, b: b, c: cc, vc: vc, vb: vb, tAcc: tAcc, tCru: tCru, tCoast: tCoast, tDec: tDec,
                dAcc: dAcc, dCru: vc * tCru, dCoast: dCoast, rho: rho
            )
        }
        guard var prof = solve(1), prof.vc <= vmax else { return (nil, closest) }
        if rho0 < 1 {
            if let deep = solve(rho0), deep.vc <= vmax {
                prof = deep
            } else {
                var lo = rho0, hi = 1.0
                for _ in 0..<14 {
                    let mid = (lo + hi) / 2
                    if let p = solve(mid), p.vc <= vmax { hi = mid; prof = p } else { lo = mid }
                }
            }
        }
        return (prof, closest)
    }

    /// `profTimeToProg(p, t)`, the non-observed branch.
    func progress(at t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= T { return 1 }
        let d: Double
        if t < tAcc {
            d = 0.5 * a * t * t
        } else if t < tAcc + tCru {
            d = dAcc + vc * (t - tAcc)
        } else if t < tAcc + tCru + tCoast {
            let tk = t - tAcc - tCru
            d = dAcc + dCru + vc * tk - 0.5 * c * tk * tk
        } else {
            let td = t - tAcc - tCru - tCoast
            d = dAcc + dCru + dCoast + vb * td - 0.5 * b * td * td
        }
        return d / L
    }

    /// `profProgToTime(p, f)`, the non-observed branch.
    func time(atProgress f: Double) -> Double {
        if f <= 0 { return 0 }
        if f >= 1 { return T }
        let d = f * L
        if d < dAcc { return (2 * d / a).squareRoot() }
        if d < dAcc + dCru { return tAcc + (d - dAcc) / vc }
        if d < dAcc + dCru + dCoast {
            let dk = d - dAcc - dCru, dis = vc * vc - 2 * c * dk
            return tAcc + tCru + (dis > 0 ? (vc - dis.squareRoot()) / c : tCoast)
        }
        let dd = d - dAcc - dCru - dCoast, disc = vb * vb - 2 * b * dd
        return tAcc + tCru + tCoast + (disc > 0 ? (vb - disc.squareRoot()) / b : tDec)
    }
}
