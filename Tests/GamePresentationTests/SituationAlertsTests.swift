import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 184: the map's bubbles beyond decision 109's: a
/// train in a deadlock, a sight of four stars or more with no station once
/// a passenger line runs, and a challenge's days left in the red.
@MainActor
final class SituationAlertsTests: XCTestCase {
    private func world() throws -> GameWorld {
        var world = try makeWorld(width: 40_960, height: 8_192, balance: 100_000)
        for (name, x) in [("Alpha", 1), ("Beta", 3)] {
            try world.buildStation(named: name, at: TestLine.centre(x, 0))
        }
        world.setTourism([
            Attraction(id: AttractionID(rawValue: 1), name: "遠方古蹟", englishName: "Far Sight",
                       point: PlanPoint(x: 36_000, y: 4_096), kind: .town, baseStars: 450),
            Attraction(id: AttractionID(rawValue: 2), name: "小景點", englishName: "Small Sight",
                       point: PlanPoint(x: 30_000, y: 4_096), kind: .town, baseStars: 300),
        ])
        return world
    }

    func testASightWithoutAStationShowsOnceALineRuns() throws {
        var world = try world()
        XCTAssertEqual(world.situationAlerts(), [], "no line yet: every sight lacks a station")
        try world.createLine(named: "Main", stops: [StationID(rawValue: 1), StationID(rawValue: 2)])
        let alerts = world.situationAlerts()
        XCTAssertEqual(alerts.map(\.kind), [.sightWithoutStation(AttractionID(rawValue: 1))], "only the four-star one")
        XCTAssertNil(alerts[0].station)
        XCTAssertEqual(alerts[0].location, PlanPoint(x: 36_000, y: 4_096))
        XCTAssertEqual(alerts[0].text(in: .traditionalChinese, subject: "遠方古蹟"), "遠方古蹟：沒有車站")
        XCTAssertEqual(alerts[0].text(in: .english, subject: "Far Sight"), "Far Sight: no station")
        XCTAssertEqual(world.mapAlerts().map(\.kind), [.lineWithoutTrains(LineID(rawValue: 1))], "kept apart from decision 109's")

        let session = GameSession(world: world)
        XCTAssertFalse(session.respond(to: alerts[0]))
        XCTAssertEqual(session.cameraRequest?.location, alerts[0].location, "the map goes to the sight")

        world.setTourism(nil)
        XCTAssertEqual(world.situationAlerts(), [])
    }

    func testTheOtherBubblesSayWhatTheyAre() throws {
        let stuck = MapAlert(kind: .trainStuck(TrainID(rawValue: 3)), station: nil, location: PlanPoint(x: 0, y: 0))
        XCTAssertEqual(stuck.text(in: .traditionalChinese, subject: "區間車 3"), "區間車 3：卡住了")
        XCTAssertEqual(stuck.text(in: .english), "Train: stuck")
        let red = MapAlert(kind: .insolvency(days: 5), station: StationID(rawValue: 1), location: PlanPoint(x: 0, y: 0))
        XCTAssertEqual(red.text(in: .traditionalChinese), insolvencyCountdownText(5, in: .traditionalChinese))
        XCTAssertTrue(try world().situationAlerts().allSatisfy { if case .trainStuck = $0.kind { false } else { true } },
                      "no traffic control, no deadlock")
    }

    func testATapOnAStuckTrainSelectsIt() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let train = try XCTUnwrap(world.trains.first)
        let session = GameSession(world: world)
        session.respond(to: MapAlert(kind: .trainStuck(train.id), station: nil, location: towns[0]))
        XCTAssertEqual(session.tappedTrainID, train.id)
    }
}
