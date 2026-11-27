@testable import GameCore
import XCTest

/// Decision 1038: ``RailwayNetwork``'s lookup of a node or an edge by its
/// number (the guess, the second guess back from it, then the search)
/// finds what going through the elements one by one finds, for numbers
/// handed out in turn with any of them removed, and for numbers far apart
/// as a save's can be.
final class NetworkIndexLookupTests: XCTestCase {
    func testTheLookupFindsWhatGoingThroughTheElementsFinds() {
        var seed: UInt64 = 0x9e37_79b9_7f4a_7c15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        var lists: [[Int]] = [[], [7], [Int.min, 0, Int.max], [Int.min + 1, -5, 3, Int.max - 1]]
        for _ in 0..<300 {
            var numbers: [Int] = []
            var number = next(20) - 10
            for _ in 0..<next(60) {
                // Mostly one apart, as handed out; now and then a gap, as
                // where some were removed.
                number += next(10) < 7 ? 1 : 1 + next(25)
                numbers.append(number)
            }
            lists.append(numbers)
        }
        for numbers in lists {
            var asked = Set([Int.min, Int.max, 0])
            if let first = numbers.first, let last = numbers.last {
                let low = max(first, Int.min + 3) - 3
                let high = min(min(last, Int.max - 3) + 3, low.addingReportingOverflow(2_000).overflow ? Int.max : low + 2_000)
                for number in low...high { asked.insert(number) }
            }
            asked.formUnion(numbers)
            for number in asked {
                XCTAssertEqual(RailwayNetwork.index(of: number, count: numbers.count) { numbers[$0] }, numbers.firstIndex(of: number),
                               "\(number) in \(numbers)")
            }
        }
    }
}
