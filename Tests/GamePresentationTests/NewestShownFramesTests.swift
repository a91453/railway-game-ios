@testable import GamePresentation
import XCTest

/// Review L14-8: while two station masters are measured at once (the new
/// one shown as building begins, before the old one goes), the legend
/// keeps above the new one, whatever order a dictionary would list them in.
final class NewestShownFramesTests: XCTestCase {
    func testTheViewShownLastIsTheOneThatCounts() {
        // Enough keys that a dictionary's order would put an older one
        // first for at least one of them.
        for count in 2...40 {
            var frames = NewestShownFrames<Int, Double>()
            for key in 0..<count { frames[key] = Double(key) }
            XCTAssertEqual(frames.newest(), Double(count - 1), "\(count) shown")
            // Measured again, the older one keeps its place.
            frames[0] = 100
            XCTAssertEqual(frames.newest(), Double(count - 1))
            frames[count - 1] = nil
            XCTAssertEqual(frames.newest(), count == 2 ? 100 : Double(count - 2), "the newest gone")
        }
    }

    func testOneWithNoSizeIsPassedOverAndNoneIsNil() {
        var frames = NewestShownFrames<String, Double>()
        XCTAssertNil(frames.newest())
        frames["old"] = 5
        frames["new"] = 0
        XCTAssertEqual(frames.newest { $0 > 0 }, 5)
        XCTAssertEqual(frames.newest(), 0)
        frames["old"] = nil
        frames["new"] = nil
        XCTAssertNil(frames.newest())
        XCTAssertNil(frames["old"])
    }
}
