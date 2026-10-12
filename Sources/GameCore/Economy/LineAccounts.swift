// Line accounts (ARCHITECTURE decision 179): what each line carried, took
// in and cost each day, for the last 30 days, and how many people got on
// and off at each station yesterday.
//
// The company's books (`Operations.swift`) stay the authority: this is a
// breakdown of them. Every money figure here is a share of a figure the
// company wrote, apportioned by the largest remainder method in whole
// dollars, so that on any settled day the lines add up to the company's
// day:
//
// - fares: a journey's fare, paid as the passenger boards for their first
//   leg, is split among the lines of its legs by the straight-line length
//   of each leg (a direct passenger's fare is the one line's);
// - operating cost `75·departures + 42·train-km + 18·stations` and
//   maintenance `12·route-km + 9·train-km + 8·trains` of an hour: the
//   hour's rounded company figure, apportioned by each line's own terms
//   (empty runs between a line's ends count as its train-km, which is how
//   the company counts them too);
// - energy `220·route-km` and `360·trains`: each part apportioned by
//   route length and by trains;
// - staff `620·stations + 480·trains`: exactly each line's own.
//
// A station two lines call at counts for both (as the company counts it).
// Freight lines carry no passenger fares: they show their costs. Only a
// managed company records anything; a removed line's records go with it.
//
// Ported from the reference's line report (`Ci/`
// `flowDashboardCaptureLineForDailyReport`, `...CaptureStationForDailyReport`).

/// What one line did over some span: a day of it, or the hour in progress.
public struct LineTally: Hashable, Codable, Sendable {
    /// People who got on one of its trains (a transfer counts on each line).
    public internal(set) var boardings: Int64 = 0
    /// Trains that left a stop for the next.
    public internal(set) var departures: Int64 = 0
    /// Distance its trains ran, in world units, empty runs included.
    public internal(set) var trainDistance: Int64 = 0
    /// Of ``trainDistance``, the empty runs to an end of the line
    /// (decision 172), in world units.
    public internal(set) var deadheadDistance: Int64 = 0
    /// The fullest a train was as it left a stop, in thousandths of its
    /// rated capacity.
    public internal(set) var peakLoad: Int64 = 0
    /// Its share of the fares, whole dollars in cents.
    public internal(set) var fareRevenue: Money = .zero
    public internal(set) var operatingCost: Money = .zero
    public internal(set) var maintenanceCost: Money = .zero
    public internal(set) var energyCost: Money = .zero
    public internal(set) var staffCost: Money = .zero

    public init() {}

    public var totalCost: Money {
        operatingCost + maintenanceCost + energyCost + staffCost
    }

    /// Fares less the line's own running costs: not the company's profit
    /// (no interest, buildings or tax) and not the cash the day moved.
    public var profit: Money {
        fareRevenue - totalCost
    }

    var isEmpty: Bool { self == LineTally() }

    mutating func add(_ other: LineTally) {
        boardings += other.boardings
        departures += other.departures
        trainDistance += other.trainDistance
        deadheadDistance += other.deadheadDistance
        peakLoad = max(peakLoad, other.peakLoad)
        fareRevenue = fareRevenue + other.fareRevenue
        operatingCost = operatingCost + other.operatingCost
        maintenanceCost = maintenanceCost + other.maintenanceCost
        energyCost = energyCost + other.energyCost
        staffCost = staffCost + other.staffCost
    }

    var isValid: Bool {
        let counts = [boardings, departures, trainDistance, deadheadDistance, peakLoad]
        let money = [fareRevenue, operatingCost, maintenanceCost, energyCost, staffCost]
        return counts.allSatisfy { $0 >= 0 && $0 <= GameWorld.maximumHourly }
            && deadheadDistance <= trainDistance
            && money.allSatisfy { $0.amount >= 0 && $0.amount % 100 == 0 && $0.amount <= GameWorld.maximumHourly * 100 }
    }
}

/// One day of a line's records.
public struct LineDay: Hashable, Codable, Sendable {
    public let day: Int64
    public internal(set) var tally: LineTally
}

