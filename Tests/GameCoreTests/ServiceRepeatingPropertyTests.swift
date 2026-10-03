import XCTest

/// Decision 21: services that turn trains round and repeat, under the checks
/// of ``ServicePropertyTests`` (the `service.repeating` campaign). A class of
/// its own only so that CI can run it in a shard of its own (see
/// `.github/scripts/swift-shards.sh`): the two service campaigns together
/// outgrew one shard once they ran on the track network (Stage F3b).
final class ServiceRepeatingPropertyTests: XCTestCase {
    func testRepeatingServicesMatchTheReferenceAndBatchesMatchSingleSteps() throws {
        let counts = try ServicePropertyTests.runServiceCampaign("service.repeating", repeating: true)
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        for (event, least) in [
            ("startService", 400), ("invalidTimetable", 40), ("departures", 100), ("arrivals", 40),
            ("turned round", 150), ("new cycles", 150), ("started late in a later cycle", 20), ("completed", 100),
            ("waits without a route", 150),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }
}
