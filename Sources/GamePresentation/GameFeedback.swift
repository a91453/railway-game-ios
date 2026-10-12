import GameCore

// A moment of motion and a sound for what went well (ARCHITECTURE decision
// 117): something put up, and money coming in. SimCity BuildIt and
// TheoTown answer a finished building with a pop and a sound, and float
// what was earned up from where it came; the reference's `Ci/` plays a
// sound on its buttons (`data-metro-sfx`). Presentation only: what
// happened is read from the world after it happened, and nothing here is
// saved.

/// Something the player put up, where it stands: the map marks it.
public struct BuildPulse: Hashable, Sendable {
    public let location: PlanPoint
    /// Counts up with each pulse, so the same place twice is two pulses.
    public let serial: Int

    public init(location: PlanPoint, serial: Int) {
        self.location = location
        self.serial = serial
    }
}

/// Money that came in, or (decision 177, negative) the loss of a day that
/// closed in the red: the status pill floats it up from the cash.
public struct IncomePulse: Hashable, Sendable {
    public let amount: Money
    /// Counts up with each pulse, so the same amount twice is two pulses.
    public let serial: Int

    public init(amount: Money, serial: Int) {
        self.amount = amount
        self.serial = serial
    }

    /// Whether it is a loss (decision 177): shown in red.
    public var isLoss: Bool { amount < .zero }

    /// What the pill floats: "+$ 1,234" for money in, "−$40k" (rounded to
    /// the thousand from $10,000, else to the dollar) for a loss.
    public var text: String {
        guard isLoss else { return "+\(amount.moneyText)" }
        let dollars = Int64(amount.amount.magnitude / 100)
        return dollars >= 10_000 ? "\u{2212}$\((dollars + 500) / 1_000)k" : "\u{2212}$\(Money(dollars).displayText)"
    }
}

/// A request to move the map's camera to a place (decision 177).
public struct CameraRequest: Hashable, Sendable {
    public let location: PlanPoint
    /// Counts up with each request, so the same place twice is two requests.
    public let serial: Int

    public init(location: PlanPoint, serial: Int) {
        self.location = location
        self.serial = serial
    }
}

extension CompanyAccounts {
    /// The ledger items that are money in (``LedgerItem``): fares, settled
    /// each hour, and the company's buildings' rent, settled each day.
    public static let incomeItems: Set<LedgerItem> = [.fareRevenue, .propertyRent, .freightRevenue, .subsidiarySales, .tourismRevenue]

    /// The money in among the ledger rows written after `last` (the
    /// newest row before; `nil` when there was none): the sum of their
    /// lines for `items` (``incomeItems`` unless given) that are money in.
    /// Rows are only ever added at the end; when `last` is no longer kept
    /// (``entries`` keeps the latest only), every row kept is newer than it.
    public static func income(
        writtenAfter last: LedgerEntry?, in entries: [LedgerEntry], of items: Set<LedgerItem> = incomeItems
    ) -> Money {
        guard entries.last != last else { return .zero }
        let start = last.flatMap { entries.lastIndex(of: $0) }.map { $0 + 1 } ?? entries.startIndex
        var total = Money.zero
        for entry in entries[start...] {
            for line in entry.breakdown where items.contains(line.item) && line.amount > .zero {
                total = total + line.amount
            }
        }
        return total
    }
}

extension GameSession {
    /// Asks the map to look at `location` (decision 177).
    public func lookAt(_ location: PlanPoint) {
        cameraRequest = CameraRequest(location: location, serial: (cameraRequest?.serial ?? 0) + 1)
    }

    /// Marks something put up at `location` (decision 117): the map's
    /// pulse there and the finished sound.
    func notePutUp(at location: PlanPoint) {
        buildPulse = BuildPulse(location: location, serial: (buildPulse?.serial ?? 0) + 1)
        playSound?(.built)
    }

    /// Marks the money that came in since `last` was the newest ledger row
    /// (decision 117): the cash's pulse and the coins' sound. Nothing when
    /// none did. Decision 177: the coins ring only while the company makes
    /// money, not while yesterday closed in the red: fares come in all the
    /// time, and coins over a losing line told the player the opposite of
    /// the books.
    func noteIncome(since last: LedgerEntry?) {
        let income = CompanyAccounts.income(writtenAfter: last, in: world.accounts.entries)
        guard income > .zero else { return }
        incomePulse = IncomePulse(amount: income, serial: (incomePulse?.serial ?? 0) + 1)
        let yesterday = world.clock.now.seconds / GameTime.secondsPerDay - 1
        let losing = world.accounts.days.first { $0.day == yesterday }.map { StationMasterAdvice.operatingResult(on: $0) < .zero } ?? false
        if !losing { playSound?(.income) }
    }

    /// Decision 177: when the game passed midnight since `dayBefore` (the
    /// day index before the step) and the day that closed lost money, the
    /// cash floats its loss, negative. Silent: a loss is not a reward.
    func noteDayLoss(since dayBefore: Int64) {
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        guard today > dayBefore, world.accounts.mode == .management,
              let day = world.accounts.days.first(where: { $0.day == today - 1 }) else { return }
        let result = StationMasterAdvice.operatingResult(on: day)
        guard result < .zero else { return }
        incomePulse = IncomePulse(amount: result, serial: (incomePulse?.serial ?? 0) + 1)
    }
}
