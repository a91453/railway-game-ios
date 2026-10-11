// High-speed rail (ARCHITECTURE decision 168, step C of the whole-island
// map): a line the player marks high-speed is paid and filled by its own
// rules.
//
// From the owner's `Ci/` reference
// (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`):
//
// - the fare, `hsrFarePassengerPrice`'s legacy branch (no per-type rate, the
//   absent v3 rules not active): `Math.max(20, Math.round(Math.max(1, km) ×
//   .45))`, in the reference's dollars, where the metro's flat fare is 5;
// - a high-speed train never overloads (`TrainType.highSpeed`, in
//   `TrainType.swift`).
//
// The reference's demand for it is a server model
// (`hsr-flow/model`, city-pair base demand cut down to what the stations
// reach, at most one transfer and five paths for each pair) its snapshot does
// not have, so the rest is this project's (gap):
//
// - A high-speed station draws on a far wider catchment than a metro
//   station's 800 m: the people (residents and jobs) within
//   ``hinterlandRadius`` of it, each shared among the high-speed stations
//   that reach it by nearness, as a metro station's catchment is
//   (``LandDemand/shares(of:among:placed:radius:)``). That count is the
//   station's ``StationDemand/hinterland``, worked out with the land
//   demand (``GameWorld/refreshLandDemand()``), so it follows the land the
//   map has read in and the high-speed lines there are.
// - Between two high-speed stations the intercity trips of a day are a
//   gravity of their hinterlands: `K · a · b` for hinterlands of `a` and
//   `b` people (``pairTrips(_:_:)``, one way), kept by a ramp of the
//   straight-line distance (``share(squaredDistance:)``: none up to 10 km,
//   all from 80 km, where the metro and the regional rail serve) and then,
//   like every pair's, by the minutes of the fastest route
//   (``PassengerCrowding``: full to 30 minutes, then inversely). That is
//   the textbook gravity form (Hansen/Wilson, `T = k·P_i·P_j·d^-β`, whose
//   formula is nobody's), with the decay the game already has in place of a
//   distance power. OpenTTD's cargodist (GPL-2.0) and Simutrans' passenger
//   destinations (Artistic) were read for ideas only; grid2demand
//   (Apache-2.0), whose urban `F(d)` has no `exp` GameCore may use and
//   falls to nothing beyond 50 km, was not taken from.
// - The trips are the pair's own, not part of either station's
//   ``StationDemand/dailyTrips``: they are not shared among the metro
//   stations of the same city, which would send most of them across town.
// - A trip whose journey rides a high-speed line pays the high-speed fare
//   for the straight-line distance from its origin to its destination, if
//   that is more than the network's (``GameWorld/tripFare(from:to:highSpeed:)``).

/// The rules of high-speed rail (ARCHITECTURE decision 168).
public enum HighSpeed {
    // MARK: Fare

    /// The least fare (`Math.max(20, …)`), in whole dollars.
    public static let minimumFareDollars: Int64 = 20
    /// The fare of a kilometre, in cents (`.45`).
    public static let centsPerKilometre: Int64 = 45

    /// The fare of a trip whose straight-line distance is
    /// `√squaredDistance` world units (1/64 m): `max(20, round(km × 0.45))`
    /// dollars, rounded half up as `Math.round` does; 153 for the 340.04 km
    /// from Taipei to Zuoying along the track, as the reference's formula
    /// gives.
    public static func fare(squaredDistance: Int64) -> Money {
        let units = FixedPoint.squareRoot(max(0, squaredDistance))
        // units / 64,000 kilometres × 45 / 100 dollars.
        let dollars = (units * centsPerKilometre + 3_200_000) / 6_400_000
        return Money(max(minimumFareDollars, dollars) * 100)
    }

    // MARK: Intercity trips

    /// How far from a high-speed station its hinterland reaches: 8 km.
    /// Cells within it are shared among the high-speed stations they lie
    /// within the reach of, nearer more.
    public static let hinterlandRadius: Int64 = 8_000 * WorldCoordinate.unitsPerMetre
    /// Up to this straight-line distance (10 km) a pair of stations has no
    /// intercity trips.
    public static let nearDistance: Int64 = 10_000 * WorldCoordinate.unitsPerMetre
    /// From this distance (80 km) a pair has all of them.
    public static let fullDistance: Int64 = 80_000 * WorldCoordinate.unitsPerMetre
    /// The trips a day from a station with a million people in its
    /// hinterland to one with a million, one way, at full distance and
    /// before the minutes of the way take their share: the gravity's `K`,
    /// chosen by `HighSpeedReportTests` so that the real Taiwan High Speed
    /// Rail's twelve stations, with their services of the real day, carry
    /// about what it does, some 180,000 passengers a day.
    public static let tripsPerMillionSquared: Int64 = 2_400

