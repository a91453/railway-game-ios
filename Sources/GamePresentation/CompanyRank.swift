import GameCore

// The company's rank (ARCHITECTURE decision 181): a free game's long-term
// goal once there is no challenge to play for. A score of 0 to 1,000 made of
// seven measures, each counting linearly up to its full marks (the two of
// how well it is run scaled down for a railway of few stations), and a title
// for every 100 points, from trainee station clerk to chairman, with
// railway tycoon from 960. A-Train's tourism game rates the company
// (格付) and A-Train 9 has milestones by cash; OpenTTD has a performance
// rating and titles. Derived from the world when asked: nothing here is
// saved, and GameCore is untouched.

/// What the rank is measured on, each with its full marks and the value
/// that earns them (decision 181).
public enum RankMeasure: String, CaseIterable, Hashable, Sendable {
    /// The most riders who paid a fare in one day.
    case bestDay
    /// The track built, in metres.
    case network
    /// The stations built.
    case stations
    /// What the company is worth (its equity), in cents.
    case netWorth
    /// The residents within 800 m of an open station.
    case servedPeople
    /// Yesterday's running costs against its takings, in thousandths; the
    /// lower the better.
    case operatingRatio
    /// The trains in service now that are at most two minutes late, in
    /// thousandths of them.
    case punctuality

    /// The points it is worth at most; the seven add up to 1,000.
    public var maximum: Int {
        switch self {
        case .bestDay: 250
        case .network: 100
        case .stations: 100
        case .netWorth: 200
        case .servedPeople: 150
        case .operatingRatio: 100
        case .punctuality: 100
        }
    }

    /// The value that earns the full marks.
    public var target: Int64 {
        switch self {
        case .bestDay: 1_000_000
        case .network: 300_000
        case .stations: 100
        case .netWorth: 50_000_000_000
        case .servedPeople: 2_000_000
        case .operatingRatio: 600
        case .punctuality: 1_000
        }
    }

    /// The operating ratio at which it earns nothing: costs as large as
    /// the takings.
    static let breakEvenRatio: Int64 = 1_000

    /// Whether it rates how well the railway is run rather than how large
    /// it is: the operating ratio and the trains on time. A railway of a
    /// few stations earns them in part only (``CompanyRank/fullQualityStations``),
    /// so one profitable train is not half-way to the next title.
    public var isQuality: Bool {
        self == .operatingRatio || self == .punctuality
    }

    /// The points `value` earns, 0 to ``maximum``.
    public func points(for value: Int64) -> Int {
        let full = Int64(maximum)
        let points: Int64
        switch self {
        case .operatingRatio:
            // Full marks at 60% or less, none at 100% or more.
            guard value < Self.breakEvenRatio else { return 0 }
            guard value > target else { return maximum }
            points = (Self.breakEvenRatio - value) * full / (Self.breakEvenRatio - target)
        default:
            guard value > 0 else { return 0 }
            guard value < target else { return maximum }
            points = value * full / target
        }
        return Int(min(max(points, 0), full))
    }

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .bestDay: language.text("Best day's riders", "最佳單日旅客")
        case .network: language.text("Track", "路網長度")
        case .stations: language.text("Stations", "車站數")
        case .netWorth: language.text("Net worth", "淨值")
        case .servedPeople: language.text("People served", "服務人口")
        case .operatingRatio: language.text("Operating ratio", "營業比")
        case .punctuality: language.text("On time", "準點率")
        }
    }

    /// `value` as the player reads it: "31,200", "12.4 km", "$ 5,000,000",
    /// "58%".
    public func valueText(_ value: Int64) -> String {
        switch self {
        case .bestDay, .stations, .servedPeople: Money(value).displayText
        case .network: "\(WorldBounds.kilometresText(value * WorldCoordinate.unitsPerMetre)) km"
        case .netWorth: Money(value).moneyText
        case .operatingRatio, .punctuality: "\((value + 5) / 10)%"
        }
    }
}

/// The titles a company's rank earns, one for every 100 points
/// (decision 181).
public enum CompanyTitle: Int, CaseIterable, Comparable, Hashable, Sendable {
    case traineeClerk, stationClerk, assistantStationmaster, stationmaster, sectionChief, operationsChief
    case divisionDirector, bureauDirector, generalManager, chairman, tycoon

