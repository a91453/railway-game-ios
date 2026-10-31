import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 525: the real-world demo, the high-speed demo and the TRA
/// demo have tourism and the real network's transfers on; the Pingxi
/// challenge, built on the flat real-world demo, keeps its one sight
/// (decision 174) and no transfers (its targets were measured without).
@MainActor
final class DemoSightsAndTransfersTests: XCTestCase {
    /// The transfer points a session with the app's railways gives
    /// `world`'s stations, by name.
    private func transfers(of world: GameWorld) throws -> [String: Int64] {
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        return Dictionary(uniqueKeysWithValues: session.world.stations.filter { $0.transferPoints > 0 }.map { ($0.name, $0.transferPoints) })
    }

    func testTheRealWorldDemoHasItsSightsAndTransfers() throws {
        let world = RealWorldDemo.make(in: .traditionalChinese, railways: try BundledRealData.railways())
        let sights = try XCTUnwrap(world.tourism?.attractions.map(\.name))
        print("real-world demo sights:", sights)
        XCTAssertGreaterThan(sights.count, 1)
        XCTAssertTrue(world.realTransfers)
        let points = try transfers(of: world)
        print("real-world demo transfers:", points.sorted { $0.key < $1.key })
        XCTAssertFalse(points.isEmpty)
    }

    func testTheHighSpeedDemoHasItsSightsAndTransfers() throws {
        let world = try HighSpeedDemoTests.built.get().world
        XCTAssertGreaterThan(world.tourism?.attractions.count ?? 0, 1)
        XCTAssertTrue(world.realTransfers)
        let points = try transfers(of: world)
        print("high-speed demo transfers:", points.sorted { $0.key < $1.key })
        XCTAssertFalse(points.isEmpty)
    }

    func testTheTRADemoHasItsSightsAndTransfers() throws {
        let world = try TRADemoTests.built.get().world
        XCTAssertGreaterThan(world.tourism?.attractions.count ?? 0, 1)
        XCTAssertTrue(world.realTransfers)
        let points = try transfers(of: world)
        print("TRA demo transfers:", points.sorted { $0.key < $1.key })
        XCTAssertFalse(points.isEmpty)
    }

    func testThePingxiChallengeKeepsOneSightAndNoTransfers() throws {
        let world = PingxiChallenge.make(in: .traditionalChinese, railways: try BundledRealData.railways())
        XCTAssertEqual(world.tourism?.attractions.count, 1)
        XCTAssertFalse(world.realTransfers)
        XCTAssertEqual(try transfers(of: world), [:])
    }
}
