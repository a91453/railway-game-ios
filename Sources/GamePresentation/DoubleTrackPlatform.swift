import GameCore

// A platform on both tracks of a double line (decision 285, TestFlight
// 70.1): a double track drawn from open ground has no crossover between its
// two tracks (decision 204, later: only an end that joins track already
// there gets one), so a player who taps one track for one station's
// platform and the other track for the next station's has two stations no
// train can run between. So where the platform tool picks a track with
// another beside it (``trackBeside(_:near:)``, decision 247) that no track
// joins it to, the same command gives the same station a platform on that
// one too, opposite it: trains on either track call there. Where the two
// already meet (a crossover, a switch at an end) the platform goes on the
// track tapped only, as before, so a side platform on one track is still
// the player's to build. Neither reference has a platform tool for double
// track (`Simulator/` places platform pieces by hand, `MapBuilder/` adds
// stations by place): this is native.
//
// Decision 571 (TestFlight 110.1, "a double track, but the trains are
// always deadlocked"): platforms on both tracks are not enough. With no
// crossover between the two stations, a line still runs on one of the two
// (GameCore counts the tracks between two stations as double only where
// both are joined at both ends, `parallelTracks`), so two trains on it meet
// head on. So where the tool puts a platform on both tracks it also lays a
// crossover just past each end of the pair, on the line's side, where there
// is room and no turnout already lies within ``DoubleTrack/stationCrossoverReach``
// on that side; and "where the two already meet" now means "meet within
// ``DoubleTrack/stationThroat`` of the platform": the first station's
// crossover no longer keeps the second station, at the line's far end, on
// one track.

/// ``GameSession/networkPlatformBeside`` as last looked for (L3-11).
struct PlatformBesideMemo {
    struct Key: Equatable {
        let edge: TrackEdgeID
        let start: Int64
        let end: Int64
        let commandRevision: Int
    }

    let key: Key
    let beside: (edge: TrackEdgeID, start: Int64, end: Int64)?
}

extension GameSession {
    /// The stretch of the track beside the platform's `stretch`, opposite
    /// it, when that track is joined to it by no track at all; `nil`
    /// otherwise, when the track beside is not the same edge along the
    /// whole stretch, or has a platform there already.
    ///
    /// `joined` (DEMO-KRTC, 2026-11-12) also gives the stretch where a
    /// switch near by joins the two tracks: the demo's real lines, whose
    /// runs end in a crossover beyond the last platform, so a train coming
    /// back on the second track had no platform to call at there.
    func besidePlatformStretch(
        of stretch: (edge: TrackEdgeID, start: Int64, end: Int64), joined: Bool = false
    ) -> (edge: TrackEdgeID, start: Int64, end: Int64)? {
        guard let geometry = world.trackGeometry(of: stretch.edge) else { return nil }
        // Decision 571: a platform reaching the end of its edge is looked
        // beside just inside it; the end itself is no place on the edge
        // (``GameWorld/nearestPoint(onEdge:to:)``), and the track beside
        // was then looked for at the edge's middle, giving the platform
        // beside it the stretch from there.
        //
        // DEMO-KRTC (2026-11-12): the track beside is found a little way
        // inside each end, not a unit inside. A second track's joints
        // stand a few units along from the first's (each rounded to whole
        // units on its own curve), so a unit inside the end of an edge the
        // nearest track beside was as often the next edge's first unit,
        // and a platform the whole of its edge got none beside it: half
        // the stations of the demo's real Kaohsiung lines, whose trains
        // then had no way along the line. Where the platform ends is then
        // measured on that edge.
        let inset = min(DoubleTrack.besideInset, max(1, (stretch.end - stretch.start) / 4))
        let inside = [max(stretch.start + inset, 1), min(stretch.end - inset, geometry.length - 1)].map { geometry.location(at: $0).position.plan }
        guard let first = trackBeside(stretch.edge, near: inside[0])?.beside,
              let last = trackBeside(stretch.edge, near: inside[1])?.beside,
              first.edge == last.edge, let beside = world.trackGeometry(of: first.edge),
              // Decision 571: joined by a switch near by, not any far away.
              joined || !world.tracksMeet([stretch.edge], [first.edge]) || !turnoutNear(stretch, within: DoubleTrack.stationThroat)
        else { return nil }
        // Each end of the platform on the track beside: as far past where
        // it was found as the platform goes on, no further than the edge.
        let before = max(stretch.start + inset, 1) - stretch.start, after = stretch.end - min(stretch.end - inset, geometry.length - 1)
        let forward = last.distance >= first.distance
        let start = max(0, min(first.distance, last.distance) - (forward ? before : after))
        let end = min(beside.length, max(first.distance, last.distance) + (forward ? after : before))
        // A platform there already: GameCore would not overlap it.
        guard end > start, !world.network.platforms(on: first.edge).contains(where: { $0.start < end && start < $0.end }) else { return nil }
        return (first.edge, start, end)
    }

