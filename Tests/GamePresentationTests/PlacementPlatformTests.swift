@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 584, PR-2: at a station of two or more platforms the train tool
/// lists them before the train is placed, picks the one on its line's track
/// for the player, and places it on the one the player picks.
@MainActor
final class PlacementPlatformTests: XCTestCase {
    /// The UI test world `platform-choice` (FeatureUITestWorld): a double
    /// track with no crossover, 海岸 on both tracks and 山邊 on the
    /// other one only, and 海岸線 between them; `train` bought, off the
    /// track, given 海岸線.
    private func twoTracks() throws -> (world: GameWorld, coast: StationID, hill: StationID, line: LineID, train: TrainID) {
        let bounds = try WorldBounds(width: 40_960, height: 20_480)
        let builder = GameSession(world: GameWorld(bounds: bounds, economy: GameEconomy(balance: 100_000_000), clock: GameClock(speed: .paused)))
        builder.selectTool(.network)
        builder.networkBuildsDouble = true
        builder.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        builder.tapNetwork(at: PlanPoint(x: 34_816, y: 10_240), reach: 16)
        builder.buildNetworkTrack()
        XCTAssertEqual(builder.message?.kind, .success, builder.message?.text ?? "")
        var world = builder.world
        func addPlatform(to station: StationID, at point: PlanPoint) throws {
            let site = try XCTUnwrap(world.trackEdgePoint(near: point, within: 64))
            try world.addTrackPlatform(station, on: site.edge, from: site.distance - 2_048, to: site.distance + 2_048)
        }
        let coast = try world.buildStation(named: "海岸", at: PlanPoint(x: 6_144, y: 10_240)).id
        let hill = try world.buildStation(named: "山邊", at: PlanPoint(x: 30_720, y: 9_920)).id
        try addPlatform(to: coast, at: PlanPoint(x: 6_144, y: 10_240))
        try addPlatform(to: coast, at: PlanPoint(x: 6_144, y: 9_920))
        try addPlatform(to: hill, at: PlanPoint(x: 30_720, y: 9_920))
        let line = try world.createLine(named: "海岸線", stops: [coast, hill]).id
        let train = try world.purchaseTrain(named: "列車 3").id
        try world.assignTrain(train, to: line)
        return (world, coast, hill, line, train)
    }

    /// The author's case: the train went to the first platform as long as
    /// it, on the track its line does not run on. Now the platform on the
    /// line's track is picked, said so, and the train goes there.
    func testTheTrainGoesToThePlatformOnItsLinesTrack() throws {
        let (world, coast, hill, _, train) = try twoTracks()
        let hillEdge = try XCTUnwrap(world.trackPlatforms(of: hill).first?.edge)
        let choices = world.placementPlatformChoices(for: train, at: coast)
        XCTAssertEqual(choices.map(\.number), [1, 2])
        XCTAssertEqual(choices.filter(\.isOnLine).map(\.platform.edge), [hillEdge], "only that track reaches 山邊")
        XCTAssertNotEqual(
            GameSession.platforms(for: try XCTUnwrap(world.train(id: train)), at: coast, in: world).first?.edge, hillEdge,
            "without the line, the other platform is tried first"
        )
        XCTAssertEqual(world.defaultPlacementPlatform(for: train, at: coast)?.edge, hillEdge)

        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTool(.train)
        session.selectTrain(train)
        session.selectStation(coast)
        XCTAssertEqual(session.placementPlatformChoices.count, 2)
        let onLine = try XCTUnwrap(session.placementPlatformChoices.first(where: \.isOnLine))
        XCTAssertEqual(session.placementPlatform, onLine.platform)
        XCTAssertEqual(session.placementPlatformNote(onLine), "海岸線的軌道")
        XCTAssertEqual(onLine.title(in: .traditionalChinese), "第 \(onLine.number) 月台 · \(NetworkBuilding.lengthText(onLine.platform.length, in: .traditionalChinese))")

        session.placeSelectedTrain()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        guard case .onEdge(let traversal, _)? = session.world.train(id: train)?.position else { return XCTFail("not placed") }
        XCTAssertTrue(session.message?.text.hasPrefix("已將 列車 3 放在 海岸 第 \(onLine.number) 月台，位於") == true, session.message?.text ?? "")
        XCTAssertEqual(traversal.edge, hillEdge)
        XCTAssertTrue(session.placementPlatformChoices.isEmpty, "a placed train lists none")
    }

    /// The platform the player picks is the one the train goes on, even
    /// off its line's track.
    func testThePlayerPicksThePlatform() throws {
        let (world, coast, _, _, train) = try twoTracks()
        let session = GameSession(world: world)
        session.selectTool(.train)
        session.selectTrain(train)
        session.selectStation(coast)
        let other = try XCTUnwrap(session.placementPlatformChoices.first(where: { !$0.isOnLine }))
        XCTAssertNil(session.placementPlatformNote(other))
        session.pickPlacementPlatform(other.platform)
        XCTAssertEqual(session.placementPlatform, other.platform)
        session.placeSelectedTrain()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        guard case .onEdge(let traversal, _)? = session.world.train(id: train)?.position else { return XCTFail("not placed") }
        XCTAssertEqual(traversal.edge, other.platform.edge)
        // The command log keeps the platform, so a replay puts it there.
        let command = PlayerCommand.edit(.placeTrainOnPlatform(train, other.platform, heading: session.placementHeading))
        XCTAssertEqual(session.commandLog.entries.last?.action, .command(command))
        let coded = try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(coded, command)
    }

    /// A platform a train stands on is said so, the one picked for the
    /// player is the free one, and a picked held platform is refused
    /// naming the train.
    func testAPlatformATrainStandsOnIsSaidAndSkipped() throws {
        var (world, coast, _, _, train) = try twoTracks()
        try world.setTrafficControl(true)
        let idle = try world.purchaseTrain(named: "列車 4").id
        let onLine = try XCTUnwrap(world.defaultPlacementPlatform(for: train, at: coast))
        _ = try GameSession.place(idle, on: onLine, heading: .east, in: &world)
        let choices = world.placementPlatformChoices(for: train, at: coast)
        let held = try XCTUnwrap(choices.first(where: { $0.platform == onLine }))
        XCTAssertEqual(held.holder, idle)
        XCTAssertEqual(held.note(train: train, line: nil, in: world, language: .english), "列車 4 stands here")
        XCTAssertNotEqual(world.defaultPlacementPlatform(for: train, at: coast), onLine)

        let session = GameSession(world: world)
        session.selectTool(.train)
        session.selectTrain(train)
        session.selectStation(coast)
        session.pickPlacementPlatform(onLine)
        session.placeSelectedTrain()
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.message?.goToTrain, idle)
        XCTAssertNil(session.world.train(id: train)?.position)
    }

    /// A station of one platform lists none and places as before.
    func testAStationOfOnePlatformListsNone() throws {
        let (world, _, hill, _, train) = try twoTracks()
        XCTAssertTrue(world.placementPlatformChoices(for: train, at: hill).isEmpty)
        XCTAssertNil(world.defaultPlacementPlatform(for: train, at: hill))
        let session = GameSession(world: world)
        session.selectTool(.train)
        session.selectTrain(train)
        session.selectStation(hill)
        session.placeSelectedTrain()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.commandLog.entries.last?.action, .command(.edit(.placeTrain(train, at: hill, heading: session.placementHeading))))
    }
}
