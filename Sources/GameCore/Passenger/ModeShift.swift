/// How many riders take a scooter or a car instead when the train is
/// slower door to door (decision 332): each pair of stations at least
/// ``DistanceDemand/fullDistance`` apart compares the rail minutes of its
/// fastest route with the faster of a scooter and a car, and loses a share
/// of its ordinary trips the further rail falls behind. Integer only, the
/// same in a batch, after a save and minute by minute.
public struct ModeShift: Hashable, Codable, Sendable {
    public enum Rule: String, Hashable, Codable, Sendable {
        /// Half the slowdown, at most ``ModeShift/simpleCap``: gentle for
        /// new games (decisions 254, 258).
        case simple
        /// Three quarters of the slowdown, at most the area's share of
        /// trips by scooter and car.
        case realistic
    }

    public let rule: Rule
    /// The most of a pair's trips that switch, in thousandths
    /// (0...1000): ``simpleCap`` for the simple rule; for the realistic
    /// one, the private motor vehicles' share of the area's trips
    /// (MOTC 2024 travel survey, table 4), ``nationalShare`` on a blank map.
    public let cap: Int64

    /// The simple rule's cap, 20%.
    public static let simpleCap: Int64 = 200
    /// Taiwan's private motor vehicles' share of daily trips in 2024
    /// (MOTC travel survey, table 4): 72.0%.
    public static let nationalShare: Int64 = 720
    /// Minutes walking to and from the stations at both ends.
    public static let accessMinutes: Int64 = 6
    /// The road's length per straight-line length, in tenths.
    static let detourTenths: Int64 = 13
    /// Metres an hour and minutes to fetch and park, by scooter and by car.
    static let scooterMetresPerHour: Int64 = 30_000
    static let scooterExtraMinutes: Int64 = 4
    static let carMetresPerHour: Int64 = 40_000
    static let carExtraMinutes: Int64 = 8

    /// The simple rule.
    public static let simple = ModeShift(rule: .simple, cap: simpleCap)

    /// The realistic rule with the area's share; `nil` outside 0...1000.
    public static func realistic(cap: Int64 = nationalShare) -> ModeShift? {
        let shift = ModeShift(rule: .realistic, cap: cap)
        return shift.isValid ? shift : nil
    }

    public init(rule: Rule, cap: Int64) {
        self.rule = rule
        self.cap = cap
    }

    public var isValid: Bool { (0...1_000).contains(cap) }

    enum CodingKeys: String, CodingKey {
        case rule, cap
    }

    /// Reads a rule, refusing a cap outside 0...1000.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rule = try container.decode(Rule.self, forKey: .rule)
        cap = try container.decode(Int64.self, forKey: .cap)
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .cap, in: container, debugDescription: "A mode shift's cap is 0 to 1000.")
        }
    }

    /// The faster of a scooter and a car over `metres` in a straight line,
    /// in whole minutes: the road is ``detourTenths`` tenths as long,
    /// rounded to the metre, and each minute count is rounded half up
    /// before the minutes to fetch and park.
    public static func roadMinutes(metres: Int64) -> Int64 {
        let road = vehicleMinutes(metres: metres)
        return min(road.scooter, road.car)
    }

    /// The minutes by scooter and by car (see ``roadMinutes(metres:)``).
    public static func vehicleMinutes(metres: Int64) -> (scooter: Int64, car: Int64) {
        let road = (metres * detourTenths + 5) / 10
        let scooter = (road * 60 + scooterMetresPerHour / 2) / scooterMetresPerHour + scooterExtraMinutes
        let car = (road * 60 + carMetresPerHour / 2) / carMetresPerHour + carExtraMinutes
        return (scooter, car)
    }

    /// The share of a pair's trips that switch, in thousandths, when rail
    /// takes `railMinutes` door to door and the road `roadMinutes`: nothing
    /// while rail is no slower; otherwise the slowdown in thousandths
    /// (truncated), halved by the simple rule and three quarters of it
    /// (truncated) by the realistic one, at most ``cap``.
    public func share(railMinutes: Int64, roadMinutes: Int64) -> Int64 {
        let slowdown = railMinutes * 1_000 / max(1, roadMinutes)
        guard slowdown > 1_000 else { return 0 }
        let over = slowdown - 1_000
        return min(cap, rule == .simple ? over / 2 : over * 3 / 4)
    }

    /// How many of `trips` switch at `share` thousandths, rounded half up.
    public static func lost(_ trips: Int64, share: Int64) -> Int64 {
        trips > 0 ? (trips * share + 500) / 1_000 : 0
    }
}

