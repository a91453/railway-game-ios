// Day passes (ARCHITECTURE decision 324; native: the reference has no
// fare products). The company may sell one pass for a day of unlimited
// rides on its network, as the Taiwan Railway sells the Pingxi, Neiwan and
// Jiji lines' one-day passes. Only the sights' tourists (decision 174) buy
// it; commuters keep paying by the trip. A tourist buys when the price is
// worth the rides it covers: the way there and back, and a round trip on
// to the nearest other sight that the pass makes free. The buyers ride
// those extra trips, and the company's subsidiaries near the stations they
// visit (decision 173) take more of them as customers.
//
// Riders are not told apart at the doors, so every ride is charged its
// fare as it boards, and the lines keep the fares they carried (decision
// 179). At midnight the day's passes are settled as one row: what they
// sold for in, the fares of the rides they covered out. Like the sights'
// counts and shops, it is worked out from the day's expected tourists.

/// The day-pass rules (decision 324).
public enum DayPass {
    /// The share of a sight's tourists who buy at a price half what the
    /// rides are worth or less, in thousandths: not every visitor wants to
    /// ride around.
    public static let fullUptake: Int64 = 500
    /// A price this many of the network's fares for its shortest trips
    /// (``suggestedPrice(for:)``): the Pingxi line's pass is NT$80, about
    /// three of its NT$28 single fares from one end to the other.
    public static let suggestedFares: Int64 = 3
    /// The share of pass holders visiting a station within reach of the
    /// company's amusement park or department store who go in, and of
    /// those within reach of its hotel who stay the night, in thousandths:
    /// a pass comes with their coupons.
    public static let parkCapture: Int64 = 100
    public static let storeCapture: Int64 = 60
    public static let hotelStay: Int64 = 40

    /// The share of tourists who buy a pass at `price` when its rides are
    /// worth `value`, in thousandths: ``fullUptake`` up to half the value,
    /// falling in a line to none at the value.
    public static func uptake(price: Money, value: Money) -> Int64 {
        guard value > .zero, price < value else { return 0 }
        let below = (value - price).amount
        return min(fullUptake, fullUptake * 2 * below / value.amount)
    }

    /// A first price to offer under `rules`: ``suggestedFares`` times the
    /// fare of the shortest trip (5 for a fare of 0 or less, as charged).
    public static func suggestedPrice(for rules: FareRules) -> Money {
        Money(suggestedFares * FareRules.charged(rules.fare(squaredDistance: 0)).amount)
    }
}

/// A day of passes (decision 324): how many sold and for what, the fares
/// of the rides they covered, and how many holders each station saw.
public struct DayPassDay: Hashable, Sendable {
    public internal(set) var sold: Int64 = 0
    public internal(set) var sales: Money = .zero
    /// The fares of the buyers' trips to their sights and back, which they
    /// would have paid without a pass.
    public internal(set) var journeyFares: Money = .zero
    /// The extra rides between sights and their fares, ridden only on a pass.
    public internal(set) var rides: Int64 = 0
    public internal(set) var rideFares: Money = .zero
    /// Pass holders by the station they visited: their sight's, and the
    /// next sight's.
    var visits: [StationID: Int64] = [:]

    public init() {}

    /// What the passes brought against selling none: their sales less
    /// the fares the buyers would have paid anyway (the extra rides'
    /// fares are charged and given back).
    public var net: Money { sales - journeyFares }
}

extension GameWorld {
    // MARK: - Commands

    /// Sells a day pass at `price` from now on, or stops selling it with
    /// `nil` (decision 324). Free.
    ///
    /// - Throws: ``GameError/invalidFareRules`` for a price outside $1 to
    ///   ``FareRules/maximumFare``, or not whole dollars.
    public mutating func setDayPass(_ price: Money?) throws(GameError) {
        if let price {
            guard (Money(100)...FareRules.maximumFare).contains(price), price.amount % 100 == 0 else { throw .invalidFareRules }
        }
        accounts.dayPass = price
        passengerPlan = PassengerPlanCache()
    }

    // MARK: - Queries

    /// The passes of game day `day` as the passenger model reaches them
    /// now: none unless the company is managed, has tourism and sells one.
    public func dayPassDay(onDay day: Int64) -> DayPassDay {
        guard accounts.mode == .management, accounts.dayPass != nil, tourism != nil else { return DayPassDay() }
        let world = self
        let graph = passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        return world.touristFlows(onDay: day) { world.reaches(from: $0, to: $1, graph: graph) }.passes
    }

    /// Today's passes as the passenger model reaches them now.
    public func dayPassToday() -> DayPassDay {
        dayPassDay(onDay: dayIndex(of: clock.now))
    }

    /// What a ride from `origin` to `destination` pays on the company's
    /// own network: its fare without the outside connection's (decision
    /// 137), which goes to the railway beyond. 0 if there is none.
    func passFare(from origin: StationID, to destination: StationID) -> Money {
        guard let fare = tripFare(from: origin, to: destination) else { return .zero }
        guard isOutsideConnection(origin) || isOutsideConnection(destination) else { return fare }
        return fare - outsideFare
    }

    /// The other sight a pass holder at the sight served by `station` rides
    /// on to: the nearest by straight line whose station is another and can
    /// be ridden to and back, the lower station first on a tie.
    func nextSight(from station: StationID, among sights: [(id: AttractionID, station: StationID)],
                   reaches: (StationID, StationID) -> Bool) -> (id: AttractionID, station: StationID)? {
        var best: (sight: (id: AttractionID, station: StationID), distance: Int64)?
        for sight in sights where sight.station != station {
            guard let distance = squaredDistance(from: station, to: sight.station) else { continue }
            if let known = best, (known.distance, known.sight.station) <= (distance, sight.station) { continue }
            guard reaches(station, sight.station), reaches(sight.station, station) else { continue }
            best = (sight, distance)
        }
        return best?.sight
    }

    // MARK: - Midnight

    /// Settles day `day`'s passes as one ledger row at `time`: their sales
    /// in, the fares of the rides they covered out.
    mutating func settleDayPasses(day: Int64, time: GameTime) {
        guard accounts.mode == .management, accounts.dayPass != nil else { return }
        let passes = dayPassDay(onDay: day)
        let covered = passes.journeyFares + passes.rideFares
        guard passes.sales > .zero || covered > .zero else { return }
        write(LedgerEntry(
            kind: .dailyDayPass, time: time, amount: passes.sales - covered,
            breakdown: [
                LedgerLine(item: .dayPassSales, amount: passes.sales),
                LedgerLine(item: .dayPassFares, amount: .zero - covered),
            ]
        ), day: day)
    }
}
