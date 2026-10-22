import Foundation
@testable import GameCore
import XCTest

/// Dispatch patterns (ARCHITECTURE decision 309; TestFlight 77.1 #1): a
/// line's two trains leave its two ends together, or the second a few
/// minutes after the first, instead of only one headway apart.
///
/// `FlexDispatchTests`' line: Alpha and Gamma four links apart on a
/// straight track, planned at a crawl (a link a minute), so a round trip is
/// 11 minutes; with two trains the line runs one every 6 minutes.
final class DispatchPatternTests: XCTestCase {
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let one = TrainID(rawValue: 1)
    private let two = TrainID(rawValue: 2)
    private let crawl = TrainPerformance(acceleration: 125, braking: 100, topSpeed: 1)

    private func makeWorld(trains count: Int = 2, secondAtGamma: Bool = false, flex: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 0), speed: .normal)
        )
        world.setFlexDispatch(flex)
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [alpha, gamma])
        try world.setLinePerformance(main, to: crawl)
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: count, offPeak: count, low: count))
        for index in 1...count {
            let train = try world.purchaseTrain(named: "T\(index)")
            let atGamma = secondAtGamma && index == 2
            try world.placeTrain(train.id, at: atGamma ? line.at(5, facingEast: false) : line.at(1, facingEast: true))
            try world.setTrainMovementRate(train.id, to: 1024)
            try world.assignTrain(train.id, to: main)
        }
        return world
    }

    /// One train sent out: when, from where, and whether empty.
    private struct Dispatch: Equatable, CustomStringConvertible {
        let train: Int
        let minute: Int64
        let from: StationID
        let empty: Bool
        var description: String { "T\(train) \(minute) from \(from.rawValue)\(empty ? " empty" : "")" }
    }

    /// Every train sent out in the next `minutes`, a tick at a time.
    private func dispatches(_ world: inout GameWorld, minutes: Int) throws -> [Dispatch] {
        var sent: [Dispatch] = []
        for _ in 0..<minutes {
            let before = world.trains
            try world.advance(ticks: 1)
            for train in world.trains {
                guard let first = train.timetable.first, first.arrival != before.first(where: { $0.id == train.id })?.timetable.first?.arrival
                      || before.first(where: { $0.id == train.id })?.execution == nil && train.execution != nil
                else { continue }
                sent.append(Dispatch(train: Int(train.id.rawValue), minute: first.arrival.seconds / 60, from: first.station, empty: train.isDeadheading))
            }
        }
        return sent
    }

    // MARK: - Even

    /// Even, as every line before decision 309: the second train waits a
    /// headway at Alpha, and later trains keep 6 minutes apart.
    func testEvenSendsTheSecondTrainAHeadwayLater() throws {
        var world = try makeWorld()
        XCTAssertEqual(world.line(id: main)?.dispatchPattern, .even)
        XCTAssertEqual(world.lineHeadway(main, at: .peak), 6)
        let sent = try dispatches(&world, minutes: 30)
        XCTAssertEqual(Array(sent.prefix(4)), [
            Dispatch(train: 1, minute: 0, from: alpha, empty: false),
            Dispatch(train: 2, minute: 6, from: alpha, empty: false),
            Dispatch(train: 1, minute: 12, from: alpha, empty: false),
            Dispatch(train: 2, minute: 18, from: alpha, empty: false),
        ])
    }

    /// Even, a train standing at the last stop takes the same slot as the
    /// first stop's (decision 172): it too waits a headway.
    func testEvenMakesATrainAtTheLastStopWaitAHeadway() throws {
        var world = try makeWorld(secondAtGamma: true)
        let sent = try dispatches(&world, minutes: 7)
        XCTAssertEqual(sent, [
            Dispatch(train: 1, minute: 0, from: alpha, empty: false),
            Dispatch(train: 2, minute: 6, from: gamma, empty: false),
        ])
    }

    // MARK: - From both ends

    /// From both ends, each end keeps its own clock: a train at Gamma
    /// leaves at once beside the one at Alpha, and each comes back to its
    /// own end and goes again a round trip later.
    func testBothEndsSendTheirTrainsTogether() throws {
        var world = try makeWorld(secondAtGamma: true)
        try world.setLineDispatchPattern(main, to: .fromBothEnds)
        let sent = try dispatches(&world, minutes: 30)
        XCTAssertEqual(Array(sent.prefix(4)), [
            Dispatch(train: 1, minute: 0, from: alpha, empty: false),
            Dispatch(train: 2, minute: 0, from: gamma, empty: false),
            Dispatch(train: 1, minute: 12, from: alpha, empty: false),
            Dispatch(train: 2, minute: 12, from: gamma, empty: false),
        ])
        XCTAssertEqual(world.line(id: main)?.lastDispatch, GameTime(minutes: 24))
        XCTAssertEqual(world.line(id: main)?.endLastDispatch, GameTime(minutes: 24))
    }

    /// Both trains at Alpha: the first goes in service, the second runs
    /// empty to Gamma, the end's share, and leaves from there as soon as it
    /// arrives. From then on the two ends send their trains together.
    func testBothEndsTakeASecondTrainToTheLastStop() throws {
        var world = try makeWorld()
        try world.setLineDispatchPattern(main, to: .fromBothEnds)
        let sent = try dispatches(&world, minutes: 40)
        XCTAssertEqual(sent.first, Dispatch(train: 1, minute: 0, from: alpha, empty: false))
        XCTAssertEqual(sent.dropFirst().first, Dispatch(train: 2, minute: 0, from: alpha, empty: true), "in the same step")
        let fromGamma = sent.filter { $0.from == gamma }
        let fromAlpha = sent.filter { $0.from == alpha && !$0.empty }
        XCTAssertEqual(fromGamma.map(\.train), Array(repeating: 2, count: fromGamma.count), "the second train keeps to Gamma")
        XCTAssertEqual(fromAlpha.map(\.train), Array(repeating: 1, count: fromAlpha.count), "the first keeps to Alpha")
        XCTAssertGreaterThanOrEqual(fromGamma.count, 2)
    }

    /// Without flexible dispatch nothing is sent out from the last stop, so
    /// the pattern cannot be set; a world that turns it off later runs the
    /// line evenly.
    func testBothEndsNeedFlexibleDispatch() throws {
        var world = try makeWorld(flex: false)
        XCTAssertThrowsError(try world.setLineDispatchPattern(main, to: .fromBothEnds)) {
            XCTAssertEqual($0 as? GameError, .invalidDispatchPattern)
        }
        var later = try makeWorld()
        try later.setLineDispatchPattern(main, to: .fromBothEnds)
        later.setFlexDispatch(false)
        var even = try makeWorld()
        even.setFlexDispatch(false)
        XCTAssertEqual(try dispatches(&later, minutes: 30), try dispatches(&even, minutes: 30))
    }

    // MARK: - Staggered

    /// Staggered by 2 minutes: the second train follows the first 2
    /// minutes later, and the next pair leaves two headways after the
    /// first of this one.
    func testStaggeredSendsTheSecondTrainTheStaggerLater() throws {
        var world = try makeWorld()
        try world.setLineDispatchPattern(main, to: .staggered(minutes: 2))
        let sent = try dispatches(&world, minutes: 30)
        XCTAssertEqual(Array(sent.prefix(4)), [
            Dispatch(train: 1, minute: 0, from: alpha, empty: false),
            Dispatch(train: 2, minute: 2, from: alpha, empty: false),
            Dispatch(train: 1, minute: 12, from: alpha, empty: false),
            Dispatch(train: 2, minute: 14, from: alpha, empty: false),
        ])
    }

    /// The gaps: the stagger, kept to at least the least headway and at
    /// most a headway, and the rest of two headways.
    func testTheStaggerGaps() {
        XCTAssertEqual(GameWorld.staggerGaps(2, headway: 6).short, 2)
        XCTAssertEqual(GameWorld.staggerGaps(2, headway: 6).long, 10)
        XCTAssertEqual(GameWorld.staggerGaps(10, headway: 6).short, 2, "past the headway it is the other train's stagger")
        XCTAssertEqual(GameWorld.staggerGaps(30, headway: 6).short, 2)
        XCTAssertEqual(GameWorld.staggerGaps(6, headway: 6).long, 6, "a headway apart is even")
    }

    /// One train has no pair: it runs as it would evenly.
    func testOneTrainRunsAsEven() throws {
        var staggered = try makeWorld(trains: 1)
        try staggered.setLineDispatchPattern(main, to: .staggered(minutes: 3))
        var even = try makeWorld(trains: 1)
        XCTAssertEqual(try dispatches(&staggered, minutes: 40), try dispatches(&even, minutes: 40))
    }

    // MARK: - The command

    func testTheCommandRejectsWhatNoLineCanHave() throws {
        var world = try makeWorld()
        for minutes: Int64 in [0, 1, 31] {
            XCTAssertThrowsError(try world.setLineDispatchPattern(main, to: .staggered(minutes: minutes))) {
                XCTAssertEqual($0 as? GameError, .invalidDispatchPattern)
            }
        }
        XCTAssertThrowsError(try world.setLineDispatchPattern(LineID(rawValue: 9), to: .even)) {
            XCTAssertEqual($0 as? GameError, .unknownLine(LineID(rawValue: 9)))
        }
        try world.setLineDispatchPattern(main, to: .staggered(minutes: 30))
        XCTAssertEqual(world.line(id: main)?.dispatchPattern, .staggered(minutes: 30))
        try world.setLineDispatchPattern(main, to: .even)
        XCTAssertEqual(world.line(id: main)?.dispatchPattern, .even)
    }

    /// A line made a ring spaces its trains evenly (a ring has no other
    /// pattern), so its save loads: before, a staggered line made a ring
    /// kept its stagger and the save was refused.
    func testALineMadeARingSpacesItsTrainsEvenly() throws {
        for pattern in [DispatchPattern.fromBothEnds, .staggered(minutes: 5)] {
            var world = try makeWorld(secondAtGamma: true)
            try world.setLineDispatchPattern(main, to: pattern)
            try world.advance(ticks: 20)
            try world.setLineStops(main, to: [alpha, StationID(rawValue: 2), gamma])
            try world.setLineRing(main, to: true)
            let ring = try XCTUnwrap(world.line(id: main))
            XCTAssertEqual(ring.dispatchPattern, .even, "\(pattern)")
            XCTAssertNil(ring.endLastDispatch, "\(pattern)")
            XCTAssertFalse(ring.opensPair, "\(pattern)")
            XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "\(pattern)")
        }
    }

    /// A line given runs sends its trains at their times, so it spaces them
    /// evenly from then on and keeps no other pattern: taking the runs away
    /// does not bring an old pattern back (A8 of the #873–#910 review).
    func testALineGivenRunsSpacesItsTrainsEvenly() throws {
        let runs = [LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 600, departure: 600), LineRunTime(arrival: 1_800, departure: 1_800)])]
        for pattern in [DispatchPattern.fromBothEnds, .staggered(minutes: 5)] {
            var world = try makeWorld(secondAtGamma: true)
            try world.setLineDispatchPattern(main, to: pattern)
            try world.setLineRuns(main, to: runs)
            var given = try XCTUnwrap(world.line(id: main))
            XCTAssertEqual(given.dispatchPattern, .even, "\(pattern)")
            XCTAssertNil(given.endLastDispatch, "\(pattern)")
            XCTAssertFalse(given.opensPair, "\(pattern)")
            try world.setLineRuns(main, to: [])
            given = try XCTUnwrap(world.line(id: main))
            XCTAssertEqual(given.dispatchPattern, .even, "\(pattern)")
        }
    }

    /// A save from before A8 whose line has runs and another pattern (a
    /// pattern set before the runs were) loads, spacing the line's trains
    /// evenly: the pattern never sent a train out while the runs were
    /// there.
    func testASavedLineWithRunsAndAnotherPatternLoadsEven() throws {
        var world = try makeWorld(secondAtGamma: true)
        try world.setLineRuns(main, to: [LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 600, departure: 600), LineRunTime(arrival: 1_800, departure: 1_800)])])
        let data = try JSONEncoder().encode(world)
        for (pattern, opensPair) in [(["kind": "staggered", "minutes": 5] as [String: Any], true), (["kind": "fromBothEnds"], false)] {
            var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            var lines = try XCTUnwrap(object["lines"] as? [[String: Any]])
            lines[0]["dispatchPattern"] = pattern
            if opensPair { lines[0]["opensPair"] = true } else { lines[0]["endLastDispatch"] = 0 }
            object["lines"] = lines
            let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(loaded, world, "\(pattern)")
        }
    }

    /// Fast-forwarding past idle minutes sends the same trains at the same
    /// times as a tick at a time, for each pattern.
    func testLongBatchesMatchSingleTicks() throws {
        for pattern in [DispatchPattern.fromBothEnds, .staggered(minutes: 3)] {
            var batch = try makeWorld()
            try batch.setLineDispatchPattern(main, to: pattern)
            var single = batch
            try batch.advance(ticks: 90)
            for _ in 0..<90 { try single.advance(ticks: 1) }
            XCTAssertEqual(batch, single, "\(pattern)")
        }
    }

    // MARK: - Saves

    /// A line's pattern and its ends' clocks are written only when they are
    /// not the default, and what no line can have is refused.
    func testTheSaveRefusesWhatNoLineCanHave() throws {
        var world = try makeWorld(secondAtGamma: true)
        try world.setLineDispatchPattern(main, to: .fromBothEnds)
        try world.advance(ticks: 1)
        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        func decodes(_ edit: (inout [String: Any]) -> Void) -> Bool {
            guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            var lines = object["lines"] as? [[String: Any]] ?? []
            edit(&lines[0])
            object["lines"] = lines
            guard let edited = try? JSONSerialization.data(withJSONObject: object) else { return false }
            return (try? JSONDecoder().decode(GameWorld.self, from: edited)) != nil
        }
        XCTAssertTrue(decodes { _ in })
        XCTAssertFalse(decodes { $0["dispatchPattern"] = ["kind": "even"] }, "even is not written")
        XCTAssertFalse(decodes { $0["dispatchPattern"] = nil }, "only both ends have the last stop's clock")
        XCTAssertFalse(decodes { $0["endLastDispatch"] = 120 * 60 }, "not after the clock")
        XCTAssertFalse(decodes { $0["dispatchPattern"] = ["kind": "staggered", "minutes": 31]; $0["endLastDispatch"] = nil })
        XCTAssertTrue(decodes { $0["dispatchPattern"] = ["kind": "staggered", "minutes": 5]; $0["endLastDispatch"] = nil; $0["opensPair"] = true })
        XCTAssertFalse(decodes { $0["opensPair"] = true }, "only a staggered line has a pair")
        XCTAssertFalse(decodes { $0["dispatchPattern"] = ["kind": "fromBothEnds", "minutes": 5] })
        XCTAssertFalse(decodes { $0["dispatchPattern"] = ["kind": "evenly"] })
        XCTAssertFalse(decodes { $0["dispatchPattern"] = ["kind": "staggered", "minutes": 5]; $0["endLastDispatch"] = nil; $0["opensPair"] = false })
    }

    /// Version 65 (decision 309): Main runs from both ends, its trains sent
    /// out from Alpha and Gamma together at 0:00 and 0:12, saved at 0:15
    /// with each end's last dispatch; it saves byte for byte and is the world this build
    /// makes.
    func testVersionSixtyFiveKeepsTheDispatchPattern() throws {
        var world = try makeWorld(secondAtGamma: true)
        try world.setLineDispatchPattern(main, to: .fromBothEnds)
        try world.advance(ticks: 15)

        let url = SavedGameTests.fixtures.appendingPathComponent("v65-dispatch-pattern.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["DISPATCH_PATTERN_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 65)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.line(id: main)?.dispatchPattern, .fromBothEnds)
        XCTAssertEqual(loaded.line(id: main)?.endLastDispatch, GameTime(minutes: 12))
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 65,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }
}
