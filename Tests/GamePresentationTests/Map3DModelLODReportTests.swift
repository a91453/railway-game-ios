import Foundation
import XCTest
@testable import GamePresentation

/// Decision 420's measurements: every model of the pack at each share,
/// how long it took and how much more memory the levels hold. Only on
/// request, best in a release build:
///
///     swift build -c release --build-tests -Xswiftc -enable-testing
///     MAP3D_LOD_REPORT=1 swift test -c release --skip-build --filter Map3DModelLODReportTests
final class Map3DModelLODReportTests: XCTestCase {
    func testReport() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_LOD_REPORT"] != nil else { throw XCTSkip("Set MAP3D_LOD_REPORT=1.") }
        let shares = [0.5, 0.25, 0.1]
        let started = Date()
        let pack = Map3DModelPack.standard
        let built = Date().timeIntervalSince(started)
        var totals = [Int](repeating: 0, count: shares.count + 1)
        var slowest: [(String, Double, Int)] = []
        let begun = Date()
        for model in pack.models {
            let one = Date()
            let levels = model.simplified(to: shares)
            let took = Date().timeIntervalSince(one)
            totals[0] += model.triangleCount
            for (k, level) in levels.enumerated() { totals[k + 1] += level.triangleCount }
            slowest.append((model.name, took, model.triangleCount))
            print(String(format: "%@\t%d\t%@\t%.3f s", model.name, model.triangleCount,
                         levels.map { String($0.triangleCount) }.joined(separator: "\t"), took))
        }
        let all = Date().timeIntervalSince(begun)
        let stride = MemoryLayout<Map3DVertex>.stride
        print("models \(pack.models.count), pack built in \(String(format: "%.2f", built)) s, levels in \(String(format: "%.2f", all)) s")
        for (k, total) in totals.enumerated() {
            print("share \(k == 0 ? 1 : shares[k - 1]): \(total) triangles, \(String(format: "%.1f", Double(total * 3 * stride) / 1_048_576)) MB")
        }
        for (name, took, count) in slowest.sorted(by: { $0.1 > $1.1 }).prefix(8) {
            print("slowest \(name) \(count) \(String(format: "%.3f", took)) s")
        }
    }
}