    /// The score a tycoon needs.
    public static let tycoonScore = 960

    public init(score: Int) {
        self = score >= Self.tycoonScore ? .tycoon : CompanyTitle(rawValue: min(max(score / 100, 0), 9)) ?? .traineeClerk
    }

    /// The least score with this title.
    public var minimumScore: Int {
        self == .tycoon ? Self.tycoonScore : rawValue * 100
    }

    public var next: CompanyTitle? {
        CompanyTitle(rawValue: rawValue + 1)
    }

    public static func < (lhs: CompanyTitle, rhs: CompanyTitle) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .traineeClerk: language.text("Trainee Station Clerk", "見習站務員")
        case .stationClerk: language.text("Station Clerk", "站務員")
        case .assistantStationmaster: language.text("Assistant Stationmaster", "副站長")
        case .stationmaster: language.text("Stationmaster", "站長")
        case .sectionChief: language.text("Section Chief", "段長")
        case .operationsChief: language.text("Operations Section Chief", "運務段長")
        case .divisionDirector: language.text("Division Director", "處長")
        case .bureauDirector: language.text("Bureau Director", "局長")
        case .generalManager: language.text("General Manager", "總經理")
        case .chairman: language.text("Chairman", "董事長")
        case .tycoon: language.text("Railway Tycoon", "鐵道大亨")
        }
    }
}

/// What the company has, measured for its rank and its achievements
/// (decision 181). Read from the world once; the panel and the midnight
/// check share it.
public struct CompanyFigures: Hashable, Sendable {
    /// The most riders in a day the world still knows: the days of the
    /// accounts (two years) and, on a map bought tile by tile, the best day
    /// it keeps for good.
    public var bestDayRiders: Int64
    /// Yesterday's riders.
    public var yesterdayRiders: Int64
    /// The track built, in metres.
    public var trackMetres: Int64
    public var stations: Int
    /// The company's equity (``BalanceSheet/equity``).
    public var netWorth: Money
    /// The residents within 800 m of an open station, each counted once.
    public var servedPeople: Int64
    /// Yesterday's running costs and the buildings' upkeep against the
    /// fares, freight and rent, in thousandths; `nil` without takings.
    public var operatingRatio: Int64?
    /// The trains on the track now at most two minutes late, in
    /// thousandths of them; `nil` with none on the track.
    public var punctuality: Int64?

    /// The lateness a train may have and still be on time: two minutes.
    public static let onTimeSeconds: Int64 = 120

    public init(
        bestDayRiders: Int64 = 0, yesterdayRiders: Int64 = 0, trackMetres: Int64 = 0, stations: Int = 0, netWorth: Money = .zero,
        servedPeople: Int64 = 0, operatingRatio: Int64? = nil, punctuality: Int64? = nil
    ) {
        self.bestDayRiders = bestDayRiders
        self.yesterdayRiders = yesterdayRiders
        self.trackMetres = trackMetres
        self.stations = stations
        self.netWorth = netWorth
        self.servedPeople = servedPeople
        self.operatingRatio = operatingRatio
        self.punctuality = punctuality
    }

    public init(world: GameWorld) {
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        let closed = world.accounts.days.filter { $0.day < today }
        bestDayRiders = max(closed.map(\.fareTrips).max() ?? 0, world.mapExpansion?.bestDayRiders ?? 0)
        let yesterday = closed.first { $0.day == today - 1 }
        yesterdayRiders = yesterday?.fareTrips ?? 0
        trackMetres = world.network.edges.reduce(0) { $0 + $1.length } / WorldCoordinate.unitsPerMetre
        stations = world.stations.count
        netWorth = world.balanceSheet().equity
        servedPeople = Self.servedPeople(in: world)
        if let yesterday {
            let takings = (yesterday.fareRevenue + yesterday.freightRevenue + yesterday.propertyRevenue).amount
            let costs = (yesterday.totalCost + yesterday.propertyCost).amount
            operatingRatio = takings > 0 ? min(costs.multipliedReportingOverflow(by: 1_000).partialValue / takings, 1_000_000) : nil
        } else {
            operatingRatio = nil
        }
        var running = 0, onTime = 0
        // A train on the track between services (at a terminus, waiting
        // to be sent out) is on time; one in the depot is not counted.
        for train in world.trains where train.position != nil {
            running += 1
            if world.lateness(of: train.id) ?? 0 <= Self.onTimeSeconds { onTime += 1 }
        }
        punctuality = running > 0 ? Int64(onTime * 1_000 / running) : nil
    }