    /// The share of the intercity trips a pair `squaredDistance` (world
    /// units squared) apart keeps, in thousandths: none up to
    /// ``nearDistance``, all from ``fullDistance``, in a straight line
    /// between them by the distance rounded down to a unit.
    public static func share(squaredDistance: Int64) -> Int64 {
        let distance = FixedPoint.squareRoot(max(0, squaredDistance))
        guard distance > nearDistance else { return 0 }
        guard distance < fullDistance else { return 1_000 }
        return 1_000 * (distance - nearDistance) / (fullDistance - nearDistance)
    }

    /// The intercity trips a day, one way, from a station whose hinterland
    /// has `origin` people to one whose hinterland has `destination`, at
    /// full distance: `K · a · b` for people in millions, rounded down.
    ///
    /// - Precondition: both are from 0 to ``StationDemand/maximumHinterland``.
    public static func pairTrips(_ origin: Int64, _ destination: Int64) -> Int64 {
        precondition((0...StationDemand.maximumHinterland).contains(origin) && (0...StationDemand.maximumHinterland).contains(destination),
                     "pairTrips(_:_:) requires hinterlands from 0 to maximumHinterland")
        return origin * destination / 1_000_000 * tripsPerMillionSquared / 1_000_000
    }
}

extension GameWorld {
    // MARK: - Queries

    /// Whether line `id` is a high-speed line (decision 168); `false` for an
    /// unknown line.
    func isHighSpeedLine(_ id: LineID) -> Bool {
        lines.first { $0.id == id }?.isHighSpeed ?? false
    }

    /// The stations a high-speed line calls at (decision 168).
    public var highSpeedStations: Set<StationID> {
        Set(lines.filter { $0.isHighSpeed && !$0.isFreight }.flatMap(\.stops))
    }

    /// Whether station `id` is called at by a high-speed line.
    public func isHighSpeedStation(_ id: StationID) -> Bool {
        lines.contains { $0.isHighSpeed && !$0.isFreight && $0.stops.contains(id) }
    }

    /// Whether the passengers of `group` ride a high-speed line on their
    /// way: their journey's legs, or the line they wait for.
    func ridesHighSpeed(_ group: WaitingGroup) -> Bool {
        if let journey = group.journey {
            return journey.legs.contains { isHighSpeedLine($0.line) }
        }
        return isHighSpeedLine(group.line)
    }

    // MARK: - Deriving

    /// The people of each open high-speed station's hinterland: the
    /// residents and jobs of the land and the player's buildings within
    /// ``HighSpeed/hinterlandRadius`` of it, shared among the stations by
    /// nearness (decision 168). Empty without high-speed lines.
    func highSpeedHinterlands() -> [StationID: Int64] {
        let served = highSpeedStations
        guard !served.isEmpty else { return [:] }
        let stations = landStations.filter { served.contains($0.id) }
        guard !stations.isEmpty else { return [:] }
        let shares = LandDemand.shares(of: land, among: stations, placed: placedBuildings, radius: HighSpeed.hinterlandRadius)
        return shares.mapValues { min(StationDemand.maximumHinterland, $0.people) }
    }

    /// The intercity trips of today from the station `origin`, with demand
    /// `from`, to the station `destination`, with demand `to`, before the
    /// minutes of the way take their share: the pair's ``HighSpeed/pairTrips(_:_:)``
    /// kept by their distance, for the day (weekly demand, events, holidays
    /// and weather as for any trips) and today's typhoons. None unless both
    /// have a hinterland.
    func intercityTrips(from origin: StationID, _ from: StationDemand, to destination: StationID, _ to: StationDemand,
                        typhoons: [StationID: Int64]) -> Int64 {
        guard from.hinterland > 0, to.hinterland > 0, origin != destination,
              let squared = squaredDistance(from: origin, to: destination)
        else { return 0 }
        let share = HighSpeed.share(squaredDistance: squared)
        guard share > 0 else { return 0 }
        var trips = (HighSpeed.pairTrips(from.hinterland, to.hinterland) * share + 500) / 1_000
        if weeklyDemand { trips = StationDemand.trips(trips, onDay: dayIndex(of: clock.now)) }
        return Self.typhoonTrips(scaledTrips(trips, at: origin), from: origin, to: destination, multipliers: typhoons)
    }
}
