import GameCore

// Why a line loses money (ARCHITECTURE decision 194): the line card's fares
// and its four running costs over the report's days (decision 179's
// ``LineReport``), and, for a line that lost money over them, at most two
// reasons out of four, each with the figure that shows it. Read from the
// line accounts (``LineTally``) and the line as it is now; nothing is kept
// in the world.
//
// The reference's finance summary (`Ci/` `summarizeFinanceForTransport`)
// splits a span's books the same way: fares against operating,
// maintenance, energy and crew costs. It names no reasons; its high-speed
// guide only says empty seats cost as much as full ones
// (`guide.hsr.economy.costs`). The four reasons and their thresholds are
// this project's own.

/// One of a line's four running costs (decision 179).
public enum LineCost: String, CaseIterable, Hashable, Sendable {
    /// Each departure, each train-kilometre and each station, by the hour.
    case operating
    /// The route and the trains' kilometres and weight, by the hour.
    case maintenance
    /// The route's length and the trains' weight, by the day.
    case energy
    /// Each station and the trains' weight, by the day.
    case staff

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .operating: language.text("Operating", "營運")
        case .maintenance: language.text("Maintenance", "保養")
        case .energy: language.text("Energy", "能源")
        case .staff: language.text("Staff", "人事")
        }
    }
}

/// Why a line loses money (decision 194), with the figure that shows it.
public enum LineLossReason: Hashable, Sendable {
    /// More trains than the riders pay for: a day's fares come to less
    /// than ``LineLossDiagnosis/trainKeepMultiple`` times what its trains
    /// cost to keep on the line. `ridersPerTrain` a day each.
    case tooManyTrains(trains: Int64, ridersPerTrain: Int64)
    /// A train only every `minutes` each way, and the fullest leaving
    /// `peakPermille` thousandths full: riders are left waiting.
    case longHeadway(minutes: Int64, peakPermille: Int64)
    /// `permille` thousandths of the trains' kilometres run empty.
    case emptyRuns(permille: Int64)
    /// A trip takes on `permille` thousandths of a train's room.
    case lowLoad(permille: Int64)

    /// Which reason it is, without its figures.
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case tooManyTrains, longHeadway, emptyRuns, lowLoad

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .tooManyTrains: language.text("Too many trains", "車太多")
            case .longHeadway: language.text("Trains too far apart", "班距太長")
            case .emptyRuns: language.text("Too much empty running", "空車回送太多")
            case .lowLoad: language.text("Trains run nearly empty", "載客率低")
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .tooManyTrains: .tooManyTrains
        case .longHeadway: .longHeadway
        case .emptyRuns: .emptyRuns
        case .lowLoad: .lowLoad
        }
    }

    public func title(in language: DisplayLanguage) -> String {
        kind.title(in: language)
    }

    /// What it means, with its figure, in a sentence or two.
    public func detail(in language: DisplayLanguage) -> String {
        switch self {
        case let .tooManyTrains(trains, riders):
            return language.text(
                "\(trains) trains carry \(Money(riders).displayText) riders a day each: the fares don't come to twice what the trains cost to keep (staff, energy, maintenance). Take some trains off the line, or use shorter ones.",
                "\(trains) 列車平均每列每天只載 \(Money(riders).displayText) 人次，票收還不到車輛本身開銷（人事、能源、保養）的兩倍。試著撤下幾列車，或改用短一點的列車。"
            )
        case let .longHeadway(minutes, peak):
            return language.text(
                "About one train every \(minutes) min each way, and the fullest leaves \(LineLossDiagnosis.percentText(peak, in: language)) full: riders are left on the platform. Run more trains.",
                "每個方向約 \(minutes) 分鐘才一班，最擠的一班坐滿 \(LineLossDiagnosis.percentText(peak, in: language))：月台上的人等不到車。試著加開列車。"
            )
        case let .emptyRuns(permille):
            return language.text(
                "\(LineLossDiagnosis.percentText(permille, in: language)) of the trains' kilometres run empty, paid for like the rest. Stop trains at the line's ends.",
                "列車里程有 \(LineLossDiagnosis.percentText(permille, in: language)) 是不載客的空車回送，照樣要付里程與保養費。試著讓列車停在路線兩端。"
            )
        case let .lowLoad(permille):
            return language.text(
                "Each trip takes on \(LineLossDiagnosis.percentText(permille, in: language)) of the train's room: every departure pays its running cost, and empty seats don't pay it back. Run trains less often, or shorter.",
                "每趟上車的人只佔列車定員的 \(LineLossDiagnosis.percentText(permille, in: language))：每次發車都要付營運費，位子坐不滿就虧。試著拉長班距，或改用短一點的列車。"
            )
        }
    }
}

