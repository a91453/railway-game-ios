import GameCore

// Decision 400 (FOLLOWBUS, 2026-11-04): the camera following a bus, the
// bus counterpart of following a train (``GameSession/followTrain(_:)``).
// A bus is not a GameCore thing: ``BusMotion`` works its place out from the
// route and the game's clock, so the session keeps only the bus's ID
// (``BusID``: the route and which run of its day) and reads the rest
// through ``GameSession/followedBus``. Presentation only: nothing here
// changes the world, the save or a golden value.

/// What the follow bar shows of the bus followed: the route and where it
/// is going, read through ``GameSession/busFollowBar``.
public struct BusFollowFacts: Equatable, Sendable {
    public var bus: BusID
    /// "Feeder bus 3" or "City bus 3".
    public var routeName: String
    /// The line colour of the station the route feeds, for its badge; `nil`
    /// for a city route or a station on no coloured line.
    public var color: LineColor?
    /// "Standing at Stop 2" or "Next: Stop 3", "Next: Taipei" for the
    /// station.
    public var stopText: String
    /// "To Taipei" or "Back to Stop 1": the way it goes.
    public var directionText: String
    public var runningSpeed: GameSpeed?
}

/// A bus the camera follows and where it is in its route.
public struct FollowedBus: Equatable, Sendable {
    public var id: BusID
    public var route: BusRoute
    public var bus: BusMotion.Bus
}

extension GameWorld {
    /// The seconds of the game's day now (0 to 86,400), what ``BusMotion``
    /// is asked at.
    public var busSecondOfDay: Double {
        let now = clock.now
        let day = GameDate.floorDivide(now.seconds, GameTime.secondsPerDay)
        return Double(now.seconds - day * GameTime.secondsPerDay)
    }

    /// The bus `id` as it is out now, with its route, or `nil` when the
    /// route is gone or has no bus, or that run is not out.
    public func followedBus(_ id: BusID) -> FollowedBus? {
        guard let route = busRoutes.first(where: { $0.id == id.route }), let motion = BusMotion(route),
              let bus = motion.bus(run: id.run, at: busSecondOfDay) else { return nil }
        return FollowedBus(id: id, route: route, bus: bus)
    }

    /// Where bus `bus` of `route` is: the index (0 is the first stop, the
    /// station after the last) of the stop it stands at, or `nil` on the
    /// way, and the stop it comes to next, `nil` at the end of its trip.
    static func busStops(of bus: BusMotion.Bus, legs: Int) -> (at: Int?, next: Int?) {
        let last = legs
        if bus.stopped {
            let at = bus.share >= 1 ? bus.leg + 1 : bus.leg
            let next = bus.outbound ? (at < last ? at + 1 : nil) : (at > 0 ? at - 1 : nil)
            return (at, next)
        }
        return (nil, bus.outbound ? bus.leg + 1 : bus.leg)
    }

    /// The text for the bar: where a followed bus stands and goes.
    func busFollowFacts(of followed: FollowedBus, in language: DisplayLanguage) -> BusFollowFacts {
        let route = followed.route
        let station = route.station.flatMap { self.station(id: $0) }
        func stop(_ index: Int) -> String {
            // The station follows the last stop of a feeder route.
            if station != nil, index >= route.stops.count { return station?.name ?? "" }
            return language.text("Stop \(index + 1)", "\(index + 1) 號站牌")
        }
        let legs = route.legMetres.count
        let (at, next) = Self.busStops(of: followed.bus, legs: legs)
        let nextText = next.map { language.text("Next: \(stop($0))", "下一站：\(stop($0))") }
            ?? language.text("End of the run", "這一班到終點了")
        let stopText: String
        if let at {
            let standing = language.text("At \(stop(at))", "停在\(stop(at))")
            stopText = next == nil ? standing : standing + " · " + nextText
        } else {
            stopText = nextText
        }
        let end = followed.bus.outbound ? legs : 0
        let direction = followed.bus.outbound
            ? language.text("To \(stop(end))", "往\(stop(end))")
            : language.text("Back to \(stop(end))", "回\(stop(end))")
        return BusFollowFacts(
            bus: followed.id, routeName: BusRouteText.name(route.id, city: route.station == nil, in: language),
            color: station.flatMap { lines(callingAt: $0.id).first?.color },
            stopText: stopText, directionText: direction, runningSpeed: clock.isPaused ? nil : clock.speed)
    }
}

extension GameSession {
    /// The bus the camera follows, `nil` once it is no longer out.
    public var followedBus: FollowedBus? {
        followedBusID.flatMap { world.followedBus($0) }
    }

    public var isFollowingBus: Bool { followedBusID != nil }

    /// Whether the camera follows a train or a bus now.
    public var isFollowingVehicle: Bool { followedTrainID != nil || followedBusID != nil || followedCabinID != nil
        || followedFerryBoatID != nil }

    /// Starts following bus `id` if it is out; never changes the world.
    public func followBus(_ id: BusID) {
        guard world.followedBus(id) != nil else { return }
        followedTrainID = nil
        followedCabinID = nil
        followedFerryBoatID = nil
        followedBusID = id
        updateFollowSounds()
    }

    /// Follows a bus of route `route` that is out: the one that left its
    /// first stop last (the route card's follow button). Without one out,
    /// nothing changes.
    public func followBus(onRoute route: BusRouteID) {
        guard let found = world.busRoutes.first(where: { $0.id == route }), let motion = BusMotion(found),
              let bus = motion.successor(of: -1, at: world.busSecondOfDay) else { return }
        followBus(BusID(route: route, run: bus.run))
    }

    /// Whether any bus of `route` is out to follow.
    public func hasBusToFollow(onRoute route: BusRouteID) -> Bool {
        guard let found = world.busRoutes.first(where: { $0.id == route }), let motion = BusMotion(found) else { return false }
        return motion.successor(of: -1, at: world.busSecondOfDay) != nil
    }

    /// Whether the camera follows bus `id` now.
    public func isFollowing(_ id: BusID) -> Bool { followedBusID == id }

    /// Stops following a bus (and a train).
    public func stopFollowingBus() { stopFollowingTrain() }

    /// Works ``busFollowBar`` out again; set only when it differs.
    func refreshBusFollow() {
        updateMap3DSpeedCapForBus()
        guard let followed = followedBus else {
            if busFollowBar != nil { busFollowBar = nil }
            return
        }
        let facts = world.busFollowFacts(of: followed, in: language)
        if facts != busFollowBar { busFollowBar = facts }
    }

    /// After a step or an edit: a bus that ended its run (shrinking into its
    /// first stop) or is gone is followed on by the route's next run, or the
    /// camera goes back to the map's own view when none is out (the
    /// route is gone, stopped, or between runs).
    func keepFollowingBus() {
        guard let id = followedBusID else { return }
        guard let route = world.busRoutes.first(where: { $0.id == id.route }), let motion = BusMotion(route) else {
            followedBusID = nil
            return
        }
        let second = world.busSecondOfDay
        if let bus = motion.bus(run: id.run, at: second), bus.scale >= 1 || bus.elapsed < motion.cycle / 2 {
            refreshBusFollow()
            return
        }
        // Over, or shrinking into its first stop: on to the next run.
        if let next = motion.successor(of: id.run, at: second) {
            followedBusID = BusID(route: id.route, run: next.run)
        } else {
            followedBusID = nil
        }
    }
}