    /// The residents of the land within 800 m (``Land/catchmentRadius``) of
    /// an open station, each cell counted once.
    static func servedPeople(in world: GameWorld) -> Int64 {
        servedCells(in: world).reduce(0) { $0 + (world.land.cell(row: $1.row, column: $1.column)?.residents ?? 0) }
    }

    /// The cells of land with anyone living or working in them whose
    /// middles lie within 800 m of an open station.
    static func servedCells(in world: GameWorld) -> Set<CellPosition> {
        let radius = Land.catchmentRadius, reach = radius * radius, cell = Land.cellLength
        var counted: Set<CellPosition> = []
        for station in world.stations where station.operationMode != .closed {
            let point = station.location
            let rows = Int((point.y - radius) / cell)...Int((point.y + radius) / cell)
            let columns = Int((point.x - radius) / cell)...Int((point.x + radius) / cell)
            for row in rows where row >= 0 {
                for column in columns where column >= 0 {
                    guard let land = world.land.cell(row: row, column: column) else { continue }
                    let middle = land.middle
                    let dx = middle.x - point.x, dy = middle.y - point.y
                    if dx * dx + dy * dy < reach { counted.insert(land.position) }
                }
            }
        }
        return counted
    }

    /// The value of `measure`.
    public func value(of measure: RankMeasure) -> Int64 {
        switch measure {
        case .bestDay: bestDayRiders
        case .network: trackMetres
        case .stations: Int64(stations)
        case .netWorth: netWorth.amount
        case .servedPeople: servedPeople
        case .operatingRatio: operatingRatio ?? RankMeasure.breakEvenRatio
        case .punctuality: punctuality ?? 0
        }
    }
}

/// The company's rank (decision 181): each measure's points, the score and
/// its title.
public struct CompanyRank: Hashable, Sendable {
    public struct Part: Hashable, Sendable {
        public let measure: RankMeasure
        /// The value measured (see ``CompanyFigures/value(of:)``); `nil`
        /// when there is nothing to measure yet (no takings, no train
        /// running).
        public let value: Int64?
        public let points: Int

        public var maximum: Int { measure.maximum }
    }

    public let figures: CompanyFigures
    public let parts: [Part]

    public init(figures: CompanyFigures) {
        self.figures = figures
        parts = RankMeasure.allCases.map { measure in
            let value: Int64? = switch measure {
            case .operatingRatio: figures.operatingRatio
            case .punctuality: figures.punctuality
            default: figures.value(of: measure)
            }
            var points = value.map(measure.points(for:)) ?? 0
            if measure.isQuality {
                points = points * min(figures.stations, Self.fullQualityStations) / Self.fullQualityStations
            }
            return Part(measure: measure, value: value, points: points)
        }
    }

    /// The stations a railway needs for the full marks of the measures of
    /// how well it is run (``RankMeasure/isQuality``): with fewer, their
    /// points are scaled by stations ÷ 20.
    public static let fullQualityStations = 20

    public init(world: GameWorld) {
        self.init(figures: CompanyFigures(world: world))
    }

    /// 0 to 1,000.
    public var score: Int {
        parts.reduce(0) { $0 + $1.points }
    }

    public var title: CompanyTitle {
        CompanyTitle(score: score)
    }

    /// The points to the next title; `nil` for a tycoon.
    public var pointsToNextTitle: Int? {
        title.next.map { $0.minimumScore - score }
    }

    /// "Station Clerk · 142 / 1,000".
    public func headline(in language: DisplayLanguage) -> String {
        "\(title.title(in: language)) · \(score) / 1,000"
    }

    /// "58 points to Assistant Stationmaster", or the top's own words.
    public func nextTitleText(in language: DisplayLanguage) -> String {
        guard let next = title.next, let points = pointsToNextTitle else {
            return language.text("The top of the railway world.", "已經是鐵道界的頂點。")
        }
        return language.text(
            "\(points) point\(points == 1 ? "" : "s") to \(next.title(in: .english))",
            "再 \(points) 分升為\(next.title(in: .traditionalChinese))"
        )
    }

