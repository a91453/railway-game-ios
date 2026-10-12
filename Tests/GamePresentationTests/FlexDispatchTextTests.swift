import GameCore
import GamePresentation
import XCTest

/// Decision 172: the notice an edit of a line gives about what becomes of
/// its trains, and the follow bar's word for an empty run.
@MainActor
final class FlexDispatchTextTests: XCTestCase {
    private let line = TestLine(tiles: 7, row: 1)

    private func makeLineWorld() throws -> (world: GameWorld, main: LineID, train: TrainID, stops: [StationID]) {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        world.setFlexDispatch(true)
        try line.build(in: &world)
        let alpha = try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let beta = try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        let gamma = try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let main = try world.createLine(named: "Main", stops: [alpha, beta, gamma]).id
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.assignTrain(train.id, to: main)
        return (world, main, train.id, [alpha, beta, gamma])
    }

    func testTakingOutTheFirstStopSaysWhereTheTrainGoes() throws {
        let (world, main, _, _) = try makeLineWorld()
        let session = GameSession(world: world, language: .english)
        session.selectLine(main)
        session.removeStopFromSelectedLine(at: 0)
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Main now calls at Beta – Gamma. 1 train runs empty to Beta."))

        let chinese = GameSession(world: world, language: .traditionalChinese)
        chinese.selectLine(main)
        chinese.removeStopFromSelectedLine(at: 0)
        XCTAssertEqual(chinese.message, StatusMessage(kind: .success, text: "Main 改停 Beta – Gamma。1 列車空車回送到 Beta。"))
    }

    func testWithoutFlexibleDispatchNothingIsAdded() throws {
        var (world, main, _, _) = try makeLineWorld()
        world.setFlexDispatch(false)
        let session = GameSession(world: world, language: .english)
        session.selectLine(main)
        session.removeStopFromSelectedLine(at: 0)
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Main now calls at Beta – Gamma."))
    }

    func testAnEditThatChangesNothingSaysNothingMore() throws {
        let (world, main, _, _) = try makeLineWorld()
        let session = GameSession(world: world, language: .english)
        session.selectLine(main)
        session.removeStopFromSelectedLine(at: 2)
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Main now calls at Alpha – Beta."))
    }

    func testReversingTellsTheTrainsThatTurnAroundAtTheNewEnd() throws {
        let (world, main, _, _) = try makeLineWorld()
        let session = GameSession(world: world, language: .english)
        session.selectLine(main)
        session.reverseSelectedLine()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Reversed Main: Gamma – Beta – Alpha. 1 train sets out from Alpha, now the last stop, once its trip is over, running back first."))
    }

    func testTheFollowBarSaysRunningEmpty() throws {
        var (world, main, train, stops) = try makeLineWorld()
        try world.setLineStops(main, to: [stops[1], stops[2]])
        try world.advance(ticks: 1)
        XCTAssertTrue(try XCTUnwrap(world.train(id: train)).isDeadheading)
        let info = try XCTUnwrap(world.followBarInfo(of: train, in: .english))
        XCTAssertEqual(info.status, .deadheading)
        XCTAssertTrue(info.detail(in: .english).hasSuffix("· Running empty"), info.detail(in: .english))
        XCTAssertEqual(FollowBarInfo.Status.deadheading.text(in: .traditionalChinese), "回送中")
    }
}