    /// The platform beside the one on `stretch` (``besidePlatformStretch(of:)``),
    /// levelled first where it is on a grade (decision 190); `nil` where
    /// there is none to add, or it cannot be levelled.
    func besidePlatform(of stretch: (edge: TrackEdgeID, start: Int64, end: Int64), joined: Bool = false) -> PlayerCommand.BesidePlatform? {
        guard let other = besidePlatformStretch(of: stretch, joined: joined) else { return nil }
        var levelling: PlatformLevelling?
        if platformGrade(of: other) != nil {
            guard case .success(let found) = platformLevelling(of: other.edge, from: other.start, to: other.end, in: world) else { return nil }
            levelling = found
        }
        return PlayerCommand.BesidePlatform(edge: other.edge, start: other.start, end: other.end, levelling: levelling)
    }

    /// How steeply `stretch` climbs or falls, in whole per mille, at least
    /// 1; `nil` where it is level.
    func platformGrade(of stretch: (edge: TrackEdgeID, start: Int64, end: Int64)) -> Int64? {
        guard let geometry = world.trackGeometry(of: stretch.edge) else { return nil }
        let rise = abs(geometry.height(at: stretch.end) - geometry.height(at: stretch.start))
        let run = stretch.end - stretch.start
        guard rise > 0, run > 0 else { return nil }
        return max(1, (rise * 1_000 + run / 2) / run)
    }

    /// Whether a turnout (a node where three or more track ends meet)
    /// lies along the track from either end of the platform's `stretch`
    /// within `limit` (decision 571), following the track through plain
    /// joints.
    func turnoutNear(_ stretch: (edge: TrackEdgeID, start: Int64, end: Int64), within limit: Int64) -> Bool {
        [false, true].contains { turnout(from: stretch, forward: $0, within: limit) }
    }

    /// Whether a turnout lies along the track from the `forward` end (its
    /// `end`, else its `start`) of `stretch` within `limit`, in `base`
    /// (this session's world by default).
    func turnout(
        from stretch: (edge: TrackEdgeID, start: Int64, end: Int64), forward: Bool, within limit: Int64, in base: GameWorld? = nil
    ) -> Bool {
        let world = base ?? self.world
        guard let edge = world.network.edge(stretch.edge) else { return false }
        var travelled = forward ? edge.length - stretch.end : stretch.start
        var node = forward ? edge.to : edge.from
        var came = stretch.edge
        // A ring of plain joints ends the walk once round.
        for _ in 0..<world.network.edges.count {
            guard travelled <= limit, let ends = world.network.node(node)?.ends else { return false }
            if ends.count >= 3 { return true }
            guard ends.count == 2, let next = ends.first(where: { $0.edge != came }), let nextEdge = world.network.edge(next.edge) else { return false }
            travelled += nextEdge.length
            node = nextEdge.from == node ? nextEdge.to : nextEdge.from
            came = next.edge
        }
        return false
    }

