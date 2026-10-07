// Fares and running costs on the world (G1c, ARCHITECTURE decision 36),
// ported from the owner's `Ci/` reference's legacy economy path
// (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`):
//
// - a passenger pays once, as they board, the fare of the straight-line
//   distance from their origin to their destination
//   (`updateTrainAtStation`'s `fareTrips`, `metroEconomyAccrueHourlyFare`:
//   `fareRevenue += Math.round(count × fare)`, in whole dollars);
// - every departure of a line's train counts, with the distance to its
//   next stop, the passengers on board and the seats
//   (`metroEconomyAccrueDeparture`);
// - each hour is settled into one row (`metroEconomySettleHourlyIfNeeded`):
//   operating `round(75·departures + 42·train-km + 18·stations)`,
//   maintenance `round(12·route-km + 9·train-km + 8·trains)`, in dollars;
// - each day's end writes energy `round(220·route-km + 360·trains)` and
//   staff `round(620·stations + 480·trains)`
//   (`metroEconomySettleDailyForEndedDay`), with the balance allowed to go
//   below zero.
//
// Nothing happens in the free economy mode, the default.

extension GameWorld {
    // MARK: - Commands

    /// Sets the economy mode (see ``EconomyMode``). Becoming managed opens
    /// the accounts now: the first hour is settled at the next full hour.
    /// Switching to `free` keeps the accounts as they are; nothing is
    /// accrued or settled until the mode is `management` again. Free.
    public mutating func setEconomyMode(_ mode: EconomyMode) {
        if mode == .management, accounts.mode != .management {
            accounts.openedAt = clock.now
        }
        accounts.mode = mode
        passengerPlan = PassengerPlanCache()
    }

    /// Sets the network's fare rules. From then on fares change demand
    /// (see ``FareRules/demandFactor(fare:)``) while the company is managed.
    /// Free.
    ///
    /// - Throws: ``GameError/invalidFareRules`` for rules
    ///   ``FareRules/isValid`` refuses.
    public mutating func setFareRules(_ rules: FareRules) throws(GameError) {
        guard rules.isValid else { throw .invalidFareRules }
        accounts.fareRules = rules
        passengerPlan = PassengerPlanCache()
    }

    /// Sets the city's fare baseline (see ``CompanyAccounts/fareBaseline``):
    /// the reference picks it by city (`metroFareDemandBaselineForCity`,
    /// 0.75 for its default city, 5.50 for the most expensive). Free.
    ///
    /// - Throws: ``GameError/invalidFareRules`` for a baseline outside 0.01
    ///   to ``FareRules/maximumFare``.
    public mutating func setFareBaseline(_ baseline: Money) throws(GameError) {
        guard (Money(1)...FareRules.maximumFare).contains(baseline) else { throw .invalidFareRules }
        accounts.fareBaseline = baseline
        passengerPlan = PassengerPlanCache()
    }

    /// Borrows `amount` from the bank (decision 67): the balance goes up by
    /// it and the loan with it, and interest is paid on the loan every
    /// midnight. Only a managed company borrows, in whole
    /// ``CompanyAccounts/loanStep``s, up to ``CompanyAccounts/maximumLoan``
    /// in all.
    ///
    /// - Throws, checked in this order: ``GameError/loanNeedsManagement``,
    ///   or ``GameError/invalidLoanAmount``.
    public mutating func borrow(_ amount: Money) throws(GameError) {
        guard accounts.mode == .management else { throw .loanNeedsManagement }
        guard Self.isLoanStep(amount), amount <= CompanyAccounts.maximumLoan - accounts.loan,
              economy.balance.amount <= Self.maximumBalance - amount.amount else { throw .invalidLoanAmount }
        accounts.loan = accounts.loan + amount
        economy.earn(amount)
    }

