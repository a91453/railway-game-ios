import GameCore

// The monthly report (ARCHITECTURE decision 175): every 30 game days a
// small card, after the reference's economy report
// (`flowDashboardBuildEconomyReport`, the period against the one before it):
// riders, fares, costs, net profit and cash, each against the month before,
// the stations whose planned trips grew and fell most, the towers that
// appeared, the stations short of building materials, and a headline.
// Worked out from the world and the baseline of the last report; GameCore
// is not touched.

/// What the player chose to happen when a month closes (settings).
public enum MonthlyReportMode: String, CaseIterable, Sendable {
    /// Open the card and pause (the default).
    case openAndPause
    /// Only write it in the news log.
    case logOnly
    case off
}

/// A figure of the report against the month before.
public struct MonthlyFigure: Hashable, Sendable {
    public let value: Int64
    /// The month before, `nil` when the game had no such month.
    public let previous: Int64?

    /// The change in whole percent (rounded half away from zero), or `nil`
    /// when the month before was not above zero.
    public var percent: Int64? {
        guard let previous, previous > 0 else { return nil }
        let change = (value - previous) * 100
        return (change + (change >= 0 ? previous / 2 : -previous / 2)) / previous
    }

    /// "▲ 18%", "▼ 5%", "–" for no change, "" without a comparison.
    public var arrowText: String {
        guard let percent else { return "" }
        if percent == 0 { return "–" }
        return percent > 0 ? "▲ \(percent)%" : "▼ \(-percent)%"
    }
}

/// A station whose planned daily trips changed since the last report.
public struct StationTripChange: Hashable, Sendable {
    public let station: StationID
    public let name: String
    public let before: Int64
    public let after: Int64
    public var delta: Int64 { after - before }
}

/// The one line the report opens with: the biggest change.
public enum MonthlyHeadline: Hashable, Sendable {
    public enum Item: String, Sendable {
        case riders, fares, net
    }

    /// The month's value is the highest of all months so far.
    case record(Item, percent: Int64)
    case turnedProfit
    case turnedLoss
    case change(Item, percent: Int64)
    case quiet

    public func text(in language: DisplayLanguage) -> String {
        func name(_ item: Item) -> String {
            switch item {
            case .riders: language.text("Ridership", "客流量")
            case .fares: language.text("Fare revenue", "票收")
            case .net: language.text("Net profit", "淨利")
            }
        }
        switch self {
        case .record(let item, let percent):
            return language.text("\(name(item)) hit a record: +\(percent)%", "\(name(item))創新高 +\(percent)%")
        case .turnedProfit:
            return language.text("Back in the black: a profit this month", "轉虧為盈：本月有賺錢")
        case .turnedLoss:
            return language.text("Into the red: a loss this month", "轉盈為虧：本月虧損")
        case .change(let item, let percent):
            return percent >= 0
                ? language.text("\(name(item)) up \(percent)% on last month", "\(name(item))比上月增加 \(percent)%")
                : language.text("\(name(item)) down \(-percent)% on last month", "\(name(item))比上月減少 \(-percent)%")
        case .quiet:
            return language.text("A quiet month: little changed", "平穩的一個月，變化不大")
        }
    }
}

/// The report of one closed month.
public struct MonthlyReport: Hashable, Sendable {
    /// The month (game day ÷ 30, from 0).
    public let month: Int64
    public let riders: MonthlyFigure
    public let fares: MonthlyFigure
    public let costs: MonthlyFigure
    public let net: MonthlyFigure
    /// The balance at the end of the month, and what it was a month
    /// before (this balance less the month's net cash flow).
    public let cash: MonthlyFigure
    /// The three stations whose planned trips grew most, and the three
    /// that fell most.
    public let grown: [StationTripChange]
    public let fallen: [StationTripChange]
    /// New buildings of density D3 or D4 since the last report.
    public let newTowers: Int
    /// The stations that ran short of building materials at the last
    /// midnight.
    public let shortOfMaterials: [(id: StationID, name: String)]
    public let headline: MonthlyHeadline

    public static func == (lhs: MonthlyReport, rhs: MonthlyReport) -> Bool {
        lhs.month == rhs.month && lhs.riders == rhs.riders && lhs.fares == rhs.fares && lhs.costs == rhs.costs
            && lhs.net == rhs.net && lhs.cash == rhs.cash && lhs.grown == rhs.grown && lhs.fallen == rhs.fallen
            && lhs.newTowers == rhs.newTowers && lhs.shortOfMaterials.map(\.id) == rhs.shortOfMaterials.map(\.id)
            && lhs.headline == rhs.headline
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(month)
        hasher.combine(riders)
        hasher.combine(net)
    }

    /// The date of the month's first day.
    public var firstDate: GameDate { GameDate(day: month * FinancePeriod.month.days) }