    /// A part's line: "Best day's riders 31,200 · 26 / 250".
    public func partText(_ part: Part, in language: DisplayLanguage) -> String {
        let value = part.value.map(part.measure.valueText) ?? "—"
        return "\(part.measure.title(in: language)) \(value) · \(part.points) / \(part.maximum)"
    }

    // MARK: - Milestones

    /// The rungs each measure's milestones climb, the last its full marks.
    static func rungs(of measure: RankMeasure) -> [Int64] {
        switch measure {
        case .bestDay: [1_000, 5_000, 10_000, 30_000, 50_000, 100_000, 200_000, 300_000, 500_000, 1_000_000]
        case .network: [5_000, 10_000, 25_000, 50_000, 100_000, 200_000, 300_000]
        case .stations: [5, 10, 25, 50, 75, 100]
        case .netWorth: [500_000_000, 1_000_000_000, 2_500_000_000, 5_000_000_000, 10_000_000_000, 25_000_000_000, 50_000_000_000]
        case .servedPeople: [10_000, 50_000, 100_000, 250_000, 500_000, 1_000_000, 2_000_000]
        case .operatingRatio: [900, 800, 700, 600]
        case .punctuality: [700, 800, 900, 1_000]
        }
    }

    /// A next step of a measure: reach `target`, which earns `gain` points.
    public struct Milestone: Hashable, Sendable {
        public let measure: RankMeasure
        public let target: Int64
        public let current: Int64?
        public let gain: Int

        /// "Daily riders 50,000 (now 31,200)".
        public func text(in language: DisplayLanguage) -> String {
            let goal = measure.valueText(target)
            let now = current.map(measure.valueText) ?? "—"
            let name: String = switch measure {
            case .bestDay: language.text("Riders in a day", "每日旅客")
            case .operatingRatio: language.text("Operating ratio at most", "營業比降到")
            case .punctuality: language.text("Trains on time", "準點率")
            default: measure.title(in: language)
            }
            return language.text("\(name) \(goal) (now \(now))", "\(name) \(goal)（目前 \(now)）")
        }
    }

    /// Up to `count` next steps (decision 181): each measure's next rung,
    /// the ones that earn the most points first.
    public func milestones(count: Int = 3) -> [Milestone] {
        let steps: [Milestone] = parts.compactMap { part in
            guard part.points < part.maximum else { return nil }
            let measure = part.measure
            let current = part.value
            let now = current ?? (measure == .operatingRatio ? RankMeasure.breakEvenRatio : 0)
            let rung = Self.rungs(of: measure).first { measure == .operatingRatio ? $0 < now : $0 > now }
            guard let rung else { return nil }
            var reached = measure.points(for: rung)
            if measure.isQuality {
                reached = reached * min(figures.stations, Self.fullQualityStations) / Self.fullQualityStations
            }
            return Milestone(measure: measure, target: rung, current: current, gain: reached - part.points)
        }
        return Array(steps.enumerated().sorted { ($0.element.gain, -$0.offset) > ($1.element.gain, -$1.offset) }.prefix(count).map(\.element))
    }
}

extension UnservedCluster {
    /// The town to reach next (decision 181): the largest without a
    /// station, said from the nearest open station: "About 12,300 people
    /// 4.2 km northeast of Riverside"; without a station, its people only.
    public func suggestionText(in world: GameWorld, language: DisplayLanguage) -> String {
        let people = Money(people).displayText
        let nearest = world.stations.filter { $0.operationMode != .closed }.min { a, b in
            func squared(_ point: PlanPoint) -> Int64 {
                let dx = point.x - center.x, dy = point.y - center.y
                return dx * dx + dy * dy
            }
            return squared(a.location) < squared(b.location)
        }
        guard let nearest else {
            return language.text("A town of about \(people) people has no station", "約 \(people) 人的城鎮還沒有車站")
        }
        let (compass, tenths) = direction(from: nearest.location)
        let km = "\(tenths / 10).\(tenths % 10)"
        return language.text(
            "About \(people) people \(km) km \(compass.title(in: language)) of \(nearest.name), with no station",
            "\(nearest.name)\(compass.title(in: language))方 \(km) 公里，約 \(people) 人還沒有車站"
        )
    }
}
