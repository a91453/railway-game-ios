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

/// Money that came in: the status pill floats it up from the cash.
public struct IncomePulse: Hashable, Sendable {
    public let amount: Money
    /// Counts up with each pulse, so the same amount twice is two pulses.
    public let serial: Int

    public init(amount: Money, serial: Int) {
        self.amount = amount
        self.serial = serial
    }
}

extension CompanyAccounts {
    /// The ledger items that are money in (``LedgerItem``): fares, settled
    /// each hour, and the company's buildings' rent, settled each day.
    public static let incomeItems: Set<LedgerItem> = [.fareRevenue, .propertyRent]

    /// The money in among the ledger rows written after `last` (the
    /// newest row before; `nil` when there was none): the sum of their
    /// ``incomeItems`` lines. Rows are only ever added at the end; when
    /// `last` is no longer kept (``entries`` keeps the latest only), every
    /// row kept is newer than it.
    public static func income(writtenAfter last: LedgerEntry?, in entries: [LedgerEntry]) -> Money {
        guard entries.last != last else { return .zero }
        let start = last.flatMap { entries.lastIndex(of: $0) }.map { $0 + 1 } ?? entries.startIndex
        var total = Money.zero
        for entry in entries[start...] {
            for line in entry.breakdown where incomeItems.contains(line.item) && line.amount > .zero {
                total = total + line.amount
            }
        }
        return total
    }
}

extension GameSession {
    /// Marks something put up at `location` (decision 117): the map's
    /// pulse there and the finished sound.
    func notePutUp(at location: PlanPoint) {
        buildPulse = BuildPulse(location: location, serial: (buildPulse?.serial ?? 0) + 1)
        playSound?(.built)
    }

    /// Marks the money that came in since `last` was the newest ledger row
    /// (decision 117): the cash's pulse and the coins' sound. Nothing when
    /// none did.
    func noteIncome(since last: LedgerEntry?) {
        let income = CompanyAccounts.income(writtenAfter: last, in: world.accounts.entries)
        guard income > .zero else { return }
        incomePulse = IncomePulse(amount: income, serial: (incomePulse?.serial ?? 0) + 1)
        playSound?(.income)
    }
}
