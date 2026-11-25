import Foundation
import GameCore

// How tight a traced edge may turn, how steep a mountain edge is laid,
// and the level a traced station stands at (decisions 401, 752, 973).

extension GameSession {
    /// The tightest curve a traced edge may have on the TRA and the High
    /// Speed Rail: 40 m, the forest railway's tightest. GameCore has no curve radius (a stretch may turn
    /// up to 90° where it joins, decision 103); this only stops a trace
    /// where a kink in the real line's drawing, or a link between two
    /// lines, would bend the track into a hairpin. Measured as the
    /// reference's `radiusAtPoint` does (`Ci/`), at sixteenths along the
    /// edge.
    static let traceMinimumRadius = 40 * RealRailwayTraces.metre
    /// The tightest on the metros and light rails (decision 401's sequel):
    /// 20 m. Their real lines turn tighter than the forest railway's, the
    /// Wenhu Line about 35 m round its corners and Kaohsiung's Circular
    /// Line 26 m, and 40 m left gaps in them. Since decision 515 the
    /// Alishan Forest Railway's too: its drawn line measures 28 to 39 m
    /// round its real 40 m curves, and 40 m stopped every trace of it
    /// within a station or two.
    static let urbanTraceMinimumRadius = 20 * RealRailwayTraces.metre
    /// The tightest on a mountain line (decision 973): 12 m. The Alishan
    /// Forest Railway's drawn line measures 16 to 19 m at a few places
    /// round its real 40 m curves (the Dulishan spiral, above Erwanping,
    /// the Zhushan Line), and 20 m stopped a trace at each; where its
    /// trains reverse (the switchbacks) the way measures 3 to 6 m, and
    /// still stops.
    static let mountainTraceMinimumRadius = 12 * RealRailwayTraces.metre
    /// Under this, a way that also faces back within 60 m is
    /// a place where trains reverse, not a curve (decision 973): the
    /// switchbacks measure 3 to 6 m, the spiral's and the hairpins' real
    /// curves 16 m and more.
    static let reversalRadius = 10 * RealRailwayTraces.metre
    /// The steepest a traced mountain edge is laid (decision 973): just
    /// under GameCore's 70‰.
    static let mountainEdgeGrade = 0.069

    /// Decision 752: the level a traced station's stretch is laid at
    /// where it stands on a long real viaduct or in a long real tunnel,
    /// `level` (between the heights the track would have along it) moved
    /// to keep the whole stretch as high over `ground` (the ground along
    /// the structure's part of it) as ``TrackRise/carriedHeight`` asks of
    /// a viaduct, or as deep under it as ``TrackRise/carriedDepth`` asks
    /// of a tunnel. A level the structure's bounds clash with lets them go
    /// (``TrackRise``), and the station came down to the ground.
    static func tracedStationLevel(_ level: TrackRise.Level, on structure: TrackRise.Carried, ground: [Double]) -> TrackRise.Level {
        guard let highest = ground.max(), let lowest = ground.min() else { return level }
        switch structure.kind {
        case .bridge:
            let floor = highest + TrackRise.carriedHeight
            return TrackRise.Level(level.range, from: max(level.low, floor), to: max(level.high, floor))
        case .tunnel:
            let ceiling = lowest - TrackRise.carriedDepth
            var under = TrackRise.Level(level.range, from: min(level.low, ceiling), to: min(level.high, ceiling))
            under.staysUnder = true
            return under
        }
    }

    /// The tightest curve a traced edge of `system`'s line may have.
    static func traceMinimumRadius(ofSystem system: String?) -> Double {
        switch system {
        case nil, "tra_sched", "thsr_sched": traceMinimumRadius
        case let system? where mountainSystems.contains(system): mountainTraceMinimumRadius
        default: urbanTraceMinimumRadius
        }
    }

    /// The tightest radius along `stretch`'s curve in world units; `nil`
    /// for a straight edge.
    static func tightestRadius(of stretch: PlayerCommand.TrackStretch) -> Double? {
        guard case .cubic(let c1, let c2) = stretch.curve else { return nil }
        let p0 = WorldVector(stretch.from.plan), p1 = WorldVector(c1), p2 = WorldVector(c2), p3 = WorldVector(stretch.to.plan)
        func point(_ t: Double) -> WorldVector {
            let u = 1 - t
            return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
        }
        var tightest = Double.infinity
        for step in 1..<16 {
            let a = point(Double(step - 1) / 16), b = point(Double(step) / 16), c = point(Double(step + 1) / 16)
            // The circle through three points: abc / 4·area (Heron).
            let ab = (b - a).length, bc = (c - b).length, ca = (a - c).length
            let twiceArea = abs((b - a).x * (c - a).y - (b - a).y * (c - a).x)
            guard twiceArea > 1e-9 else { continue }
            tightest = min(tightest, ab * bc * ca / (2 * twiceArea))
        }
        return tightest.isFinite ? tightest : nil
    }
}
