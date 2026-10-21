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

    /// What ✓ pays for the platform picked (``platformSitePlanPoint``):
    /// levelling its stretch (``networkPlatformLevelling``), and for a new
    /// station the station and clearing what stands where it goes, as
    /// `GameWorld.buildStation(named:at:)` charges; the platform itself is
    /// free. `nil` when nothing is picked, it costs nothing, or the
    /// stretch cannot be levelled.
    public var networkPlatformCost: Money? {
        guard platformSitePlanPoint != nil, let stretch = networkPlatformStretch,
              let geometry = world.trackGeometry(of: stretch.edge) else { return nil }
        var total = Money.zero
        // The new station stands at the middle of the platform, on the
        // level stretch once levelled, and clears what stands there then
        // (decision 245: ✓'s price is what is paid).
        var clearing: Money
        let middle = geometry.location(at: (stretch.start + stretch.end) / 2).position.plan
        clearing = world.clearingCost(of: world.placedBuildings(inTheWayOf: [middle]))
        if let levelling = networkPlatformLevelling {
            guard let cost = levelling.cost else { return nil }
            total = total + cost
            clearing = levelling.stationClearing ?? clearing
        }
        // Decision 285: the track beside is levelled too where it is on a
        // grade (left out, as ✓ leaves it, where it cannot be).
        if let beside = besidePlatform(of: stretch), let levelling = beside.levelling {
            var draft = world.pricingCopy()
            if (try? build(levelling, in: &draft)) != nil {
                total = total + Money(GameWorld.pricingBalance.amount - draft.economy.balance.amount)
            }
        }
        if platformStationID.flatMap({ world.station(id: $0) }) == nil {
            total = total + world.economy.costs.station + clearing
        }
        return total > .zero ? total : nil
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

    /// What the map says of the platform site (``platformSitePlanPoint``):
    /// its catchment (``catchmentText(_:)``), and by the map's edge that a
    /// station there is an outside connection (decision 137): "Outside
    /// connection: +$10 a trip". That is said of the station the platform
    /// joins (``platformStationID``), or of a new one where
    /// ``addNetworkPlatform()`` builds it, at the middle of the stretch.
    public func platformSiteCaption(_ totals: LandTotals, at site: PlanPoint) -> String {
        let catchment = catchmentText(totals)
        let outside: Bool
        if let id = platformStationID, world.station(id: id) != nil {
            outside = world.isOutsideConnection(id)
        } else if let stretch = networkPlatformStretch, let geometry = world.trackGeometry(of: stretch.edge) {
            outside = world.isOutsideConnectionSite(geometry.location(at: (stretch.start + stretch.end) / 2).position.plan)
        } else {
            outside = world.isOutsideConnectionSite(site)
        }
        guard outside else { return catchment }
        let fare = world.outsideFare.moneyText
        return catchment + "\n" + language.text("Outside connection: +\(fare) a trip", "外地連絡站：每趟多收 \(fare)")
    }

    /// An outside connection as its opening says it (decision 137):
    /// "Outside connection: travellers from beyond the map's edge ride from
    /// here, paying $10 more a trip."
    var outsideConnectionText: String {
        let fare = world.outsideFare.moneyText
        return language.text(
            "Outside connection: travellers from beyond the map's edge ride from here, paying \(fare) more a trip.",
            "外地連絡站：地圖外的旅客由這裡進出，每趟多付 \(fare)。"
        )
    }
}
