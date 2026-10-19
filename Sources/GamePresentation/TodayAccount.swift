import GameCore

// The economy panel's first card (City Transport Manager study 4.12, step
// M0): today's fares, running costs and what is left, so a new player sees
// where the money comes from and goes in three lines before the reports.
// Read from the hours settled so far today (the company's day account, of
// which the lines' records that #834 reads for a new line are the
// breakdown): an hour belongs to the day it ran in and is settled at its
// end, so the card runs to the last full hour. The day's staff, energy and
// the rest are settled at midnight, so the card leaves them out and says
// so, rather than calling an unfinished day a profit.

/// Today so far, as the economy panel's first card shows it.
public struct TodayAccount: Equatable, Sendable {
    /// The hour of the day the figures run to: hours before it are
    /// settled. 0 while none of today's hours is.
    public let throughHour: Int64
    /// Fares charged in today's settled hours.
    public let fareRevenue: Money
    /// Running the trains and stations, and keeping the lines and trains,
    /// in today's settled hours.
    public let runningCost: Money

    public init(throughHour: Int64, fareRevenue: Money, runningCost: Money) {
        self.throughHour = throughHour
        self.fareRevenue = fareRevenue
        self.runningCost = runningCost
    }

    /// Fares less running costs.
    public var result: Money {
        fareRevenue - runningCost
    }

    /// Whether any of today's hours is settled.
    public var hasSettledHours: Bool {
        throughHour > 0
    }

    /// "Today, to 14:00", or "Today" before the first hour is settled.
    public func title(in language: DisplayLanguage) -> String {
        guard hasSettledHours else { return language.text("Today", "今天") }
        let hour = throughHour < 10 ? "0\(throughHour)" : "\(throughHour)"
        return language.text("Today, to \(hour):00", "今天（截至 \(hour):00）")
    }

    /// The card's three lines: fares, running costs (as money out) and
    /// the result with its sign. Empty before the first hour is settled.
    public func rows(in language: DisplayLanguage) -> [(title: String, value: String)] {
        guard hasSettledHours else { return [] }
        return [
            (language.text("Fares", "票收"), fareRevenue.moneyText),
            (language.text("Running costs", "營運成本"), LedgerEntry.signedMoneyText(Money(-runningCost.amount))),
            (language.text("Result", "結果"), LedgerEntry.signedMoneyText(result)),
        ]
    }

    /// Under the lines: when they are settled, and what comes at midnight.
    public func note(in language: DisplayLanguage) -> String {
        guard hasSettledHours else {
            return language.text(
                "Nothing settled yet today: fares and running costs are settled at the end of each hour.",
                "今天還沒有入帳：票收和營運成本每個整點入帳一次。"
            )
        }
        return language.text(
            "Settled at the end of each hour. Staff, energy and the rest of the day's costs are paid at midnight.",
            "每個整點入帳。人事、電費與其他每天的費用在午夜支付。"
        )
    }
}

extension GameWorld {
    /// Today so far (``TodayAccount``), or `nil` unless the company is
    /// managed: in free play no fares are charged and nothing is paid.
    public func todayAccount() -> TodayAccount? {
        guard accounts.mode == .management else { return nil }
        let today = FinanceHistory.floorDay(clock.now)
        let hour = (clock.now.seconds - today * GameTime.secondsPerDay) / GameTime.secondsPerHour
        let account = accounts.days.first { $0.day == today }
        return TodayAccount(
            throughHour: hour,
            fareRevenue: account?.fareRevenue ?? .zero,
            runningCost: (account?.operatingCost ?? .zero) + (account?.maintenanceCost ?? .zero)
        )
    }
}
