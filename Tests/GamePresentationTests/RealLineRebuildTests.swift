import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 605 (third part): a Taoyuan Airport MRT bought as it was before
/// its expresses and Chang Gung's loops came is offered the rebuild from
/// its panel, and told what stops it where it cannot be done.
@MainActor
final class RealLineRebuildTests: XCTestCase {
    static let id = "tymc:A"

    /// The line bought from the timetable as it was before decision 605:
    /// every train stopping everywhere, two tracks at Chang Gung. A new
    /// game opens at midnight, before the first train: the line at rest.
    static func boughtAsBefore(rules: NewGameRules = .realistic) throws -> (session: GameSession, line: LineID) {
        let session = try RealLineAcquisitionTests.game(round: id, side: 1 << 22, heights: true, rules: rules)
        let current = try XCTUnwrap(session.railways)
        var before = current
        before.metroRuns[id] = try XCTUnwrap(current.metroRuns[id]).stoppingEverywhere()
        session.railways = before
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, "on sale")
        let offer = session.realLineOffer(for: line)
        XCTAssertTrue(session.acquireRealLine(offer), offer.problem ?? session.message?.text ?? "")
        session.railways = current
        let bought = try XCTUnwrap(session.world.acquisition(of: id)?.line)
        XCTAssertFalse(try XCTUnwrap(session.world.line(id: bought)).runs.contains { !$0.passes.isEmpty })
        return (session, bought)
    }

    /// Laid before decision 605, Chang Gung's track is level only along
    /// its platforms (112 m) and climbs at some 25 to 38‰ beyond them up
    /// to the turn-back crossovers. The rebuild lays the station's stretch
    /// again as the purchase lays it now: level 150 m either way, a loop
    /// outside each platform, the crossovers beyond, joined to the track
    /// kept; the line's route goes to the new platforms and its expresses
    /// run.
    func testALineBoughtBeforeIsRebuiltAsReal() throws {
        let (session, id) = try Self.boughtAsBefore()
        let station = try XCTUnwrap(session.world.line(id: id)?.stops.first { session.world.station(id: $0)?.name == "長庚醫院站" })
        XCTAssertEqual(session.world.network.platforms(of: station).count, 2)
        let trains = try XCTUnwrap(session.world.line(id: id)?.trains)
        let runCount = try XCTUnwrap(session.world.line(id: id)?.runs.count)

        session.selectLine(id)
        XCTAssertTrue(session.rebuildsAsReal(id))
        let offer = try XCTUnwrap(session.selectedLineRealRebuildOffer)
        XCTAssertNil(offer.problem, offer.problem ?? "")
        XCTAssertFalse(offer.waitsForTheLastTrain)
        let rebuild = try XCTUnwrap(offer.rebuild)
        let price = try XCTUnwrap(offer.price)
        XCTAssertGreaterThan(price, .zero)
        let relaid = try XCTUnwrap(offer.relaid)
        XCTAssertGreaterThan(relaid, 680)
        XCTAssertLessThan(relaid, 1_600)
        XCTAssertTrue(offer.summaryText(in: .traditionalChinese).hasPrefix("長庚醫院站前後 \(relaid) 公尺的軌道重鋪成平的"), offer.summaryText(in: .traditionalChinese))
        XCTAssertTrue(offer.canRebuild(balance: session.world.economy.balance))
        XCTAssertEqual(RealLineRebuildOffer.buttonTitle(in: .traditionalChinese), "照真實改建")

        let balance = session.world.economy.balance
        XCTAssertTrue(session.rebuildRealLine(offer), session.message?.text ?? "")
        XCTAssertEqual(session.world.economy.balance, balance - price)
        let platforms = session.world.network.platforms(of: station)
        XCTAssertEqual(platforms.count, 4)
        // Every platform level, and the turnouts either side on the level.
        for platform in platforms {
            let geometry = try XCTUnwrap(session.world.trackGeometry(of: platform.edge))
            XCTAssertEqual(geometry.startHeight, geometry.endHeight)
        }
        let line = try XCTUnwrap(session.world.line(id: id))
        XCTAssertEqual(line.trains, trains)
        XCTAssertEqual(line.runs, rebuild.runs)
        // The same runs as before, the expresses now passing; the
        // timetable's positioning runs stay left out, as the purchase
        // leaves them out with its depot laid.
        XCTAssertEqual(line.runs.count, runCount)
        XCTAssertTrue(line.runs.contains { !$0.passes.isEmpty })
        let routed = line.routePreferences.filter { $0.platform.station == station }
        XCTAssertFalse(routed.isEmpty)
        XCTAssertTrue(routed.allSatisfy { platforms.contains($0.platform) })
        // Nothing left to rebuild, and the command log replays it.
        XCTAssertNil(session.realRebuildOffer(for: id)?.rebuild)
        let encoded = try JSONEncoder().encode(PlayerCommand.rebuildRealLine(rebuild))
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: encoded), .rebuildRealLine(rebuild))
    }

    /// Where something of the company's other than a building stands where
    /// the new track goes, the card names the station and what is in the
    /// way, and the button changes nothing.
    func testItSaysWhatStandsInTheWay() throws {
        let (session, id) = try Self.boughtAsBefore()
        let station = try XCTUnwrap(session.world.line(id: id)?.stops.first { session.world.station(id: $0)?.name == "長庚醫院站" })
        session.selectLine(id)
        let clear = try XCTUnwrap(session.selectedLineRealRebuildOffer?.rebuild)
        // A track of the player's where the middle of the first loop goes.
        let loop = clear.pieces[2]
        let first = loop.nodes[loop.nodes.count / 2 - 1], second = loop.nodes[loop.nodes.count / 2]
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            let a = try world.buildTrackNode(at: first)
            let b = try world.buildTrackNode(at: second)
            _ = try world.buildTrackEdge(from: a, to: b, curve: .straight, structure: .automatic)
            return ""
        }, session.message?.text ?? "")

        let offer = try XCTUnwrap(session.selectedLineRealRebuildOffer)
        XCTAssertNil(offer.rebuild)
        let problem = try XCTUnwrap(offer.problem)
        XCTAssertTrue(problem.hasPrefix("長庚醫院站改建不了：月台外側的待避線："), problem)
        XCTAssertFalse(offer.canRebuild(balance: session.world.economy.balance))

        let before = session.world
        XCTAssertFalse(session.rebuildRealLine(offer))
        XCTAssertEqual(session.message?.text, problem)
        XCTAssertEqual(session.world.economy.balance, before.economy.balance)
        XCTAssertEqual(session.world.network.platforms(of: station).count, 2)
    }

    /// Decision 605 (continued): whether a line is at rest counts only the
    /// runs carrying riders, on the days they run. The Taoyuan Airport
    /// MRT's empty runs keep its trains moving all night; counted, its
    /// last train is never in.
    func testOnlyTheRunsWithRidersOnTheirDaysKeepALineBusy() throws {
        let (session, id) = try Self.boughtAsBefore()
        var line = try XCTUnwrap(session.world.line(id: id))
        let railways = try XCTUnwrap(session.railways)
        let real = try XCTUnwrap(railways.metroRuns[Self.id])
        let runs = real.runs.map { $0.lineRun(stops: real.stops, reversed: true) }
        let positioning = Set(zip(real.runs, runs).filter { $0.0.positioning }.map { RealLineRunKey($0.1) })
        XCTAssertFalse(positioning.isEmpty)
        line.runs = []
        // Every minute of a week, the runs with riders leave some night
        // free; the empty ones fill every one.
        var free = 0
        for minute in stride(from: Int64(0), to: 7 * 24 * 60, by: 5) {
            let now = GameTime.secondsPerDay + minute * 60
            XCTAssertFalse(RealLineDepotAddition.isAtRest(line, runs: runs, at: now))
            if RealLineDepotAddition.isAtRest(line, runs: runs, positioning: positioning, at: now) { free += 1 }
        }
        XCTAssertGreaterThan(free, 7 * 12 * 3)
        // A weekday's run does not keep a weekend busy.
        let day = (1...7).first { StationDemand.weekday(ofDay: Int64($0)) == 0 }.map(Int64.init) ?? 0
        let weekdays = LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 36_000, departure: 36_000), LineRunTime(arrival: 36_600, departure: 36_600)], days: 0b0111110)
        XCTAssertTrue(RealLineDepotAddition.isAtRest(line, runs: [weekdays], at: day * GameTime.secondsPerDay + 36_300))
        XCTAssertFalse(RealLineDepotAddition.isAtRest(line, runs: [weekdays], at: (day + 1) * GameTime.secondsPerDay + 36_300))
    }

    /// While the line's trains run, the card says to wait for the last.
    func testItWaitsForTheLastTrain() throws {
        // Bought at midnight, before the first train: at rest. At 06:30
        // its trains are out.
        let (session, id) = try Self.boughtAsBefore()
        session.selectLine(id)
        XCTAssertEqual(session.selectedLineRealRebuildOffer?.waitsForTheLastTrain, false)
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.advance(ticks: 6 * 60 + 30)
            return ""
        })
        let offer = try XCTUnwrap(session.selectedLineRealRebuildOffer)
        XCTAssertTrue(offer.waitsForTheLastTrain)
        XCTAssertFalse(offer.canRebuild(balance: session.world.economy.balance))
        XCTAssertFalse(session.rebuildRealLine(offer))
    }

    /// Decision 605 (continued): a train still out on a late run when the
    /// line is rebuilt is taken off it where it stands. Left there, between
    /// the ends, it took the next run from that station, one a line bought
    /// now has no train for, and the west end had no room for the train it
    /// sent there: under a new game's rules the whole line stood still from
    /// 07:30 (the release report `tymc-rebuilt`, 333 of 333 runs not sent
    /// out on its second day). It goes to a free depot track instead, of
    /// the nearest depot first; a train already in a depot stays.
    func testATrainTakenOffBetweenTheEndsGoesToADepot() throws {
        let (session, id) = try Self.boughtAsBefore(rules: .simple)
        var world = session.world
        let line = try XCTUnwrap(world.line(id: id))
        let sanchong = try XCTUnwrap(line.stops.first { world.station(id: $0)?.name == "三重站" })
        let luzhu = try XCTUnwrap(line.depots.first { world.station(id: $0)?.name == "蘆竹機廠" })
        let inDepots = line.trains.filter { !Set(world.stationsStoppedAt(by: $0)).isDisjoint(with: line.depots) }
        XCTAssertGreaterThan(inDepots.count, 2)
        let train = inDepots[0], staying = inDepots[1]
        let stayingAt = try XCTUnwrap(world.train(id: staying)).position
        let platform = try XCTUnwrap(world.trackPlatforms(of: sanchong).first)
        let length = try XCTUnwrap(world.train(id: train)).length
        try world.unassignTrain(train)
        try world.unplaceTrain(train)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: platform.edge, direction: .forward), offset: platform.start + length))
        try world.setTrainContinuation(train, along: [], stoppingAt: platform.start + length)
        XCTAssertEqual(world.stationsStoppedAt(by: train), [sanchong])

        try GameSession.berthInDepots([train, staying], of: line, in: &world)
        XCTAssertEqual(world.stationsStoppedAt(by: train), [luzhu])
        XCTAssertEqual(world.train(id: train)?.movement.rate, 512)
        XCTAssertEqual(world.train(id: staying)?.position, stayingAt)
        // Not on a track another train stands on.
        func edges(_ train: Train) -> [TrackEdgeID] {
            guard case .onEdge(let traversal, _)? = train.position else { return [] }
            return [traversal.edge] + train.trailEdges
        }
        let berth = try XCTUnwrap(world.train(id: train)).position
        let edge = try XCTUnwrap(world.train(id: train).flatMap(edges)?.first, "\(String(describing: berth))")
        XCTAssertFalse(world.trains.contains { $0.id != train && edges($0).contains(edge) })
        try world.assignTrain(train, to: id)
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))))
    }

    /// A line bought now has its loops: nothing to rebuild.
    func testALineBoughtNowHasNothingToRebuild() throws {
        let session = try RealLineAcquisitionTests.game(round: Self.id, side: 1 << 22, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id }, "on sale")
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let id = try XCTUnwrap(session.world.acquisition(of: Self.id)?.line)
        XCTAssertNil(session.realRebuildOffer(for: id))
    }
}
