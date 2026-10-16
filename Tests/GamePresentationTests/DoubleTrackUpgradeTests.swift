import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 247: a traced stretch can be double track too, and the select
/// tool's track card makes single track double or adds an X crossover on
/// double track, each previewed with its whole price and built as one
/// command undo takes back.
@MainActor
final class DoubleTrackUpgradeTests: XCTestCase {
    private let metre = WorldCoordinate.unitsPerMetre

    // MARK: - A: tracing with double track

    /// A small made-up real railway: one line about 2 km long that bends
    /// gently in the middle, at 25° N 121.5° E.
    private static func fakeRailways() throws -> RealRailways {
        let lines = #"{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"sys":"mrt","name":"測試線","sortKey":0,"lineKey":"mrt|BL"},"geometry":{"type":"LineString","coordinates":[[121.490,25.000],[121.500,25.000],[121.510,25.002]]}}]}"#
        return try RealRailways(
            lines: Data(lines.utf8), stations: Data(#"{"type":"FeatureCollection","features":[]}"#.utf8), names: Data(#"{"systems":{}}"#.utf8)
        )
    }

    /// A real-world game at the made-up line, the network tool tracing it
    /// with double track on, and the world points of the line's two ends.
    private func tracing() throws -> (session: GameSession, west: PlanPoint, east: PlanPoint) {
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0, longitudeDegrees: 121.5)))
        let session = GameSession(world: world, language: .english)
        session.railways = try Self.fakeRailways()
        session.selectTool(.network)
        session.setNetworkMode(.build)
        session.networkTracesRealRailway = true
        session.networkBuildsDouble = true
        let west = try BundledRealData.point(RealRailways.Coordinate(latitude: 25.0, longitude: 121.4905), in: world)
        let east = try BundledRealData.point(RealRailways.Coordinate(latitude: 25.0019, longitude: 121.5095), in: world)
        return (session, west, east)
    }

    func testTracingAndDoubleTrackAreBothOn() throws {
        let (session, west, east) = try tracing()
        XCTAssertTrue(session.networkTracesRealRailway && session.networkBuildsDouble, "neither turns the other off")
        session.tapNetwork(at: west, reach: 24 * metre)
        session.tapNetwork(at: east, reach: 24 * metre)
        let draft = try XCTUnwrap(session.networkDraftPreview)
        XCTAssertNil(draft.preview.problem, draft.preview.problem ?? "")
        let pieces = try XCTUnwrap(draft.preview.traced)
        XCTAssertGreaterThan(pieces, 1, "traced along the line, not one curve")
        XCTAssertFalse(draft.crossing.isEmpty, "the second track is drawn")
        XCTAssertNil(draft.preview.crossoverNote, "its ends join nothing")
        let cost = try XCTUnwrap(draft.preview.cost)

        let before = session.world
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.message?.text.contains("With a second track beside it.") ?? false, session.message?.text ?? "")
        let world = session.world
        XCTAssertEqual(world.economy.balance, before.economy.balance - cost, "what the preview said")
        XCTAssertEqual(world.network.edges.count, 2 * pieces)
        guard case .command(.buildDoubleTrackChain(let main, let parallel, _, let crossovers))? = session.commandLog.entries.last?.action else {
            return XCTFail("one double-track command")
        }
        XCTAssertEqual(main.count, pieces)
        XCTAssertEqual(parallel.count, pieces)
        XCTAssertTrue(crossovers.isEmpty)
        // Every node of the second track stands about 5 m from the first.
        let first = Set(main.flatMap { [$0.from, $0.to] }.map(\.plan))
        for node in world.network.nodes where !first.contains(node.position.plan) {
            let nearest = try XCTUnwrap(main.flatMap(\.geometryPoints).map { point in
                let dx = Double(point.x - node.position.x), dy = Double(point.y - node.position.y)
                return (dx * dx + dy * dy).squareRoot()
            }.min())
            XCTAssertEqual(nearest / Double(metre), 5, accuracy: 0.6)
        }
        if case .node? = session.networkStart {} else { XCTFail("the next stretch starts at its end") }
        session.undo()
        XCTAssertEqual(session.world, before, "one undo takes it all back")
    }

    func testATracedDoubleTrackFromTrackJoinsItWithACrossover() throws {
        let (session, west, east) = try tracing()
        // A traced single track first; then double track on from its end.
        session.networkBuildsDouble = false
        let middle = try BundledRealData.point(RealRailways.Coordinate(latitude: 25.0, longitude: 121.499), in: session.world)
        session.tapNetwork(at: west, reach: 24 * metre)
        session.tapNetwork(at: middle, reach: 24 * metre)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.networkBuildsDouble = true
        session.tapNetwork(at: east, reach: 24 * metre)
        let draft = try XCTUnwrap(session.networkDraftPreview)
        XCTAssertNil(draft.preview.problem, draft.preview.problem ?? "")
        XCTAssertEqual(draft.preview.crossovers.count, 1)
        session.buildNetworkTrack()
        XCTAssertTrue(session.message?.text.contains("A crossover joins the second track") ?? false, session.message?.text ?? "")
    }

    // MARK: - B: the track card

    /// A straight single track along y 8,192 m-units: W, X, Y and Z, a
    /// branch leaving X (so X is a switch), and a station whose platform is
    /// on Y–Z; the select tool picked X–Y.
    private func singleTrack(balance: Money = Money(100_000_000)) throws -> (session: GameSession, west: TrackNodeID, station: StationID) {
        var world = try makeWorld(width: 65_536, height: 16_384, balance: balance, speed: .paused)
        let y: Int64 = 8_192
        let w = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: y))
        let x = try world.buildTrackNode(at: WorldCoordinate(x: 13_824, y: y))
        let yNode = try world.buildTrackNode(at: WorldCoordinate(x: 33_024, y: y))
        let z = try world.buildTrackNode(at: WorldCoordinate(x: 52_224, y: y))
        try world.buildTrackEdge(from: w, to: x)
        let picked = try world.buildTrackEdge(from: x, to: yNode)
        let platformEdge = try world.buildTrackEdge(from: yNode, to: z)
        let spur = try world.buildTrackNode(at: WorldCoordinate(x: 26_624, y: y + 6_400))
        try world.buildTrackEdge(from: x, to: spur, curve: try XCTUnwrap(NetworkBuilding.curve(
            from: PlanPoint(x: 13_824, y: y), leaving: PlanVector(dx: 1, dy: 0), to: PlanPoint(x: 26_624, y: y + 6_400), leaving: nil
        )))
        let station = try world.buildStation(named: "Central", at: PlanPoint(x: 42_624, y: y - 640))
        try world.addTrackPlatform(station.id, on: platformEdge, from: 6_400, to: 12_800)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.select)
        session.tapMap(at: PlanPoint(x: 23_424, y: y), reach: 16)
        XCTAssertEqual(session.selectedTrackEdge, picked)
        return (session, w, station.id)
    }

    /// Whether a train at the far end of the second track, heading back,
    /// can reach `node`.
    private func secondTrackReaches(_ node: TrackNodeID, from far: PlanPoint, in world: GameWorld) throws -> Bool {
        let end = try XCTUnwrap(world.network.nodes.first { $0.position.plan == far })
        let edgeID = try XCTUnwrap(end.ends.first?.edge)
        let edge = try XCTUnwrap(world.network.edge(edgeID))
        let traversal = TrackTraversal(edge: edgeID, direction: edge.to == end.id ? .backward : .forward)
        return world.route(from: .onEdge(traversal, offset: 0), to: node) != nil
    }

    func testMakingTrackDoubleRunsToTheSwitchAndTheEndWithCrossoversAndPlatforms() throws {
        let (session, west, station) = try singleTrack()
        XCTAssertTrue(session.canDoubleSelectedTrack)
        XCTAssertFalse(session.canAddScissorsOnSelectedTrack, "no second track to cross to")
        XCTAssertEqual(session.trackRun(from: try XCTUnwrap(session.selectedTrackEdge), whole: true).count, 2, "X–Y and Y–Z: X is a switch, Z an end")

        session.trackUpgradeSide = .left
        XCTAssertEqual(session.trackUpgradeSideText(.left), "north side")
        let before = session.world
        session.beginTrackUpgrade(.doubleTrack)
        let preview = try XCTUnwrap(session.trackUpgradePreview)
        XCTAssertNil(preview.problem, preview.problem ?? "")
        let cost = try XCTUnwrap(preview.cost)
        XCTAssertEqual(preview.track.count, 3, "the second track and a crossover at each end")
        XCTAssertTrue(preview.note?.contains("Crossovers join the two tracks at both ends.") ?? false, preview.note ?? "")
        XCTAssertTrue(preview.note?.contains("Its station gets a platform on the second track.") ?? false, preview.note ?? "")
        XCTAssertNotNil(session.networkOverlay?.preview, "drawn on the map")
        XCTAssertEqual(session.world, before, "a preview changes nothing")

        session.buildTrackUpgrade()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let world = session.world
        XCTAssertEqual(world.economy.balance, before.economy.balance - cost, "what the preview said")
        XCTAssertNil(session.trackUpgrade)
        guard case .command(.buildDoubleTrackChain(let main, let parallel, let platforms, let crossovers))? = session.commandLog.entries.last?.action else {
            return XCTFail("one command")
        }
        XCTAssertTrue(main.isEmpty)
        XCTAssertEqual(parallel.count, 2)
        XCTAssertEqual(crossovers.count, 2)
        XCTAssertEqual(platforms.map(\.station), [station])
        // The station now has a platform on each track, side by side.
        let stationPlatforms = world.network.platforms.filter { $0.station == station }
        XCTAssertEqual(stationPlatforms.count, 2)
        // 5 m north, from beside X to beside Z.
        let far = PlanPoint(x: 52_224, y: 8_192 - DoubleTrack.spacing)
        XCTAssertTrue(world.network.nodes.contains { $0.position.plan == PlanPoint(x: 13_824, y: 8_192 - DoubleTrack.spacing) })
        XCTAssertTrue(try secondTrackReaches(west, from: far, in: world), "a crossover joins it to the first track")
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)

        session.undo()
        XCTAssertEqual(session.world, before, "one undo takes it all back")
    }

    func testOnlyThePiecePicked() throws {
        let (session, _, _) = try singleTrack()
        session.trackUpgradeWholeRun = false
        session.beginTrackUpgrade(.doubleTrack)
        XCTAssertNil(session.trackUpgradePreview?.problem)
        XCTAssertFalse(session.trackUpgradePreview?.note?.contains("station") ?? true, "Y–Z's station is not on it")
        session.buildTrackUpgrade()
        guard case .command(.buildDoubleTrackChain(_, let parallel, let platforms, _))? = session.commandLog.entries.last?.action else {
            return XCTFail("one command")
        }
        XCTAssertEqual(parallel.count, 1)
        XCTAssertTrue(platforms.isEmpty)
    }

    /// The review of #695: the piece picked is single track, but the run to
    /// the switches takes in Y–Z, which already has a second track beside
    /// it. The card says so and points to "This piece only", which builds.
    func testARunPartlyDoubleSaysSoAndThisPieceOnlyStillBuilds() throws {
        let (session, _, _) = try singleTrack()
        var world = session.world
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 33_024, y: 8_192 - DoubleTrack.spacing))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 52_224, y: 8_192 - DoubleTrack.spacing))
        try world.buildTrackEdge(from: a, to: b)
        let doubled = GameSession(world: world, language: .english)
        doubled.selectTool(.select)
        doubled.tapMap(at: PlanPoint(x: 23_424, y: 8_192), reach: 16)
        XCTAssertTrue(doubled.canDoubleSelectedTrack, "the piece picked has nothing beside it")

        doubled.trackUpgradeSide = .left
        doubled.beginTrackUpgrade(.doubleTrack)
        let preview = try XCTUnwrap(doubled.trackUpgradePreview)
        XCTAssertEqual(
            preview.problem,
            "Part of this stretch already has a second track. Choose \u{201C}This piece only\u{201D} to double the piece picked."
        )
        XCTAssertNil(preview.cost)
        let before = doubled.world
        doubled.buildTrackUpgrade()
        XCTAssertEqual(doubled.message?.kind, .failure)
        XCTAssertEqual(doubled.world, before, "nothing built")

        doubled.trackUpgradeWholeRun = false
        let piece = try XCTUnwrap(doubled.trackUpgradePreview)
        XCTAssertNil(piece.problem, piece.problem ?? "")
        doubled.buildTrackUpgrade()
        XCTAssertEqual(doubled.message?.kind, .success, doubled.message?.text ?? "")
    }

    func testARunPartlyDoubleSaysSoInChinese() throws {
        let (session, _, _) = try singleTrack()
        var world = session.world
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 33_024, y: 8_192 + DoubleTrack.spacing))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 52_224, y: 8_192 + DoubleTrack.spacing))
        try world.buildTrackEdge(from: a, to: b)
        let doubled = GameSession(world: world, language: .traditionalChinese)
        doubled.selectTool(.select)
        doubled.tapMap(at: PlanPoint(x: 23_424, y: 8_192), reach: 16)
        doubled.beginTrackUpgrade(.doubleTrack)
        XCTAssertEqual(doubled.trackUpgradePreview?.problem, "這段路有一部分已經是複線。請選「只有這一段」，只把點的這一段升級。")
    }

    /// The review of #695: a loop of six pieces with no switch, picked on
    /// its south straight. The run to the switches goes all the way round;
    /// the card says why that cannot be doubled at once, and a piece can.
    func testALoopWithNoSwitchSaysSoAndAPieceStillBuilds() throws {
        var world = try makeWorld(width: 65_536, height: 65_536, balance: Money(1_000_000_000), speed: .paused)
        let r: Int64 = 9_600, l: Int64 = 25_600, x0: Int64 = 16_000, y0: Int64 = 16_000
        let points = [
            PlanPoint(x: x0, y: y0), PlanPoint(x: x0 + l, y: y0), PlanPoint(x: x0 + l + r, y: y0 + r),
            PlanPoint(x: x0 + l, y: y0 + 2 * r), PlanPoint(x: x0, y: y0 + 2 * r), PlanPoint(x: x0 - r, y: y0 + r),
        ]
        let ways = [
            PlanVector(dx: 1, dy: 0), PlanVector(dx: 1, dy: 0), PlanVector(dx: 0, dy: 1),
            PlanVector(dx: -1, dy: 0), PlanVector(dx: -1, dy: 0), PlanVector(dx: 0, dy: -1),
        ]
        let nodes = try points.map { try world.buildTrackNode(at: WorldCoordinate(x: $0.x, y: $0.y)) }
        for index in nodes.indices {
            let next = (index + 1) % nodes.count
            let curve = try XCTUnwrap(NetworkBuilding.curve(
                from: points[index], leaving: ways[index], to: points[next], leaving: PlanVector(dx: -ways[next].dx, dy: -ways[next].dy)
            ))
            try world.buildTrackEdge(from: nodes[index], to: nodes[next], curve: curve)
        }
        let session = GameSession(world: world, language: .english)
        session.selectTool(.select)
        session.tapMap(at: PlanPoint(x: x0 + l / 2, y: y0), reach: 16)
        let picked = try XCTUnwrap(session.selectedTrackEdge)
        XCTAssertEqual(session.trackRun(from: picked, whole: true).count, 6, "all the way round")
        XCTAssertTrue(session.canDoubleSelectedTrack)

        session.beginTrackUpgrade(.doubleTrack)
        XCTAssertEqual(
            session.trackUpgradePreview?.problem,
            "This track is a loop with no switch, so the second track has no ends to join. Choose \u{201C}This piece only\u{201D} to double it a piece at a time."
        )
        let chinese = GameSession(world: world, language: .traditionalChinese)
        chinese.selectTool(.select)
        chinese.tapMap(at: PlanPoint(x: x0 + l / 2, y: y0), reach: 16)
        chinese.beginTrackUpgrade(.doubleTrack)
        XCTAssertEqual(chinese.trackUpgradePreview?.problem, "這是沒有道岔的環線，第二條軌道沒有兩端可以接。請選「只有這一段」，一段一段升級。")

        session.trackUpgradeWholeRun = false
        XCTAssertNil(session.trackUpgradePreview?.problem, session.trackUpgradePreview?.problem ?? "")
        session.buildTrackUpgrade()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
    }

    func testOneDollarShortTheCardSaysTheWholePriceAndNothingIsBuilt() throws {
        let (rich, _, _) = try singleTrack()
        rich.beginTrackUpgrade(.doubleTrack)
        let cost = try XCTUnwrap(rich.trackUpgradePreview?.cost)

        // The same world with a dollar less than that in hand.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(rich.world)) as? [String: Any])
        var economy = try XCTUnwrap(json["economy"] as? [String: Any])
        let cash = cost - Money(1)
        economy["balance"] = cash.amount
        json["economy"] = economy
        let session = GameSession(world: try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json)), language: .english)
        session.selectTool(.select)
        session.tapMap(at: PlanPoint(x: 23_424, y: 8_192), reach: 16)
        session.beginTrackUpgrade(.doubleTrack)
        let preview = try XCTUnwrap(session.trackUpgradePreview)
        XCTAssertEqual(preview.cost, cost, "the whole price, though the cash is short")
        let (required, available) = Money.shortfallTexts(required: cost, available: cash)
        let text = "Not enough cash to make this track double: it costs \(required) and you have \(available)."
        XCTAssertEqual(preview.problem, text)
        let before = session.world
        session.buildTrackUpgrade()
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: text, fundsNeeded: cost))
        XCTAssertEqual(session.world, before, "nothing of it built")
        XCTAssertEqual(session.trackUpgrade, .doubleTrack, "the draft stays, to try again")
    }

    func testAnXCrossoverOnDoubleTrack() throws {
        let (session, west, _) = try singleTrack()
        session.beginTrackUpgrade(.doubleTrack)
        session.buildTrackUpgrade()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        // Tap the first track again, between the crossovers.
        session.tapMap(at: PlanPoint(x: 33_024 + 9_600, y: 8_192 + 640), reach: 16)
        session.tapMap(at: PlanPoint(x: 26_624, y: 8_192), reach: 16)
        XCTAssertNotNil(session.selectedTrackEdge)
        XCTAssertFalse(session.canDoubleSelectedTrack, "already double")
        XCTAssertTrue(session.canAddScissorsOnSelectedTrack)

        let before = session.world
        session.beginTrackUpgrade(.scissors)
        let preview = try XCTUnwrap(session.trackUpgradePreview)
        XCTAssertNil(preview.problem, preview.problem ?? "")
        XCTAssertEqual(preview.track.count, 4, "its four halves")
        let cost = try XCTUnwrap(preview.cost)
        session.buildTrackUpgrade()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        guard case .command(.buildCrossover)? = session.commandLog.entries.last?.action else { return XCTFail("the X crossover's command") }
        XCTAssertEqual(session.world.economy.balance, before.economy.balance - cost)
        // Four splits and four halves.
        XCTAssertEqual(session.world.network.edges.count, before.network.edges.count + 8)
        XCTAssertTrue(try secondTrackReaches(west, from: PlanPoint(x: 52_224, y: 8_192 - DoubleTrack.spacing), in: session.world))
        session.undo()
        XCTAssertEqual(session.world, before)
    }

    func testAnXCrossoverOnAGradeSaysWhyNot() throws {
        var world = try makeWorld(width: 65_536, height: 16_384, balance: Money(100_000_000), speed: .paused)
        for y: Int64 in [8_192, 8_192 - 320] {
            let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: y, z: 0))
            let b = try world.buildTrackNode(at: WorldCoordinate(x: 33_024, y: y, z: 640))
            try world.buildTrackEdge(from: a, to: b, structure: .elevated)
        }
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTool(.select)
        session.tapMap(at: PlanPoint(x: 17_024, y: 8_192), reach: 16)
        XCTAssertTrue(session.canAddScissorsOnSelectedTrack)
        session.beginTrackUpgrade(.scissors)
        XCTAssertEqual(session.trackUpgradePreview?.problem, "X 渡線只能建在平坦的路段。")
        XCTAssertNil(session.trackUpgradePreview?.cost)
    }

    func testTheCardForgetsTheDraftWhenTheSelectionChanges() throws {
        let (session, _, _) = try singleTrack()
        session.beginTrackUpgrade(.doubleTrack)
        XCTAssertNotNil(session.trackUpgradePreview)
        session.clearSelection()
        XCTAssertNil(session.trackUpgrade)
    }

    func testTheChainCommandCodesAsItIs() throws {
        let (session, _, _) = try singleTrack()
        session.beginTrackUpgrade(.doubleTrack)
        session.buildTrackUpgrade()
        guard case .command(let command)? = session.commandLog.entries.last?.action else { return XCTFail("a command") }
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: JSONEncoder().encode(command)), command)
        XCTAssertThrowsError(try JSONDecoder().decode(PlayerCommand.self, from: Data(#"{"kind":"buildDoubleTrackChain"}"#.utf8)))
    }
}
