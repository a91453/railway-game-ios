import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 557: a line bought before its real depot came with it is
/// offered the depot on its panel, priced and laid as the purchase lays
/// it; reading the save changes nothing.
@MainActor
final class RealLineDepotAdditionTests: XCTestCase {
    /// A game round the Ankeng LRT with it bought as it was before decision
    /// 535 (continued): no depot, its trains overnight at stations between.
    static func ankengBoughtWithoutItsDepot(rules: NewGameRules = .realistic) throws -> (session: GameSession, line: LineID) {
        let session = try RealLineAcquisitionTests.game(round: "ntalrt:K", side: 1 << 21, heights: true, rules: rules)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let old = try RealLineRuns.metroLines(data: Data(contentsOf: root.appendingPathComponent("RealLineFixtures/ankeng-runs-before-depot.json")))
        let current = try XCTUnwrap(session.railways)
        var before = current
        before.metroRuns["ntalrt:K"] = try XCTUnwrap(old["ntalrt:K"])
        session.railways = before
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "ntalrt:K" })
        var (offer, crosses) = session.realLineOffer(for: line, raising: .viaducts, depot: false)
        if crosses { offer = session.realLineOffer(for: line, raising: .viaductsAndShared, depot: false).offer }
        XCTAssertNil(offer.acquisition?.depot)
        XCTAssertTrue(session.acquireRealLine(offer), offer.problem ?? session.message?.text ?? "")
        session.railways = current
        let id = try XCTUnwrap(session.world.acquisition(of: "ntalrt:K")?.line)
        XCTAssertEqual(session.world.line(id: id)?.depots, [])
        return (session, id)
    }

    /// The old line is offered the Ankeng depot; added, it is the line's,
    /// with its seven sidings where the real depot is, and is offered no
    /// more.
    func testAnAnkengLineBoughtWithoutItsDepotIsOfferedIt() throws {
        let (session, id) = try Self.ankengBoughtWithoutItsDepot()
        XCTAssertEqual(session.missingRealDepots(of: id), ["安坑機廠"])
        // Two in the morning: the last train of the day in.
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.advance(ticks: 2 * 60)
            return ""
        })
        session.selectLine(id)
        let offer = try XCTUnwrap(session.selectedLineRealDepotOffer)
        XCTAssertNil(offer.problem, offer.problem ?? "")
        let price = try XCTUnwrap(offer.price)
        FileHandle.standardError.write(Data("Ankeng depot added: \(price.amount) (land \(offer.land?.amount ?? 0)), demolished \(offer.demolished)\n".utf8))
        XCTAssertGreaterThan(price, .zero)
        XCTAssertEqual(offer.buttonTitle(in: .traditionalChinese), "加建安坑機廠")
        let unbuilt = session.world
        let before = session.world.economy.balance
        XCTAssertTrue(session.addRealDepot(offer), session.message?.text ?? "")
        XCTAssertEqual(before - session.world.economy.balance, price)
        // The command log keeps it (decision 193) and replays it alike.
        let command = PlayerCommand.addRealLineDepot(try XCTUnwrap(offer.addition))
        let decoded = try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(decoded, command)
        var replayed = unbuilt
        _ = try session.apply(decoded, to: &replayed)
        XCTAssertEqual(replayed.economy.balance, session.world.economy.balance)
        XCTAssertEqual(replayed.network.edges.count, session.world.network.edges.count)
        XCTAssertEqual(replayed.line(id: id)?.runs, session.world.line(id: id)?.runs)

        let world = session.world
        let depot = try XCTUnwrap(world.stations.first(where: \.isDepot))
        XCTAssertEqual(depot.name, "安坑機廠")
        XCTAssertEqual(world.line(id: id)?.depots, [depot.id])
        XCTAssertEqual(world.network.platforms(of: depot.id).count, RealLineDepotSite.ankeng.sidings)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let real = WorldVector(frame.worldPosition(latitude: 24.943973, longitude: 121.487067))
        XCTAssertLessThan((WorldVector(depot.location) - real).length / RealLineAcquisition.metre, 300)
        XCTAssertEqual(session.missingRealDepots(of: id), [])
        XCTAssertNil(session.selectedLineRealDepotOffer)
    }

    /// By day, with the line's trains out, the card says to add it after
    /// the last train, and nothing is built.
    func testByDayItWaitsForTheLastTrain() throws {
        let (session, id) = try Self.ankengBoughtWithoutItsDepot()
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.advance(ticks: 9 * 60)
            return ""
        })
        session.selectLine(id)
        let offer = try XCTUnwrap(session.selectedLineRealDepotOffer)
        XCTAssertNotNil(offer.addition)
        XCTAssertNotNil(offer.price)
        XCTAssertTrue(offer.waitsForTheLastTrain)
        XCTAssertFalse(offer.canAdd(balance: session.world.economy.balance))
        XCTAssertTrue(offer.summaryText(in: .traditionalChinese).hasSuffix("請在今天末班車收班後加建。"))
        let balance = session.world.economy.balance
        XCTAssertFalse(session.addRealDepot(offer))
        XCTAssertEqual(session.world.economy.balance, balance)
        XCTAssertFalse(session.world.stations.contains(where: \.isDepot))
    }

    /// With traffic control off the old line can leave a train waiting at
    /// a stop for good; after the last train it is taken off its run and
    /// back on the line, so the depot is still added.
    func testAStuckTrainDoesNotHoldItBack() throws {
        let (session, id) = try Self.ankengBoughtWithoutItsDepot(rules: .simple)
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.advance(ticks: 26 * 60)
            return ""
        })
        let trains = try XCTUnwrap(session.world.line(id: id)?.trains)
        let stuck = trains.filter { session.world.train(id: $0)?.execution != nil }
        session.selectLine(id)
        let offer = try XCTUnwrap(session.selectedLineRealDepotOffer)
        XCTAssertFalse(offer.waitsForTheLastTrain)
        XCTAssertTrue(session.addRealDepot(offer), session.message?.text ?? "")
        XCTAssertEqual(session.world.line(id: id)?.trains, trains)
        for train in stuck {
            XCTAssertNil(session.world.train(id: train)?.execution)
        }
        XCTAssertEqual(session.world.line(id: id)?.depots.count, 1)
    }

    /// The card stays open while the game runs (decision 557, continued;
    /// review L7-3): an offer taken in the night and confirmed after the
    /// first train has left is refused, and no train is taken off its run.
    func testAnOfferConfirmedAfterTheFirstTrainWaits() throws {
        let (session, id) = try Self.ankengBoughtWithoutItsDepot(rules: .simple)
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.advance(ticks: 26 * 60)
            return ""
        })
        session.selectLine(id)
        let offer = try XCTUnwrap(session.selectedLineRealDepotOffer)
        XCTAssertFalse(offer.waitsForTheLastTrain)
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.advance(ticks: 6 * 60)
            return ""
        })
        let trains = try XCTUnwrap(session.world.line(id: id)?.trains)
        let running = trains.filter { session.world.train(id: $0)?.execution != nil }
        XCTAssertFalse(running.isEmpty)
        let balance = session.world.economy.balance
        XCTAssertFalse(session.addRealDepot(offer))
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertTrue(session.message?.text.contains("末班車收班後") == true || session.message?.text.contains("last train") == true, session.message?.text ?? "")
        XCTAssertEqual(session.world.economy.balance, balance)
        XCTAssertFalse(session.world.stations.contains(where: \.isDepot))
        XCTAssertEqual(session.world.line(id: id)?.depots, [])
        for train in running {
            XCTAssertNotNil(session.world.train(id: train)?.execution)
        }
    }

    /// Review L7-4: asked for a depot the line does not miss, the offer is
    /// refused rather than reading past the end of an empty list.
    func testAnOfferForNoMissingDepotIsRefused() throws {
        let (session, id) = try Self.ankengBoughtWithoutItsDepot()
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.advance(ticks: 2 * 60)
            return ""
        })
        session.selectLine(id)
        XCTAssertTrue(session.addRealDepot(try XCTUnwrap(session.selectedLineRealDepotOffer)), session.message?.text ?? "")
        XCTAssertEqual(session.missingRealDepots(of: id), [])
        let offer = session.realDepotOffer(for: id, site: "安坑機廠")
        XCTAssertNil(offer.addition)
        XCTAssertNotNil(offer.problem)
        XCTAssertFalse(offer.canAdd(balance: session.world.economy.balance))
        // Confirming the first offer again adds no second depot.
        let balance = session.world.economy.balance
        XCTAssertFalse(session.addRealDepot(offer))
        XCTAssertEqual(session.world.economy.balance, balance)
    }

    /// A line bought with its depot is offered none.
    func testALineBoughtWithItsDepotIsOfferedNone() throws {
        let session = try RealLineAcquisitionTests.game(round: "ntalrt:K", side: 1 << 21, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "ntalrt:K" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let id = try XCTUnwrap(session.world.acquisition(of: "ntalrt:K")?.line)
        XCTAssertEqual(session.missingRealDepots(of: id), [])
        session.selectLine(id)
        XCTAssertNil(session.selectedLineRealDepotOffer)
    }

    /// Off a real-world map no depot is offered, where it could only be
    /// refused: the demo's line recorded as the Green Mountain Line.
    func testNoDepotIsOfferedOffARealWorldMap() throws {
        var world = DemoWorld.make(in: .traditionalChinese)
        let line = try XCTUnwrap(world.lines.first)
        let id = line.id
        let stops = line.stops.count
        try world.setLineRuns(id, to: [LineRun(from: 0, to: stops - 1, times: (0..<stops).map { stop in
            LineRunTime(arrival: Int64(6 * 3_600 + stop * 180), departure: Int64(6 * 3_600 + stop * 180))
        })])
        try world.recordLineAcquisition(line: id, realLine: "ntdlrt:V", dailyRiders: 0, tier: .lightRail)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        XCTAssertEqual(session.missingRealDepots(of: id), [])
    }

    /// Where the line's track past Shuangcheng has been joined on to, the
    /// card says the depot's track has nowhere to start, and adds nothing.
    func testTheCardSaysWhatIsInTheWay() throws {
        let (session, id) = try Self.ankengBoughtWithoutItsDepot()
        let world = session.world
        var reached: [TrackNodeID: Int] = [:]
        for edge in world.network.edges {
            reached[edge.from, default: 0] += 1
            reached[edge.to, default: 0] += 1
        }
        let shuangcheng = try XCTUnwrap(world.stations.first { $0.name == "雙城" })
        let ends = world.network.nodes.filter { reached[$0.id] == 1 && (WorldVector($0.position.plan) - WorldVector(shuangcheng.location)).length <= RealLineDepotAddition.endReach }
        XCTAssertFalse(ends.isEmpty)
        // Each end joined on to track running on 700 m, so none is left.
        let away = (WorldVector(ends[0].position.plan) - WorldVector(shuangcheng.location)).unit
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            for end in ends {
                let far = WorldVector(end.position.plan) + away * (700 * RealLineAcquisition.metre)
                let node = try world.buildTrackNode(at: WorldCoordinate(x: far.plan.x, y: far.plan.y, z: end.position.z))
                _ = try world.buildTrackEdge(from: end.id, to: node, structure: .automatic)
            }
            return ""
        }, session.message?.text ?? "")
        session.selectLine(id)
        let offer = try XCTUnwrap(session.selectedLineRealDepotOffer)
        XCTAssertNil(offer.addition)
        XCTAssertEqual(offer.summaryText(in: .traditionalChinese), "雙城過去的軌道已經接了別的軌道，機廠的入出庫線沒有地方接。")
        let balance = session.world.economy.balance
        XCTAssertFalse(session.addRealDepot(offer))
        XCTAssertEqual(session.world.economy.balance, balance)
        XCTAssertFalse(session.world.stations.contains(where: \.isDepot))
    }

    /// Added after the old line runs, the depot takes its trains in and
    /// sends them out, and two real days run as the line bought with it
    /// does: no run of the second day left unsent that the line bought
    /// with it sends.
    func testTheOldLineWithItsDepotAddedRunsTwoRealDays() throws {
        func missed(_ world: GameWorld) throws -> (missed: Int, runs: Int, deadlocked: Int) {
            var world = world
            var deadlocked = 0
            for _ in 0..<51 {
                try world.advance(ticks: 60)
                deadlocked = max(deadlocked, world.deadlockedTrains().count)
            }
            let today = world.clock.now.seconds / GameTime.secondsPerDay
            var missed = 0, runs = 0
            for line in world.lines where line.hasRuns {
                let yesterday = zip(line.runs, line.runDays).filter { run, _ in run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 }
                runs += yesterday.count
                missed += yesterday.count { _, day in (day ?? -1) < today - 1 }
            }
            return (missed, runs, deadlocked)
        }
        // A day of the old line, the depot added at two in the morning,
        // after the last train.
        let (session, id) = try Self.ankengBoughtWithoutItsDepot()
        XCTAssertTrue(session.perform { (world: inout GameWorld) throws(GameError) in
            try world.advance(ticks: 26 * 60)
            return ""
        })
        session.selectLine(id)
        let offer = try XCTUnwrap(session.selectedLineRealDepotOffer)
        XCTAssertFalse(offer.waitsForTheLastTrain)
        XCTAssertTrue(session.addRealDepot(offer), session.message?.text ?? "")
        let added = try missed(session.world)
        let bought = try missed(DepotReturnReportTests.bought("ntalrt:K", rules: .realistic))
        FileHandle.standardError.write(Data("Ankeng two days: depot added \(added), bought with it \(bought)\n".utf8))
        XCTAssertLessThanOrEqual(added.missed, bought.missed)
        XCTAssertEqual(added.deadlocked, 0)
    }
}