/// One line's records: its last days, and the hour in progress.
public struct LineRecords: Hashable, Codable, Sendable {
    public let line: LineID
    /// Ascending by day, at most ``LineAccounts/keptDays``.
    public internal(set) var days: [LineDay] = []
    /// The hour in progress, settled into a day at the next full hour.
    public internal(set) var pending = LineTally()

    mutating func record(_ tally: LineTally, day: Int64) {
        guard !tally.isEmpty else { return }
        if let index = days.firstIndex(where: { $0.day == day }) {
            days[index].tally.add(tally)
        } else {
            days.append(LineDay(day: day, tally: tally))
            days.sort { $0.day < $1.day }
            if days.count > LineAccounts.keptDays { days.removeFirst(days.count - LineAccounts.keptDays) }
        }
    }
}

/// How many got on and off at a station on a day.
public struct StationFlowDay: Hashable, Codable, Sendable {
    public let station: StationID
    public let day: Int64
    public internal(set) var boarded: Int64 = 0
    public internal(set) var alighted: Int64 = 0
}

public struct LineAccounts: Equatable, Sendable {
    /// Days of records kept for a line.
    public static let keptDays = 30

    public internal(set) var lines: [LineRecords] = []
    /// Station flows of today and yesterday.
    public internal(set) var flows: [StationFlowDay] = []

    public init() {}

    func records(of line: LineID) -> LineRecords? {
        lines.first { $0.line == line }
    }

    mutating func index(of line: LineID) -> Int {
        if let index = lines.firstIndex(where: { $0.line == line }) { return index }
        lines.append(LineRecords(line: line))
        lines.sort { $0.line < $1.line }
        return lines.firstIndex { $0.line == line }!
    }

    mutating func count(_ change: (inout LineTally) -> Void, on line: LineID) {
        change(&lines[index(of: line)].pending)
    }

    mutating func countFlow(boarded: Int64 = 0, alighted: Int64 = 0, at station: StationID, day: Int64) {
        flows.removeAll { $0.day < day - 1 }
        if let index = flows.firstIndex(where: { $0.station == station && $0.day == day }) {
            flows[index].boarded = min(flows[index].boarded + boarded, GameWorld.maximumHourly)
            flows[index].alighted = min(flows[index].alighted + alighted, GameWorld.maximumHourly)
        } else {
            flows.append(StationFlowDay(station: station, day: day, boarded: boarded, alighted: alighted))
            flows.sort { ($0.station, $0.day) < ($1.station, $1.day) }
        }
    }

    /// `total` shared out among `weights` in proportion, by the largest
    /// remainder method (ties to the earlier), so the shares add up to
    /// `total` exactly. All zero if there is nothing to share or no weight.
    static func apportion(_ total: Int64, by weights: [Int64]) -> [Int64] {
        let sum = weights.reduce(0, +)
        guard total > 0, sum > 0 else { return Array(repeating: 0, count: weights.count) }
        var shares: [Int64] = []
        var remainders: [Int64] = []
        for weight in weights {
            let product = total.multipliedFullWidth(by: weight)
            let (quotient, remainder) = sum.dividingFullWidth(product)
            shares.append(quotient)
            remainders.append(remainder)
        }
        var left = total - shares.reduce(0, +)
        for index in weights.indices.sorted(by: { remainders[$0] != remainders[$1] ? remainders[$0] > remainders[$1] : $0 < $1 }) where left > 0 {
            shares[index] += 1
            left -= 1
        }
        return shares
    }

    /// Whether every record is well formed and belongs to one of `lineIDs`
    /// and `stationIDs`.
    func isValid(lines lineIDs: Set<LineID>, stations stationIDs: Set<StationID>) -> Bool {
        let ordered = zip(lines, lines.dropFirst()).allSatisfy { $0.line < $1.line }
        let recordsOK = lines.allSatisfy { records in
            lineIDs.contains(records.line) && records.pending.isValid
                && records.days.count <= Self.keptDays
                && zip(records.days, records.days.dropFirst()).allSatisfy { $0.day < $1.day }
                && records.days.allSatisfy { $0.tally.isValid }
        }
        let flowsOK = zip(flows, flows.dropFirst()).allSatisfy { ($0.station, $0.day) < ($1.station, $1.day) }
            && flows.allSatisfy { stationIDs.contains($0.station) && $0.boarded >= 0 && $0.alighted >= 0
                && $0.boarded <= GameWorld.maximumHourly && $0.alighted <= GameWorld.maximumHourly }
        return ordered && recordsOK && flowsOK
    }
}