/// What the diagnosis reads: a line's report days added up, and the line
/// and its trains as they are now (decision 194).
public struct LineLossMeasures: Hashable, Sendable {
    /// Completed days in the report.
    public var days: Int64
    public var fareRevenue: Money
    public var boardings: Int64
    public var departures: Int64
    /// World units, empty runs included.
    public var trainDistance: Int64
    /// Of ``trainDistance``, the empty runs.
    public var deadheadDistance: Int64
    /// Each day's fullest departure, in thousandths, added up.
    public var peakLoadSum: Int64
    /// The trains assigned to the line now.
    public var trains: Int64
    /// Their rated room, on average.
    public var seatsPerTrain: Int64
    /// What they cost a day to keep on the line, all together
    /// (``GameWorld/dailyRunningCost(of:cars:)``).
    public var trainKeepPerDay: Money
    /// Departures in one trip end to end: a stop fewer than the line's,
    /// or a ring's stops for a lap.
    public var legsPerTrip: Int64
    /// The minutes a day the line runs.
    public var serviceMinutes: Int64

    public init(
        days: Int64, fareRevenue: Money, boardings: Int64, departures: Int64, trainDistance: Int64,
        deadheadDistance: Int64, peakLoadSum: Int64, trains: Int64, seatsPerTrain: Int64,
        trainKeepPerDay: Money, legsPerTrip: Int64, serviceMinutes: Int64
    ) {
        self.days = days
        self.fareRevenue = fareRevenue
        self.boardings = boardings
        self.departures = departures
        self.trainDistance = trainDistance
        self.deadheadDistance = deadheadDistance
        self.peakLoadSum = peakLoadSum
        self.trains = trains
        self.seatsPerTrain = seatsPerTrain
        self.trainKeepPerDay = trainKeepPerDay
        self.legsPerTrip = legsPerTrip
        self.serviceMinutes = serviceMinutes
    }

    /// Riders a train a day, or `nil` without trains.
    public var ridersPerTrainPerDay: Int64? {
        guard trains > 0, days > 0 else { return nil }
        return boardings / (trains * days)
    }

    /// Riders boarding a trip, end to end, in thousandths of a train's
    /// rated room, or `nil` with no departure or no room. A trip a
    /// passenger rides only part of can take on more than the room.
    public var tripFillPermille: Int64? {
        guard departures > 0, seatsPerTrain > 0, legsPerTrip > 0 else { return nil }
        return boardings * legsPerTrip * 1_000 / (departures * seatsPerTrain)
    }

    /// The minutes between trains each way, from the trips the line ran
    /// over its running hours, rounded; `nil` with no departure.
    public var headwayMinutes: Int64? {
        guard departures > 0, days > 0, legsPerTrip > 0 else { return nil }
        let numerator = serviceMinutes * 2 * days * legsPerTrip
        return (numerator + departures / 2) / departures
    }

    /// The empty runs in thousandths of the trains' kilometres, or `nil`
    /// with none run.
    public var emptyRunPermille: Int64? {
        guard trainDistance > 0 else { return nil }
        return deadheadDistance * 1_000 / trainDistance
    }

