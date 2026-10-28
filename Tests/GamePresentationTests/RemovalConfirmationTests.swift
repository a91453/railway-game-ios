import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// UI review 2026-10-28, A: a removal made from a panel while the game runs
/// cannot be undone once a tick passes, so the panels confirm it first.
@MainActor
final class RemovalConfirmationTests: XCTestCase {
    /// Why the panels confirm: any tick empties Undo (decision 82), and
    /// the panels do not pause the game as the building tools do.
    func testATickTakesAwayTheUndoOfAPanelsRemoval() throws {
        var world = try makeWorld(width: 6_144, height: 3_072, balance: 100_000)
        let line = TestLine(tiles: 5, row: 1)
        try line.build(in: &world)
        let alpha = try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        let session = GameSession(world: world)
        session.addStopToSelectedTrainTimetable(alpha)
        session.setSpeed(.x1)
        session.advance(ticks: 1)

        session.clearSelectedTrainTimetable()
        XCTAssertEqual(session.selectedTrain?.timetable, [])
        XCTAssertTrue(session.canUndo)
        session.advance(ticks: 1)
        XCTAssertFalse(session.canUndo, "a tick empties Undo: the confirmation is the only guard")
    }

    /// The building tool pauses a running game (decision 99), so its
    /// one-tap demolish can still be undone after the clock would have
    /// moved on.
    func testDemolishingWithTheBuildingToolCanBeUndone() throws {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480), language: .english)
        session.setSpeed(.x1)
        session.selectTool(.building)
        XCTAssertTrue(session.world.clock.isPaused)
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000)))
        session.buildingMode = .demolish
        let built = session.world
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 0))
        session.advance(realElapsed: GameSession.tickInterval)
        XCTAssertTrue(session.canUndo)
        session.undo()
        XCTAssertEqual(session.world.placedBuildings, built.placedBuildings)
    }

    /// Every panel removal the review found taken in one tap is now made
    /// only from a confirmation (`removalConfirmation`, a
    /// `confirmationDialog`): the call sits in its closure, a few lines
    /// after it opens.
    func testEveryPanelRemovalIsMadeFromAConfirmation() throws {
        let calls = [
            "clearSelectedTrainTimetable()", "removeNetworkPlatform(", "removeFreightYardAtSelectedStation()",
            "removeSelectedStationDemand()", "unlinkSelectedStationTransfer()", "removePatternFromSelectedLine(",
            "removeStopFromSelectedLine(", "resetServiceDay()",
        ]
        let views = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("RailwayGameApp/Views")
        let files = ["TimetableEditor.swift", "StationPanel.swift", "LinesPanel.swift"]
        var found: [String: Int] = [:]
        for file in files {
            let lines = try String(contentsOf: views.appendingPathComponent(file), encoding: .utf8)
                .components(separatedBy: "\n")
            for (index, text) in lines.enumerated() {
                for call in calls where text.contains("session.\(call)") {
                    found[call, default: 0] += 1
                    let before = lines[max(0, index - 4)..<index]
                    XCTAssertTrue(
                        before.contains { $0.contains(".confirmationDialog(") || $0.contains(".removalConfirmation(") },
                        "\(file):\(index + 1) \(call) is made without a confirmation"
                    )
                }
            }
        }
        XCTAssertEqual(Set(found.keys), Set(calls), "each removal is still in these panels")
    }

    func testTheConfirmationsNameWhatTheyDoInBothLanguages() {
        let all: [RemovalConfirmation] = [
            .clearTimetable(train: "T1"), .removePlatform(number: 2), .removeFreightYard, .removeRidership,
            .leaveTransferGroup, .removePattern(title: "Express"), .removeStop(station: "Alpha"), .standardDay,
        ]
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertEqual(Set(all.map { $0.title(in: language) }).count, all.count)
            XCTAssertEqual(Set(all.map { $0.button(in: language) }).count, all.count)
        }
        XCTAssertEqual(RemovalConfirmation.clearTimetable(train: "T1").title(in: .traditionalChinese), "清空 T1 的時刻表？")
        XCTAssertEqual(RemovalConfirmation.removePlatform(number: 2).button(in: .english), "Remove Platform 2")
        XCTAssertEqual(RemovalConfirmation.removePlatform(number: 2).button(in: .traditionalChinese), "拆除第 2 月台")
        XCTAssertEqual(RemovalConfirmation.removeStop(station: "Alpha").title(in: .english), "Remove Alpha from the line?")
        XCTAssertNil(RemovalConfirmation.leaveTransferGroup.message(in: .english))
        XCTAssertEqual(RemovalConfirmation.standardDay.message(in: .traditionalChinese), "你切分或調整過的時段都會刪除。")
    }
}
