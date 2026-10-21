// High-speed rail (ARCHITECTURE decision 168, step C of the whole-island
// map): a line planned at high speed (``ServiceLine/isHighSpeed``) is paid
// and filled by its own rules. It is not a kind of line the player declares,
// as the metro game's `lineKind` makes it: it is built like any line, with
// the "High-speed rail" the line menu already had or a high-speed set, and
// shown differently.
//
// From the owner's `Ci/` reference
// (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`):
//
// - the fare, `hsrFarePassengerPrice`'s legacy branch (no per-type rate, the
//   absent v3 rules not active): `Math.max(20, Math.round(Math.max(1, km) ×
//   .45))`, in the reference's dollars, where the metro's flat fare is 5.
//   Deliberately without the reference's floor of 20: a line is high-speed
//   by how it is planned here, not by being built of high-speed stations, and
//   a floor would let any metro line be planned at high speed to charge 4
//   times its fare on every short ride (the fare does not change demand). The
//   fare is the network's or the kilometres', whichever is more, which is
//   also nearer the real Taiwan High Speed Rail's shortest fare against its
//   longest (NT$40 for NT$1,490, 3 %, against 13 %);
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

    /// The fare of a kilometre, in cents (`.45`).
    public static let centsPerKilometre: Int64 = 45

    /// The fare of a trip whose straight-line distance is
    /// `√squaredDistance` world units (1/64 m): `round(km × 0.45)` dollars,
    /// rounded half up as `Math.round` does, in whole dollars; 153 for the
    /// 340.04 km from Taipei to Zuoying along the track, as the reference's
    /// formula gives. A trip pays this or the network's fare, whichever is
    /// more (``GameWorld/tripFare(from:to:highSpeed:)``).
    public static func fare(squaredDistance: Int64) -> Money {
        let units = FixedPoint.squareRoot(max(0, squaredDistance))
        // units / 64,000 kilometres × 45 / 100 dollars.
        let dollars = (units * centsPerKilometre + 3_200_000) / 6_400_000
        return Money(dollars * 100)
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
        Set(lines.filter(\.isHighSpeed).flatMap(\.stops))
    }

    /// Whether station `id` is called at by a high-speed line.
    public func isHighSpeedStation(_ id: StationID) -> Bool {
        lines.contains { $0.isHighSpeed && $0.stops.contains(id) }
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

/// Decision 325: a pair of stations' high-speed fare, a real fare table's
/// (``CompanyAccounts/highSpeedFares``). The same either way: the official
/// table's fares are (the reference's `thsr_fare.json` keys each pair once).
public struct HighSpeedFare: Hashable, Sendable {
    /// The pair's stations, the lower ID first.
    public let from: StationID
    public let to: StationID
    public let fare: Money

    /// The fare between `a` and `b`, which ever is named first.
    public init(between a: StationID, and b: StationID, fare: Money) {
        (from, to) = a < b ? (a, b) : (b, a)
        self.fare = fare
    }

    /// A pair of stations, the lower ID first, ordered by the lower then
    /// the higher.
    struct Key: Hashable, Comparable {
        let from: Int
        let to: Int

        init(_ a: StationID, _ b: StationID) {
            (from, to) = a < b ? (a.rawValue, b.rawValue) : (b.rawValue, a.rawValue)
        }

        static func < (lhs: Key, rhs: Key) -> Bool {
            (lhs.from, lhs.to) < (rhs.from, rhs.to)
        }
    }

    var key: Key { Key(from, to) }

    /// Whether `fares` is a table a world keeps: each between two
    /// different stations, the lower first, from 0.01 to
    /// ``FareRules/maximumFare``, in ascending pairs without a pair twice.
    static func isTable(_ fares: [HighSpeedFare]) -> Bool {
        fares.allSatisfy { $0.from < $0.to && (Money(1)...FareRules.maximumFare).contains($0.fare) }
            && zip(fares, fares.dropFirst()).allSatisfy { $0.key < $1.key }
    }
}

extension HighSpeedFare: Codable {
    private enum CodingKeys: String, CodingKey {
        case from, to, fare
    }

    /// Decodes `{"from", "to", "fare"}` as written; whether the table holds
    /// together is checked with the accounts.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(StationID.self, forKey: .from)
        to = try container.decode(StationID.self, forKey: .to)
        fare = try container.decode(Money.self, forKey: .fare)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(fare, forKey: .fare)
    }
}