extension GameWorld {
    /// Chooses whether and how riders take a scooter or a car instead
    /// (decision 332), or `nil` for none. Free; passengers already waiting
    /// stay, and the next release uses the new rule.
    ///
    /// - Throws: ``GameError/invalidModeShift`` for a cap outside 0...1000;
    ///   nothing changes then.
    public mutating func setModeShift(_ shift: ModeShift?) throws(GameError) {
        guard shift?.isValid ?? true else { throw .invalidModeShift }
        guard shift != modeShift else { return }
        modeShift = shift
        passengerPlan = PassengerPlanCache()
    }

    /// The share of the trips from `origin` to `destination` that take a
    /// scooter or a car instead when the fastest route takes `minutes`
    /// (``PassengerRoute/totalMinutes``), in thousandths: 0 without a mode
    /// shift and for stations under ``DistanceDemand/fullDistance`` apart,
    /// which decision 137 already leaves to walking and cycling.
    func modeShiftShare(from origin: StationID, to destination: StationID, minutes: Int64) -> Int64 {
        guard let modeShift, let metres = modeShiftMetres(from: origin, to: destination) else { return 0 }
        return modeShift.share(railMinutes: minutes + ModeShift.accessMinutes, roadMinutes: ModeShift.roadMinutes(metres: metres))
    }

    /// The straight line between the stations in whole metres, rounded,
    /// or `nil` under ``DistanceDemand/fullDistance``.
    private func modeShiftMetres(from origin: StationID, to destination: StationID) -> Int64? {
        guard let squared = squaredDistance(from: origin, to: destination),
              squared >= DistanceDemand.fullDistance * DistanceDemand.fullDistance else { return nil }
        let units = FixedPoint.roundedSquareRoot(squared)
        return (units + WorldCoordinate.unitsPerMetre / 2) / WorldCoordinate.unitsPerMetre
    }

    /// `trips` less those that take a scooter or a car instead.
    func modeShiftKept(_ trips: Int64, from origin: StationID, to destination: StationID, minutes: Int64) -> Int64 {
        guard modeShift != nil, trips > 0 else { return trips }
        return trips - ModeShift.lost(trips, share: modeShiftShare(from: origin, to: destination, minutes: minutes))
    }

    /// What kept riders from `origin` off the trains, a pair at a time by
    /// ascending station ID (decision 332): those who took a scooter or a
    /// car instead and those the fare kept away (decision 36), for every
    /// pair ``dailyDemands(from:)`` works out, those that lost no one
    /// too. Empty without a mode shift. Read from the world; nothing is
    /// kept.
    public func modeShiftLosses(from origin: StationID) -> [ModeShiftLoss] {
        guard modeShift != nil else { return [] }
        return dailyDemandDetails(from: origin).map { detail in
            let metres = modeShiftMetres(from: origin, to: detail.destination)
            let road = metres.map(ModeShift.vehicleMinutes(metres:))
            let waiting = detail.route.map { $0.waitMinutes + $0.transferMinutes } ?? 0
            return ModeShiftLoss(
                destination: detail.destination, switched: detail.switched, tooExpensive: detail.tooExpensive,
                waitsLongest: waiting >= (detail.route?.rideMinutes ?? 0), byCar: road.map { $0.car < $0.scooter } ?? false,
                isNear: metres == nil, lines: detail.route?.legs.map(\.line) ?? []
            )
        }
    }
}

/// What kept one pair's riders off the trains (decision 332; see
/// ``GameWorld/modeShiftLosses(from:)``).
public struct ModeShiftLoss: Hashable, Sendable {
    public let destination: StationID
    /// The trips a day that took a scooter or a car instead.
    public let switched: Int64
    /// The trips a day the fare kept away (decision 36).
    public let tooExpensive: Int64
    /// Whether waiting and changing trains take at least as long as
    /// riding on the fastest route: more trains bring them back sooner
    /// than faster ones.
    public let waitsLongest: Bool
    /// Whether a car is faster than a scooter between them.
    public let byCar: Bool
    /// Whether the stations stand under ``DistanceDemand/fullDistance``
    /// apart, where nobody switches.
    public let isNear: Bool
    /// The lines of the fastest route's legs, in order.
    public let lines: [LineID]

    public init(destination: StationID, switched: Int64, tooExpensive: Int64, waitsLongest: Bool, byCar: Bool,
                isNear: Bool, lines: [LineID]) {
        self.destination = destination
        self.switched = switched
        self.tooExpensive = tooExpensive
        self.waitsLongest = waitsLongest
        self.byCar = byCar
        self.isNear = isNear
        self.lines = lines
    }
}
