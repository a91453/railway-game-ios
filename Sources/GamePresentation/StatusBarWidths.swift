import GameCore

/// Decision 251: what the status bar keeps room for, so it holds one width
/// while the game runs. Each text in it that changes with the game (the
/// date, the cash, the speed, the followed train's speed) is laid out as
/// wide as the widest text it can show until the player changes something
/// (the year, the cash gaining a digit, a speed below 600×, following a
/// train); the app measures these texts and keeps the room of the widest.
/// Without it the bar narrowed and widened from day to day ("May 9" then
/// "May 10", a weekday's name, the seconds coming and going each minute at
/// real time), and on a small phone it then changed its layout (the
/// shorter date, cash and time stacked) and moved the buttons under the
/// player's finger.
public enum StatusBarWidths {
    /// Every date and time the status bar can show in `clock`'s year, one
    /// for each way it is written (month and weekday names, how many
    /// digits), with the most digits: the digits are drawn all one width
    /// (`monospacedDigit`), so these cover every day of the year. With the
    /// seconds whenever they can show at the speed the game runs at
    /// (``showsSeconds(_:)``). `short`: the board's shorter date (decision
    /// 226).
    public static func dateTexts(of clock: GameClock, short: Bool, in language: DisplayLanguage) -> [String] {
        let yearStart = (clock.now.date.year - 1) * FinancePeriod.year.days
        let seconds = showsSeconds(clock) ? ":00" : ""
        var widest: [String: String] = [:]
        var order: [String] = []
        for day in yearStart..<(yearStart + FinancePeriod.year.days) {
            // 23:59: the hour has two digits like any other.
            let time = GameTime(seconds: day * GameTime.secondsPerDay + 23 * 3_600 + 59 * 60)
            let text = (short ? time.shortCalendarText(in: language) : time.calendarText(in: language)) + seconds
            let words = String(text.filter { !$0.isNumber })
            if let kept = widest[words] {
                if text.filter(\.isNumber).count > kept.filter(\.isNumber).count { widest[words] = text }
            } else {
                widest[words] = text
                order.append(words)
            }
        }
        return order.compactMap { widest[$0] }
    }

    /// Whether the date can show the seconds at the speed the game runs
    /// at, paused or not: below 600× they come and go each minute
    /// (``GameClock/calendarText(in:)``), and the room for them stays.
    public static func showsSeconds(_ clock: GameClock) -> Bool {
        !clock.now.isWholeMinute || clock.runningSpeed.tenthsPerTick < GameSpeed.normal.tenthsPerTick
    }

    /// The widest the cash can read until its amount gains a digit, with
    /// the room of a minus sign and of at least seven digits ("NT$
    /// -8,888,888"): a balance that goes up and down by a digit, or below
    /// zero, keeps one width. In Chinese, where the cash is in 萬 or 億
    /// (``Money/compactText(in:)``), the room of the widest 萬 ("NT$
    /// -8,888.8 萬", every balance under 1 億), and from 1 億 that of the
    /// 億 with at least four digits before the point and two after it
    /// ("NT$ -8,888.88 億"), so passing 1 億 never narrows the bar.
    public static func moneyText(_ balance: Money, in language: DisplayLanguage) -> String {
        let size = balance.wholeDollars.magnitude
        guard language == .traditionalChinese else {
            let digits = balance.moneyText.filter(\.isNumber).count
            return Money.currencySymbol + " -" + eights(max(7, min(digits, 18))).groupedText
        }
        // Under 1 億 once rounded to the thousand, the cash is in 萬.
        guard (size + 500) / 1_000 >= 100_000 else { return Money.currencySymbol + " -8,888.8 萬" }
        let yi = (size + 500_000) / 100_000_000
        return Money.currencySymbol + " -" + eights(max(4, min(String(yi).count, 16))).groupedText + ".88 億"
    }

    private static func eights(_ count: Int) -> Int64 {
        Int64(String(repeating: "8", count: count)) ?? 8_888_888
    }

    /// Every label the speed menu's button can show.
    public static func speedLabels(in language: DisplayLanguage) -> [String] {
        GameSpeed.allCases.map { $0.label(in: language) }
    }

    /// The followed train's speed at its widest (``ViewingSpeed/trainSpeedText``).
    public static let trainSpeedText = "888 km/h"

    /// The curve limit under the followed train's speed at its widest
    /// (``CurveLimitReading/text(in:)``).
    public static func curveTexts(in language: DisplayLanguage) -> [String] {
        [true, false].map { CurveLimitReading(speed: 888, ahead: $0).text(in: language) }
    }
}
