import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 959 (TRAIN-TYPE-PICK, the author's report on TestFlight 145):
/// the train types change the train they were opened for, not the train
/// selected when the choice is made.
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
}
