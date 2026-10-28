@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 464: the one-time hint beside the speed when the device cannot
/// keep up: when it comes, once for each speed, the warm phone's words and
/// the speed it offers.
final class SpeedLagHintTests: XCTestCase {
    /// Feeds `seconds` one-second readings of `permille` at `speed`, from
    /// real time `start`; returns the real time after.
    @discardableResult
    private func feed(_ watch: inout SpeedLagWatch, from start: Int, seconds: Int, speed: GameSpeed = .fast, permille: Int64?, heat: Map3DQuality.Heat = .nominal) -> Int {
        for second in 1...seconds {
            watch.record(real: .seconds(start + second), speed: speed, permille: permille, heat: heat)
        }
        return start + seconds
    }

    func testComesOnlyAfterTwentySecondsFarBehind() {
        var watch = SpeedLagWatch()
        let now = feed(&watch, from: 0, seconds: 20, permille: 330)
        XCTAssertNil(watch.hint, "19 seconds behind: not yet")
        feed(&watch, from: now, seconds: 1, permille: 330)
        XCTAssertEqual(watch.hint?.speed, .fast)
        XCTAssertEqual(watch.hint?.actualTenths, 20_000)
        XCTAssertEqual(watch.hint?.reason, .slow)
    }

    func testAShortBadStretchOrALittleBehindGivesNone() {
        var watch = SpeedLagWatch()
        var now = feed(&watch, from: 0, seconds: 15, permille: 300)
        now = feed(&watch, from: now, seconds: 1, permille: 900)
        now = feed(&watch, from: now, seconds: 15, permille: 300)
        XCTAssertNil(watch.hint, "caught up in between: the 20 seconds start again")
        var near = SpeedLagWatch()
        feed(&near, from: 0, seconds: 60, permille: 750)
        XCTAssertNil(near.hint, "between 70% and 80%: the dot only")
        _ = now
    }

    func testOnceForEachSpeedAndNotAgainOnceDismissed() {
        var watch = SpeedLagWatch()
        var now = feed(&watch, from: 0, seconds: 21, permille: 330)
        XCTAssertNotNil(watch.hint)
        now = feed(&watch, from: now, seconds: 1, permille: 900)
        XCTAssertNil(watch.hint, "keeps up again: the hint goes with the dot")
        now = feed(&watch, from: now, seconds: 30, permille: 330)
        XCTAssertNil(watch.hint, "same speed, same game: not twice")
        now = feed(&watch, from: now, seconds: 21, speed: .double, permille: 330)
        XCTAssertEqual(watch.hint?.speed, .double, "another speed has its own")
        watch.dismiss()
        XCTAssertNil(watch.hint)
        now = feed(&watch, from: now, seconds: 30, speed: .normal, permille: 100)
        XCTAssertNil(watch.hint, "dismissed: none for the rest of the game")
    }

    func testChangingSpeedOrPausingTakesItAway() {
        var watch = SpeedLagWatch()
        let now = feed(&watch, from: 0, seconds: 21, permille: 330)
        watch.record(real: .seconds(now + 1), speed: .double, permille: nil, heat: .nominal)
        XCTAssertNil(watch.hint)
        var paused = SpeedLagWatch()
        feed(&paused, from: 0, seconds: 21, permille: 330)
        paused.pause()
        XCTAssertNil(paused.hint)
    }

    func testAHotPhoneSaysSoAndOffersNoSpeed() {
        var watch = SpeedLagWatch()
        feed(&watch, from: 0, seconds: 21, permille: 330, heat: .serious)
        let hint = try? XCTUnwrap(watch.hint)
        XCTAssertEqual(hint?.reason, .warm)
        XCTAssertFalse(hint?.offersSpeed ?? true)
        XCTAssertNil(hint?.switchText(in: .english))
        XCTAssertEqual(hint?.text(in: .english), "The device is warm, so the game slows down for now.")
        XCTAssertEqual(hint?.text(in: .traditionalChinese), "裝置有點燙，遊戲先放慢。")
        var fair = SpeedLagWatch()
        feed(&fair, from: 0, seconds: 21, permille: 330, heat: .fair)
        XCTAssertEqual(fair.hint?.reason, .slow, "fair is not hot")
        // It follows the phone while it shows.
        feed(&fair, from: 20, seconds: 1, permille: 330, heat: .critical)
        XCTAssertEqual(fair.hint?.reason, .warm)
    }

    func testTheSuggestedSpeedIsTheFastestOneTheGameKeeps() {
        func suggested(_ speed: GameSpeed, tenths: Int64) -> GameSpeed? {
            SpeedLagHint(speed: speed, actualTenths: tenths, reason: .slow).suggestedSpeed
        }
        XCTAssertEqual(suggested(.fast, tenths: 20_000), .double, "×2000 is kept at ×1200")
        XCTAssertEqual(suggested(.fast, tenths: 6_000), .normal)
        XCTAssertEqual(suggested(.fast, tenths: 5_900), .x60)
        XCTAssertEqual(suggested(.normal, tenths: 3_000), .x60)
        XCTAssertNil(suggested(.x1, tenths: 5), "nothing slower than real time")
        XCTAssertNil(suggested(.x10, tenths: 5))
    }

    func testTheWordsInBothLanguages() {
        let hint = SpeedLagHint(speed: .fast, actualTenths: 20_000, reason: .slow)
        XCTAssertEqual(hint.text(in: .english), "This map only runs about ×2000 on this device.")
        XCTAssertEqual(hint.text(in: .traditionalChinese), "這張地圖在這台裝置上大約只跑得到 ×2000。")
        XCTAssertEqual(hint.switchText(in: .english), "Switch to ×1200")
        XCTAssertEqual(hint.switchText(in: .traditionalChinese), "改成 ×1200")
        XCTAssertEqual(hint.dismissText(in: .traditionalChinese), "知道了")
        let none = SpeedLagHint(speed: .x1, actualTenths: 5, reason: .slow)
        XCTAssertNil(none.switchText(in: .english), "no slower speed: the words only")
    }
}
