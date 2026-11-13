/// A term loan (decision 715): money borrowed for a number of years at
/// interest fixed the day it is signed, paid back with that interest in one
/// sum when it falls due. It stands beside the company's loan of decision
/// 67, which is borrowed and repaid at will and pays by the day.
public struct TermLoan: Hashable, Sendable, Codable {
    /// Handed out from 1 in the order signed; never used again.
    public let id: Int64
    /// What was borrowed: whole ``CompanyAccounts/loanStep``s.
    public let principal: Money
    /// The interest for the whole term, in whole dollars, fixed at signing.
    public let interest: Money
    /// The yearly rate it was signed at, in hundredths of a percent.
    public let rate: Int64
    /// The term: 1 to ``CompanyAccounts/longestTermLoan`` years of 360 days.
    public let years: Int64
    /// The day it was signed, as ``DayAccount/day``.
    public let borrowedDay: Int64

    /// The term in days.
    public var termDays: Int64 {
        years * FinancePeriod.year.days
    }

    /// The day it falls due: paid at the midnight that begins it.
    public var dueDay: Int64 {
        borrowedDay + termDays
    }

    /// The principal and the whole term's interest.
    public var total: Money {
        principal + interest
    }
}

/// What a term loan of an amount and a term would be, before it is signed.
public struct TermLoanQuote: Hashable, Sendable {
    public let principal: Money
    public let years: Int64
    /// The yearly rate, in hundredths of a percent.
    public let rate: Int64
    public let interest: Money
    /// The day it would fall due, signed today.
    public let dueDay: Int64

    public var total: Money {
        principal + interest
    }
}

/// What paying a term loan back today costs: its principal, the interest of
/// the days gone by, and a part of the interest of the days left.
public struct TermLoanRepaymentQuote: Hashable, Sendable {
    public let loan: TermLoan
    /// The days since it was signed, no more than its term.
    public let elapsedDays: Int64
    /// The interest of the days gone by, in whole dollars.
    public let accruedInterest: Money
    /// ``CompanyAccounts/earlyRepaymentPercent`` of the interest of the
    /// days left, in whole dollars.
    public let penalty: Money
    /// What is charged for interest: the two together, rounded down to
    /// NT$100.
    public let interest: Money

    public var total: Money {
        loan.principal + interest
    }
}

/// How much more the bank lends on term loans now.
public struct TermLoanCredit: Hashable, Sendable {
    /// Half of what the company is worth once every term loan's principal
    /// and interest are taken off, in whole dollars; it can be below zero.
    public let limit: Money
    /// The principal and interest of every term loan not yet paid.
    public let outstanding: Money
    /// How many more term loans there can be at once.
    public let freeSlots: Int
    /// The most a new term loan can be: whole ``CompanyAccounts/loanStep``s
    /// that keep ``outstanding`` and it below ``limit``; nothing with no
    /// slot free.
    public let maximumPrincipal: Money
}

extension CompanyAccounts {
    /// The most term loans at once.
    public static let termLoanSlots = 50
    /// The longest term, in years.
    public static let longestTermLoan: Int64 = 10
    /// The rate a one-year term loan is signed at, in hundredths of a
    /// percent: 5 %, the rate of the loan of decision 67.
    public static let termLoanBaseRate: Int64 = 500
    /// What the base rate is multiplied by for a term of 1 to 10 years, in
    /// per cent: a longer term costs more a year.
    public static let termLoanFactors: [Int64] = [100, 102, 104, 106, 108, 110, 114, 118, 122, 126]
    /// The share of the interest of the days left that paying early still
    /// costs, in per cent.
    public static let earlyRepaymentPercent: Int64 = 20

    /// The yearly rate of a term of `years`, in hundredths of a percent, or
    /// `nil` for a term the bank does not offer.
    public static func termLoanRate(years: Int64) -> Int64? {
        guard (1...longestTermLoan).contains(years) else { return nil }
        return termLoanFactors[Int(years - 1)] * termLoanBaseRate / 100
    }