    /// The report for month `month` of `world`, against `baseline` (the
    /// stations' trips and towers at the last report), or `nil` for a
    /// company that is not managed (free play keeps no accounts).
    public static func make(month: Int64, in world: GameWorld, baseline: MonthlyBaseline?) -> MonthlyReport? {
        guard world.accounts.mode == .management else { return nil }
        let length = FinancePeriod.month.days
        let lastDay = (month + 1) * length - 1
        let (current, previous) = world.accounts.report(.month, day: lastDay)

        // Riders and fares by month, from the days kept.
        var tripsByMonth: [Int64: Int64] = [:]
        var faresByMonth: [Int64: Int64] = [:]
        var firstDay = Int64.max
        for day in world.accounts.days {
            let index = day.day >= 0 ? day.day / length : -((-day.day + length - 1) / length)
            tripsByMonth[index, default: 0] += day.fareTrips
            faresByMonth[index, default: 0] += day.fareRevenue.amount
            firstDay = min(firstDay, day.day)
        }
        // A month before the days kept (or before the game) is not one to
        // compare with.
        let hasPrevious = month >= 1 && tripsByMonth[month - 1] != nil
        func figure(_ value: Int64, _ before: Int64) -> MonthlyFigure {
            MonthlyFigure(value: value, previous: hasPrevious ? before : nil)
        }
        let riders = figure(tripsByMonth[month] ?? 0, tripsByMonth[month - 1] ?? 0)
        let fares = figure(current.fareRevenue.amount, previous.fareRevenue.amount)
        let costs = figure(current.totalCost.amount, previous.totalCost.amount)
        let net = figure(current.netProfit.amount, previous.netProfit.amount)
        let balance = world.economy.balance.amount
        let cash = figure(balance, balance - current.netCashFlow.amount)

        // Stations: the planned trips against the baseline's.
        var changes: [StationTripChange] = []
        if let baseline {
            for station in world.stations {
                guard let before = baseline.stationTrips[station.id.rawValue],
                      let after = world.stationDemand(of: station.id)?.dailyTrips, before != after else { continue }
                changes.append(StationTripChange(station: station.id, name: station.name, before: before, after: after))
            }
        }
        // Largest change first; equal changes by station, so the same world
        // always gives the same report.
        let ordered = changes.sorted { $0.delta != $1.delta ? abs($0.delta) > abs($1.delta) : $0.station < $1.station }
        let grown = Array(ordered.filter { $0.delta > 0 }.prefix(3))
        let fallen = Array(ordered.filter { $0.delta < 0 }.prefix(3))

        let towers = world.buildings.all.count { $0.density == .d3 || $0.density == .d4 }
        let newTowers = max(0, towers - (baseline?.tallBuildings ?? towers))
        let short = (world.freight?.lastShort ?? []).compactMap { id in
            world.station(id: id).map { (id: id, name: $0.name) }
        }

        // The headline: a change of sign of the net profit, a record, else
        // the biggest change.
        let headline: MonthlyHeadline
        let earlier = { (values: [Int64: Int64]) in values.filter { $0.key < month }.map(\.value).max() ?? 0 }
        if let before = net.previous, before < 0, net.value > 0 {
            headline = .turnedProfit
        } else if let before = net.previous, before > 0, net.value < 0 {
            headline = .turnedLoss
        } else if hasPrevious, let percent = fares.percent, percent > 0, fares.value > earlier(faresByMonth) {
            headline = .record(.fares, percent: percent)
        } else if hasPrevious, let percent = riders.percent, percent > 0, riders.value > earlier(tripsByMonth) {
            headline = .record(.riders, percent: percent)
        } else {
            let candidates: [(MonthlyHeadline.Item, Int64)] = [(.fares, fares.percent), (.riders, riders.percent), (.net, net.percent)]
                .compactMap { item, percent in percent.map { (item, $0) } }
            if let biggest = candidates.max(by: { abs($0.1) < abs($1.1) }), abs(biggest.1) >= 5 {
                headline = .change(biggest.0, percent: biggest.1)
            } else {
                headline = .quiet
            }
        }
        return MonthlyReport(
            month: month, riders: riders, fares: fares, costs: costs, net: net, cash: cash, grown: grown, fallen: fallen,
            newTowers: newTowers, shortOfMaterials: short, headline: headline
        )
    }

    /// The news item's text: the headline with the month.
    public func newsText(in language: DisplayLanguage) -> String {
        language.text(
            "Month \(month + 1) report: \(headline.text(in: language))",
            "第 \(month + 1) 個月月報：\(headline.text(in: language))"
        )
    }
}

extension MonthlyFigure {
    /// "1,234", for riders.
    public func countText() -> String { Money(value).displayText }
}

extension MonthlyReportMode {
    /// The name in the settings.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .openAndPause: language.text("Open and pause", "自動開啟並暫停")
        case .logOnly: language.text("News log only", "只記在新聞紀錄")
        case .off: language.text("Off", "關閉")
        }
    }
}
