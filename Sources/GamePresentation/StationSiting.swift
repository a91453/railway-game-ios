import GameCore

// Choosing where a station goes (ARCHITECTURE decision 108, UI/UX step
// UX-5d): while the network tool's platform mode has a place on track
// picked, the map shows who lives and works within a station's walk of
// it, so the player sees what a station there would serve before
// building it. The count is the land GameCore's station demand draws on
// (``Land/totals(within:of:)`` over ``Land/catchmentRadius``, 800 m), so
// it is what the station would actually get, on a blank map and a
// real-world one alike. SimCity BuildIt shows what a building would add
// on the ghost being placed, and TheoTown colours the ground good or bad
// for it; the reference has nothing to port.

extension GameSession {
    /// Where the next platform would go: the place on track picked with
    /// the network tool's platform mode, on the plan; `nil` otherwise.
    public var platformSitePlanPoint: PlanPoint? {
        guard tool == .network, networkMode == .platform, let point = networkEdgePoint else { return nil }
        return planPoint(of: .track(point))
    }

    /// Who lives and works within a station's catchment of the platform
    /// site (``platformSitePlanPoint``): `nil` when none is picked.
    public var platformSiteCatchment: LandTotals? {
        platformSitePlanPoint.map { world.land.totals(within: Land.catchmentRadius, of: $0) }
    }

    /// `totals` as the map says it: "Within 800 m: 12,345 residents ·
    /// 6,789 jobs".
    public func catchmentText(_ totals: LandTotals) -> String {
        let residents = Money(totals.residents).displayText, jobs = Money(totals.jobs).displayText
        return language.text(
            "Within 800 m: \(residents) residents · \(jobs) jobs",
            "800 公尺內：居民 \(residents) · 工作 \(jobs)"
        )
    }
}
