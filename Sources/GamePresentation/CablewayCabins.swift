import GameCore

// Decision 574 (PR-2): where a cable car's cabins are at a moment, for the
// 3D map (decision 575) and anything else that draws them. GameCore keeps
// no cabins: they run a fixed loop one ``Cableway/cabinIntervalSeconds``
// apart, so where each one is follows from the time alone. A pure
// function: nothing kept, the same answer for the same cable car and
// second.
//
// The loop: out along each span at ``Cableway/metresPerSecond``, through
// each stop after it in ``Cableway/stopPassSeconds`` (the last, where it
// turns round, too), and back the same way to the first stop, where it
// turns again. OpenWorld's Sun Moon Lake ropeway does the same with six
// cabins on a fixed cycle (`sunmoon-ropeway.js`: 48 s running, 5 s in a
// station); here the cycle comes from the rope's length, and there are as
// many cabins as fit at the interval (the Maokong Gondola's 4,033 m take
// some 175; it has 136, decision 574).

/// The cabins of a cable car at a moment.
public enum CablewayCabins {
    /// Where a cabin is.
    public enum Place: Hashable, Sendable {
        /// On span `leg` (between stops `leg` and `leg + 1`), `permille`
        /// of the way from stop `leg`; `outbound` runs towards the last
        /// stop, else back (the 3D map puts the two ropes either side).
        case span(leg: Int, permille: Int, outbound: Bool)
        /// In stop `stop`: passing through, turning round at an end, or
        /// put away there while the cable car stands still; `outbound` the
        /// way it goes on.
        case station(stop: Int, outbound: Bool)
    }

    public struct Cabin: Hashable, Sendable {
        /// 0 up: the same cabin from one moment to the next.
        public let number: Int
        /// A crystal cabin, with a glass floor: two in nine (the Maokong
        /// Gondola's 30 of 136).
        public let crystal: Bool
        public let place: Place
    }

    /// Seconds once round the loop: each span out and back at
    /// ``Cableway/metresPerSecond`` (rounded up), and
    /// ``Cableway/stopPassSeconds`` at every stop passed or turned at.
    public static func loopSeconds(of cableway: Cableway) -> Int64 {
        2 * cableway.legMetres.map(spanSeconds).reduce(0, +) + 2 * Int64(cableway.stops.count - 1) * Cableway.stopPassSeconds
    }

    /// How many cabins run: as many as fit round the loop at the
    /// interval, one at least.
    public static func count(of cableway: Cableway) -> Int {
        Int(max(1, loopSeconds(of: cableway) / Cableway.cabinIntervalSeconds))
    }

    /// Whether the cabins run at `time` on `world`: on a day the cable car
    /// runs (``GameWorld/cablewayIsOpen(_:onDay:)``), within its hours
    /// (from 9:00, ``Cableway/operatingHours(onDay:)``).
    public static func runs(_ id: CablewayID, in world: GameWorld, at time: GameTime) -> Bool {
        let day = time.seconds / GameTime.secondsPerDay, second = time.seconds % GameTime.secondsPerDay
        guard world.cablewayIsOpen(id, onDay: day) else { return false }
        return second >= 9 * 3_600 && second < (9 + Cableway.operatingHours(onDay: day)) * 3_600
    }

    /// Every cabin of `cableway` at second `second` (of the day, or any
    /// count of seconds: only its place in the loop matters). With `open`
    /// false (``runs(_:in:at:)``) they stand in the two end stations, half
    /// in each.
    public static func cabins(of cableway: Cableway, atSecond second: Int64, open: Bool) -> [Cabin] {
        let count = count(of: cableway), last = cableway.stops.count - 1
        guard open else {
            return (0..<count).map { number in
                Cabin(number: number, crystal: isCrystal(number), place: .station(stop: number.isMultiple(of: 2) ? 0 : last, outbound: number.isMultiple(of: 2)))
            }
        }
        let loop = loopSeconds(of: cableway)
        return (0..<count).map { number in
            let behind = Int64(number) * Cableway.cabinIntervalSeconds
            let at = ((second - behind) % loop + loop) % loop
            return Cabin(number: number, crystal: isCrystal(number), place: place(at: at, on: cableway))
        }
    }

    /// The point on the map under `place`: along the straight span
    /// between the two stops' cells' middles, or a stop's middle. The
    /// height, the towers and the rope's sag are the 3D map's.
    public static func planPoint(of place: Place, in cableway: Cableway) -> PlanPoint {
        switch place {
        case .station(let stop, _):
            return cableway.stops[stop].cell.middle
        case .span(let leg, let permille, _):
            let from = cableway.stops[leg].cell.middle, to = cableway.stops[leg + 1].cell.middle
            return PlanPoint(x: from.x + (to.x - from.x) * Int64(permille) / 1_000, y: from.y + (to.y - from.y) * Int64(permille) / 1_000)
        }
    }

