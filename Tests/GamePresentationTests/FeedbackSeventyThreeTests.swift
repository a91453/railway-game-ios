import GameCore
@testable import GamePresentation
import XCTest

/// Decision 284, TestFlight 70.1 and 73.1: the new line's draft says why no
/// track joins the stations picked, and a train too long for a platform of
/// its line says which and what fits, rather than "check the track".
@MainActor
final class FeedbackSeventyThreeTests: XCTestCase {
    // MARK: - 70.1: a double track drawn from open ground

    /// A double track 500 m long drawn from open ground: the main track
    /// along y = 10,240, the second 5 m north, no crossover between them.
    private func doubleTrack(language: DisplayLanguage = .english) throws -> GameSession {
        let world = try makeWorld(width: 40_960, height: 20_480, balance: 100_000_000, speed: .paused)
        let session = GameSession(world: world, language: language)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 34_816, y: 10_240), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, 2, "two tracks, no crossover")
        session.setNetworkMode(.platform)
        return session
    }

    /// A station's platform 64 m long at `x`, put on one track only, as
    /// the platform tool did before decision 285 (and still does beside a
    /// platform there already): the session over the world with it.
    private func platformOnOneTrack(_ session: GameSession, x: Int64, north: Bool) throws -> GameSession {
        var world = session.world
        let y: Int64 = north ? 10_240 - 320 : 10_240
        let point = try XCTUnwrap(world.trackEdgePoint(near: PlanPoint(x: x, y: y), within: 64))
        let station = try world.buildStation(named: "Station \(world.stations.count + 1)", at: PlanPoint(x: x, y: y))
        try world.addTrackPlatform(station.id, on: point.edge, from: point.distance - 2_048, to: point.distance + 2_048)
        let next = GameSession(world: world, language: session.language)
        next.selectTool(.network)
        next.setNetworkMode(.platform)
        return next
    }

    private func addPlatform(_ session: GameSession, x: Int64, north: Bool) {
        session.tapNetwork(at: PlanPoint(x: x, y: north ? 10_240 - 320 : 10_240), reach: 64)
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
    }

    private func draftBothStations(_ session: GameSession) {
        let ids = session.world.stations.map(\.id)
        session.selectTool(.select)
        for id in ids {
            session.selectStation(id)
            session.addSelectedStationToLineDraft()
        }
    }

    func testStationsOnTheTwoTracksOfADoubleLineAreToldTheyDoNotMeet() throws {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let session = try platformOnOneTrack(
                platformOnOneTrack(doubleTrack(language: language), x: 6_144, north: false), x: 30_720, north: true
            )
            draftBothStations(session)
            let ids = session.world.stations.map(\.id)
            XCTAssertNil(session.lineDraftRoute)
            XCTAssertEqual(session.lineDraftGap, .separateTracks(ids[0], ids[1]))
            let text = session.world.lineDraftGapText(try XCTUnwrap(session.lineDraftGap), in: language)
            let names = ids.map { session.world.station(id: $0)!.name }
            XCTAssertEqual(text, language.text(
                "The platforms of \(names[0]) and \(names[1]) are on tracks that do not meet, such as the two tracks of a double line with no crossover. Give both a platform on the same track, or select the track and tap Add X crossover. The line calls at the stations picked; its trains run once track joins them.",
                "\(names[0]) 和 \(names[1]) 的月台在兩條不相連的軌道上（例如複線的兩條之間沒有渡線）。在同一條軌道上為兩站都設月台，或選取軌道按「加 X 渡線」。路線只停點選的車站，軌道接通後列車才能行駛。"
            ))
        }
    }

    func testAPlatformOnTheOtherTrackJoinsThem() throws {
        let session = try platformOnOneTrack(platformOnOneTrack(doubleTrack(), x: 6_144, north: false), x: 30_720, north: true)
        draftBothStations(session)
        XCTAssertNotNil(session.lineDraftGap)
        // The east station's second platform, on the main track: the
        // draft finds the route at once, and the gap goes.
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        addPlatform(session, x: 30_720, north: false)
        XCTAssertEqual(session.world.stations.count, 2, "the platform joins the east station")
        let ids = session.world.stations.map(\.id)
        XCTAssertEqual(session.lineDraftRoute, ids)
        XCTAssertNil(session.lineDraftGap)
    }

    func testAStationWithNoPlatformIsNamed() throws {
        var world = try makeWorld(width: 40_960, height: 20_480, balance: 100_000_000, speed: .paused)
        let line = TestLine(tiles: 6)
        try line.build(in: &world)
        let west = try line.buildStation(named: "West", beside: 1, at: 0, in: &world)
        let lonely = try world.buildStation(named: "Lonely", at: TestLine.centre(4, 0)).id
        XCTAssertEqual(world.lineDraftGap(through: [west, lonely]), .noPlatform(lonely))
        XCTAssertEqual(
            world.lineDraftGapText(.noPlatform(lonely), in: .traditionalChinese),
            "Lonely 還沒有月台：用路網工具的「月台」在軌道上設一座。路線只停點選的車站，軌道接通後列車才能行駛。"
        )
        let east = try line.buildStation(named: "East", beside: 4, at: 0, in: &world)
        XCTAssertNil(world.lineDraftGap(through: [west, east]), "joined")
        XCTAssertNil(world.lineDraftGap(through: [west]))
    }

    func testTheOtherCasesSayWhatTheyAlwaysSaid() throws {
        let a = StationID(rawValue: 1), b = StationID(rawValue: 2)
        let world = try makeWorld(width: 4_096, height: 4_096, balance: 0, speed: .paused)
        XCTAssertEqual(
            world.lineDraftGapText(.noWay(a, b), in: .english),
            "No track joins these stations yet. The line calls at the stations picked; its trains run once track joins them."
        )
        XCTAssertEqual(
            world.lineDraftGapText(.noWay(a, b), in: .traditionalChinese),
            "這些車站之間還沒有軌道相連。路線只停點選的車站，軌道接通後列車才能行駛。"
        )
    }

    // MARK: - 73.1: a train longer than a terminus's platform

    /// A single track 3 km long, a line between a station near each end
    /// with a platform `platformMetres` long, and a train of `cars` cars
    /// assigned to it through the session, then placed at West.
    private func line(cars: Int, platformMetres: Int64) throws -> (GameSession, TrainID, StationID) {
        let world = try makeWorld(width: 204_800, height: 20_480, balance: 100_000_000, speed: .normal)
        let builder = GameSession(world: world)
        builder.selectTool(.network)
        builder.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        builder.tapNetwork(at: PlanPoint(x: 194_560, y: 10_240), reach: 16)
        builder.buildNetworkTrack()
        var w = builder.world
        let west = try w.buildStation(named: "West", at: PlanPoint(x: 6_000, y: 10_000)).id
        let east = try w.buildStation(named: "East", at: PlanPoint(x: 190_000, y: 10_000)).id
        let edge = w.network.edges[0]
        let platform = platformMetres * WorldCoordinate.unitsPerMetre
        try w.addTrackPlatform(west, on: edge.id, from: 3_200, to: 3_200 + platform)
        try w.addTrackPlatform(east, on: edge.id, from: edge.length - 3_200 - platform, to: edge.length - 3_200)
        let line = try w.createLine(named: "L", stops: [west, east]).id
        try w.setLineServiceWindow(line, to: .allDay)
        let train = try w.purchaseTrain(named: "T").id
        try w.setTrainCars(train, to: cars)
        let session = GameSession(world: w)
        session.assignTrain(train, toLine: line)
        session.place(session.world.train(id: train)!, atPlatformOf: session.world.station(id: west)!)
        XCTAssertNotNil(session.world.train(id: train)?.position, session.message?.text ?? "")
        return (session, train, east)
    }

    func testATrainLongerThanThePlatformsSaysWhichAndWhatFits() throws {
        // 8 cars, 16 m apart: 112 m from the first car to the last, on
        // platforms of 110 m.
        let (session, train, _) = try line(cars: 8, platformMetres: 110)
        var world = session.world
        XCTAssertEqual(world.lineDispatchHold(of: train), .noRoundTrip(firstStop: world.stations[0].id))
        let short = try XCTUnwrap(world.shortPlatformCall(ofTrain: train))
        XCTAssertEqual(short.station, world.stations[0].id, "the first call it does not fit")
        XCTAssertEqual(short.cars, 7, "110 m holds 7 cars")
        XCTAssertEqual(
            world.lineDispatchHoldText(of: train, in: .traditionalChinese),
            "列車比 West 的月台長：把月台加長到 112 公尺，或把列車移出軌道、減到 7 節"
        )
        XCTAssertEqual(
            world.lineDispatchHoldText(of: train, in: .english),
            "Too long for the platforms at West: lengthen one to 112 m, or take the train off the track and shorten it to 7 cars"
        )
        // It never leaves: the reason stays true.
        try world.advance(ticks: 3_600)
        XCTAssertNil(world.train(id: train)?.execution)
        XCTAssertNotNil(world.shortPlatformCall(ofTrain: train))
    }

    func testAssigningATrainTooLongSaysSoAtOnce() throws {
        var w = try makeWorld(width: 204_800, height: 20_480, balance: 100_000_000, speed: .paused)
        let track = TestLine(tiles: 12)
        try track.build(in: &w)
        let west = try track.buildStation(named: "West", beside: 2, at: 0, in: &w)
        let east = try track.buildStation(named: "East", beside: 9, at: 0, in: &w)
        let line = try w.createLine(named: "L", stops: [west, east]).id
        let train = try w.purchaseTrain(named: "T").id
        // TestLine's platforms are 512 long (8 m) either side of the
        // node; 4 cars of 16 m are 48 m from the first to the last.
        try w.setTrainCars(train, to: 4)
        let assigning = GameSession(world: w, language: .traditionalChinese)
        assigning.assignTrain(train, toLine: line)
        let text = try XCTUnwrap(assigning.message?.text)
        XCTAssertTrue(text.hasSuffix("列車比 West 的月台長：把月台加長到 48 公尺，或把列車移出軌道、減到 1 節。"), text)
    }

    func testATrainThatFitsIsNotTold() throws {
        let (session, train, _) = try line(cars: 4, platformMetres: 110)
        XCTAssertNil(session.world.shortPlatformCall(ofTrain: train))
        XCTAssertNil(session.world.lineDispatchHold(of: train))
        XCTAssertFalse(session.message?.text.contains("月台長") ?? false)
    }
}
