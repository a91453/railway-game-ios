import XCTest
@testable import GamePresentation

/// `Map3DTrainOwnGlassList.swift` merges with `merge=union`: when two
/// branches change the same line, both copies stay. No line may come in
/// twice.
final class Map3DTrainOwnGlassListTests: XCTestCase {
    func testNoPrefixTwice() {
        XCTAssertEqual(Set(Map3DTrainOwnGlassList.prefixes).count, Map3DTrainOwnGlassList.prefixes.count)
        XCTAssertEqual(Set(Map3DTrainOwnGlassList.darkNeverGlass).count, Map3DTrainOwnGlassList.darkNeverGlass.count)
    }

    func testNoStudioCarTwice() throws {
        var names: [String] = []
        for far in [false, true] {
            for train in Map3DTrainOwnGlassList.studioCars {
                for car in train(far) { names.append(try XCTUnwrap(car).name) }
            }
        }
        XCTAssertGreaterThan(names.count, 10)
        XCTAssertEqual(Set(names).count, names.count, "a train's line came in twice")
    }

}