    /// Repays `amount` of the loan from the balance (decision 67), in whole
    /// ``CompanyAccounts/loanStep``s and no more than is owed. Allowed in
    /// free play too, so a company that stopped being managed can still
    /// clear its debt.
    ///
    /// - Throws, checked in this order: ``GameError/invalidLoanAmount``, or
    ///   ``GameError/insufficientFunds(required:available:)`` when the
    ///   balance is less than `amount`.
    public mutating func repayLoan(_ amount: Money) throws(GameError) {
        guard Self.isLoanStep(amount), amount <= accounts.loan else { throw .invalidLoanAmount }
        try economy.spend(amount)
        accounts.loan = accounts.loan - amount
    }

    private static func isLoanStep(_ amount: Money) -> Bool {
        amount > .zero && amount.amount % CompanyAccounts.loanStep.amount == 0
    }

    // MARK: - Queries

    /// The fare a passenger from `origin` to `destination` pays: the rule's
    /// fare for the straight-line distance between the stations' points, or
    /// 5 if that is 0 or less. `nil` for the same station or an unknown one.
    public func tripFare(from origin: StationID, to destination: StationID) -> Money? {
        guard origin != destination, let squared = squaredDistance(from: origin, to: destination) else { return nil }
        return FareRules.charged(accounts.effectiveFareRules.fare(squaredDistance: squared))
    }

    /// The finance report's statements for `period`: the one containing
    /// the current day and the one before.
    public func financeReport(_ period: FinancePeriod) -> (current: FinanceSummary, previous: FinanceSummary) {
        accounts.report(period, day: dayIndex(of: clock.now))
    }

    /// The square of the straight-line distance between two stations'
    /// points, in world units, exactly (Stage F3d; until then it was the
    /// distance between the 1024-unit tiles under them). Stations stand in
    /// the world's bounds, so each difference is below 2^20 and the sum of
    /// the squares below 2^41.
    func squaredDistance(from origin: StationID, to destination: StationID) -> Int64? {
        guard let a = station(id: origin), let b = station(id: destination) else { return nil }
        let dx = a.point.x - b.point.x
        let dy = a.point.y - b.point.y
        return dx * dx + dy * dy
    }

    /// How much of the pair's demand its fare keeps, in thousandths, or
    /// `nil` while fares do not change demand: the company is free, or the
    /// player never set fare rules.
    func demandFactor(from origin: StationID, to destination: StationID) -> Int64? {
        guard accounts.mode == .management, accounts.fareRules != nil, origin != destination,
              let squared = squaredDistance(from: origin, to: destination)
        else { return nil }
        // The reference's demand reads the rule's fare, before the minimum.
        return FareRules.demandFactor(fare: accounts.effectiveFareRules.fare(squaredDistance: squared), baseline: accounts.fareBaseline)
    }

    // MARK: - Accrual

    /// `count` passengers from `origin` to `destination` boarded: they pay
    /// the fare now, in whole dollars (`Math.round(count × fare)`). The
    /// hour's fares and counts stop at ``maximumHourly``, the most a save
    /// holds: the largest fare the commands take, ``FareRules/maximumFare``,
    /// reaches it with about a thousand boarders, far beyond any real fare.
    mutating func chargeFares(_ count: Int64, from origin: StationID, to destination: StationID) {
        guard accounts.mode == .management, count > 0, let fare = tripFare(from: origin, to: destination) else { return }
        let fares = accounts.pending.fareRevenue.amount + Self.wholeDollars(count * fare.amount).amount
        accounts.pending.fareRevenue = Money(min(fares, Self.maximumHourly / 100 * 100))
        accounts.pending.fareTrips = min(accounts.pending.fareTrips + count, Self.maximumHourly)
    }

    /// A line's train left a stop for its next, `distance` world units
    /// away, with `passengers` on board and `seats` rated; each count stops
    /// at its bound, as the fares do.
    mutating func countDeparture(distance: Int64, passengers: Int64, seats: Int64) {
        guard accounts.mode == .management else { return }
        accounts.pending.departures = min(accounts.pending.departures + 1, Self.maximumDepartures)
        accounts.pending.trainDistance = min(accounts.pending.trainDistance + distance, Self.maximumHourly)
        accounts.pending.passengers = min(accounts.pending.passengers + passengers, Self.maximumHourly)
        accounts.pending.seats = min(accounts.pending.seats + seats, Self.maximumHourly)
    }

