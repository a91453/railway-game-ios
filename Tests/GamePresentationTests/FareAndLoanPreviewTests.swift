import GameCore
@testable import GamePresentation
import XCTest

/// Decision 374 (City Transport Manager study 4.11, 4.12): the demand line
/// beside the fares, the loan's preview before borrowing, and the train
/// types a lesson has not opened yet.
final class FareAndLoanPreviewTests: XCTestCase {
    // MARK: - Fares

    func testTheShareIsGameCoresDemandFactor() {
        let baseline = FareRules.demandBaseline
        for fare in [Money(0), 25, 75, 100, 150, 300, 500] {
            let share = FareDemandHint.Share(rules: .flat(fare), baseline: baseline)
            XCTAssertEqual(share.shortest, FareRules.demandFactor(fare: fare, baseline: baseline))
            XCTAssertEqual(share.longest, share.shortest)
        }
        let bands = FareDemandHint.Share(rules: .distance(FareRules.standardBands), baseline: baseline)
        XCTAssertEqual(bands.shortest, FareRules.demandFactor(fare: 55, baseline: baseline))
        XCTAssertEqual(bands.longest, FareRules.demandFactor(fare: 120, baseline: baseline))
    }

    func testTheLevels() {
        func level(_ fare: Money) -> FareDemandHint.Level {
            FareDemandHint.Level(FareDemandHint.Share(rules: .flat(fare), baseline: 75))
        }
        XCTAssertEqual(level(25), .more, "a third of the usual fare keeps 1,053")
        XCTAssertEqual(level(75), .usual)
        XCTAssertEqual(level(85), .usual, "1.13 times keeps 953")
        XCTAssertEqual(level(120), .lower, "1.6 times keeps 697")
        XCTAssertEqual(level(500), .veryLow)
        XCTAssertEqual(FareDemandHint.Level(FareDemandHint.Share(shortest: 900, longest: 900)), .usual)
        XCTAssertEqual(FareDemandHint.Level(FareDemandHint.Share(shortest: 899, longest: 899)), .lower)
        XCTAssertEqual(FareDemandHint.Level(FareDemandHint.Share(shortest: 499, longest: 499)), .veryLow)
    }

    func testTheHintsWords() {
        let flat = FareDemandHint(proposed: FareDemandHint.Share(rules: .flat(120), baseline: 75), current: .unchanged)
        XCTAssertEqual(flat.text(in: .english), "Demand: fewer riders, about 70% of the riders at the usual fare (now 100%).")
        XCTAssertEqual(flat.text(in: .traditionalChinese), "需求：偏低，約是一般票價時乘客的 70%（現在 100%）。")
        XCTAssertTrue(flat.isWarning)
        let bands = FareDemandHint(proposed: FareDemandHint.Share(rules: .distance(FareRules.standardBands), baseline: 75), current: FareDemandHint.Share(rules: .flat(120), baseline: 75))
        XCTAssertEqual(bands.proposed.percentText, "102%–70%")
        XCTAssertEqual(
            bands.text(in: .english),
            "Demand: fewer riders, about 102% of the riders at the usual fare on short trips and 70% on the longest (now 70%)."
        )
        XCTAssertEqual(bands.text(in: .traditionalChinese), "需求：偏低，短程約是一般票價時乘客的 102%，最遠的 70%（現在 70%）。")
        XCTAssertFalse(bands.isWarning, "more riders than now")
        XCTAssertEqual(FareDemandHint.usualFareText(75, in: .traditionalChinese), "這座城市的一般票價：$ 0.75。")
    }

    @MainActor
    func testTheHintComparesWithTheFaresChargedNowAndIsNotMadeInFreePlay() throws {
        var world = GameWorld.newGame()
        XCTAssertEqual(world.fareDemandHint(for: .flat(500))?.current, .unchanged, "fares never set leave demand as it is")
        try world.setFareRules(.flat(150))
        let hint = try XCTUnwrap(world.fareDemandHint(for: .flat(world.accounts.fareBaseline)))
        XCTAssertEqual(hint.current, FareDemandHint.Share(rules: .flat(150), baseline: world.accounts.fareBaseline))
        XCTAssertEqual(hint.proposed, .unchanged, "the city's usual fare keeps its riders")
        world.setEconomyMode(.free)
        XCTAssertNil(world.fareDemandHint(for: .flat(75)))
    }

    // MARK: - Loan

