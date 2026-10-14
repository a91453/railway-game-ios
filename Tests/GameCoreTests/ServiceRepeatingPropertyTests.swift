import XCTest

/// Decision 21: services that turn trains round and repeat, under the checks
/// of ``ServicePropertyTests`` (the `service.repeating` campaign). A class of
/// its own only so that CI can run it in a shard of its own (see
/// `.github/scripts/swift-shards.sh`): the two service campaigns together
/// outgrew one shard once they ran on the track network (Stage F3b).
///
/// 2026-10-14: the campaign alone took up to 802 s of tests and timed a job
/// out on a slow runner, so it runs as two halves: cases 0 to 14 of every
/// seed here, 15 to 29 in ``ServiceRepeatingSecondHalfPropertyTests``. Every
/// case keeps its ID, operations and checks; each half asks at least half
/// of each event floor the whole campaign asked.
final class ServiceRepeatingPropertyTests: XCTestCase {
    func testRepeatingServicesMatchTheReferenceAndBatchesMatchSingleSteps() throws {
        try Self.check(cases: 0..<15)
    }

    static func check(cases: Range<Int>) throws {
        let counts = try ServicePropertyTests.runServiceCampaign("service.repeating", repeating: true, cases: cases)
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        // The whole campaign's floors (startService 400, invalidTimetable
        // 40, departures 100, arrivals 40, turned round 150, new cycles 150,
        // started late in a later cycle 20, completed 100, waits without a
        // route 150), halved for each half.
        for (event, least) in [
            ("startService", 200), ("invalidTimetable", 20), ("departures", 50), ("arrivals", 20),
            ("turned round", 75), ("new cycles", 75), ("started late in a later cycle", 10), ("completed", 50),
            ("waits without a route", 75),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }
}

final class ServiceRepeatingSecondHalfPropertyTests: XCTestCase {
    func testRepeatingServicesMatchTheReferenceAndBatchesMatchSingleSteps() throws {
        try ServiceRepeatingPropertyTests.check(cases: 15..<30)
    }
}