    /// `cents` rounded half up to whole dollars, in cents.
    static func wholeDollars(_ cents: Int64) -> Money {
        Money(CompanyAccounts.floorDivide(cents + 50, 100) * 100)
    }

    /// `numerator / denominator` dollars, rounded half up to whole dollars,
    /// in cents: the reference's `Math.round` on a sum it computed in
    /// floating point, here exactly.
    static func roundedDollars(_ numerator: Int64, over denominator: Int64) -> Money {
        Money(CompanyAccounts.floorDivide(2 * numerator + denominator, 2 * denominator) * 100)
    }

    // MARK: - Settlement

    /// The network's fixed assets at the moment of a settlement: its
    /// stations (each line's own, once each: a station two lines call at
    /// counts for both, as the reference counts each line's stations,
    /// `metroEconomyFixedAssets`), its route
    /// length (each line's own service, out to its far end, or once round
    /// a ring, in world units; 0 for one that cannot be driven) and its
    /// trains (each
    /// service's most at any level).
    struct FixedAssets {
        let stations: Int64
        let routeLength: Int64
        let trains: Int64
    }

    func fixedAssets(memo: inout DispatchMemo) -> FixedAssets {
        var stations: Int64 = 0
        var length: Int64 = 0
        var trains: Int64 = 0
        for line in lines {
            stations += Int64(Set(line.stops).count)
            let journey: LineJourney?
            if let known = memo.journeys[line.id]?[0] {
                journey = known
            } else {
                journey = self.journey(of: line, service: 0)
                memo.journeys[line.id, default: [:]][0] = journey
            }
            if let journey {
                // A ring's journey is one lap (see ``LineJourney/legs``), its
                // whole route, as the reference measures a ring closed.
                let route = journey.isRing ? journey.legs[...] : journey.legs.prefix(journey.legs.count / 2)
                length += route.reduce(0) { $0 + $1.path.distance }
            }
            for service in 0..<line.serviceCount {
                let counts = service == 0 ? line.trainsInService : line.patterns[service - 1].trainsInService
                trains += Int64(max(counts.peak, counts.offPeak, counts.low))
            }
        }
        return FixedAssets(stations: stations, routeLength: length, trains: trains)
    }

    /// World units in a kilometre.
    static let unitsPerKilometre: Int64 = 1_000 * WorldCoordinate.unitsPerMetre

    /// The settlements due at the start of the minute from `now`: the hour
    /// that ended, if `now` is on the hour, then the day that ended, if
    /// `now` is midnight (the reference settles the hour before the day).
    mutating func settleAccounts(at now: GameTime, memo: inout DispatchMemo) {
        guard accounts.mode == .management, now.seconds % GameTime.secondsPerHour == 0, let opened = accounts.openedAt, opened < now else { return }
        accounts.openedAt = now
        let assets = fixedAssets(memo: &memo)
        settleHour(at: now, assets: assets)
        if now.seconds % GameTime.secondsPerDay == 0 {
            settleDay(endingBefore: now, assets: assets)
        }
    }

    private mutating func settleHour(at now: GameTime, assets: FixedAssets) {
        let pending = accounts.pending
        let km = Self.unitsPerKilometre
        // 75·departures + 42·train-km + 18·stations, over 64000.
        let operating = Self.roundedDollars(
            (75 * pending.departures + 18 * assets.stations) * km + 42 * pending.trainDistance, over: km
        )
        let maintenance = Self.roundedDollars(12 * assets.routeLength + 9 * pending.trainDistance + 8 * assets.trains * km, over: km)
        accounts.pending = .empty
        guard pending.fareRevenue > .zero || operating > .zero || maintenance > .zero else { return }
        let breakdown = [
            LedgerLine(item: .fareRevenue, amount: pending.fareRevenue),
            LedgerLine(item: .operatingCost, amount: .zero - operating),
            LedgerLine(item: .maintenanceCost, amount: .zero - maintenance),
        ]
        let amount = pending.fareRevenue - operating - maintenance
        // The hour belongs to the day it ran in: the reference settles the
        // hour that ends at midnight before the day turns.
        let day = dayIndex(of: GameTime(seconds: now.seconds - GameTime.secondsPerMinute))
        write(LedgerEntry(kind: .hourlyNet, time: now, amount: amount, breakdown: breakdown, crowding: crowding()), day: day)
    }