    @MainActor
    func testTheLoanPreviewGivesTheDailyInterestAndItsTotals() throws {
        let session = GameSession(world: GameWorld.newGame())
        let preview = try XCTUnwrap(session.world.loanPreview())
        XCTAssertEqual(preview.amount, CompanyAccounts.loanStep)
        XCTAssertEqual(preview.dailyInterest, GameWorld.dailyLoanInterest(on: CompanyAccounts.loanStep))
        XCTAssertEqual(preview.dailyInterest, Money(1_400))
        XCTAssertEqual(preview.monthInterest, Money(1_400 * 30))
        XCTAssertEqual(preview.yearInterest, Money(1_400 * 360))
        XCTAssertNil(preview.recentDailyResult, "no full day yet")
        XCTAssertNil(preview.resultText(in: .english))
        XCTAssertEqual(preview.paymentText(in: .english), "Borrowing $ 100,000 adds $ 14 of interest each day, paid at midnight.")
        XCTAssertEqual(preview.paymentText(in: .traditionalChinese), "借入 $ 100,000：每天多付利息 $ 14，午夜支付。")
        XCTAssertEqual(
            preview.totalText(in: .english),
            "Kept a month, $ 420 of interest in all; kept a year, $ 5,040, and $ 105,040 with the loan repaid. Repay it whenever you like."
        )
        XCTAssertEqual(preview.totalText(in: .traditionalChinese), "借一個月共付利息 $ 420；借一年共付 $ 5,040，連本金共 $ 105,040。本金隨時可以還。")

        // The step is what it adds to the interest on what is owed.
        session.borrowLoanStep()
        let second = try XCTUnwrap(session.world.loanPreview())
        XCTAssertEqual(
            second.dailyInterest,
            GameWorld.dailyLoanInterest(on: CompanyAccounts.loanStep + CompanyAccounts.loanStep) - GameWorld.dailyLoanInterest(on: CompanyAccounts.loanStep)
        )
    }

    @MainActor
    func testTheLoanPreviewReadsTheLastFullDays() throws {
        var world = GameWorld.newGame()
        try world.borrow(CompanyAccounts.loanStep)
        try world.advance(ticks: 2 * 1_440 + 1)
        let preview = try XCTUnwrap(world.loanPreview())
        let days = world.accounts.days.filter { $0.day < FinanceHistory.floorDay(world.clock.now) }
        XCTAssertFalse(days.isEmpty)
        XCTAssertEqual(preview.recentDayCount, min(days.count, LoanPreview.recentDays))
        let paid = days.map(\.interestCost.amount).reduce(0, +) / Int64(days.count)
        XCTAssertLessThanOrEqual(preview.recentDailyResult?.amount ?? 0, -paid, "the interest paid is in the result")
        XCTAssertEqual(preview.dailyResultAfter, preview.recentDailyResult.map { $0 - preview.dailyInterest })
        XCTAssertNotNil(preview.resultText(in: .traditionalChinese))
    }

    @MainActor
    func testNoPreviewWhenNothingCanBeBorrowed() throws {
        var world = GameWorld.newGame()
        while world.accounts.loan < CompanyAccounts.maximumLoan {
            try world.borrow(CompanyAccounts.loanStep)
        }
        XCTAssertNil(world.loanPreview(), "at its most")
        world = GameWorld.newGame()
        world.setEconomyMode(.free)
        XCTAssertNil(world.loanPreview(), "free play")
    }

    // MARK: - Train types in the lessons

    func testEveryTypeOpensInALessonAndAllByTheLast() {
        for type in TrainType.offered {
            XCTAssertTrue((1...Lesson.all.count).contains(Lesson.number(unlocking: type)), "\(type.rawValue)")
            XCTAssertTrue(Lesson.all.last?.allows(type) == true, "\(type.rawValue)")
        }
        XCTAssertEqual(Lesson.number(unlocking: .a), 1)
        XCTAssertEqual(Lesson.number(unlocking: .l), 3)
        XCTAssertEqual(Lesson.number(unlocking: .emu3000), 4)
        XCTAssertEqual(Lesson.number(unlocking: .highSpeed), 5)
        XCTAssertEqual(Lesson.number(unlocking: .maglev), 6)
        XCTAssertEqual(Lesson.number(unlocking: .haiFeng), 9)
    }

    @MainActor
    func testTheShowroomListsTheShutTypesWithTheirLesson() throws {
        let lesson = try XCTUnwrap(Lesson.all.first)
        let world = GameWorld.newGame(lesson: lesson)
        let catalog = RollingStockCatalog(world: world)
        XCTAssertEqual(Set(catalog.entries.map(\.type)), Set(world.offeredTrainTypes), "every type is listed")
        for entry in catalog.entries {
            XCTAssertEqual(entry.opensInLesson, Lesson.number(unlocking: entry.type) > 1 ? Lesson.number(unlocking: entry.type) : nil)
        }
        XCTAssertEqual(world.lessonUnlockText(for: .highSpeed, in: .traditionalChinese), "第 5 關解鎖")
        XCTAssertEqual(world.lessonUnlockText(for: .highSpeed, in: .english), "Opens in lesson 5")
        XCTAssertNil(world.lessonUnlockText(for: .a, in: .english))
        XCTAssertEqual(catalog.firstOpen, .a)
        XCTAssertEqual(world.openTrainTypes, world.offeredTrainTypes.filter { Lesson.number(unlocking: $0) == 1 })
        let session = GameSession(world: world)
        XCTAssertEqual(session.trainTypeCardChoices.map(\.id), world.openTrainTypes, "the line's menu offers the open ones")
    }

    @MainActor
    func testOutsideTheLessonsEveryTypeIsOpen() {
        let world = DemoWorld.make(in: .english)
        XCTAssertTrue(RollingStockCatalog(world: world).entries.allSatisfy(\.isOpen))
        XCTAssertEqual(world.openTrainTypes, world.offeredTrainTypes)
    }
}
