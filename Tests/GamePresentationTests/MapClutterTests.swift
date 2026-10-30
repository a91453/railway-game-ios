import GameCore
@testable import GamePresentation
import XCTest

/// Decision 510 (a player's report: too much over the map, easy to tap by
/// mistake): which sights the map marks at a zoom, how the warnings are
/// put together, and which taps a sight's mark leaves to the map.
final class MapClutterTests: XCTestCase {
    private static func bubble(_ kind: MapAlert.Kind, station: Int?, at x: Int64 = 0) -> MapMarks.Bubble {
        MapMarks.Bubble(
            alert: MapAlert(kind: kind, station: station.map { StationID(rawValue: $0) }, location: PlanPoint(x: x, y: 0)),
            lineName: nil, trainName: nil, sight: nil, waitReason: nil
        )
    }

    // MARK: - Sights

    func testSightsHideFromFarShowAStarInTheMiddleAndTheirRatingCloseUp() {
        XCTAssertEqual(MapClutter.sightStyle(referenceSize: 0.2), .none)
        XCTAssertEqual(MapClutter.sightStyle(referenceSize: MapProblems.mediumFrom), .star)
        XCTAssertEqual(MapClutter.sightStyle(referenceSize: MapScale.overviewBelow - 0.01), .star)
        XCTAssertEqual(MapClutter.sightStyle(referenceSize: MapScale.overviewBelow), .rated)
        XCTAssertEqual(MapClutter.sightStyle(referenceSize: MapScale.largestSize), .rated)
    }

    /// Stars alone are narrower, so more of them show side by side.
    func testAStarAloneMakesRoomForMoreMarks() {
        let marks = (0..<4).map { SightMarks.Mark(id: AttractionID(rawValue: $0), stars: 300, x: Double($0) * 36, y: 100) }
        XCTAssertEqual(SightMarks.shown(marks).count, 2)
        XCTAssertEqual(SightMarks.shown(marks, width: MapClutter.starWidth, height: MapClutter.starHeight).count, 4)
    }

    func testAStationsTapWinsOverASightBesideIt() {
        let sight = ScreenPoint(x: 100, y: 100)
        XCTAssertFalse(MapClutter.sightTakesTouch(at: sight, stations: [ScreenPoint(x: 110, y: 110)], bubbles: [], onTrack: false))
        XCTAssertTrue(MapClutter.sightTakesTouch(at: sight, stations: [ScreenPoint(x: 100 + MapClutter.stationGuard, y: 100)],
                                                 bubbles: [], onTrack: false))
        XCTAssertTrue(MapClutter.sightTakesTouch(at: sight, stations: [], bubbles: [], onTrack: false))
    }

    func testATracksTapWinsOverASightOnIt() {
        XCTAssertFalse(MapClutter.sightTakesTouch(at: ScreenPoint(x: 0, y: 0), stations: [], bubbles: [], onTrack: true))
    }

    func testABubbleTakesTheTapOverASight() {
        let over = MapLabelPlacement.Box(x: 90, y: 60, width: 80, height: 44)
        let away = MapLabelPlacement.Box(x: 300, y: 60, width: 80, height: 44)
        XCTAssertFalse(MapClutter.sightTakesTouch(at: ScreenPoint(x: 100, y: 100), stations: [], bubbles: [over], onTrack: false))
        XCTAssertTrue(MapClutter.sightTakesTouch(at: ScreenPoint(x: 100, y: 100), stations: [], bubbles: [away], onTrack: false))
    }

    // MARK: - Warnings

    func testOneBubblePerStationNamingTheMostUrgent() {
        let alerts = [
            Self.bubble(.lineLosingMoney(LineID(rawValue: 1)), station: 1),
            Self.bubble(.full(waiting: 900), station: 1),
            Self.bubble(.materialsShort, station: 2),
        ]
        let (onMap, folded) = MapClutter.arrange(alerts, markedSights: [], limit: 5)
        XCTAssertEqual(onMap.count, 2)
        XCTAssertEqual(onMap[0].top.alert.kind, .full(waiting: 900))
        XCTAssertEqual(onMap[0].more, 1)
        XCTAssertEqual(onMap[1].top.alert.kind, .materialsShort)
        XCTAssertEqual(onMap[1].more, 0)
        // The one the bubble does not name is behind the badge.
        XCTAssertEqual(folded.map(\.alert.kind), [.lineLosingMoney(LineID(rawValue: 1))])
    }

    func testAFewBubblesOnTheMapTheMostUrgentFirstTheRestBehindTheBadge() {
        let alerts = (1...6).map { Self.bubble(.materialsShort, station: $0) }
            + [Self.bubble(.trainStuck(TrainID(rawValue: 1)), station: nil, at: 500),
               Self.bubble(.insolvency(days: 3), station: 7)]
        let (onMap, folded) = MapClutter.arrange(alerts, markedSights: [], limit: 3)
        XCTAssertEqual(onMap.map(\.top.alert.kind), [.insolvency(days: 3), .trainStuck(TrainID(rawValue: 1)), .materialsShort])
        XCTAssertEqual(onMap[2].top.alert.station, StationID(rawValue: 1), "between equals, the world's order")
        XCTAssertEqual(folded.count, 5)
        XCTAssertEqual(folded.compactMap(\.alert.station).map(\.rawValue), [2, 3, 4, 5, 6])
        // Nothing is lost or shown twice.
        XCTAssertEqual(onMap.flatMap(\.bubbles).count + folded.count, alerts.count)
    }

    func testFewerBubblesFromFarther() {
        XCTAssertLessThan(MapClutter.bubbleLimit(.hidden), MapClutter.bubbleLimit(.medium))
        XCTAssertLessThan(MapClutter.bubbleLimit(.medium), MapClutter.bubbleLimit(.full))
    }

    /// A sight whose mark shows does not get a "no station" bubble too.
    func testASightsWarningIsNotRepeatedOverItsMark() {
        let sight = AttractionID(rawValue: 4)
        let alerts = [Self.bubble(.sightWithoutStation(sight), station: nil, at: 64)]
        XCTAssertTrue(MapClutter.arrange(alerts, markedSights: [sight], limit: 5).onMap.isEmpty)
        XCTAssertTrue(MapClutter.arrange(alerts, markedSights: [sight], limit: 5).folded.isEmpty)
        XCTAssertEqual(MapClutter.arrange(alerts, markedSights: [], limit: 5).onMap.count, 1)
    }

    /// Two trains stuck in different places are two bubbles.
    func testAlertsWithoutAStationAreGroupedByWhereTheyAre() {
        let alerts = [Self.bubble(.trainStuck(TrainID(rawValue: 1)), station: nil, at: 0),
                      Self.bubble(.trainStuck(TrainID(rawValue: 2)), station: nil, at: 4_000)]
        XCTAssertEqual(MapClutter.arrange(alerts, markedSights: [], limit: 5).onMap.count, 2)
    }

    func testTheBadgeSaysHowMany() {
        XCTAssertEqual(MapClutter.badgeText(1, in: .english), "1 alert")
        XCTAssertEqual(MapClutter.badgeText(3, in: .english), "3 alerts")
        XCTAssertEqual(MapClutter.badgeText(3, in: .traditionalChinese), "3 則提醒")
        XCTAssertEqual(MapClutter.moreText(2), "+2")
    }
}
