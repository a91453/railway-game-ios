import GameCore

// Decision 715's screen: the term loans as the economy panel shows them.
// Every figure is GameCore's own (`termLoanCredit()`, `termLoanQuote`,
// `termLoanRepaymentQuote`); this file only orders them, says why the bank
// lends nothing, and writes the words in the game's two languages.

/// The term loans of the company, the soonest due first, with what paying
/// each back today costs, and how much more the bank lends.
public struct TermLoanBoard: Equatable, Sendable {
    /// One term loan and what paying it back today costs.
    public struct Contract: Equatable, Sendable, Identifiable {
        public let loan: TermLoan
        /// What paying it back today costs (`termLoanRepaymentQuote`).
        public let repayment: TermLoanRepaymentQuote
        /// How much the cash in hand falls short of ``repayment``'s total;
        /// zero when it pays it.
        public let shortfall: Money

        public var id: Int64 { loan.id }

        /// Whether the cash in hand pays it back today.
        public var canRepay: Bool { shortfall == .zero }

        /// What the two parts of the charge lose to the charge being whole
        /// hundreds of dollars.
        public var roundedOff: Money {
            repayment.accruedInterest + repayment.penalty - repayment.interest
        }
    }

    /// Why the bank signs no term loan now.
    public enum Blocked: Equatable, Sendable {
        /// Free play borrows nothing (`GameError.loanNeedsManagement`).
        case freePlay
        /// As many term loans as the bank holds at once.
        case full
        /// Not one step of credit left.
        case noCredit
    }

    /// The soonest due first; loans due the same day in the order signed.
    public let contracts: [Contract]
    public let credit: TermLoanCredit
    public let blocked: Blocked?

    public init(contracts: [Contract], credit: TermLoanCredit, blocked: Blocked?) {
        self.contracts = contracts
        self.credit = credit
        self.blocked = blocked
    }

    /// The principal and interest of every term loan: what is paid as they
    /// fall due.
    public var totalDue: Money { credit.outstanding }

    /// The terms on offer, in years.
    public static var yearChoices: ClosedRange<Int64> { 1...CompanyAccounts.longestTermLoan }

    /// The amounts on offer: one ``CompanyAccounts/loanStep`` to the most
    /// the bank lends, or `nil` when it lends nothing.
    public var principalChoices: ClosedRange<Int64>? {
        guard blocked == nil, credit.maximumPrincipal >= CompanyAccounts.loanStep else { return nil }
        return CompanyAccounts.loanStep.amount...credit.maximumPrincipal.amount
    }

    /// The amount the form shows for `choice`, the player's last (`nil`
    /// before the first): whole steps within ``principalChoices``, starting
    /// from ``startingSteps`` steps or the most the bank lends if that is
    /// less. `nil` when the bank lends nothing.
    public func principal(for choice: Money?) -> Money? {
        guard let choices = principalChoices else { return nil }
        let step = CompanyAccounts.loanStep.amount
        let wanted = choice?.amount ?? Self.startingSteps * step
        return Money(min(max(wanted / step * step, choices.lowerBound), choices.upperBound))
    }

    /// The steps the form starts from: NT$3,000,000.
    public static let startingSteps: Int64 = 10

    // MARK: - Words

    /// "No term loans", or "2 term loans · $6,612,000 to pay when due".
    public func summaryText(in language: DisplayLanguage) -> String {
        guard !contracts.isEmpty else { return language.text("No term loans", "沒有定期貸款") }
        let count = contracts.count
        return language.text(
            "\(count) term \(count == 1 ? "loan" : "loans") · \(totalDue.moneyText) to pay when due",
            "定期貸款 \(count) 筆 · 到期共付 \(totalDue.moneyText)"
        )
    }

    /// "Next due Year 3 · Jan 1 (Mon): $3,306,000", or `nil` with no loan.
    public func nextDueText(in language: DisplayLanguage) -> String? {
        guard let next = contracts.first else { return nil }
        let date = GameDate(day: next.loan.dueDay).text(in: language)
        return language.text("Next due \(date): \(next.loan.total.moneyText)", "最近到期：\(date)，付 \(next.loan.total.moneyText)")
    }

    /// How much more the bank lends, "Up to $9,900,000 more · 48 more
    /// loans", or why it lends nothing.
    public func creditText(in language: DisplayLanguage) -> String {
        switch blocked {
        case .freePlay:
            return contracts.isEmpty
                ? language.text(
                    "Only a managed company can sign a term loan. Free play cannot.",
                    "定期貸款只有經營模式能借，自由模式不能簽約。"
                )
                : language.text(
                    "Free play cannot sign a term loan. The ones already signed can still be repaid early.",
                    "自由模式不能再簽定期貸款，已簽的仍可以提前還。"
                )
        case .full:
            let most = CompanyAccounts.termLoanSlots
            return language.text(
                "The bank holds \(most) term loans at once. Repay one to sign another.",
                "最多同時 \(most) 筆，還掉一筆才能再簽。"
            )
        case .noCredit:
            return language.text(
                "The bank has nothing more to lend now. It lends more as the company is worth more.",
                "目前沒有額度可借。公司的淨值增加，額度就會增加。"
            )
        case nil:
            let slots = credit.freeSlots
            return language.text(
                "Up to \(credit.maximumPrincipal.moneyText) more · \(slots) more \(slots == 1 ? "loan" : "loans")",
                "還能借 \(credit.maximumPrincipal.moneyText) · 還能簽 \(slots) 筆"
            )
        }
    }