    /// The whole term's interest on `principal` at `rate` for `years`: each
    /// year's is the rate's share of the principal's whole dollars, rounded
    /// down to a dollar.
    public static func termLoanInterest(principal: Money, rate: Int64, years: Int64) -> Money {
        Money(years * (rate * (principal.amount / 100) / 100 / 100) * 100)
    }

    /// The principal and interest of every term loan.
    public var termLoansOutstanding: Money {
        termLoans.reduce(.zero) { $0 + $1.total }
    }

    /// The principal of every term loan: what the balance sheet owes on them.
    public var termLoansPrincipal: Money {
        termLoans.reduce(.zero) { $0 + $1.principal }
    }
}

extension GameWorld {
    // MARK: - Queries

    /// How much more the bank lends on term loans now (decision 715).
    public func termLoanCredit() -> TermLoanCredit {
        let outstanding = accounts.termLoansOutstanding
        // The sheet's equity has the principals off already; the interest
        // still to pay comes off too.
        let worth = balanceSheet().equity.amount - (outstanding - accounts.termLoansPrincipal).amount
        let limit = Money(worth / 100 * 50 / 100 * 100)
        let slots = max(0, CompanyAccounts.termLoanSlots - accounts.termLoans.count)
        let step = CompanyAccounts.loanStep.amount
        let room = limit.amount - outstanding.amount - 1
        let most = slots > 0 && room >= step ? min(room, Self.maximumAccrued) / step * step : 0
        return TermLoanCredit(limit: limit, outstanding: outstanding, freeSlots: slots, maximumPrincipal: Money(most))
    }

    /// What a term loan of `principal` for `years` would be if signed now.
    ///
    /// - Throws, checked in this order: ``GameError/loanNeedsManagement``,
    ///   or ``GameError/invalidTermLoan`` for an amount that is not whole
    ///   ``CompanyAccounts/loanStep``s above 0, a term the bank does not
    ///   offer, no slot free, or more than
    ///   ``TermLoanCredit/maximumPrincipal``.
    public func termLoanQuote(principal: Money, years: Int64) throws(GameError) -> TermLoanQuote {
        guard accounts.mode == .management else { throw .loanNeedsManagement }
        guard principal > .zero, principal.amount % CompanyAccounts.loanStep.amount == 0,
              let rate = CompanyAccounts.termLoanRate(years: years),
              principal <= termLoanCredit().maximumPrincipal,
              economy.balance.amount <= Self.maximumBalance - principal.amount
        else { throw .invalidTermLoan }
        return TermLoanQuote(
            principal: principal, years: years, rate: rate,
            interest: CompanyAccounts.termLoanInterest(principal: principal, rate: rate, years: years),
            dueDay: dayIndex(of: clock.now) + years * FinancePeriod.year.days
        )
    }

    /// What paying term loan `id` back now costs.
    ///
    /// - Throws: ``GameError/invalidTermLoan`` if there is no such loan.
    public func termLoanRepaymentQuote(_ id: Int64) throws(GameError) -> TermLoanRepaymentQuote {
        guard let loan = accounts.termLoans.first(where: { $0.id == id }) else { throw .invalidTermLoan }
        return Self.repaymentQuote(of: loan, on: dayIndex(of: clock.now))
    }

    static func repaymentQuote(of loan: TermLoan, on day: Int64) -> TermLoanRepaymentQuote {
        let elapsed = min(max(0, day - loan.borrowedDay), loan.termDays)
        let whole = loan.interest.amount / 100
        let accrued = whole * elapsed / loan.termDays
        let penalty = (whole - accrued) * CompanyAccounts.earlyRepaymentPercent / 100
        return TermLoanRepaymentQuote(
            loan: loan, elapsedDays: elapsed, accruedInterest: Money(accrued * 100), penalty: Money(penalty * 100),
            interest: Money((accrued + penalty) / 100 * 100 * 100)
        )
    }

    // MARK: - Commands

