import GameCore
import GamePresentation
import XCTest

/// Picking a train on the map: the train drawn nearest a tap, by its head or
/// its body; a tap that picks one selects it for the train tool and shows
/// it in the select tool's inspector, but a station's mark right under the
/// finger still selects the station.
///
/// On the demo map at minute 0, Train 1 waits at West on Line 1's ground
/// track: its head 4 tiles west of Central, its four cars back to 8 tiles
/// west, over West's point 6 tiles west.
final class TrainPickingTests: XCTestCase {
    // The test layout's spacing: 1024 units, 16 m (the world has no cells).
    private static let tile = Int64(1_024)

    private static func point(_ x: Int64, _ y: Int64, in world: GameWorld) -> PlanPoint {
        let central = world.stations[1].location
        return PlanPoint(x: central.x + x, y: central.y + y)
    }

    func testTheNearestTrainWithinReachIsPicked() throws {
        let world = DemoWorld.make(in: .english)
        let train1 = world.trains[0].id
        let head = try XCTUnwrap(world.train(id: train1)?.position.flatMap { world.location(of: $0) })
        XCTAssertEqual(head.position.plan, Self.point(-4 * Self.tile, 0, in: world))

        XCTAssertEqual(world.train(near: head.position.plan, within: 0), train1, "on its head")
        XCTAssertEqual(world.train(near: Self.point(-7 * Self.tile, 300, in: world), within: 400), train1, "beside its body")
        XCTAssertNil(world.train(near: Self.point(-7 * Self.tile, 300, in: world), within: 299), "out of reach")
        XCTAssertNil(world.train(near: Self.point(0, 5 * Self.tile, in: world), within: Self.tile), "nothing there")
        XCTAssertNil(world.train(near: head.position.plan, within: -1))

        XCTAssertEqual(world.trainSummary(of: train1, in: .english), "Train · Train 1 · Stopped at West · Line 1")
        XCTAssertEqual(world.trainSummary(of: train1, in: .traditionalChinese), "列車 · Train 1 · 停在 West · Line 1", "the English demo's names")
        XCTAssertNil(world.trainSummary(of: TrainID(rawValue: 99), in: .english))
    }

    /// With the select tool, a tap on a train selects it and the inspector
    /// shows it, letting go of the station; a tap on West's mark, which the
    /// train's body passes over, selects West. With the train tool, a tap
    /// on a train makes it the train to send and keeps the station picked
    /// to send it to.
    func testATapSelectsATrainUnlessAStationIsUnderTheFinger() async throws {
        await MainActor.run {
            let session = GameSession(world: DemoWorld.make(in: .english))
            let world = session.world
            let (train1, train2) = (world.trains[0].id, world.trains[1].id)
            let reach = Self.tile
            session.selectTool(.select)

            session.tapMap(at: Self.point(-6 * Self.tile, 0, in: world), reach: reach)
            XCTAssertEqual(session.selectedStation?.name, "West", "the station under the finger")
            XCTAssertNil(session.tappedTrainID)

            session.tapMap(at: Self.point(-4 * Self.tile, 100, in: world), reach: reach)
            XCTAssertEqual(session.tappedTrainID, train1)
            XCTAssertEqual(session.selectedTrainID, train1)
            XCTAssertNil(session.selectedStation, "the select tool lets go of the station")
            XCTAssertNil(session.selectedPoint)
            XCTAssertEqual(session.selectionText(), "Train · Train 1 · Stopped at West · Line 1")

            session.clearSelection()
            XCTAssertNil(session.tappedTrainID)

            // The train tool: pick East to send a train to, then Train 2.
            session.selectTool(.train)
            session.selectStation(world.stations[2].id)
            let train2Head = world.train(id: train2)!.position.flatMap { world.location(of: $0) }!.position.plan
            session.tapMap(at: train2Head, reach: reach)
            XCTAssertEqual(session.selectedTrainID, train2)
            XCTAssertEqual(session.selectedStation?.name, "East", "the train tool keeps where it sends the train")
            XCTAssertEqual(session.selectionText()?.hasPrefix("Station · East"), true)
        }
    }
}