    /// The crossovers a platform on both tracks gets (decision 571): one
    /// just past each end of `stretch` where the track runs on, on the
    /// same edges, far enough for one, with no turnout within
    /// ``DoubleTrack/stationCrossoverReach`` on that side; each from the
    /// track beside over to the tapped one, as the double track's
    /// crossover at a joined end (decision 204, later). Planned in turn on
    /// `world`, the world with the platforms built, each seeing the one
    /// before; a crossover GameCore refuses there (too steep, in the way)
    /// is left out, and one it refuses for want of money is kept, so the
    /// command is refused as a whole.
    ///
    /// Decision 572: `lookingIn`, the world whose track `stretch` and the
    /// track beside are read from, this session's by default (the platform
    /// tool's `world` is it with platforms added); a station's missing
    /// crossovers (``missingStationCrossovers(of:in:)``) are looked for in
    /// the draft itself.
    func stationCrossovers(
        of stretch: (edge: TrackEdgeID, start: Int64, end: Int64), in world: GameWorld, lookingIn: GameWorld? = nil
    ) -> [PlayerCommand.TrackStretch] {
        let track = lookingIn ?? self.world
        guard let geometry = track.trackGeometry(of: stretch.edge) else { return [] }
        let margin = DoubleTrack.crossoverMargin, reach = DoubleTrack.crossoverReach
        var pairs: [(onBeside: WorldCoordinate, onTrack: WorldCoordinate)] = []
        for forward in [false, true] {
            guard !turnout(from: stretch, forward: forward, within: DoubleTrack.stationCrossoverReach, in: track) else { continue }
            // Along the tapped edge: the turnout on it, then where the
            // crossover meets the track beside, one reach further out.
            let near = forward ? stretch.end + margin : stretch.start - margin
            let far = forward ? near + reach : near - reach
            guard min(near, far) >= margin, max(near, far) <= geometry.length - margin,
                  let beside = trackBeside(stretch.edge, near: geometry.location(at: far).position.plan, in: track)?.beside,
                  let other = track.trackGeometry(of: beside.edge),
                  beside.distance >= margin, beside.distance <= other.length - margin
            else { continue }
            pairs.append((other.location(at: beside.distance).position, geometry.location(at: near).position))
        }
        var draft = world
        var stretches: [PlayerCommand.TrackStretch] = []
        for pair in pairs {
            guard let crossover = crossoverStretch(from: pair.onBeside, to: pair.onTrack, in: draft) else { continue }
            do throws(GameError) {
                _ = try crossover.build(in: &draft, heights: heights)
            } catch {
                if case .insufficientFunds = error { stretches.append(crossover) }
                continue
            }
            stretches.append(crossover)
        }
        return stretches
    }

    /// What the platform tool's message adds when the track beside got a
    /// platform too.
    func besidePlatformText() -> String {
        language.text(
            " The track beside it gets a platform too, so trains on either track call here.",
            "旁邊的軌道也設了月台，兩條軌道的列車都能停這一站。"
        )
    }

    /// What the platform tool's preview and message add for the station's
    /// crossovers (decision 571).
    func stationCrossoverText(_ count: Int, built: Bool) -> String {
        switch (count, built) {
        case (0, _): ""
        case (1, false): language.text(", and a crossover beside it", "，旁邊加一組渡線")
        case (_, false): language.text(", and a crossover at each end", "，兩端各加一組渡線")
        case (1, true):
            language.text(
                " A crossover joins the two tracks beside it, so trains can pass on the double track.",
                "旁邊加了一組渡線連接兩條軌道，列車可以在複線上交會。"
            )
        case (_, true):
            language.text(
                " A crossover at each end joins the two tracks, so trains can pass on the double track.",
                "兩端各加了一組渡線連接兩條軌道，列車可以在複線上交會。"
            )
        }
    }
}