    /// Signs a term loan of `principal` for `years` (decision 715): the
    /// balance goes up by the principal now, and the principal and the
    /// whole term's interest are paid in one sum at the midnight that
    /// begins its due day.
    ///
    /// - Throws: as ``termLoanQuote(principal:years:)``.
    @discardableResult
    public mutating func takeTermLoan(principal: Money, years: Int64) throws(GameError) -> TermLoan {
        let quote = try termLoanQuote(principal: principal, years: years)
        let loan = TermLoan(
            id: accounts.nextTermLoanID, principal: principal, interest: quote.interest, rate: quote.rate, years: years,
            borrowedDay: dayIndex(of: clock.now)
        )
        accounts.nextTermLoanID += 1
        accounts.termLoans.append(loan)
        economy.earn(principal)
        bookLoan(borrowed: principal)
        return loan
    }

    /// Pays term loan `id` back now, at what
    /// ``termLoanRepaymentQuote(_:)`` says. Allowed in free play too, as
    /// repaying the loan of decision 67 is.
    ///
    /// - Throws, checked in this order: ``GameError/invalidTermLoan`` if
    ///   there is no such loan, or
    ///   ``GameError/insufficientFunds(required:available:)`` when the
    ///   balance is less than the principal and the interest charged.
    public mutating func repayTermLoanEarly(_ id: Int64) throws(GameError) {
        let quote = try termLoanRepaymentQuote(id)
        guard economy.balance >= quote.total else {
            throw .insufficientFunds(required: quote.total, available: economy.balance)
        }
        let day = dayIndex(of: clock.now)
        accounts.termLoans.removeAll { $0.id == id }
        payBack(quote.loan.principal, interest: quote.interest, time: clock.now, day: day)
    }

    // MARK: - Settlement

    /// Pays every term loan due by the day after `day`, which just ended:
    /// its principal and its whole interest, which may take the balance
    /// below zero as the day's other costs may.
    mutating func settleTermLoans(day: Int64, time: GameTime) {
        let due = accounts.termLoans.filter { $0.dueDay <= day + 1 }
        guard !due.isEmpty else { return }
        accounts.termLoans.removeAll { $0.dueDay <= day + 1 }
        for loan in due {
            payBack(loan.principal, interest: loan.interest, time: time, day: day)
        }
    }

    /// Takes `principal` and `interest` from the balance: the principal as
    /// a loan repaid, the interest as a ledger row of the loan's interest
    /// (a managed company's; free play keeps no ledger).
    private mutating func payBack(_ principal: Money, interest: Money, time: GameTime, day: Int64) {
        economy.settle(.zero - principal)
        guard accounts.mode == .management else {
            economy.settle(.zero - interest)
            return
        }
        accounts.bookCapital(day: day) { $0.repaid = $0.repaid + principal }
        if interest > .zero {
            write(LedgerEntry(
                kind: .dailyInterest, time: time, amount: .zero - interest,
                breakdown: [LedgerLine(item: .loanInterest, amount: .zero - interest)]
            ), day: day)
        }
    }

    // MARK: - Validation

    /// Why the term loans break a rule of decision 715, or `nil`.
    func termLoansProblem() -> String? {
        let loans = accounts.termLoans
        guard loans.count <= CompanyAccounts.termLoanSlots else { return "There are more term loans than the bank holds at once." }
        guard accounts.nextTermLoanID >= 1, zip(loans, loans.dropFirst()).allSatisfy({ $0.id < $1.id }),
              loans.allSatisfy({ (1..<accounts.nextTermLoanID).contains($0.id) })
        else { return "Term loans are listed once each, in the order signed, with IDs already handed out." }
        let today = dayIndex(of: clock.now)
        for loan in loans {
            guard loan.principal > .zero, loan.principal.amount <= Self.maximumAccrued,
                  loan.principal.amount % CompanyAccounts.loanStep.amount == 0,
                  let rate = CompanyAccounts.termLoanRate(years: loan.years), loan.rate == rate,
                  loan.interest == CompanyAccounts.termLoanInterest(principal: loan.principal, rate: rate, years: loan.years),
                  loan.borrowedDay <= today
            else { return "A term loan must be whole loan steps for 1 to 10 years, at its term's rate and interest, signed no later than today." }
        }
        guard accounts.termLoansOutstanding.amount <= Self.maximumAccrued else { return "The term loans are out of range." }
        return nil
    }
}
