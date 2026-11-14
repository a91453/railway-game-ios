import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Temporary probe (not to be committed): where Hong Kong's lines deadlock.
@MainActor
final class HongKongDeadlockProbeTests: XCTestCase {
    private func hongKong(demo: Bool = false) throws -> GameSession {
        let ground = try HongKongMapTests.ground()
        var world = GameWorld.newOverseasGame(ground, balance: Money(100_000_000_000))
        if demo { world.setUnlimitedFunds(true) }
        try world.mapGround()
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try HongKongRailwaysTests.railways()
        session.population = ground.population
        session.water = ground.water
        session.heights = ground.heights
        session.news.isDemo = demo
        return session
    }

    private func describe(_ session: GameSession, label: String) {
        let world = session.world
        print("PROBE[\(label)] lines:")
        for line in world.lines {
            let stops = line.stops.compactMap { world.station(id: $0) }
            let plat = stops.map { "\($0.name)×\(world.network.platforms(of: $0.id).count)" }.joined(separator: " ")
            print("PROBE[\(label)]   \(line.name) trains=\(line.assignedTrains.count) runs=\(line.runs.count) stops: \(plat)")
        }
    }

    private func run(_ session: GameSession, label: String, minutes: Int) throws {
        var world = session.world
        var firstSeen: [TrainID: Int64] = [:]
        var peak = 0
        var reported = 0
        for minute in 0..<minutes {
            try world.advance(ticks: 1)
            guard minute % 5 == 0 else { continue }
            let stuck = world.deadlockedTrains()
            peak = max(peak, stuck.count)
            let new = stuck.filter { firstSeen[$0] == nil }
            for id in stuck where firstSeen[id] == nil { firstSeen[id] = world.clock.now.seconds }
            if !new.isEmpty, reported < 12 {
                reported += 1
                let clock = world.clock.now.seconds
                print("PROBE[\(label)] day \(clock / 86_400) \(clock % 86_400 / 3_600):\(clock % 3_600 / 60) deadlock \(stuck.count): ")
                for id in stuck {
                    guard let train = world.train(id: id) else { continue }
                    let lineName = world.assignedLine(of: id).flatMap { world.line(id: $0)?.name } ?? "-"
                    let at = train.position.flatMap { world.location(of: $0) }
                    let station = at.flatMap { loc in
                        world.stations.min { a, b in
                            let da = abs(a.location.x - loc.position.plan.x) + abs(a.location.y - loc.position.plan.y)
                            let db = abs(b.location.x - loc.position.plan.x) + abs(b.location.y - loc.position.plan.y)
                            return da < db
                        }?.name
                    } ?? "?"
                    let holder = world.trainHoldingRoute(of: id).flatMap { world.train(id: $0)?.name } ?? "-"
                    let text = world.routeWaitText(of: id, in: .traditionalChinese) ?? "-"
                    let edge = train.position.map { "\($0)" } ?? "-"
                    print("PROBE[\(label)]   \(train.name) [\(lineName)] near \(station) holder=\(holder) | \(text) | pos=\(edge) | exec=\(train.execution != nil) res=\(world.reservedResources(of: id).count)")
                }
            }
        }
        var byLine: [String: Int] = [:]
        for id in world.deadlockedTrains() {
            byLine[world.assignedLine(of: id).flatMap { world.line(id: $0)?.name } ?? "-", default: 0] += 1
        }
        print("PROBE[\(label)] end: peak=\(peak) everStuck=\(firstSeen.count) stuckNow=\(byLine)")
    }

    func testProbeAirportThenDisney() throws {
        let session = try hongKong()
        for id in ["hkmtr:AEL", "hkmtr:DRL"] {
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id })
            let offer = session.realLineOffer(for: line)
            print("PROBE[AEL+DRL] offer \(id) problem=\(offer.problem ?? "nil")")
            XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        }
        describe(session, label: "AEL+DRL")
        try run(session, label: "AEL+DRL", minutes: 2 * 24 * 60)
    }

    func testProbeDisneyAlone() throws {
        let session = try hongKong()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:DRL" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        describe(session, label: "DRL")
        try run(session, label: "DRL", minutes: 2 * 24 * 60)
    }

    func testProbeTseungKwanOAlone() throws {
        let session = try hongKong()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:TKL_LHP" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        describe(session, label: "TKL")
        try run(session, label: "TKL", minutes: 2 * 24 * 60)
    }

    func testProbeLokMaChauAlone() throws {
        let session = try hongKong()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:EAL_LMC" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        describe(session, label: "LMC")
        try run(session, label: "LMC", minutes: 2 * 24 * 60)
    }

    func testProbeAllButTungChung() throws {
        let session = try hongKong()
        for id in ["hkmtr:AEL", "hkmtr:DRL", "hkmtr:EAL_LMC", "hkmtr:SIL", "hkmtr:TKL_LHP"] {
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id })
            let offer = session.realLineOffer(for: line)
            print("PROBE[all] offer \(id) problem=\(offer.problem ?? "nil")")
            XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        }
        describe(session, label: "all")
        try run(session, label: "all", minutes: 2 * 24 * 60)
    }

    func testProbeDemo() async throws {
        let session = try hongKong(demo: true)
        let view = WorldRegion(bounds: session.world.bounds)
        let outcome = await session.layDemoRealLines(in: view, routes: .max, anyWidth: true) { $0.system.id == "hkmtr" }
        print("PROBE[demo] laid \(outcome?.lines ?? -1) missed \(outcome?.missed ?? -1)")
        describe(session, label: "demo")
        try run(session, label: "demo", minutes: 36 * 60)
    }
}