extension LineAccounts: Codable {
    private enum CodingKeys: String, CodingKey { case lines, stations }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lines = try container.decode([LineRecords].self, forKey: .lines)
        flows = try container.decode([StationFlowDay].self, forKey: .stations)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lines, forKey: .lines)
        try container.encode(flows, forKey: .stations)
    }
}

// MARK: - The world's side

extension GameWorld {
    /// Turns the line accounts on or off (decision 179). Turning them on
    /// starts empty records; turning them off drops them. Free.
    public mutating func setLineAccounts(_ enabled: Bool) {
        if enabled {
            if lineAccounts == nil { lineAccounts = LineAccounts() }
        } else {
            lineAccounts = nil
        }
    }

    // MARK: Queries

    /// The last days of line `id`, oldest first, up to the day in
    /// progress: empty without the accounts, or for a line with no records.
    public func lineDays(_ id: LineID) -> [LineDay] {
        lineAccounts?.records(of: id)?.days ?? []
    }

    /// What line `id` did on the day before the clock's day, or `nil` if it
    /// has no record of it.
    public func lineYesterday(_ id: LineID) -> LineTally? {
        let yesterday = dayIndex(of: clock.now) - 1
        return lineDays(id).first { $0.day == yesterday }?.tally
    }

    /// How many got on and off at station `id` yesterday.
    public func stationFlowYesterday(_ id: StationID) -> (boarded: Int64, alighted: Int64) {
        let yesterday = dayIndex(of: clock.now) - 1
        guard let flow = lineAccounts?.flows.first(where: { $0.station == id && $0.day == yesterday }) else { return (0, 0) }
        return (flow.boarded, flow.alighted)
    }

    // MARK: Recording

    private var recordsLines: Bool { lineAccounts != nil && accounts.mode == .management }

    mutating func countBoarding(_ count: Int64, on line: LineID?, at station: StationID) {
        guard recordsLines, count > 0 else { return }
        if let line {
            lineAccounts?.count({ $0.boardings = min($0.boardings + count, Self.maximumHourly) }, on: line)
        }
        let day = dayIndex(of: clock.now)
        lineAccounts?.countFlow(boarded: count, at: station, day: day)
    }

    mutating func countAlighting(_ count: Int64, at station: StationID) {
        guard recordsLines, count > 0 else { return }
        let day = dayIndex(of: clock.now)
        lineAccounts?.countFlow(alighted: count, at: station, day: day)
    }

    mutating func countLineDeparture(on line: LineID, distance: Int64, passengers: Int64, seats: Int64) {
        guard recordsLines else { return }
        lineAccounts?.count({
            $0.departures = min($0.departures + 1, Self.maximumDepartures)
            $0.trainDistance = min($0.trainDistance + distance, Self.maximumHourly)
            if seats > 0 { $0.peakLoad = max($0.peakLoad, min(1_000 * passengers / seats, Self.maximumHourly)) }
        }, on: line)
    }

    mutating func countLineDeadhead(_ distance: Int64, on line: LineID) {
        guard recordsLines else { return }
        lineAccounts?.count({ $0.deadheadDistance = min($0.deadheadDistance + distance, $0.trainDistance + distance, Self.maximumHourly) }, on: line)
    }

