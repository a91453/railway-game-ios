import Foundation
@testable import GameCore
import XCTest

/// Saves written before #955 in the two states it now prevents (PR #945–#961
/// review): 79.1 let a player make a staggered line a ring, or lose a
/// bought line with its stations, and saved games that would not load.
/// Reading them repairs them.
final class BrokenSaveRepairTests: XCTestCase {
    private let line = TestLine(tiles: 7)
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)

    /// `object` with the first dictionary on each branch that `body`
    /// changes (returns `true` for) changed.
    private func patch(_ object: Any, _ body: (inout [String: Any]) -> Bool) -> Any {
        if var dict = object as? [String: Any] {
            if body(&dict) { return dict }
            for (key, value) in dict { dict[key] = patch(value, body) }
            return dict
        }
        if let array = object as? [Any] { return array.map { patch($0, body) } }
        return object
    }

    /// A ring with a stagger loads spacing its trains evenly.
    func testAStaggeredRingSavedBefore955Loads() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts))
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.setLineRing(main, to: true)
        let stagger = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DispatchPattern.staggered(minutes: 5)), options: .fragmentsAllowed)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(world))
        let broken = patch(json) { dict in
            guard dict["ring"] as? Bool == true else { return false }
            dict["dispatchPattern"] = stagger
            return true
        }
        let data = try JSONSerialization.data(withJSONObject: broken)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.line(id: main)?.dispatchPattern, .even)
    }

    /// A bought line's asset left behind by its line loads without it; the
    /// purchase stays recorded.
    func testABoughtLineRemovedWithItsStationsSavedBefore955Loads() throws {
        var world = try GameWorld(bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 10_000_000, costs: testCosts))
        world.setEconomyMode(.management)
        world.setSpeed(.normal)
        try world.advance(ticks: 300)
        try line.build(in: &world)
        try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.setLineServiceWindow(main, to: .allDay)
        let blue = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(blue, at: line.at(1, facingEast: true))
        try world.setTrainMovementRate(blue, to: 1_024)
        try world.assignTrain(blue, to: main)
        try world.setLineRuns(main, to: [LineRun(from: 0, to: 2, times: [
            LineRunTime(arrival: 22_200, departure: 22_200), LineRunTime(arrival: 22_500, departure: 22_560), LineRunTime(arrival: 22_800, departure: 22_800),
        ])])
        try world.recordLineAcquisition(line: main, realLine: "tra:PINGXI", dailyRiders: 2)
        var assets: Any?
        _ = patch(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world))) { dict in
            guard let found = dict["assets"] else { return false }
            assets = found
            return true
        }
        try world.removeStation(beta)
        try world.removeStation(gamma)
        let broken = patch(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world))) { dict in
            guard let now = dict["assets"] as? [Any] else { return false }
            let line = ((assets as? [Any]) ?? []).filter { ($0 as? [String: Any])?["kind"] as? String == "acquiredLine" }
            XCTAssertEqual(line.count, 1)
            dict["assets"] = now + line
            return true
        }
        let data = try JSONSerialization.data(withJSONObject: broken)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
        XCTAssertEqual(loaded, world)
        XCTAssertFalse(loaded.accounts.assets.contains { $0.kind == .acquiredLine })
        XCTAssertEqual(loaded.acquisitions.map(\.realLine), ["tra:PINGXI"])
    }
}