    /// The fullest departure of a day, on average, in thousandths.
    public var meanPeakPermille: Int64 {
        days > 0 ? peakLoadSum / days : 0
    }
}

/// A line's fares and running costs over its report's days, and why it
/// lost money over them (decision 194).
public struct LineLossDiagnosis: Hashable, Sendable {
    public let line: LineID
    /// The completed days added up (``LineReport/days``).
    public let days: Int
    public let fareRevenue: Money
    public let operatingCost: Money
    public let maintenanceCost: Money
    public let energyCost: Money
    public let staffCost: Money
    public let measures: LineLossMeasures
    /// At most ``shownReasons``, the worst first; none unless the line
    /// lost money.
    public let reasons: [LineLossReason]

    // MARK: Thresholds (decision 194)

    /// Too many trains: a day's fares under this many times what the
    /// line's trains cost to keep (``GameWorld/dailyRunningCost(of:cars:)``:
    /// $1,032 a standard car). A train on the line also pays for every
    /// departure it makes; one that does not bring in twice its keep cannot.
    public static let trainKeepMultiple: Int64 = 2
    /// Trains too far apart: this many minutes or more each way...
    public static let longHeadwayMinutes: Int64 = 20
    /// ...with the fullest departure of a day at least this full, in
    /// thousandths, on average: riders are being left on the platform.
    public static let crowdedPeakPermille: Int64 = 900
    /// Too much empty running: this share of the kilometres, in
    /// thousandths.
    public static let emptyRunPermille: Int64 = 200
    /// Trains run nearly empty: a trip taking on less than this share of a
    /// train's room, in thousandths.
    public static let lowLoadPermille: Int64 = 100
    /// Reasons a card shows.
    public static let shownReasons = 2

    public init(
        line: LineID, days: Int, fareRevenue: Money, operatingCost: Money, maintenanceCost: Money,
        energyCost: Money, staffCost: Money, measures: LineLossMeasures
    ) {
        self.line = line
        self.days = days
        self.fareRevenue = fareRevenue
        self.operatingCost = operatingCost
        self.maintenanceCost = maintenanceCost
        self.energyCost = energyCost
        self.staffCost = staffCost
        self.measures = measures
        let cost = operatingCost + maintenanceCost + energyCost + staffCost
        reasons = fareRevenue < cost ? Self.reasons(for: measures) : []
    }

    public func cost(_ item: LineCost) -> Money {
        switch item {
        case .operating: operatingCost
        case .maintenance: maintenanceCost
        case .energy: energyCost
        case .staff: staffCost
        }
    }

    public var totalCost: Money {
        LineCost.allCases.reduce(.zero) { $0 + cost($1) }
    }

    public var profit: Money { fareRevenue - totalCost }

    public var isLosing: Bool { profit < .zero }

    /// The reasons `measures` shows, the worst first (by how far past its
    /// threshold each is; a tie in ``LineLossReason/Kind`` order), at most
    /// ``shownReasons``. Whether the line loses money is not asked here.
    public static func reasons(for measures: LineLossMeasures) -> [LineLossReason] {
        var found: [(reason: LineLossReason, severity: Int64)] = []
        if measures.trains >= 2, measures.days > 0, let riders = measures.ridersPerTrainPerDay {
            let bar = trainKeepMultiple * measures.trainKeepPerDay.amount * measures.days
            if bar > 0, measures.fareRevenue.amount < bar {
                found.append((.tooManyTrains(trains: measures.trains, ridersPerTrain: riders),
                              bar * 1_000 / max(1, measures.fareRevenue.amount)))
            }
        }
        if let minutes = measures.headwayMinutes, minutes >= longHeadwayMinutes,
           measures.meanPeakPermille >= crowdedPeakPermille {
            found.append((.longHeadway(minutes: minutes, peakPermille: measures.meanPeakPermille),
                          minutes * 1_000 / longHeadwayMinutes))
        }
        if let empty = measures.emptyRunPermille, empty >= emptyRunPermille {
            found.append((.emptyRuns(permille: empty), empty * 1_000 / emptyRunPermille))
        }
        if let fill = measures.tripFillPermille, fill < lowLoadPermille {
            found.append((.lowLoad(permille: fill), lowLoadPermille * 1_000 / max(1, fill)))
        }
        let order = LineLossReason.Kind.allCases
        return found
            .sorted { left, right in
                left.severity != right.severity
                    ? left.severity > right.severity
                    : order.firstIndex(of: left.reason.kind)! < order.firstIndex(of: right.reason.kind)!
            }
            .prefix(shownReasons)
            .map(\.reason)
    }