    private mutating func settleDay(endingBefore now: GameTime, assets: FixedAssets) {
        let km = Self.unitsPerKilometre
        // The day's last minute.
        let time = GameTime(seconds: now.seconds - GameTime.secondsPerMinute)
        let day = dayIndex(of: time)
        // Each part is rounded on its own; the total is the rounded sum, as
        // in the reference, so they may differ by a dollar.
        let routeEnergy = Self.roundedDollars(220 * assets.routeLength, over: km)
        let trainEnergy = Money(360 * assets.trains * 100)
        let energy = Self.roundedDollars(220 * assets.routeLength + 360 * assets.trains * km, over: km)
        if energy > .zero {
            write(LedgerEntry(
                kind: .dailyEnergy, time: time, amount: .zero - energy,
                breakdown: [LedgerLine(item: .routeEnergy, amount: .zero - routeEnergy), LedgerLine(item: .trainEnergy, amount: .zero - trainEnergy)]
            ), day: day)
        }
        // Decision 67: the day's interest on what is owed at midnight, 5 % a
        // 360-day year, rounded to whole dollars.
        let interest = Self.dailyLoanInterest(on: accounts.loan)
        if interest > .zero {
            write(LedgerEntry(
                kind: .dailyInterest, time: time, amount: .zero - interest,
                breakdown: [LedgerLine(item: .loanInterest, amount: .zero - interest)]
            ), day: day)
        }
        let staff = Money((620 * assets.stations + 480 * assets.trains) * 100)
        if staff > .zero {
            write(LedgerEntry(
                kind: .dailyStaff, time: time, amount: .zero - staff,
                breakdown: [
                    LedgerLine(item: .stationStaff, amount: Money(-620 * assets.stations * 100)),
                    LedgerLine(item: .trainStaff, amount: Money(-480 * assets.trains * 100)),
                ]
            ), day: day)
        }
    }

    /// A day's interest on `loan`: `loan × 5 % ÷ 360`, rounded half up to
    /// whole dollars (decision 67).
    public static func dailyLoanInterest(on loan: Money) -> Money {
        roundedDollars(loan.amount * CompanyAccounts.interestBasisPoints, over: 100 * 10_000 * FinancePeriod.year.days)
    }

    /// Writes `entry` and moves the balance by its amount, which may take
    /// it below zero (`allowNegativeBalance`).
    private mutating func write(_ entry: LedgerEntry, day: Int64) {
        economy.settle(entry.amount)
        accounts.record(entry, day: day)
    }

    func dayIndex(of time: GameTime) -> Int64 {
        CompanyAccounts.floorDivide(time.seconds, GameTime.secondsPerDay)
    }

    /// The network's crowding now (see ``CrowdingMetrics``).
    func crowding() -> CrowdingMetrics {
        let waiting = passengers.map(\.waitingCount)
        var full: Int64 = 0
        var load: Int64 = 0
        for entry in riders {
            guard let train = train(id: entry.train) else { continue }
            let count = entry.count
            if count >= train.ratedCapacity { full += 1 }
            load = max(load, (2_000 * count + train.ratedCapacity) / (2 * train.ratedCapacity))
        }
        return CrowdingMetrics(
            crowdedStations: Int64(waiting.count { $0 > CrowdingMetrics.crowdedWaiting }), fullTrains: full,
            maxWaiting: waiting.max() ?? 0, maxLoad: load
        )
    }

    // MARK: - Validation

