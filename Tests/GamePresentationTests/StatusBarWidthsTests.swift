import GameCore
import GamePresentation
import XCTest

/// Decision 251: the status bar keeps room for the widest text each of
/// its parts can show, so it holds one width while the game runs.
final class StatusBarWidthsTests: XCTestCase {
    /// Whether `template` is at least as wide as `text` with the digits
    /// drawn all one width: the same words, at least as many digits.
    private func covers(_ template: String, _ text: String) -> Bool {
        template.filter { !$0.isNumber } == text.filter { !$0.isNumber }
            && template.filter(\.isNumber).count >= text.filter(\.isNumber).count
    }

    /// Every minute of a year's days, as the board writes them at real
    /// time (with the seconds) and at 600× (without), is covered by one of
    /// the year's texts, in both languages and both lengths.
    func testTheDateTextsCoverEveryDayOfTheYear() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            for short in [false, true] {
                for speed in [GameSpeed.x1, .normal] {
                    var textsWithSeconds: [Bool: [String]] = [:]
                    for day in Int64(360)..<720 {
                        for second: Int64 in [0, 9 * 3_600 + 5 * 60 + 7] {
                            let clock = GameClock(now: GameTime(seconds: day * GameTime.secondsPerDay + second), speed: speed)
                            let seconds = StatusBarWidths.showsSeconds(clock)
                            let texts = textsWithSeconds[seconds] ?? StatusBarWidths.dateTexts(of: clock, short: short, in: language)
                            textsWithSeconds[seconds] = texts
                            XCTAssertLessThanOrEqual(texts.count, 12 * 7, "\(language) \(short) \(speed)")
                            let text = short ? clock.shortCalendarText(in: language) : clock.calendarText(in: language)
                            XCTAssertTrue(texts.contains { covers($0, text) }, "\(text) not covered (\(language), \(speed))")
                        }
                    }
                }
            }
        }
    }

    /// At real time the seconds come and go each minute; their room stays,
    /// paused too. At 600× and up there are none to keep room for.
    func testTheSecondsKeepTheirRoomAtSlowSpeedsPausedOrNot() {
        var clock = GameClock(now: GameTime(minutes: 600), speed: .x1)
        XCTAssertTrue(StatusBarWidths.showsSeconds(clock))
        clock.pause()
        XCTAssertTrue(StatusBarWidths.showsSeconds(clock))
        clock.setSpeed(.normal)
        clock.resume()
        XCTAssertFalse(StatusBarWidths.showsSeconds(clock))
        XCTAssertTrue(StatusBarWidths.showsSeconds(GameClock(now: GameTime(seconds: 601), speed: .paused)))
    }

    /// The cash keeps one width from $ 0 to $ -9,999,999 and only gains
    /// room with an eighth digit.
    func testTheCashKeepsRoomForSevenDigitsAndAMinus() {
        let small = StatusBarWidths.moneyText(Money(0))
        XCTAssertEqual(small, "$ -8,888,888")
        for dollars: Int64 in [0, 5, -1_428, 120_000, -9_999_999, 9_999_999] {
            XCTAssertEqual(StatusBarWidths.moneyText(Money(dollars * 100)), small)
            XCTAssertTrue(small.count >= Money(dollars * 100).moneyText.count)
        }
        XCTAssertEqual(StatusBarWidths.moneyText(Money(12_345_678 * 100)), "$ -88,888,888")
        XCTAssertEqual(StatusBarWidths.moneyText(Money(Int64.max)).filter(\.isNumber).count, Money(Int64.max).moneyText.filter(\.isNumber).count)
    }

    /// Every label the speed button can show is offered, and the train's
    /// speed and its curve limit at their widest.
    func testTheSpeedAndTheTrainsSpeedAtTheirWidest() {
        XCTAssertEqual(StatusBarWidths.speedLabels(in: .english).count, GameSpeed.allCases.count)
        XCTAssertTrue(StatusBarWidths.speedLabels(in: .english).contains("6000×"))
        for kilometresPerHour: Int64 in [0, 85, 320] {
            let text = "\(kilometresPerHour) km/h"
            XCTAssertTrue(covers(StatusBarWidths.trainSpeedText, text) || StatusBarWidths.trainSpeedText.count >= text.count)
        }
        let curves = StatusBarWidths.curveTexts(in: .traditionalChinese)
        XCTAssertEqual(curves, ["前方彎道 888 km/h", "彎道限速 888 km/h"])
    }
}
