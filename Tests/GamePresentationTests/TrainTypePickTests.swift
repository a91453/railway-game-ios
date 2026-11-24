import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// TRAIN-TYPE-PICK (the author's report on TestFlight 145). Decision 959:
/// the train types change the train they were opened for, not the train
/// selected when the choice is made. Decision 960: a train on the track
/// and a line that runs change type; a type is bought from the fleet.
@MainActor
final class TrainTypePickTests: XCTestCase {
    func testTheTypeChangesTheTrainNamedNotTheSelectedOne() throws {
        let session = GameSession(world: GameWorld.newGame(balance: Money(100_000_000_000)), language: .traditionalChinese)
        session.purchaseTrain()
        let first = try XCTUnwrap(session.selectedTrain?.id)
        session.purchaseTrain()
        let second = try XCTUnwrap(session.selectedTrain?.id)
        XCTAssertNotEqual(first, second)
        session.setTrainType(first, to: .emu100)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.train(id: first)?.type, .emu100)
        XCTAssertNil(session.world.train(id: second)?.type)
        XCTAssertTrue(session.message?.text.contains(try XCTUnwrap(session.world.train(id: first)?.name)) == true)
        // Back to the standard car, the same train.
        session.setTrainType(first, to: nil)
        XCTAssertNil(session.world.train(id: first)?.type)
    }
    /// The Pingxi Line bought, on a real-world map: its line.
    private func pingxi() throws -> (GameSession, LineID) {
        let session = try RealLineAcquisitionTests.game(round: "PINGXI")
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == "PINGXI" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        return (session, try XCTUnwrap(session.world.acquisition(of: "tra:PINGXI")?.line))
    }

    private func waitingTrain(of line: LineID, in session: GameSession) throws -> TrainID {
        try XCTUnwrap(session.world.line(id: line)?.assignedTrains.first {
            session.world.train(id: $0)?.execution == nil && session.world.train(id: $0)?.position != nil
        })
    }

    // MARK: Decision 960

    func testATrainOnALineChangesTypeAndStaysOnIt() throws {
        let (session, line) = try pingxi()
        let id = try waitingTrain(of: line, in: session)
        let before = try XCTUnwrap(session.world.train(id: id))
        let edits = session.undoCount
        session.changeTrainType(id, to: .r100ChuKuang)
        let train = try XCTUnwrap(session.world.train(id: id))
        XCTAssertEqual(train.type, .r100ChuKuang, session.message?.text ?? "")
        XCTAssertEqual(train.cars, before.cars)
        XCTAssertEqual(train.position, before.position, "where it stood")
        XCTAssertEqual(session.world.assignedLine(of: id), line)
        XCTAssertEqual(session.undoCount, edits + 1, "one edit")
    }

    func testATrainOnNoLineChangesTypeWhereItStands() throws {
        let (session, line) = try pingxi()
        let id = try waitingTrain(of: line, in: session)
        session.unassignTrain(id)
        let position = try XCTUnwrap(session.world.train(id: id)?.position)
        session.changeTrainType(id, to: .blueTrain)
        XCTAssertEqual(session.world.train(id: id)?.type, .blueTrain, session.message?.text ?? "")
        XCTAssertEqual(session.world.train(id: id)?.position, position)
        XCTAssertNil(session.world.assignedLine(of: id))
    }

    /// A train on a trip is left as it is, and the message says when.
    func testATrainOnATripIsNotChanged() throws {
        let (session, line) = try pingxi()
        session.setSpeed(.x1)
        var running: Train?
        for _ in 0..<1440 where running == nil {
            session.advance(ticks: 600)
            running = session.world.line(id: line)?.assignedTrains.compactMap(session.world.train(id:)).first { $0.execution != nil }
        }
        let train = try XCTUnwrap(running, "a train sets off")
        session.changeTrainType(train.id, to: .blueTrain)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.world.train(id: train.id)?.type, train.type)
    }

    /// A line that runs changes its trains' type, each keeping its cars.
    func testALineThatRunsChangesItsTrainsKeepingTheirCars() throws {
        let (session, line) = try pingxi()
        session.selectLine(line)
        let before = try XCTUnwrap(session.world.line(id: line)?.assignedTrains).compactMap { session.world.train(id: $0) }
        XCTAssertFalse(try XCTUnwrap(session.world.line(id: line)).trains.isEmpty, "its own service runs")
        session.reformSelectedLine(type: .blueTrain, cars: nil)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        for train in before where train.execution == nil {
            XCTAssertEqual(session.world.train(id: train.id)?.type, .blueTrain, session.message?.text ?? "")
            XCTAssertEqual(session.world.train(id: train.id)?.cars, train.cars)
            XCTAssertEqual(session.world.assignedLine(of: train.id), line)
        }
    }

    func testATypeIsBoughtFromTheTrainTypes() throws {
        let session = GameSession(world: GameWorld.newGame(balance: Money(100_000_000_000)), language: .traditionalChinese)
        let balance = session.world.economy.balance
        session.purchaseTrain(of: .e500ChuKuang, cars: 4)
        let train = try XCTUnwrap(session.selectedTrain)
        XCTAssertEqual(train.type, .e500ChuKuang, session.message?.text ?? "")
        XCTAssertEqual(train.cars, 4)
        XCTAssertNil(train.position)
        XCTAssertEqual(train.performance, .e500ChuKuang)
        XCTAssertLessThan(session.world.economy.balance, balance)
        XCTAssertEqual(session.undoCount, 1, "one edit")
    }

    // MARK: Decision 960, buy first, assign later

    func testABoughtTrainIsAssignedToALineFromTheFleet() throws {
        let (session, line) = try pingxi()
        session.purchaseTrain(of: nil, cars: 1)
        XCTAssertTrue(session.message?.text.contains("到車隊總覽把它配屬到路線") == true, session.message?.text ?? "")
        let id = try XCTUnwrap(session.selectedTrain?.id)
        XCTAssertNil(session.world.train(id: id)?.position)
        XCTAssertTrue(session.offersAssignToLine(for: id))
        XCTAssertTrue(session.assignToLineChoices(for: id).contains { $0.id == line })
        let edits = session.undoCount
        session.assignUnplacedTrain(id, to: line)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertNotNil(session.world.train(id: id)?.position, "on the track")
        XCTAssertEqual(session.world.assignedLine(of: id), line)
        XCTAssertEqual(session.undoCount, edits + 1, "one edit")
        XCTAssertFalse(session.offersAssignToLine(for: id))
    }

    func testATrainTooLongForTheLineStaysInTheFleet() throws {
        let (session, line) = try pingxi()
        session.purchaseTrain(of: nil, cars: Train.maximumCars)
        let id = try XCTUnwrap(session.selectedTrain?.id)
        let edits = session.undoCount
        session.assignUnplacedTrain(id, to: line)
        XCTAssertEqual(session.message?.kind, .failure, session.message?.text ?? "")
        XCTAssertTrue(session.message?.text.contains("減少節數就停得下") == true, session.message?.text ?? "")
        XCTAssertNil(session.world.train(id: id)?.position, "still off the track")
        XCTAssertNil(session.world.assignedLine(of: id), "not assigned")
        XCTAssertEqual(session.undoCount, edits, "nothing changed")
    }
}
