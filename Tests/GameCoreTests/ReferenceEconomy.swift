import GameCore

/// G1c (ARCHITECTURE decision 36) written a second time for
/// ``ReferenceWorld``, straight from the rules, and differently on purpose:
///
/// - fares are charged as each stop is served, the moment the train leaves;
/// - amounts are kept in 1/64000ths of a dollar until a row is written, and
///   rounded there by adding half and dividing;
/// - the fare rules are checked step by step against the engine's messages,
///   not by one predicate;
/// - days are a dictionary, summed for the report on demand;
/// - fixed assets are counted from each line's stops, sorted with the
///   repeats dropped, and the route from the reference's own journey.
///
/// Only the demand table (``FareRules/demandFactor(fare:)``) is shared:
/// `EconomyAccountsTests` checks it against the reference's formula.
struct ReferenceAccounts: Equatable {
    var managed = false
    var rules: FareRules?
    /// The city's fare baseline, in cents: the reference's default city's
    /// 75 until set.
    var baseline: Int64 = 75
    var opened: Int64?
    var fareCents: Int64 = 0
    var fareTrips: Int64 = 0
    var departures: Int64 = 0
    var distance: Int64 = 0
    var passengers: Int64 = 0
    var seats: Int64 = 0
    var rows: [LedgerEntry] = []
    /// Day → (fares, operating, maintenance, energy, staff), in cents.
    var days: [Int64: [Int64]] = [:]
}

extension ReferenceWorld {
    // MARK: - Commands

    mutating func setEconomyMode(_ mode: EconomyMode) {
        // Stage W2a: opened in seconds, as the clock may be between minutes.
        if mode == .management, !accounts.managed { accounts.opened = clockSeconds }
        accounts.managed = mode == .management
    }

    mutating func setFareRules(_ rules: FareRules) -> GameError? {
        switch rules {
        case .flat(let fare):
            if fare.amount < 0 || fare.amount > 1_000_000_000 { return .invalidFareRules }
        case .distance(let bands):
            // "expected 1–64 bands"
            if bands.isEmpty || bands.count > 64 { return .invalidFareRules }
            // "bands must cover all distances without gaps"
            var reached: Int64 = 0
            for (index, band) in bands.enumerated() {
                if band.fromMeters != reached || band.fare.amount < 0 || band.fare.amount > 1_000_000_000 { return .invalidFareRules }
                guard let to = band.toMeters else {
                    // "last band must be open ended": only the last.
                    if index != bands.count - 1 { return .invalidFareRules }
                    break
                }
                if index == bands.count - 1 || to < band.fromMeters || to > 10_000_000 || band.fromMeters > 10_000_000 { return .invalidFareRules }
                reached = to
            }
        }
        accounts.rules = rules
        return nil
    }

    mutating func setFareBaseline(_ baseline: Money) -> GameError? {
        // A cent at least, and no dearer than any fare may be.
        if baseline.amount < 1 || baseline.amount > 1_000_000_000 { return .invalidFareRules }
        accounts.baseline = baseline.amount
        return nil
    }

    // MARK: - Fares

    /// The rule's fare between two stations, before the minimum.
    func ruleFare(from origin: Int, to destination: Int) -> Int64? {
        guard origin != destination,
              let a = stations.first(where: { $0.id == origin }), let b = stations.first(where: { $0.id == destination })
        else { return nil }
        let dx = Int64(a.position.x - b.position.x) * 1024
        let dy = Int64(a.position.y - b.position.y) * 1024
        let squared = dx * dx + dy * dy
        switch accounts.rules ?? .flat(500) {
        case .flat(let fare):
            return fare.amount
        case .distance(let bands):
            // The first step whose end lies beyond the trip.
            for band in bands {
                guard let to = band.toMeters else { return band.fare.amount }
                let end = to * 64
                if squared < end * end { return band.fare.amount }
            }
            return 0
        }
    }

    func tripFare(from origin: Int, to destination: Int) -> Int64? {
        ruleFare(from: origin, to: destination).map { $0 <= 0 ? 500 : $0 }
    }

