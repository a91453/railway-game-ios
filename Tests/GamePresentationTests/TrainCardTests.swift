import GameCore
@testable import GamePresentation
import XCTest

/// Decision 223: the train card's flight-card layout reads the train's trip
/// from its timetable, its run and its lateness.
final class TrainCardTests: XCTestCase {
    func testEveryRunningTrainHasACardOfItsTripWithin0To1() throws {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 120)
        var cards = 0
        for train in world.trains where train.timetable.count > 1 {
            let card = try XCTUnwrap(world.trainCard(of: train.id, in: .english))
            cards += 1
            XCTAssertEqual(card.origin, world.station(id: train.timetable[0].station)?.name)
            XCTAssertEqual(card.terminus, world.station(id: train.timetable[train.timetable.count - 1].station)?.name)
            XCTAssertTrue((0...1).contains(card.progress))
            XCTAssertGreaterThanOrEqual(card.remainingMetres, 0)
            XCTAssertEqual(card.expectedArrival.seconds, card.arrival.seconds + card.lateMinutes * 60)
            XCTAssertGreaterThanOrEqual(card.departure.seconds, 0)
            XCTAssertLessThanOrEqual(card.departure.seconds, card.arrival.seconds)
        }
        XCTAssertGreaterThan(cards, 0, "the demo's lines run trains")
    }

    func testATrainGoesForwardAlongItsTripAndItsDistanceLeftComesDown() throws {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 30)
        let id = try XCTUnwrap(world.trains.first { world.trainCard(of: $0.id, in: .english)?.state == .running }).id
        var last = try XCTUnwrap(world.trainCard(of: id, in: .english))
        var moved = false
        for _ in 0..<20 {
            try world.advance(ticks: 1)
            guard let card = world.trainCard(of: id, in: .english), card.departure == last.departure else { break }
            XCTAssertGreaterThanOrEqual(card.progress, last.progress - 1e-9)
            XCTAssertLessThanOrEqual(card.remainingMetres, last.remainingMetres)
            moved = moved || card.progress > last.progress
            last = card
        }
        XCTAssertTrue(moved, "the train moved along its trip")
    }

    func testAnUnknownTrainHasNoCard() {
        XCTAssertNil(DemoWorld.make(in: .english).trainCard(of: TrainID(rawValue: 9_999), in: .english))
    }

    func testTheCardsWords() {
        func card(late: Int64 = 0, departed: Bool = true, state: FollowBarInfo.Status = .running, next: String? = "Taoyuan") -> TrainCard {
            TrainCard(
                origin: "Keelung", terminus: "Hsinchu",
                departure: GameTime(seconds: 8 * 3600 + 12 * 60), arrival: GameTime(seconds: 9 * 3600 + 20 * 60),
                lateMinutes: late, hasDeparted: departed, progress: 0.42, remainingMetres: 38_640,
                nextStop: next, nextStopMinutes: next == nil ? nil : 3, speed: 92, load: nil, state: state,
                now: GameTime(seconds: 8 * 3600 + 33 * 60)
            )
        }
        XCTAssertEqual(card().statusText(in: .traditionalChinese), "準點")
        XCTAssertEqual(card(late: 6).statusText(in: .traditionalChinese), "誤點 6 分")
        XCTAssertEqual(card(late: 6).statusText(in: .english), "6 min late")
        XCTAssertEqual(card(state: .arrived).statusText(in: .traditionalChinese), "已抵達")
        XCTAssertFalse(card(state: .arrived).showsPunctuality)
        XCTAssertEqual(card(late: 6).expectedArrival.clockText, "09:26")
        XCTAssertEqual(card().departureText(in: .traditionalChinese), "21 分前發車")
        XCTAssertEqual(card(departed: false, state: .notDeparted).departureText(in: .english), "Leaves in 0 min")
        XCTAssertEqual(card(late: 6).arrivalText(in: .traditionalChinese), "53 分後到站")
        XCTAssertEqual(card(state: .arrived).arrivalText(in: .traditionalChinese), "已抵達")
        XCTAssertEqual(card().remainingText(in: .traditionalChinese), "剩 38.6 km")
        XCTAssertEqual(card().nextStopText(in: .traditionalChinese), "Taoyuan 3 分")
        XCTAssertEqual(card(next: nil).nextStopText(in: .english), "—")
    }
}