    /// What a term loan is, under the list.
    public static func termsText(in language: DisplayLanguage) -> String {
        let longest = CompanyAccounts.longestTermLoan
        return language.text(
            "Borrowed for 1 to \(longest) years. The interest is fixed when you sign, and the loan and its interest are paid in one sum on the due day. A longer term costs more a year. The bank lends up to half of what the company is worth.",
            "借 1 到 \(longest) 年，利息在簽約時固定，到期日一次還本付息；年期越長，年利率越高。額度是公司淨值的一半。"
        )
    }

    /// The yearly rate, in hundredths of a percent, as "5.10%".
    public static func rateText(_ rate: Int64) -> String {
        let hundredths = rate % 100
        return "\(rate / 100).\(hundredths < 10 ? "0" : "")\(hundredths)%"
    }

    /// "2 years" or "2 年".
    public static func yearsText(_ years: Int64, in language: DisplayLanguage) -> String {
        language.text("\(years) \(years == 1 ? "year" : "years")", "\(years) 年")
    }
}

extension TermLoan {
    /// "2 years at 5.10% · due Year 3 · Jan 1 (Mon)".
    public func termsText(in language: DisplayLanguage) -> String {
        let years = TermLoanBoard.yearsText(years, in: language), rate = TermLoanBoard.rateText(rate)
        let date = GameDate(day: dueDay).text(in: language)
        return language.text("\(years) at \(rate) · due \(date)", "\(years) · 年利率 \(rate) · \(date)到期")
    }
}

extension TermLoan {
    /// "Pays $3,306,000 when due".
    public func dueTotalText(in language: DisplayLanguage) -> String {
        language.text("Pays \(total.moneyText) when due", "到期付 \(total.moneyText)")
    }
}

extension TermLoanQuote {
    /// The rows of the quote before signing: the rate, the whole term's
    /// interest, the due day and what is paid then.
    public func rows(in language: DisplayLanguage) -> [(title: String, value: String)] {
        [
            (language.text("Rate a year", "年利率"), TermLoanBoard.rateText(rate)),
            (language.text("Interest in all", "整期利息"), interest.moneyText),
            (language.text("Due", "到期日"), GameDate(day: dueDay).text(in: language)),
            (language.text("Paid when due", "到期一次付"), total.moneyText),
        ]
    }

    /// What signing does, asked before it is signed.
    public func confirmText(in language: DisplayLanguage) -> String {
        let date = GameDate(day: dueDay).text(in: language)
        return language.text(
            "You get \(principal.moneyText) now and pay \(total.moneyText) in one sum on \(date). Repaying before then costs an early fee.",
            "現在拿到 \(principal.moneyText)，\(date)一次付 \(total.moneyText)。提前還要付違約金。"
        )
    }
}

extension TermLoanBoard.Contract {
    /// What paying it back today costs: "Repaying today: $76,500 of
    /// interest for 180 days and a $45,900 early fee, $3,122,400 in all
    /// with the loan."
    public func repaymentText(in language: DisplayLanguage) -> String {
        let days = repayment.elapsedDays
        let accrued = repayment.accruedInterest.moneyText, total = repayment.total.moneyText
        let fee = repayment.penalty > .zero
            ? language.text(" and a \(repayment.penalty.moneyText) early fee", "，違約金 \(repayment.penalty.moneyText)") : ""
        let rounded = roundedOff > .zero ? language.text(", less the odd \(roundedOff.moneyText)", "，不滿百元的 \(roundedOff.moneyText) 不計") : ""
        return language.text(
            "Repaying today: \(accrued) of interest for \(days) \(days == 1 ? "day" : "days")\(fee)\(rounded), \(total) in all with the loan.",
            "今天提前還：已過 \(days) 天的利息 \(accrued)\(fee)\(rounded)，連本金共付 \(total)。"
        )
    }

    /// The button that asks to pay it back today: "Repay Today for
    /// $3,122,400…".
    public func repayText(in language: DisplayLanguage) -> String {
        language.text("Repay Today for \(repayment.total.moneyText)…", "今天提前還 \(repayment.total.moneyText)…")
    }

    /// Why it cannot be paid back today, or `nil` when it can.
    public func shortfallText(in language: DisplayLanguage) -> String? {
        guard !canRepay else { return nil }
        return language.text(
            "Not enough cash to repay it today: \(shortfall.moneyText) short.",
            "現金不夠，今天還不了：還差 \(shortfall.moneyText)。"
        )
    }
}

extension GameWorld {
    /// The term loans as the economy panel shows them (decision 715).
    public func termLoanBoard() -> TermLoanBoard {
        let credit = termLoanCredit()
        let balance = economy.balance
        let contracts = accounts.termLoans.compactMap { loan -> TermLoanBoard.Contract? in
            guard let quote = try? termLoanRepaymentQuote(loan.id) else { return nil }
            let short = quote.total > balance ? quote.total - balance : .zero
            return TermLoanBoard.Contract(loan: loan, repayment: quote, shortfall: short)
        }.sorted { ($0.loan.dueDay, $0.loan.id) < ($1.loan.dueDay, $1.loan.id) }
        let blocked: TermLoanBoard.Blocked? = if accounts.mode != .management {
            .freePlay
        } else if credit.freeSlots == 0 {
            .full
        } else if credit.maximumPrincipal < CompanyAccounts.loanStep {
            .noCredit
        } else {
            nil
        }
        return TermLoanBoard(contracts: contracts, credit: credit, blocked: blocked)
    }

    /// Whether the economy panel shows the term loans: as the loan of
    /// decision 67, not with unlimited funds (decision 200), unless there
    /// are some to pay back.
    public var showsTermLoans: Bool {
        !economy.unlimitedFunds || !accounts.termLoans.isEmpty
    }
}