    /// The demand factor of a pair while fares change demand.
    func demandFactor(from origin: Int, to destination: Int) -> Int64? {
        guard accounts.managed, accounts.rules != nil, let fare = ruleFare(from: origin, to: destination) else { return nil }
        return FareRules.demandFactor(fare: Money(fare), baseline: Money(accounts.baseline))
    }

    mutating func chargeFare(_ count: Int64, from origin: Int, to destination: Int) {
        guard accounts.managed, let fare = tripFare(from: origin, to: destination) else { return }
        // Math.round(count × fare) in dollars.
        let cents = count * fare
        accounts.fareCents += ((cents + 50) / 100) * 100
        accounts.fareTrips += count
    }

    mutating func countDeparture(_ i: Int, distance: Int64) {
        let train = trains[i]
        guard accounts.managed, lines.contains(where: { $0.roster.contains(train.id) || $0.patterns.contains { $0.roster.contains(train.id) } }) else { return }
        accounts.departures += 1
        accounts.distance += distance
        accounts.passengers += (passengers.riders[train.id] ?? [:]).values.reduce(0) { $0 + $1.values.reduce(0, +) }
        accounts.seats += Int64(train.cars) * 320
    }

    // MARK: - Settlements

    mutating func settle(memo: inout DispatchMemo) {
        guard accounts.managed, clockSeconds % 3600 == 0, let opened = accounts.opened, opened < clockSeconds else { return }
        accounts.opened = clockSeconds
        var stations: Int64 = 0
        var route: Int64 = 0
        var trainCount: Int64 = 0
        for line in lines {
            let stops = line.stops.map(\.rawValue).sorted()
            stations += Int64(stops.indices.filter { $0 == 0 || stops[$0] != stops[$0 - 1] }.count)
            let key = ServiceKey(line: line.id, service: 0)
            if memo.journeys[key] == nil { memo.journeys[key] = .some(serviceJourney(line, 0)) }
            if let journey = memo.journeys[key]! {
                for leg in journey.legs[0..<(journey.legs.count / 2)] { route += leg.path.distance }
            }
            trainCount += Int64([line.trains[.peak]!, line.trains[.offPeak]!, line.trains[.low]!].max()!)
            for pattern in line.patterns {
                trainCount += Int64([pattern.trains[.peak]!, pattern.trains[.offPeak]!, pattern.trains[.low]!].max()!)
            }
        }
        func round(_ sixtyFourThousandths: Int64) -> Int64 {
            ((sixtyFourThousandths + 32_000) / 64_000) * 100
        }
        let operating = round(75 * 64_000 * accounts.departures + 42 * accounts.distance + 18 * 64_000 * stations)
        let maintenance = round(12 * route + 9 * accounts.distance + 8 * 64_000 * trainCount)
        let fares = accounts.fareCents
        accounts.fareCents = 0
        accounts.fareTrips = 0
        accounts.departures = 0
        accounts.distance = 0
        accounts.passengers = 0
        accounts.seats = 0
        // The hour's day: that of its last minute.
        let last = minutes - 1
        let day = last >= 0 ? last / 1440 : -((-last + 1439) / 1440)
        if fares > 0 || operating > 0 || maintenance > 0 {
            let waiting = passengers.queue.values.map { $0.reduce(Int64(0)) { $0 + $1.count } }
            var full: Int64 = 0
            var load: Int64 = 0
            for (id, onBoard) in passengers.riders {
                let cars = Int64(trains.first { $0.id == id }!.cars)
                let count = onBoard.values.reduce(0) { $0 + $1.values.reduce(0, +) }
                if count >= cars * 320 { full += 1 }
                // Math.round(count / rated × 1000).
                load = max(load, (count * 1000 * 2 + cars * 320) / (cars * 320 * 2))
            }
            let crowding = CrowdingMetrics(
                crowdedStations: Int64(waiting.filter { $0 > 1500 }.count), fullTrains: full, maxWaiting: waiting.max() ?? 0, maxLoad: load
            )
            write(LedgerEntry(
                kind: .hourlyNet, time: GameTime(minutes: minutes), amount: Money(fares - operating - maintenance),
                breakdown: [
                    LedgerLine(item: .fareRevenue, amount: Money(fares)), LedgerLine(item: .operatingCost, amount: Money(-operating)),
                    LedgerLine(item: .maintenanceCost, amount: Money(-maintenance)),
                ],
                crowding: crowding
            ), day: day, totals: [fares, operating, maintenance, 0, 0])
        }
        guard minutes % 1440 == 0 else { return }
        let ended = day
        let energy = round(220 * route + 360 * 64_000 * trainCount)
        if energy > 0 {
            write(LedgerEntry(
                kind: .dailyEnergy, time: GameTime(minutes: minutes - 1), amount: Money(-energy),
                breakdown: [LedgerLine(item: .routeEnergy, amount: Money(-round(220 * route))), LedgerLine(item: .trainEnergy, amount: Money(-36_000 * trainCount))]
            ), day: ended, totals: [0, 0, 0, energy, 0])
        }
        let staff = 62_000 * stations + 48_000 * trainCount
        if staff > 0 {
            write(LedgerEntry(
                kind: .dailyStaff, time: GameTime(minutes: minutes - 1), amount: Money(-staff),
                breakdown: [LedgerLine(item: .stationStaff, amount: Money(-62_000 * stations)), LedgerLine(item: .trainStaff, amount: Money(-48_000 * trainCount))]
            ), day: ended, totals: [0, 0, 0, 0, staff])
        }
    }

