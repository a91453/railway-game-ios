import GameCore
@testable import GamePresentation
import XCTest

/// Decision 224 (1C): the promotion line and the score train.
final class PromotionLineTests: XCTestCase {
    func testTheTrainStandsAtTheTitleHeldAsFarAsTheScoreHasCome() {
        let rank = CompanyRank(world: DemoWorld.make(in: .english))
        let line = PromotionLine(rank: rank)
        XCTAssertEqual(line.titles, CompanyTitle.allCases)
        let index = Double(CompanyTitle.allCases.firstIndex(of: rank.title)!)
        XCTAssertGreaterThanOrEqual(line.position, index)
        XCTAssertLessThanOrEqual(line.position, index + 1)
        XCTAssertTrue(line.isReached(0))
        XCTAssertTrue(line.isReached(Int(index)))
        XCTAssertFalse(line.isReached(Int(index) + 2))
    }

    func testTheProgressBetweenTwoTitles() {
        let title = CompanyTitle.stationClerk
        let next = title.next!
        XCTAssertEqual(StationMasterTitleProgress.progress(score: title.minimumScore, title: title), 0)
        XCTAssertEqual(StationMasterTitleProgress.progress(score: (title.minimumScore + next.minimumScore) / 2, title: title), 0.5, accuracy: 0.02)
        XCTAssertEqual(StationMasterTitleProgress.progress(score: 1_000, title: .tycoon), 1)
    }

    func testACarFillsItsSquaresAsFarAsItsPointsGo() {
        let rank = CompanyRank(world: DemoWorld.make(in: .english))
        for part in rank.parts {
            let filled = part.filledCells(of: 6)
            XCTAssertTrue((0...6).contains(filled))
            XCTAssertEqual(filled == 0, part.points == 0)
            if part.points == part.maximum { XCTAssertEqual(filled, 6) }
        }
    }
}