    /// Decision 583 (CABLEFOLLOW): where a cabin is between whole seconds,
    /// for the one the 3D map follows: ``place(at:on:)`` with the fraction
    /// of a second, and through a stop the way it came in and the way it
    /// goes on, so the followed cabin moves on without a jump.
    public enum Glide: Equatable, Sendable {
        /// On span `leg`, `share` (0–1) of the way from stop `leg`.
        case span(leg: Int, share: Double, outbound: Bool)
        /// In stop `stop`, `share` (0–1) of the way through it, come in
        /// `arrivedOutbound` and going on `leavesOutbound` (they differ
        /// where it turns round).
        case station(stop: Int, share: Double, arrivedOutbound: Bool, leavesOutbound: Bool)
    }

    /// Cabin `number` of `cableway` at second `second` (any count of
    /// seconds, with its fraction), running.
    public static func glide(of number: Int, on cableway: Cableway, atSecond second: Double) -> Glide {
        let loop = Double(loopSeconds(of: cableway))
        let behind = Double(number) * Double(Cableway.cabinIntervalSeconds)
        var at = (second - behind).truncatingRemainder(dividingBy: loop)
        if at < 0 { at += loop }
        return glide(at: at, on: cableway)
    }

    /// The same `at` seconds into the loop.
    static func glide(at: Double, on cableway: Cableway) -> Glide {
        var left = at
        let legs = cableway.legMetres.map { Double(spanSeconds($0)) }
        let pass = Double(Cableway.stopPassSeconds)
        for (leg, seconds) in legs.enumerated() {
            if left < seconds { return .span(leg: leg, share: left / seconds, outbound: true) }
            left -= seconds
            if left < pass { return .station(stop: leg + 1, share: left / pass, arrivedOutbound: true, leavesOutbound: leg + 1 < legs.count) }
            left -= pass
        }
        for leg in legs.indices.reversed() {
            let seconds = legs[leg]
            if left < seconds { return .span(leg: leg, share: 1 - left / seconds, outbound: false) }
            left -= seconds
            if left < pass || leg == 0 { return .station(stop: leg, share: min(left / pass, 1), arrivedOutbound: false, leavesOutbound: leg == 0) }
            left -= pass
        }
        return .station(stop: 0, share: 1, arrivedOutbound: false, leavesOutbound: true)
    }

    /// The stop a cabin at `glide` comes to next (in a stop, the one after
    /// it the way it goes on), and the stop it stands in, if any.
    public static func stops(of glide: Glide, on cableway: Cableway) -> (at: Int?, next: Int) {
        let last = cableway.stops.count - 1
        switch glide {
        case .span(let leg, _, let outbound):
            return (nil, outbound ? leg + 1 : leg)
        case .station(let stop, _, _, let leaves):
            return (stop, leaves ? min(stop + 1, last) : max(stop - 1, 0))
        }
    }

    // MARK: - Internals

    static func spanSeconds(_ metres: Int64) -> Int64 {
        (metres + Cableway.metresPerSecond - 1) / Cableway.metresPerSecond
    }

    static func isCrystal(_ number: Int) -> Bool {
        number % 9 < 2
    }

    /// Where a cabin `at` seconds into the loop is.
    static func place(at: Int64, on cableway: Cableway) -> Place {
        var left = at
        let legs = cableway.legMetres.map(spanSeconds)
        // Out: span i, then stop i + 1.
        for (leg, seconds) in legs.enumerated() {
            if left < seconds { return .span(leg: leg, permille: Int(left * 1_000 / seconds), outbound: true) }
            left -= seconds
            if left < Cableway.stopPassSeconds { return .station(stop: leg + 1, outbound: leg + 1 < legs.count) }
            left -= Cableway.stopPassSeconds
        }
        // Back: span i, then stop i.
        for leg in legs.indices.reversed() {
            let seconds = legs[leg]
            if left < seconds { return .span(leg: leg, permille: 1_000 - Int(left * 1_000 / seconds), outbound: false) }
            left -= seconds
            if left < Cableway.stopPassSeconds || leg == 0 { return .station(stop: leg, outbound: leg == 0) }
            left -= Cableway.stopPassSeconds
        }
        return .station(stop: 0, outbound: true)
    }
}
