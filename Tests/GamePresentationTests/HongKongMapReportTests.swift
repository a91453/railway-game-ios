import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 712: what Hong Kong's map costs to open and to play, measured
/// only when asked (`HK_MAP_REPORT=1`): reading the pack, laying out the
/// world, buying every line on sale, a save's size, a tick, and the
/// process's memory.
@MainActor
final class HongKongMapReportTests: XCTestCase {
    func testWhatTheMapCosts() throws {
        guard ProcessInfo.processInfo.environment["HK_MAP_REPORT"] != nil else {
            throw XCTSkip("Set HK_MAP_REPORT=1 to measure Hong Kong's map.")
        }
        func resident() -> Int {
            ((try? String(contentsOfFile: "/proc/self/status", encoding: .utf8)) ?? "")
                .split(separator: "\n").first { $0.hasPrefix("VmRSS") }
                .flatMap { Int($0.split(separator: " ").dropFirst().first ?? "") }.map { $0 / 1_024 } ?? 0
        }
        func timed<Value>(_ work: () throws -> Value) rethrows -> (Value, Double) {
            let start = Date()
            let value = try work()
            return (value, Date().timeIntervalSince(start) * 1_000)
        }
        var rows: [String] = []
        let before = resident()
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.hongKong))
        let (taiwan, taiwanTime) = timed { RealRailways.load(overseas: [], pack: HongKongRailwaysTests.pack) { try BundledRealData.file($0, $1) } }
        let afterTaiwan = resident()
        let (loaded, bothTime) = timed { RealRailways.load(overseas: [.hongKong], pack: HongKongRailwaysTests.pack) { try BundledRealData.file($0, $1) } }
        rows.append("| read the railways, Taiwan alone | \(Int(taiwanTime)) ms | \(afterTaiwan - before) MB |")
        rows.append("| read the railways, Taiwan and Hong Kong | \(Int(bothTime)) ms | \(resident() - afterTaiwan) MB |")
        XCTAssertNotNil(taiwan.railways)
        let (ground, groundTime) = try timed { try OverseasGround(city: .hongKong, pack: pack) }
        rows.append("| read the pack's extent and people | \(Int(groundTime)) ms | |")
        let half = RealWorldFrame.halfExtent(of: ground.bounds)
        rows.append("| the map | \(Int(half.east * 2)) m by \(Int(half.south * 2)) m | |")
        let (world, worldTime) = timed { GameWorld.newOverseasGame(ground, balance: Money(100_000_000_000)) }
        rows.append("| lay out the world | \(Int(worldTime)) ms | |")
        let (empty, emptyTime) = try timed { try JSONEncoder().encode(SavedGame(world: world)) }
        rows.append("| a new game's save | \(empty.count) bytes | \(Int(emptyTime)) ms to write |")
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try XCTUnwrap(loaded.railways)
        session.population = ground.population
        for id in session.buyableRealLines.map(\.id).sorted() {
            guard let line = session.buyableRealLines.first(where: { $0.id == id }) else { continue }
            let (offer, offerTime) = timed { session.realLineOffer(for: line) }
            let (bought, buyTime) = timed { offer.problem == nil && session.acquireRealLine(offer) }
            rows.append("| buy \(id) | laid out in \(Int(offerTime)) ms, built in \(Int(buyTime)) ms | \(bought ? "bought" : "refused: \(offer.problem ?? session.message?.text ?? "")") |")
        }
        var played = session.world
        rows.append("| after buying | \(played.stations.count) stations, \(played.trains.count) trains, \(played.land.cells.count) land cells, \(played.land.cells.reduce(0) { $0 + $1.residents }) residents | \(resident()) MB resident |")
        let (saved, savedTime) = try timed { try JSONEncoder().encode(SavedGame(world: played)) }
        let (_, readTime) = try timed { try JSONDecoder().decode(SavedGame.self, from: saved) }
        rows.append("| its save | \(saved.count) bytes | \(Int(savedTime)) ms to write, \(Int(readTime)) ms to read |")
        var ticks: [Double] = []
        for _ in 0..<(24 * 6) {
            let (_, time) = try timed { try played.advance(ticks: 1) }
            ticks.append(time)
        }
        ticks.sort()
        rows.append("| a day of ticks at 600× (144) | median \(String(format: "%.1f", ticks[ticks.count / 2])) ms, p95 \(String(format: "%.1f", ticks[ticks.count * 95 / 100])) ms, most \(String(format: "%.1f", ticks.last ?? 0)) ms | \(resident()) MB resident |")
        print("HK_MAP_REPORT\n| what | measured | |\n| --- | --- | --- |\n" + rows.joined(separator: "\n"))
    }
}
