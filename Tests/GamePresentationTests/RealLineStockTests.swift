import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 536, the author's question of 2026-11-01: a real line bought
/// kept none of its own trains: the TRA branch lines' were drawn as a
/// three-car urban EMU, the Danhai light rail's as the green tram. Now
/// they are drawn, and named, as the line's own stock, as before they were
/// bought, and so is a train put on the line later.
@MainActor
final class RealLineStockTests: XCTestCase {
    /// Each line on sale, the set its trains are drawn as: the one its
    /// trains are drawn as before it is bought.
    func testEachLineOnSaleKeepsItsOwnStock() {
        let expected: [String: String] = [
            "tra:PINGXI": "dieselRailcar", "tra:JIJI": "dieselRailcar", "tra:NEIWAN": "dieselRailcar", "tra:SHENAO": "dieselRailcar",
            "tra:LIUJIA": "emu800", "tra:SHALUN": "emu800",
            "ntdlrt:V": "danhaiLRT", "ntdlrt:VB": "danhaiLRT", "ntalrt:K": "ankengLRT",
            "trtc:R_XBT": "metroC371", "trtc:G_XBT": "metroC371", "trtc:BR": "wenhu", "sanying:LB": Map3DTrainSet.sanyingKey,
        ]
        for (line, key) in expected {
            XCTAssertEqual(RealLineStock.setKey(ofRealLine: line), key, line)
            XCTAssertNotNil(Map3DTrainSet.named(key), "\(line): \(key) has a set")
            XCTAssertNotNil(RealLineStock.lineName(ofSet: key, in: .traditionalChinese), "\(line): \(key) has a name")
        }
        XCTAssertNil(RealLineStock.setKey(ofRealLine: "bus"))
    }

    /// The Neiwan Line bought: its three-car trains are DR1000s, three
    /// cars and all, not the urban EMU nor the DR3100; and so is a train
    /// put on it afterwards. Its cards say so.
    func testTheNeiwanLineRunsItsDR1000s() throws {
        let world = try bought("tra:NEIWAN", round: "NEIWAN")
        try check(world, line: "tra:NEIWAN", key: "dieselRailcar", set: "dieselRailcar", train: "DR1000 柴油客車", row: "DR1000 柴油客車")
    }

    /// The Danhai light rail's Green Mountain Line bought: its own trains,
    /// not the green tram.
    func testTheDanhaiLineRunsItsOwnTrains() throws {
        let world = try bought("ntdlrt:V", round: "ntdlrt:V")
        try check(world, line: "ntdlrt:V", key: "danhaiLRT", set: "danhaiLRT", train: "淡海輕軌列車", row: "淡海輕軌列車")
    }

    private func bought(_ id: String, round: String) throws -> GameWorld {
        let session = try RealLineAcquisitionTests.game(round: round, side: 1 << 21)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, "\(id) on sale")
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        // A train bought later and put on the line, standing where its
        // first train does.
        var world = session.world
        let lineID = try XCTUnwrap(world.acquisition(of: id)?.line)
        let first = try XCTUnwrap(world.line(id: lineID)?.assignedTrains.first)
        let cars = try XCTUnwrap(world.train(id: first)).cars
        let later = try world.purchaseTrain(named: "Later").id
        try world.setTrainCars(later, to: cars)
        try world.assignTrain(later, to: lineID)
        return world
    }

    private func check(_ world: GameWorld, line id: String, key: String, set: String, train: String, row: String) throws {
        let lineID = try XCTUnwrap(world.acquisition(of: id)?.line)
        let trains = try XCTUnwrap(world.line(id: lineID)?.assignedTrains)
        XCTAssertGreaterThan(trains.count, 1)
        let keys = RealLineStock.setKeys(in: world)
        let heights = Map3DTrains.Heights(world: world)
        for train in trains {
            XCTAssertEqual(keys[train], key, "\(id): train \(train.rawValue)")
            let cars = try XCTUnwrap(world.train(id: train)).cars
            let drawn = Map3DTrainSet.set(forKey: Map3DTrainSet.variant(of: keys[train] ?? "", number: train.rawValue), count: cars)
            XCTAssertEqual(drawn?.key, set, "\(id): train \(train.rawValue), \(cars) cars")
            if world.train(id: train)?.position != nil { XCTAssertEqual(heights.type(of: train), key) }
        }
        XCTAssertEqual(world.boughtStockText(of: trains[0], in: .traditionalChinese), train)
        XCTAssertTrue(world.lineTrainsRowText(lineID, in: .traditionalChinese).contains(row), world.lineTrainsRowText(lineID, in: .traditionalChinese))
        // A train of no line bought is not named.
        let own = world.trains.first { !trains.contains($0.id) }
        if let own { XCTAssertNil(world.boughtStockText(of: own.id, in: .traditionalChinese)) }
    }
}

/// Decision 536's screenshot scene builds: its two bought lines' trains
/// on the track, drawn as their real lines' stock.
@MainActor
final class RealLineStockSceneTests: XCTestCase {
    func testTheAcquiredSceneDrawsTheRealStock() throws {
        let world = ScreenshotScene.acquired.make(in: .traditionalChinese)
        let keys = RealLineStock.setKeys(in: world)
        for (real, key) in zip(ScreenshotScene.acquiredLines, ["dieselRailcar", "danhaiLRT"]) {
            let line = try XCTUnwrap(world.acquisition(of: real)?.line, real)
            let trains = try XCTUnwrap(world.line(id: line)?.assignedTrains)
            XCTAssertFalse(trains.isEmpty, real)
            XCTAssertTrue(trains.contains { world.train(id: $0)?.position != nil }, "\(real): a train on the track")
            for train in trains { XCTAssertEqual(keys[train], key, real) }
        }
    }
}