    // MARK: Text

    /// "Fares and costs, last 3 days": the span the figures add up.
    public func spanText(in language: DisplayLanguage) -> String {
        language.text("Fares and costs, last \(days) \(days == 1 ? "day" : "days")", "票收與成本（最近 \(days) 天）")
    }

    /// What a losing line with none of the four reasons says instead, or
    /// `nil` for a line that made money or has a reason.
    public func noReasonText(in language: DisplayLanguage) -> String? {
        guard isLosing, reasons.isEmpty else { return nil }
        if measures.departures == 0 {
            return language.text(
                "No train ran: the line pays for its stations and route all the same.",
                "這段期間沒有列車開出：車站與路線的成本照付。"
            )
        }
        return language.text(
            "None of the usual four (too many trains, trains too far apart, empty running, nearly empty trains) stands out: see which cost above is the largest.",
            "四個常見原因（車太多、班距太長、空車回送、載客率低）都不明顯：看上面哪一項成本最大。"
        )
    }

    /// "12%", "under 1%" or "over 100%" of `permille` thousandths.
    public static func percentText(_ permille: Int64, in language: DisplayLanguage) -> String {
        if permille < 10 { return language.text("under 1%", "不到 1%") }
        return "\((permille + 5) / 10)%"
    }

    /// One bar of the card: the fares or a cost.
    public struct Bar: Hashable, Identifiable, Sendable {
        /// "fares", or the cost's ``LineCost`` raw value.
        public let id: String
        public let title: String
        public let amount: Money
        /// Its length, in thousandths of the longest bar.
        public let permille: Int64
        public let isFares: Bool

        /// "Operating $ 54,240", what VoiceOver reads.
        public var text: String { "\(title) \(amount.moneyText)" }
    }

    /// The fares, then the four costs, each as long as its amount next to
    /// the largest of the five.
    public func bars(in language: DisplayLanguage) -> [Bar] {
        let items: [(String, String, Money, Bool)] = [("fares", language.text("Fares", "票收"), fareRevenue, true)]
            + LineCost.allCases.map { ($0.rawValue, $0.title(in: language), cost($0), false) }
        let longest = max(1, items.map { $0.2.amount }.max() ?? 1)
        return items.map { id, title, amount, isFares in
            Bar(id: id, title: title, amount: amount, permille: max(0, amount.amount) * 1_000 / longest, isFares: isFares)
        }
    }
}

extension GameWorld {
    /// The first day not yet settled: the clock's, or at midnight exactly
    /// the day before. The day that ended is settled (its last hour's
    /// operating and maintenance, and its energy and staff) at the start of
    /// the minute after midnight, not by the time the clock reads 00:00.
    var lineLossSettledDay: Int64 {
        FinanceHistory.floorDay(GameTime(seconds: clock.now.seconds - 1))
    }