    private mutating func write(_ row: LedgerEntry, day: Int64, totals: [Int64]) {
        balance += row.amount.amount
        accounts.rows.append(row)
        if accounts.rows.count > 50 { accounts.rows.removeFirst() }
        // Energy and staff count the cost of the parts as written.
        var added = totals
        if row.kind == .dailyEnergy || row.kind == .dailyStaff {
            let parts = -row.breakdown.reduce(Int64(0)) { $0 + $1.amount.amount }
            added = row.kind == .dailyEnergy ? [0, 0, 0, parts, 0] : [0, 0, 0, 0, parts]
        }
        accounts.days[day] = zip(accounts.days[day] ?? [0, 0, 0, 0, 0], added).map { $0 + $1 }
        for old in accounts.days.keys where old <= day - 720 {
            accounts.days[old] = nil
        }
    }

    // MARK: - Summaries

    var accountsSummary: AccountsSummary {
        AccountsSummary(
            mode: accounts.managed ? "management" : "free",
            fareRules: accounts.rules.map(FareRulesSummary.init),
            openedAt: accounts.opened,
            pending: PendingSummary(
                fareRevenue: accounts.fareCents, fareTrips: accounts.fareTrips, departures: accounts.departures,
                trainDistance: accounts.distance, passengers: accounts.passengers, seats: accounts.seats
            ),
            ledger: accounts.rows.map(LedgerRowSummary.init),
            days: accounts.days.keys.sorted().map { day in
                let t = accounts.days[day]!
                return DaySummary(day: day, fareRevenue: t[0], operatingCost: t[1], maintenanceCost: t[2], energyCost: t[3], staffCost: t[4])
            }
        )
    }

    func reportSummary(_ period: FinancePeriod) -> ReportSummary {
        let today = minutes >= 0 ? minutes / 1440 : -((-minutes + 1439) / 1440)
        let span = period.days
        func bucket(_ day: Int64) -> Int64 { day >= 0 ? day / span : -((-day + span - 1) / span) }
        func sum(_ index: Int64) -> PeriodSummary {
            var t: [Int64] = [0, 0, 0, 0, 0]
            for (day, totals) in accounts.days where bucket(day) == index {
                t = zip(t, totals).map { $0 + $1 }
            }
            return PeriodSummary(index: index, fareRevenue: t[0], operatingCost: t[1], maintenanceCost: t[2], energyCost: t[3], staffCost: t[4])
        }
        return ReportSummary(current: sum(bucket(today)), previous: sum(bucket(today) - 1))
    }
}
