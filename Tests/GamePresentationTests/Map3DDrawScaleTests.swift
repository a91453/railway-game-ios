@testable import GamePresentation
import XCTest

final class Map3DDrawScaleTests: XCTestCase {
    func testOnlyAGPUOverItsBudgetCountsAsOver() {
        // The owner's iPhone 17 Pro on Taipei, 2026-10-21: the first
        // screenshots' 2.2–4.4 ms keep the screen's own pixels; the
        // second's 10.1–11.8 ms are over.
        for gpu in [2.2, 2.7, 4.4, 9.9] { XCTAssertFalse(Map3DDrawScale.isOver(gpuMilliseconds: gpu, aim: 60), "\(gpu)") }
        for gpu in [10.1, 11.6, 11.8] { XCTAssertTrue(Map3DDrawScale.isOver(gpuMilliseconds: gpu, aim: 60), "\(gpu)") }
        XCTAssertFalse(Map3DDrawScale.isOver(gpuMilliseconds: 50, aim: 0))
    }

    func testLoweredDrawsTwoByTwoAndNeverMoreThanTheScreen() {
        XCTAssertEqual(Map3DDrawScale.scale(display: 3, lowered: false), 3)
        XCTAssertEqual(Map3DDrawScale.scale(display: 3, lowered: true), 2)
        // An iPad's 2× screen is already there.
        XCTAssertEqual(Map3DDrawScale.scale(display: 2, lowered: true), 2)
        XCTAssertEqual(Map3DDrawScale.scale(display: 1, lowered: true), 1)
    }
}
