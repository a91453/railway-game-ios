import GameCore

// Decision 585 PR-4 (FERRYFOLLOW, 2026-11-05): the 3D map's camera following
// a boat of a player's ferry route, after following a cable car cabin
// (decision 583, `FollowCabin.swift`). Boats are not GameCore things: where
// each one is follows from the route's timetable and the clock
// (``Map3DFerries/numberedSailings(of:atSecond:open:)``), so the session
// keeps only the boat's ID (``FerryBoatID``) and reads the rest.
// Presentation only: nothing here changes the world, the save or a golden
// value.

/// What the follow bar shows of the boat followed, read through
/// ``GameSession/ferryFollowBar``.
public struct FerryFollowFacts: Equatable, Sendable {
    public var boat: FerryBoatID
    /// "Ferry 1".
    public var name: String
    /// "To Bali Pier".
    public var directionText: String
    /// "Next: Bali Pier · in at 10:26", "At Bali Pier · leaves 10:28",
    /// "At Tamsui Pier · next sailing 10:30".
    public var stopText: String
    public var runningSpeed: GameSpeed?
}

/// Decision 585 PR-4: where a boat is among its route's piers.
enum FerryBoats {
    /// The pier boat at `stage` lies at (`nil` while it crosses) and the
    /// one it sails to next, of `piers`; lying by the first pier with no
    /// sailing (`stage` `nil`), the first and the second.
    static func piers(of stage: Map3DFerries.Stage?, piers: Int) -> (at: Int?, next: Int) {
        let last = piers - 1
        switch stage {
        case nil: return (0, min(1, last))
        case .sailing(let leg, _, let outbound)?: return (nil, outbound ? leg + 1 : leg)
        case .docked(let pier, _, let outbound)?:
            if outbound { return (pier, pier == last ? pier - 1 : pier + 1) }
            return (pier, pier == 0 ? min(1, last) : pier - 1)
        }
    }
}

extension RealFerry {
    /// The real ferry `route` was laid as (its piers' names for the follow
    /// bar): the same piers on the same cells, the same crossings; `nil`
    /// for one the player laid pier by pier.
    public static func matching(_ route: FerryRoute, in world: GameWorld) -> RealFerry? {
        all.first { $0.legMetres == route.legMetres && $0.piers(in: world) == route.piers }
    }
}

extension GameWorld {
    /// Whether boat `id` is there to follow: its route is, with a boat of
    /// that number. It may lie by the first pier (overnight, on a typhoon
    /// day): the camera stays with it.
    public func ferryBoatExists(_ id: FerryBoatID) -> Bool {
        guard let route = ferryRoute(id: id.route) else { return false }
        return id.number >= 0 && id.number < route.boats
    }

    /// The sailings of route `route` under way now, numbered.
    func ferrySailings(of route: FerryRoute) -> [Map3DFerries.Sailing] {
        Map3DFerries.numberedSailings(of: route, atSecond: Double(clock.now.seconds)) { ferryRouteIsOpen(route.id, onDay: $0) }
    }

    /// The boat of route `id` to follow: the one that left its first pier
    /// last (the card's follow button), or boat 1 while none sails; `nil`
    /// with no boats.
    public func ferryBoatToFollow(on id: FerryRouteID) -> FerryBoatID? {
        guard let route = ferryRoute(id: id), route.boats > 0 else { return nil }
        let number = ferrySailings(of: route).max { $0.start < $1.start }?.number ?? 0
        return FerryBoatID(route: id, number: number)
    }

    /// A boat of route `id` out on a crossing, the nearest its middle
    /// first (the screenshots' views, so the water is round it); else as
    /// ``ferryBoatToFollow(on:)``.
    public func ferryBoatMidCrossing(on id: FerryRouteID) -> FerryBoatID? {
        guard let route = ferryRoute(id: id) else { return nil }
        let crossing = ferrySailings(of: route).compactMap { sailing -> (number: Int, offMiddle: Double)? in
            guard case .sailing(_, let share, _) = sailing.stage else { return nil }
            return (sailing.number, abs(share - 0.5))
        }
        if let best = crossing.min(by: { $0.offMiddle < $1.offMiddle }) { return FerryBoatID(route: id, number: best.number) }
        return ferryBoatToFollow(on: id)
    }

