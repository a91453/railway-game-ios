@testable import GameCore
import XCTest

/// Decision 755 (PLATFORM-BOOK PB-3): what the line panel and a train's
/// card read of a leg's list, and the two gaps of decision 740 the review
/// of 2026-11-14 found (REVIEW-L21 P3-1, P3-2). The world of
/// ``PlatformListTests``.
final class PlatformListEditTests: XCTestCase {
    /// P3-1: with traffic control off, a list whose first platform the
    /// train cannot stop at (too short for it) goes on to the next, as
    /// under traffic control; it used to go to any platform.
    func testWithTrafficControlOffTheListGoesOnPastAFirstPlatformTheTrainDoesNotFit() throws {
        func world(list: Bool) throws -> (GameWorld, TrainID) {
            var (world, _, line, train) = try LineRoutePreferenceTests.setup(traffic: false)
            try world.addTrackPlatform(SingleTrackMeet.middle, on: .edge(2), from: 2_048, to: 4_096)
            try world.addTrackPlatform(SingleTrackMeet.middle, on: .edge(2), from: 5_120, to: 5_184)
            let platforms = world.trackPlatforms(of: SingleTrackMeet.middle)
            let short = try XCTUnwrap(platforms.first { $0.edge == .edge(2) && $0.start == 5_120 })
            let far = try XCTUnwrap(platforms.first { $0.edge == .edge(2) && $0.start == 7_168 })
            XCTAssertLessThan(short.length, try XCTUnwrap(world.train(id: train)).length)
            try world.setLineRoutePreferences(line, to: [LineRoutePreference(from: 0, to: 1, platform: short, alternates: list ? [far] : [])])
            return (world, train)
        }
        var (listed, a) = try world(list: true)
        let next = try XCTUnwrap(try PlatformListTests.setOff(&listed, a))
        XCTAssertEqual(next.edge, .edge(2))
        XCTAssertEqual(next.end, 9_216, "the list's second platform")
        // One platform the train cannot stop at: the leg's way is automatic.
        var (single, b) = try world(list: false)
        XCTAssertNotEqual(try XCTUnwrap(try PlatformListTests.setOff(&single, b)).end, 9_216)
    }

    /// P3-2: every platform of a list is one a line of real runs calls at
    /// (decision 518), not only the first.
    func testEveryPlatformOfAListIsACallingPlatform() throws {
        var (world, _, line, _) = try LineRoutePreferenceTests.setup(traffic: false)
        try world.addTrackPlatform(SingleTrackMeet.middle, on: .edge(2), from: 2_048, to: 4_096)
        try world.setLineRuns(line, to: [LineRun(from: 0, to: 2, times: [
            LineRunTime(arrival: 21_900, departure: 21_900), LineRunTime(arrival: 22_200, departure: 22_260), LineRunTime(arrival: 22_500, departure: 22_500),
        ])])
        let (loop, far, _) = PlatformListTests.platforms(world)
        try world.setLineRoutePreferences(line, to: [LineRoutePreference(from: 0, to: 1, platform: loop)])
        XCTAssertEqual(world.callingPlatforms(of: SingleTrackMeet.middle), [loop.edge])
        try world.setLineRoutePreferences(line, to: [LineRoutePreference(from: 0, to: 1, platform: loop, alternates: [far])])
        XCTAssertEqual(world.callingPlatforms(of: SingleTrackMeet.middle), [loop.edge, far.edge])
    }

    /// A train bound for a platform outside its leg's list is named with
    /// it, under traffic control only; one bound for a platform of the
    /// list is not.
    func testATrainBoundOutsideItsListIsNamed() throws {
        var (world, line, train) = try PlatformListTests.world(list: false)
        let bound = try XCTUnwrap(try PlatformListTests.setOff(&world, train))
        XCTAssertEqual(bound.end, 4_096, "the near platform, with no list")
        let (loop, far, near) = PlatformListTests.platforms(world)
        XCTAssertNil(world.offListPlatform(of: train), "no list")
        var listed = world
        try listed.setLineRoutePreferences(line, to: [LineRoutePreference(from: 0, to: 1, tracks: LineRoutePreferenceTests.loop(world).tracks, platform: loop, alternates: [far])])
        let off = try XCTUnwrap(listed.offListPlatform(of: train))
        XCTAssertEqual(off.station, SingleTrackMeet.middle)
        XCTAssertEqual(off.platform, near)
        var onList = world
        try onList.setLineRoutePreferences(line, to: [LineRoutePreference(from: 0, to: 1, platform: loop, alternates: [near])])
        XCTAssertNil(onList.offListPlatform(of: train), "the near platform is on this list")
        try listed.setTrafficControl(false)
        XCTAssertNil(listed.offListPlatform(of: train), "only under traffic control")
    }

    /// The most trains of a line its timetables have at a station at once:
    /// none before the train runs, one once it does.
    func testTheMostTrainsAtAStationAtOnceCountsTheLinesTimetables() throws {
        var (world, line, train) = try PlatformListTests.world(list: true)
        XCTAssertEqual(world.mostTrainsAtOnce(at: SingleTrackMeet.middle, line: line), 0)
        _ = try XCTUnwrap(try PlatformListTests.setOff(&world, train))
        XCTAssertEqual(world.mostTrainsAtOnce(at: SingleTrackMeet.middle, line: line), 1)
        XCTAssertEqual(world.mostTrainsAtOnce(at: SingleTrackMeet.middle, line: line, pattern: 3), 0, "no such pattern")
    }
}