    /// Line `id`'s fares, costs and reasons over its report's days
    /// (decision 194), or `nil` without line accounts, for a freight line
    /// (its fares are not the line's), or before a completed day. A day the
    /// report already counts at midnight exactly is left out until it is
    /// settled (``lineLossSettledDay``).
    public func lineLossDiagnosis(_ id: LineID) -> LineLossDiagnosis? {
        let settled = lineLossSettledDay
        guard let report = lineReport(id), let line = line(id: id), !line.isFreight else { return nil }
        let days = report.days.filter { $0.day < settled }
        guard !days.isEmpty else { return nil }
        let counted = Set(days.map(\.day))
        let tallies = lineDays(id).filter { counted.contains($0.day) }.map(\.tally)
        func sum(_ value: (LineTally) -> Int64) -> Int64 { tallies.reduce(0) { $0 + value($1) } }
        func sum(_ value: (LineTally) -> Money) -> Money { tallies.reduce(.zero) { $0 + value($1) } }
        let trains = line.assignedTrains.compactMap { train(id: $0) }
        let seats = trains.isEmpty ? 0 : trains.reduce(Int64(0)) { $0 + $1.ratedCapacity } / Int64(trains.count)
        let keep = trains.reduce(Money.zero) { $0 + dailyRunningCost(of: $1.type, cars: $1.cars) }
        let minutes: Int64 = switch line.window {
        case .allDay: 1_440
        case let .hours(open, close): Int64(close - open)
        }
        let fares = sum(\.fareRevenue)
        let measures = LineLossMeasures(
            days: Int64(days.count), fareRevenue: fares, boardings: sum(\.boardings),
            departures: sum(\.departures), trainDistance: sum(\.trainDistance), deadheadDistance: sum(\.deadheadDistance),
            peakLoadSum: sum(\.peakLoad), trains: Int64(trains.count), seatsPerTrain: seats, trainKeepPerDay: keep,
            legsPerTrip: Int64(line.isRing ? line.stops.count : max(1, line.stops.count - 1)), serviceMinutes: minutes
        )
        return LineLossDiagnosis(
            line: id, days: days.count, fareRevenue: fares, operatingCost: sum(\.operatingCost),
            maintenanceCost: sum(\.maintenanceCost), energyCost: sum(\.energyCost), staffCost: sum(\.staffCost),
            measures: measures
        )
    }
}

/// Keeps the selected line's diagnosis (decision 194) for the line panel,
/// which is drawn again at every tick while the game runs. Worked out once
/// for a ``GameSession/commandRevision``, a line and a settled game day
/// (``GameWorld/lineLossSettledDay``): it counts only settled days, so
/// nothing else changes it. As
/// ``LinePanelMemo``, the view keeps one for as long as it is shown; it is
/// not game state.
@MainActor
public final class LineLossMemo {
    private struct Key: Equatable {
        let session: ObjectIdentifier
        let revision: Int
        let line: LineID
        let day: Int64
    }

    private var key: Key?
    private var kept: LineLossDiagnosis?
    private var keptFixes: [LineLossReason.Kind: LineLossFix] = [:]
    /// How many times it has worked the diagnosis out (for the tests).
    private(set) var workedOut = 0

    public init() {}

    /// The change that answers each of the diagnosis's reasons (decision
    /// 194, later: ``GameWorld/lineLossFix(_:on:)``), worked out with it.
    public func fixes(_ id: LineID, of session: GameSession) -> [LineLossReason.Kind: LineLossFix] {
        _ = diagnosis(id, of: session)
        return keptFixes
    }

    /// ``GameWorld/lineLossDiagnosis(_:)`` of `session`'s world.
    public func diagnosis(_ id: LineID, of session: GameSession) -> LineLossDiagnosis? {
        let world = session.world
        let now = Key(session: ObjectIdentifier(session), revision: session.commandRevision, line: id,
                      day: world.lineLossSettledDay)
        guard now != key else { return kept }
        key = now
        kept = world.lineLossDiagnosis(id)
        var fixes: [LineLossReason.Kind: LineLossFix] = [:]
        for reason in kept?.reasons ?? [] {
            fixes[reason.kind] = world.lineLossFix(reason.kind, on: id)
        }
        keptFixes = fixes
        workedOut += 1
        return kept
    }
}
