import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

@MainActor
final class HKProbeTests: XCTestCase {
    private func hongKong(demo: Bool = false) throws -> GameSession {
        let ground = try HongKongMapTests.ground()
        var world = GameWorld.newOverseasGame(ground, balance: Money(100_000_000_000))
        if demo { world.setUnlimitedFunds(true) }
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try HongKongRailwaysTests.railways()
        session.population = ground.population
        session.news.isDemo = demo
        return session
    }

    func testProbeAlone() throws {
        let ids = try hongKong().buyableRealLines.map(\.id).sorted()
        for id in ids {
            let session = try hongKong()
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id })
            let offer = session.realLineOffer(for: line)
            let ok = offer.problem == nil && session.acquireRealLine(offer)
            print("PROBE alone \(id): \(ok) \(offer.problem ?? "") price \(offer.acquisition.map { "\($0)".count } ?? 0)")
        }
    }

    func testProbeOrders() throws {
        let ids = try hongKong().buyableRealLines.map(\.id).sorted()
        for order in [ids, Array(ids.reversed())] {
            let session = try hongKong()
            for id in order {
                guard let line = session.buyableRealLines.first(where: { $0.id == id }) else { print("PROBE seq \(id): not on sale"); continue }
                let offer = session.realLineOffer(for: line)
                let ok = offer.problem == nil && session.acquireRealLine(offer)
                print("PROBE seq \(id): \(ok) \(offer.problem ?? session.message?.text ?? "")")
            }
        }
    }

    func testProbeRuns() throws {
        for id in ["hkmtr:TCL", "hkmtr:SIL", "hkmtr:DRL", "hkmtr:EAL_LMC", "hkmtr:TKL_LHP"] {
            let session = try hongKong()
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id })
            guard session.acquireRealLine(session.realLineOffer(for: line)) else { print("PROBE run \(id): not bought"); continue }
            var played = session.world
            let bought = try XCTUnwrap(played.acquisition(of: id))
            for _ in 0..<51 { try played.advance(ticks: 60) }
            let ran = try XCTUnwrap(played.line(id: try XCTUnwrap(bought.line)))
            let today = played.clock.now.seconds / GameTime.secondsPerDay
            let missed = zip(ran.runs, ran.runDays).enumerated().filter { _, pair in
                pair.0.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (pair.1 ?? -1) < today - 1
            }
            print("PROBE run \(id): missed \(missed.count) of \(ran.runs.count) trains \(ran.assignedTrains.count) fare \(played.accounts.days.last?.fareRevenue.amount ?? 0) first missed \(missed.prefix(6).map { "\($0.offset)" })")
        }
    }
}