    /// The text for the bar: where a followed boat is and goes, and when
    /// it comes in or leaves. A real ferry's piers take their real names
    /// (Tamsui, Bali…); others are counted, the one that meets a railway
    /// station taking its name.
    func ferryFollowFacts(of id: FerryBoatID, in language: DisplayLanguage) -> FerryFollowFacts? {
        guard ferryBoatExists(id), let route = ferryRoute(id: id.route) else { return nil }
        let real = RealFerry.matching(route, in: self)
        func name(_ pier: Int) -> String {
            if let real, real.piers.indices.contains(pier) {
                let named = real.piers[pier]
                return language.text("\(named.englishName) Pier", "\(named.name)碼頭")
            }
            if let transfer = route.transfer, transfer.stop == pier, let station = station(id: transfer.station) {
                return language.text("\(station.name) Pier", "\(station.name)碼頭")
            }
            return language.text("Pier \(pier + 1)", "第 \(pier + 1) 碼頭")
        }
        let second = Double(clock.now.seconds)
        let minute = second / 60
        func at(_ minutes: Double) -> String { clockText(minuteOfDay: Int(minutes.rounded(.up))) }
        let sailing = ferrySailings(of: route).first { $0.number == id.number }
        let (pierAt, next) = FerryBoats.piers(of: sailing?.stage, piers: route.piers.count)
        let direction = language.text("To \(name(next))", "往\(name(next))")
        let stopText: String
        switch sailing?.stage {
        case .sailing(let leg, let share, _)?:
            let left = (1 - share) * Map3DFerries.crossingMinutes(route.legMetres[leg])
            stopText = language.text("Next: \(name(next)) · in at \(at(minute + left))", "下一站：\(name(next)) · \(at(minute + left)) 到")
        case .docked(_, let share, _)?:
            let left = (1 - share) * Double(FerryRoute.dockMinutes)
            stopText = language.text("At \(name(pierAt ?? 0)) · leaves \(at(minute + left))", "停在\(name(pierAt ?? 0)) · \(at(minute + left)) 開")
        case nil:
            let here = language.text("At \(name(0))", "停在\(name(0))")
            let today = clock.now.seconds / GameTime.secondsPerDay
            let until = Map3DFerries.lying(id.number, of: route, atSecond: second) { ferryRouteIsOpen(route.id, onDay: $0) }.until
            if !ferryRouteIsOpen(route.id, onDay: today) {
                stopText = here + " · " + language.text("No sailings today: typhoon", "今天停航：颱風")
            } else if let until {
                stopText = here + " · " + language.text("Next sailing \(at(until / 60))", "下一班 \(at(until / 60)) 開")
            } else {
                stopText = here + " · " + language.text("No more sailings", "沒有班次了")
            }
        }
        return FerryFollowFacts(boat: id, name: FerryText.name(id.route, in: language), directionText: direction, stopText: stopText,
                                runningSpeed: clock.isPaused ? nil : clock.speed)
    }
}

extension GameSession {
    public var isFollowingFerry: Bool { followedFerryBoatID != nil }

    /// Starts following boat `id` if it is there; never changes the world.
    public func followFerryBoat(_ id: FerryBoatID) {
        guard world.ferryBoatExists(id) else { return }
        followedTrainID = nil
        followedBusID = nil
        followedCabinID = nil
        followedAircraftID = nil
        followedFerryBoatID = id
        updateFollowSounds()
    }

    /// Follows the boat of route `id` that left its first pier last (the
    /// card's follow button).
    public func followFerry(on id: FerryRouteID) {
        guard let boat = world.ferryBoatToFollow(on: id) else { return }
        followFerryBoat(boat)
    }

    /// Whether route `id` has a boat to follow.
    public func hasFerryBoatToFollow(on id: FerryRouteID) -> Bool { world.ferryBoatToFollow(on: id) != nil }

    /// Works ``ferryFollowBar`` out again; set only when it differs.
    func refreshFerryFollow() {
        let facts = followedFerryBoatID.flatMap { world.ferryFollowFacts(of: $0, in: language) }
        if facts != ferryFollowBar { ferryFollowBar = facts }
    }

    /// After a step or an edit: a boat whose route is gone or sold is let
    /// go, and the camera goes back to the map's own view; one there has
    /// its bar brought up to date.
    func keepFollowingFerry() {
        guard let id = followedFerryBoatID else { return }
        guard world.ferryBoatExists(id) else {
            followedFerryBoatID = nil
            return
        }
        refreshFerryFollow()
    }
}
