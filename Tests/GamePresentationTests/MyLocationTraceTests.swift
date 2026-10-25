@testable import GamePresentation
import XCTest

/// TestFlight 86.1: a test build's line under "Use my location" says when
/// it was pressed and what the ask came to.
final class MyLocationTraceTests: XCTestCase {
    func testTheLineSaysWhenItWasPressedAndWhatCameOfIt() {
        var trace = MyLocationTrace(hour: 9, minute: 5, second: 7)
        XCTAssertEqual(trace.text(in: .traditionalChinese), "09:05:07 定位中…")
        XCTAssertEqual(trace.text(in: .english), "09:05:07 Locating…")
        trace.outcome = .located(accuracyMetres: 64.6, ageSeconds: 182.4)
        XCTAssertEqual(trace.text(in: .traditionalChinese), "09:05:07 成功 ±65 m，182 秒前的位置")
        XCTAssertEqual(trace.text(in: .english), "09:05:07 Found ±65 m, 182 s old")
        trace.outcome = .failed(code: 0, description: "The operation couldn’t be completed.")
        XCTAssertEqual(trace.text(in: .traditionalChinese), "09:05:07 失敗：0 The operation couldn’t be completed.")
        trace.outcome = .timedOut(seconds: 30)
        XCTAssertEqual(trace.text(in: .traditionalChinese), "09:05:07 逾時 30 秒")
        trace.outcome = .denied
        XCTAssertEqual(trace.text(in: .traditionalChinese), "09:05:07 定位未允許")
        // A fix stamped a little after it arrived (clocks) is "0 s old".
        trace = MyLocationTrace(hour: 23, minute: 59, second: 59, outcome: .located(accuracyMetres: 5, ageSeconds: -0.3))
        XCTAssertEqual(trace.text(in: .english), "23:59:59 Found ±5 m, 0 s old")
    }
}