    /// Why the accounts break a G1c rule, or `nil`: counts, amounts and the
    /// balance are within bounds, rows are not dated after now and are
    /// shaped as settlements write them, and days are in order, each once.
    func accountsProblem() -> String? {
        let pending = accounts.pending
        let counts = [pending.fareTrips, pending.trainDistance, pending.passengers, pending.seats, pending.fareRevenue.amount]
        guard counts.allSatisfy({ (0...Self.maximumHourly).contains($0) }), (0...Self.maximumDepartures).contains(pending.departures) else {
            return "The hour's accrued counts are out of range."
        }
        guard (-Self.maximumBalance...Self.maximumBalance).contains(economy.balance.amount) else { return "The balance is out of range." }
        guard pending.fareRevenue.amount % 100 == 0 else { return "The hour's fares must be whole dollars." }
        guard (Money(1)...FareRules.maximumFare).contains(accounts.fareBaseline) else { return "The fare baseline is out of range." }
        guard (.zero...CompanyAccounts.maximumLoan).contains(accounts.loan),
              accounts.loan.amount % CompanyAccounts.loanStep.amount == 0 else {
            return "The loan must be whole steps of $100,000, up to the most the bank lends."
        }
        guard accounts.entries.allSatisfy({ $0.time <= clock.now }) else { return "Ledger rows cannot be dated after now." }
        if let opened = accounts.openedAt {
            guard opened <= clock.now else { return "The accounts cannot open after now." }
        } else if accounts.mode == .management {
            return "Managed accounts must say when they opened."
        }
        guard accounts.entries.count <= CompanyAccounts.keptEntries, accounts.days.count <= CompanyAccounts.keptDays else {
            return "The accounts keep more rows or days than they may."
        }
        guard zip(accounts.days, accounts.days.dropFirst()).allSatisfy({ $0.day < $1.day }) else {
            return "Day accounts must be listed once each, by ascending day."
        }
        let amounts = accounts.entries.flatMap { [$0.amount] + $0.breakdown.map(\.amount) }
            + accounts.days.flatMap { [$0.fareRevenue, $0.operatingCost, $0.maintenanceCost, $0.energyCost, $0.staffCost, $0.interestCost] }
        guard amounts.allSatisfy({ (-Self.maximumAccrued...Self.maximumAccrued).contains($0.amount) }) else { return "Ledger amounts are out of range." }
        guard accounts.days.allSatisfy({ [$0.fareRevenue, $0.operatingCost, $0.maintenanceCost, $0.energyCost, $0.staffCost, $0.interestCost].allSatisfy { $0 >= .zero } }) else {
            return "Day accounts cannot be negative."
        }
        guard accounts.entries.allSatisfy(Self.isWellFormed) else {
            return "A ledger row must have its kind's items, fares in and costs out, adding up to its amount."
        }
        return nil
    }

    /// Whether `entry` is shaped as settlements write it: its kind's items
    /// in order, fares 0 or more and costs 0 or less, adding up to its
    /// amount, with crowding (none of it negative) only on an hourly row.
    static func isWellFormed(_ entry: LedgerEntry) -> Bool {
        let items: [LedgerItem] = switch entry.kind {
        case .hourlyNet: [.fareRevenue, .operatingCost, .maintenanceCost]
        case .dailyEnergy: [.routeEnergy, .trainEnergy]
        case .dailyStaff: [.stationStaff, .trainStaff]
        case .dailyInterest: [.loanInterest]
        }
        guard entry.breakdown.map(\.item) == items,
              entry.breakdown.allSatisfy({ $0.item == .fareRevenue ? $0.amount >= .zero : $0.amount <= .zero }),
              entry.breakdown.reduce(Int64(0), { $0 + $1.amount.amount }) == entry.amount.amount
        else { return false }
        guard let crowding = entry.crowding else { return entry.kind != .hourlyNet }
        return entry.kind == .hourlyNet
            && [crowding.crowdedStations, crowding.fullTrains, crowding.maxWaiting, crowding.maxLoad].allSatisfy { (0...maximumAccrued).contains($0) }
    }

    /// The largest count or amount a save may hold: far beyond any game.
    static let maximumAccrued: Int64 = 1 << 50
    /// The largest an hour's count or fares may be, and its departures:
    /// small enough that settling the hour, and a day of such hours, stays
    /// within ``maximumAccrued``.
    static let maximumHourly: Int64 = 1 << 40
    static let maximumDepartures: Int64 = 1 << 30
    /// The largest balance either way a save may hold, so that settling
    /// can never overflow it.
    static let maximumBalance: Int64 = 1 << 62
}