    /// `fare` just charged for boarders whose journeys ride `lines` (each
    /// with its weight): shared among them.
    mutating func shareFare(_ fare: Money, among weights: [(line: LineID, weight: Int64)]) {
        guard recordsLines, fare > .zero, !weights.isEmpty else { return }
        let ordered = weights.sorted { $0.line < $1.line }
        let shares = LineAccounts.apportion(fare.amount / 100, by: ordered.map(\.weight))
        for (entry, share) in zip(ordered, shares) where share > 0 {
            lineAccounts?.count({ $0.fareRevenue = Money(min($0.fareRevenue.amount + share * 100, Self.maximumHourly / 100 * 100)) }, on: entry.line)
        }
    }

    /// The weights that share a journey's fare among its legs' lines: each
    /// leg's straight-line length, scaled so that every journey weighs the
    /// same, times `count` riders; the one line's alone without a journey
    /// of more than one leg.
    func fareWeights(of journey: PassengerJourney?, line: LineID?, count: Int64) -> [(line: LineID, weight: Int64)] {
        let scale: Int64 = 1_000_000
        guard let journey, journey.legs.count > 1 else {
            return (journey?.legs.first?.line ?? line).map { [($0, count * scale)] } ?? []
        }
        let lengths = journey.legs.map { leg in
            max(1, FixedPoint.squareRoot(squaredDistance(from: leg.from, to: leg.to) ?? 1))
        }
        let total = lengths.reduce(0, +)
        var byLine: [LineID: Int64] = [:]
        for (leg, length) in zip(journey.legs, lengths) {
            byLine[leg.line, default: 0] += count * (scale * length / total)
        }
        return byLine.map { ($0.key, $0.value) }.filter { $0.1 > 0 }
    }

    // MARK: Settling

    /// The hour ending at `now` is settled: the pending counts of each line
    /// join its day, with its share of the hour's operating and maintenance
    /// cost.
    mutating func settleLineHour(day: Int64, assets: FixedAssets, operating: Money, maintenance: Money) {
        guard lineAccounts != nil else { return }
        let km = Self.unitsPerKilometre
        for line in assets.lines { _ = lineAccounts?.index(of: line.id) }
        guard var book = lineAccounts else { return }
        let owned = assets.lines
        let pendings = owned.map { entry in book.records(of: entry.id)?.pending ?? LineTally() }
        let operatingShares = LineAccounts.apportion(operating.amount / 100, by: zip(owned, pendings).map { entry, tally in
            (75 * tally.departures + 18 * entry.stations) * km + 42 * tally.trainDistance
        })
        let maintenanceShares = LineAccounts.apportion(maintenance.amount / 100, by: zip(owned, pendings).map { entry, tally in
            (12 * entry.routeLength + 9 * tally.trainDistance) * 1_000 + 8 * entry.trainWeight * km
        })
        for (index, entry) in owned.enumerated() {
            var tally = pendings[index]
            tally.operatingCost = Money(operatingShares[index] * 100)
            tally.maintenanceCost = Money(maintenanceShares[index] * 100)
            let slot = book.index(of: entry.id)
            book.lines[slot].pending = LineTally()
            book.lines[slot].record(tally, day: day)
        }
        lineAccounts = book
    }

    /// The day ending is settled: each line's share of the day's energy
    /// and its own staff.
    mutating func settleLineDay(day: Int64, assets: FixedAssets, routeEnergy: Money, trainEnergy: Money, trainStaff: Money) {
        guard var book = lineAccounts else { return }
        let owned = assets.lines
        let routeShares = LineAccounts.apportion(routeEnergy.amount / 100, by: owned.map(\.routeLength))
        let trainShares = LineAccounts.apportion(trainEnergy.amount / 100, by: owned.map(\.trainWeight))
        let staffShares = LineAccounts.apportion(trainStaff.amount / 100, by: owned.map(\.trainWeight))
        for (index, entry) in owned.enumerated() {
            var tally = LineTally()
            tally.energyCost = Money((routeShares[index] + trainShares[index]) * 100)
            tally.staffCost = Money((620 * entry.stations + staffShares[index]) * 100)
            book.lines[book.index(of: entry.id)].record(tally, day: day)
        }
        lineAccounts = book
    }

    mutating func removeLineAccounts(of id: LineID) {
        lineAccounts?.lines.removeAll { $0.line == id }
    }
}
