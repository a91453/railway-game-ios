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

extension GameSession {
    /// The stretch of the track beside the platform's `stretch`, opposite
    /// it, when that track is joined to it by no track at all; `nil`
    /// otherwise, when the track beside is not the same edge along the
    /// whole stretch, or has a platform there already.
    func besidePlatformStretch(of stretch: (edge: TrackEdgeID, start: Int64, end: Int64)) -> (edge: TrackEdgeID, start: Int64, end: Int64)? {
        guard let geometry = world.trackGeometry(of: stretch.edge) else { return nil }
        let ends = [stretch.start, stretch.end].map { geometry.location(at: $0).position.plan }
        guard let first = trackBeside(stretch.edge, near: ends[0])?.beside,
              let last = trackBeside(stretch.edge, near: ends[1])?.beside,
              first.edge == last.edge,
              !world.tracksMeet([stretch.edge], [first.edge])
        else { return nil }
        let start = min(first.distance, last.distance), end = max(first.distance, last.distance)
        // A platform there already: GameCore would not overlap it.
        guard end > start, !world.network.platforms(on: first.edge).contains(where: { $0.start < end && start < $0.end }) else { return nil }
        return (first.edge, start, end)
    }

    /// The platform beside the one on `stretch` (``besidePlatformStretch(of:)``),
    /// levelled first where it is on a grade (decision 190); `nil` where
    /// there is none to add, or it cannot be levelled.
    func besidePlatform(of stretch: (edge: TrackEdgeID, start: Int64, end: Int64)) -> PlayerCommand.BesidePlatform? {
        guard let other = besidePlatformStretch(of: stretch) else { return nil }
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

    /// What the platform tool's message adds when the track beside got a
    /// platform too.
    func besidePlatformText() -> String {
        language.text(
            " The track beside it gets a platform too, so trains on either track call here.",
            "旁邊的軌道也設了月台，兩條軌道的列車都能停這一站。"
        )
    }
}
