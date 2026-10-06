import GameCore
import GamePresentation
import XCTest

/// Stage C1: the network tool lays the track network at any angle from taps,
/// adds platforms and removes edges, through GameCore's commands applied all
/// or nothing. Each test compares the session's world with the same
/// commands applied to GameCore directly, and the curves and costs are
/// worked out by hand.
final class NetworkBuildingSessionTests: XCTestCase {
    private static let reach: Int64 = 512
    private static let a = PlanPoint(x: 2_048, y: 2_048)
    private static let b = PlanPoint(x: 6_144, y: 2_048)
    private static let c = PlanPoint(x: 10_240, y: 4_096)

    private func makeNetworkWorld(balance: Money = 1_000_000) throws -> GameWorld {
        try makeWorld(width: 16_384, height: 8_192, balance: balance, speed: .paused)
    }

    // MARK: - Curves

    func testTwoFreeEndsMakeAStraightEdge() {
        XCTAssertEqual(NetworkBuilding.curve(from: Self.a, leaving: nil, to: Self.b, leaving: nil), .straight)
        XCTAssertNil(NetworkBuilding.curve(from: Self.a, leaving: nil, to: Self.a, leaving: nil), "the same point twice")
    }

    /// The end that continues the track keeps its direction, the free end
    /// points along the chord, both handles a third of the chord long.
    func testAJoinedEndKeepsTheTrackDirectionAndAFreeEndFollowsTheChord() {
        let start = PlanPoint(x: 1_024, y: 1_024), end = PlanPoint(x: 4_096, y: 2_048)
        // The chord is (3072, 1024), 3238.17 long; a third is 1079.39, and
        // a third of the chord is (1024, 341.33).
        XCTAssertEqual(
            NetworkBuilding.curve(from: start, leaving: PlanVector(dx: 5, dy: 0), to: end, leaving: nil),
            .cubic(PlanPoint(x: 2_103, y: 1_024), PlanPoint(x: 3_072, y: 1_707))
        )
        // The same arc from the other end: the free start along the chord.
        XCTAssertEqual(
            NetworkBuilding.curve(from: start, leaving: nil, to: end, leaving: PlanVector(dx: 0, dy: -3)),
            .cubic(PlanPoint(x: 2_048, y: 1_365), PlanPoint(x: 4_096, y: 969))
        )
        // Both ends fixed: each handle along its own track.
        XCTAssertEqual(
            NetworkBuilding.curve(from: start, leaving: PlanVector(dx: 1, dy: 0), to: end, leaving: PlanVector(dx: 0, dy: -1)),
            .cubic(PlanPoint(x: 2_103, y: 1_024), PlanPoint(x: 4_096, y: 969))
        )
    }

    /// The reference refuses a turn of more than 90° (`MIN_TURN_ANGLE_DEG`);
    /// exactly 90° is allowed.
    func testATurnOfMoreThanARightAngleIsRefused() {
        let start = PlanPoint(x: 0, y: 0), end = PlanPoint(x: 3_000, y: 1_000)
        XCTAssertNil(NetworkBuilding.curve(from: start, leaving: PlanVector(dx: -1, dy: 0), to: end, leaving: nil))
        XCTAssertNil(NetworkBuilding.curve(from: start, leaving: PlanVector(dx: -1, dy: 2), to: end, leaving: nil), "dot product -1000")
        XCTAssertNotNil(NetworkBuilding.curve(from: start, leaving: PlanVector(dx: -1, dy: 3), to: end, leaving: nil), "exactly 90°")
        XCTAssertNil(NetworkBuilding.curve(from: start, leaving: nil, to: end, leaving: PlanVector(dx: 1, dy: 0)), "the end turning back")
    }

    // MARK: - Building

    func testTwoTapsAndBuildLayAStraightEdgeAndContinueFromItsEnd() async throws {
        let world = try makeNetworkWorld()
        var expected = world
        let n1 = try expected.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let n2 = try expected.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
        // 4096 long: four tiles of track at 100 each.
        try expected.buildTrackEdge(from: n1, to: n2)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            XCTAssertEqual(session.networkDraftText(), "Tap where the track starts: a node, or anywhere for a new one.")
            session.tapNetwork(at: Self.a, reach: Self.reach)
            XCTAssertEqual(session.networkStart, .point(Self.a))
            XCTAssertEqual(session.networkDraftText(), "From a new node. Tap where it ends.")
            XCTAssertNil(session.networkPreview)
            session.tapNetwork(at: Self.b, reach: Self.reach)
            XCTAssertEqual(session.networkDraftText(), "a new node → a new node")

            let preview = session.networkPreview
            XCTAssertEqual(preview?.curve, .straight)
            XCTAssertEqual(preview?.length, 4_096)
            XCTAssertEqual(preview?.cost, Money(400))
            XCTAssertNil(preview?.problem)
            XCTAssertEqual(preview?.text(in: .english), "64 m · $ 4")
            XCTAssertEqual(session.world, world, "a preview builds nothing")

            session.buildNetworkTrack()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built Edge #1: 64 m, surface, for $ 4."))
            XCTAssertEqual(session.networkStart, .node(.node(2)), "the next stretch starts where this one ended")
            XCTAssertNil(session.networkEnd)
            XCTAssertEqual(session.networkDraftText(), "From Node #2. Tap where it ends.")
        }
    }

    /// The second stretch leaves the first one's end the way it arrived, so
    /// GameCore joins them: a train arriving along one may leave by the
    /// other.
    func testTheNextStretchContinuesTheTrackSmoothly() async throws {
        let world = try makeNetworkWorld()
        var expected = world
        let n1 = try expected.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let n2 = try expected.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
        try expected.buildTrackEdge(from: n1, to: n2)
        let n3 = try expected.buildTrackNode(at: WorldCoordinate(x: 10_240, y: 4_096))
        // The chord (4096, 2048) is 4579.42 long: the start's handle 1526
        // east, the end's a third of the chord, (1365.33, 682.67), back.
        try expected.buildTrackEdge(from: n2, to: n3, curve: .cubic(PlanPoint(x: 7_670, y: 2_048), PlanPoint(x: 8_875, y: 3_413)))
        XCTAssertEqual(expected.network.node(n2)?.end(of: .edge(1))?.exits, [.edge(2)], "the edges join")
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.tapNetwork(at: Self.a, reach: Self.reach)
            session.tapNetwork(at: Self.b, reach: Self.reach)
            session.buildNetworkTrack()
            session.tapNetwork(at: Self.c, reach: Self.reach)

            let preview = session.networkPreview
            XCTAssertEqual(preview?.curve, .cubic(PlanPoint(x: 7_670, y: 2_048), PlanPoint(x: 8_875, y: 3_413)))
            XCTAssertEqual(preview?.joinsStart, true)
            XCTAssertEqual(preview?.joinsEnd, false)
            XCTAssertEqual(preview?.text(in: .english).contains("continues the track"), true)

            session.buildNetworkTrack()

            XCTAssertEqual(session.world, expected)
        }
    }

    func testATapNearANodePicksItAndTappingTheStartAgainForgetsTheDraft() async throws {
        var world = try makeNetworkWorld()
        let node = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.tapNetwork(at: PlanPoint(x: 6_400, y: 2_300), reach: Self.reach)
            XCTAssertEqual(session.networkStart, .node(node), "within reach of the node")
            session.tapNetwork(at: PlanPoint(x: -1, y: 100), reach: Self.reach)
            XCTAssertNil(session.networkEnd, "a tap off the map is ignored")
            session.tapNetwork(at: PlanPoint(x: 6_144, y: 2_048), reach: Self.reach)
            XCTAssertNil(session.networkStart)
            XCTAssertNil(session.networkEnd)
            XCTAssertEqual(session.world, world)
        }
    }

    /// The reference's own checks come before GameCore's: a new node within
    /// 22 m of the other end, and a turn of more than 90° from the track.
    func testTooCloseAndTooSharpAreRefusedBeforeAnythingIsBuilt() async throws {
        var world = try makeNetworkWorld()
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let n2 = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
        try world.buildTrackEdge(from: n1, to: n2)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.tapNetwork(at: Self.b, reach: Self.reach)
            // 1400 units is 21.9 m.
            session.tapNetwork(at: PlanPoint(x: 6_144 + 1_400, y: 2_048), reach: Self.reach)
            XCTAssertEqual(session.networkPreview?.problem, "That point is too close to the other end: keep at least 22 m between them.")
            XCTAssertNil(session.networkPreview?.cost)
            XCTAssertEqual(session.networkPreview?.length, 1_400, "the straight distance, drawn as not buildable")
            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.kind, .failure)
            XCTAssertEqual(session.world, world)

            // Back the way the track came.
            session.tapNetwork(at: PlanPoint(x: 3_072, y: 4_096), reach: Self.reach)
            XCTAssertEqual(
                session.networkPreview?.problem,
                "That turns too sharply: from the track it continues, new track may turn at most 90° toward the other end."
            )
            session.buildNetworkTrack()
            XCTAssertEqual(session.world, world)

            // Straight, it does not continue the track and may go anywhere.
            session.networkFollowsTrack = false
            XCTAssertEqual(session.networkPreview?.curve, .straight)
            XCTAssertNil(session.networkPreview?.problem)
        }
    }

    /// When GameCore refuses the edge, the new nodes go too: the build is
    /// all or nothing, and the preview says why with no cost.
    func testARefusedBuildLeavesNoNewNode() async throws {
        // Four tiles of track cost 400; there are 300.
        let world = try makeNetworkWorld(balance: 300)
        await MainActor.run {
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.tapNetwork(at: Self.a, reach: Self.reach)
            session.tapNetwork(at: Self.b, reach: Self.reach)
            let preview = session.networkPreview
            XCTAssertNil(preview?.cost)
            XCTAssertEqual(preview?.problem, "Not enough cash: this costs $ 4.00 and you have $ 3.00.")
            XCTAssertEqual(preview?.points.count, 2, "the stretch is still drawn")

            session.buildNetworkTrack()

            XCTAssertEqual(session.world, world, "no node without its edge")
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Not enough cash: this costs $ 4.00 and you have $ 3.00."))
            XCTAssertEqual(session.networkStart, .point(Self.a), "the draft is kept")
        }
    }

    /// A viaduct climbing 8 m from a surface node: 512 over 13,312 is 38‰,
    /// within 40‰; three times the surface price; and one tile shorter is
    /// too steep.
    func testAnElevatedStretchClimbsFromTheGround() async throws {
        var world = try makeNetworkWorld()
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 4_096))
        let n2 = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 4_096))
        try world.buildTrackEdge(from: n1, to: n2)
        var expected = world
        let top = try expected.buildTrackNode(at: WorldCoordinate(x: 15_360, y: 4_096, z: 512))
        try expected.buildTrackEdge(from: n2, to: top, curve: .cubic(PlanPoint(x: 6_485, y: 4_096), PlanPoint(x: 10_923, y: 4_096)), structure: .elevated)
        await MainActor.run { [world, expected] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.networkStructure = .elevated
            session.networkHeight = 512
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 4_096), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 14_336, y: 4_096), reach: Self.reach)
            XCTAssertEqual(session.networkPreview?.problem, GameError.trackTooSteep.playerMessage(in: .english), "12,288 long: 41.7‰")

            session.tapNetwork(at: PlanPoint(x: 15_360, y: 4_096), reach: Self.reach)
            // 13 tiles at 3 × 100.
            XCTAssertEqual(session.networkPreview?.text(in: .english), "208 m · 0 m → 8 m · continues the track · $ 39")
            session.buildNetworkTrack()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(
                session.world.trackEdgeSummary(.edge(2), in: .english),
                "Edge #2 · 208 m · Elevated · 0 m → 8 m, 38‰ at its steepest"
            )
            XCTAssertEqual(
                session.world.trackEdgeSummary(.edge(2), in: .traditionalChinese),
                "軌段 #2 · 208 公尺 · 高架 · 0 公尺 → 8 公尺，最陡 38‰"
            )
            XCTAssertEqual(session.world.trackEdgeSummary(.edge(1), in: .english), "Edge #1 · 16 m · Surface · 0 m")
        }
    }

    /// Easing the grade puts a vertical curve a quarter of the length long
    /// at each end; the middle is steeper (4/3 of 512 over 16,384: 42‰),
    /// so it needs a longer stretch.
    func testEasingTheGradeAddsVerticalCurvesAtBothEnds() async throws {
        var world = try makeWorld(width: 24_576, height: 8_192, balance: 10_000_000)
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 4_096))
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.networkStructure = .elevated
            session.networkHeight = 512
            session.networkEasesGrade = true
            session.tapNetwork(at: PlanPoint(x: 1_024, y: 4_096), reach: Self.reach)
            XCTAssertEqual(session.networkStart, .node(n1))
            session.tapNetwork(at: PlanPoint(x: 17_408, y: 4_096), reach: Self.reach)
            XCTAssertEqual(session.networkPreview?.profile, TrackProfile(startTransition: 4_096, endTransition: 4_096))
            XCTAssertEqual(session.networkPreview?.problem, GameError.trackTooSteep.playerMessage(in: .english))
            session.tapNetwork(at: PlanPoint(x: 19_456, y: 4_096), reach: Self.reach)
            XCTAssertEqual(session.networkPreview?.profile, TrackProfile(startTransition: 4_608, endTransition: 4_608))
            XCTAssertNil(session.networkPreview?.problem)
            session.buildNetworkTrack()
            XCTAssertEqual(session.world.network.edge(.edge(1))?.profile, TrackProfile(startTransition: 4_608, endTransition: 4_608))
        }
    }

    // MARK: - Platforms and trains

    /// One straight edge, 8192 long, along y = 3072.
    private func makeLineWorld() throws -> GameWorld {
        var world = try makeNetworkWorld()
        let west = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 3_072))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 3_072))
        try world.buildTrackEdge(from: west, to: east)
        return world
    }

    /// A tap 3000 along the edge with four cars picks 952–5048; no station
    /// is near, so a new one goes at the middle, (4024, 3072), taking no
    /// tile (Stage F1).
    func testAPlatformGetsANewStationAtItsMiddle() async throws {
        let world = try makeLineWorld()
        var expected = world
        let station = try expected.buildStation(named: "Station 1", at: PlanPoint(x: 4_024, y: 3_072))
        try expected.addTrackPlatform(station.id, on: .edge(1), from: 952, to: 5_048)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 4_024, y: 3_200), reach: Self.reach)
            XCTAssertEqual(session.networkEdgePoint, NetworkEdgePoint(edge: .edge(1), distance: 3_000))
            XCTAssertNil(session.platformStationID, "no station within two tiles")
            XCTAssertEqual(session.networkDraftText(), "64 m platform on edge #1, 952–5048 units along")

            session.addNetworkPlatform()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(
                session.message,
                StatusMessage(kind: .success, text: "Built station “Station 1” with a 64 m platform on edge #1.")
            )
            XCTAssertEqual(session.platformStationID, station.id)
            XCTAssertEqual(session.stationName, "Station 2")
            XCTAssertEqual(session.world.trackEdgeSummary(.edge(1), in: .english), "Edge #1 · 128 m · Surface · 0 m · platforms: Station 1")

            // Another platform over the same stretch overlaps it.
            session.addNetworkPlatform()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.invalidPlatform.playerMessage(in: .english)))
            XCTAssertEqual(session.world, expected)
        }
    }

    /// Near the end of the edge the stretch moves back to fit, and a
    /// station within two tiles is chosen for it.
    func testAPlatformNearAStationServesIt() async throws {
        var world = try makeLineWorld()
        let station = try world.buildStation(named: "East", at: PlanPoint(x: 8_704, y: 4_608))
        var expected = world
        try expected.addTrackPlatform(station.id, on: .edge(1), from: 6_144, to: 8_192)
        await MainActor.run { [expected] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.platformCars = 2
            session.tapNetwork(at: PlanPoint(x: 9_000, y: 3_072), reach: Self.reach)
            XCTAssertEqual(session.platformStationID, station.id)

            session.addNetworkPlatform()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Added a 32 m platform to East on edge #1."))
            session.removeNetworkPlatform(TrackPlatform(station: station.id, edge: .edge(1), start: 6_144, end: 8_192))
            XCTAssertEqual(session.world, world)
        }
    }

    /// The train tool puts a train onto a station's network platform, its
    /// head at the far end the way it faces, standing there.
    func testATrainIsPlacedOnAPlatformTheWayItFaces() async throws {
        var world = try makeLineWorld()
        let station = try world.buildStation(named: "Mid", at: PlanPoint(x: 4_608, y: 3_584))
        try world.addTrackPlatform(station.id, on: .edge(1), from: 952, to: 5_048)
        let train = try world.purchaseTrain(named: "Tram")
        try world.setTrainCars(train.id, to: 2)
        for (heading, direction, offset) in [(CompassHeading.east, TrackEdgeDirection.forward, Int64(5_048)), (.west, .backward, 7_240)] {
            var expected = world
            try expected.placeTrain(train.id, at: .onEdge(TrackTraversal(edge: .edge(1), direction: direction), offset: offset))
            try expected.setTrainContinuation(train.id, along: [], stoppingAt: offset)
            try expected.useTrainPerformanceForMovement(train.id)
            await MainActor.run { [world, expected] in
                let session = GameSession(world: world)
                session.selectTool(.train)
                session.setPlacementHeading(heading)
                session.tapMap(at: PlanPoint(x: 4_700, y: 3_500), reach: 256)
                session.applyTool()

                XCTAssertEqual(session.world, expected, "\(heading)")
                XCTAssertEqual(session.world.stationStopText(of: train.id, in: .english), "Stopped at Mid")
                XCTAssertEqual(
                    session.message?.text,
                    "Placed Tram at Mid, on edge #1 going \(direction == .forward ? "forward" : "backward")."
                )
            }
        }
    }

    // MARK: - Removing

    /// Removing an edge removes its end nodes no other edge ends at.
    func testRemovingAnEdgeTakesItsLooseNodesWithIt() async throws {
        var world = try makeNetworkWorld()
        let n1 = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let n2 = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
        let n3 = try world.buildTrackNode(at: WorldCoordinate(x: 10_240, y: 2_048))
        try world.buildTrackEdge(from: n1, to: n2)
        try world.buildTrackEdge(from: n2, to: n3)
        var expected = world
        try expected.removeTrackEdge(.edge(2))
        try expected.removeTrackNode(n3)
        await MainActor.run { [world, expected] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.setNetworkMode(.remove)
            session.tapNetwork(at: PlanPoint(x: 8_000, y: 2_300), reach: Self.reach)
            XCTAssertEqual(session.networkEdgePoint?.edge, .edge(2))
            XCTAssertEqual(session.networkDraftText(), "Edge #2 · 64 m · Surface · 0 m")

            session.removeNetworkEdge()

            XCTAssertEqual(session.world, expected)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Removed edge #2."))
            XCTAssertNil(session.networkEdgePoint)
            session.removeNetworkEdge()
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Tap the track to remove."))
        }
    }

    func testAnEdgeWithAPlatformIsNotRemoved() async throws {
        var world = try makeLineWorld()
        let station = try world.buildStation(named: "Mid", at: PlanPoint(x: 4_608, y: 3_584))
        try world.addTrackPlatform(station.id, on: .edge(1), from: 952, to: 5_048)
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectTool(.network)
            session.setNetworkMode(.remove)
            session.tapNetwork(at: PlanPoint(x: 6_000, y: 3_072), reach: Self.reach)
            session.removeNetworkEdge()
            XCTAssertEqual(session.world, world)
            XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: GameError.trackEdgeHasPlatform(.edge(1)).playerMessage(in: .english)))
        }
    }

    // MARK: - Text

    func testTheNetworkToolReadsInChinese() async throws {
        let world = try makeNetworkWorld()
        await MainActor.run {
            let session = GameSession(world: world, language: .traditionalChinese)
            session.selectTool(.network)
            XCTAssertEqual(session.networkDraftText(), "請點軌道的起點：既有的節點，或任何地方建立新節點。")
            session.tapNetwork(at: Self.a, reach: Self.reach)
            XCTAssertEqual(session.networkDraftText(), "從新節點開始。請點終點。")
            session.tapNetwork(at: Self.b, reach: Self.reach)
            XCTAssertEqual(session.networkPreview?.text(in: .traditionalChinese), "64 公尺 · $ 4")
            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.text, "已建造軌段 #1：64 公尺，地面，花費 $ 4。")
            session.tapNetwork(at: PlanPoint(x: 6_144 + 1_000, y: 2_048), reach: Self.reach)
            XCTAssertEqual(session.networkPreview?.problem, "該位置與另一端太近：兩者至少要相距 22 公尺。")
            XCTAssertEqual(NetworkToolMode.allCases.map { $0.title(in: .traditionalChinese) }, ["鋪設", "月台", "拆除"])
            XCTAssertEqual(TrackStructure.allCases.map { $0.name(in: .traditionalChinese) }, ["地面", "高架", "橋樑", "隧道"])
        }
    }

    // MARK: - The map

    func testTheMapTurnsTapsIntoWorldPointsAndAFingertipsReach() {
        // 32 points a tile: 32 world units a point.
        XCTAssertEqual(MapScale.worldPoint(atX: 48, y: 16.5, referenceSize: 32), PlanPoint(x: 1_536, y: 528))
        XCTAssertEqual(MapScale.worldDistance(NetworkBuilding.touchRadius, referenceSize: 32), 768)
        XCTAssertEqual(MapScale.worldDistance(NetworkBuilding.touchRadius, referenceSize: 64), 384, "closer in, a finger reaches less of the world")
    }

    func testTheOverlayDrawsWhatTheNetworkToolPicked() async throws {
        let world = try makeLineWorld()
        await MainActor.run {
            let session = GameSession(world: world)
            XCTAssertNil(session.networkOverlay, "only the network tool draws one")
            session.selectTool(.network)
            XCTAssertEqual(session.networkOverlay, NetworkOverlay())

            session.tapNetwork(at: PlanPoint(x: 1_024, y: 6_144), reach: Self.reach)
            session.tapNetwork(at: PlanPoint(x: 9_216, y: 6_144), reach: Self.reach)
            var expected = NetworkOverlay()
            expected.anchors = [WorldCoordinate(x: 1_024, y: 6_144), WorldCoordinate(x: 9_216, y: 6_144)]
            expected.preview = expected.anchors
            expected.previewIsBuildable = true
            XCTAssertEqual(session.networkOverlay, expected)

            session.setNetworkMode(.remove)
            session.tapNetwork(at: PlanPoint(x: 5_000, y: 3_000), reach: Self.reach)
            XCTAssertEqual(session.networkOverlay?.highlight, [WorldCoordinate(x: 1_024, y: 3_072), WorldCoordinate(x: 9_216, y: 3_072)])
            XCTAssertEqual(session.networkOverlay?.highlightKind, .removal)

            session.setNetworkMode(.platform)
            session.platformCars = 1
            session.tapNetwork(at: PlanPoint(x: 5_120, y: 3_000), reach: Self.reach)
            XCTAssertEqual(session.networkOverlay?.highlight, [WorldCoordinate(x: 4_608, y: 3_072), WorldCoordinate(x: 5_632, y: 3_072)])
            XCTAssertEqual(session.networkOverlay?.highlightKind, .platform)
        }
    }

    func testTheToolsSettingsAndTheNetworkSummaryRead() async throws {
        let world = try makeLineWorld()
        XCTAssertEqual(world.networkSummary(in: .english), "0 stations · 1 edge")
        XCTAssertEqual(world.networkSummary(in: .traditionalChinese), "0 座車站 · 1 個軌段")
        await MainActor.run {
            let session = GameSession(world: world)
            XCTAssertEqual(session.networkHeightText(), "New nodes on the ground")
            session.networkHeight = 512
            XCTAssertEqual(session.networkHeightText(), "New nodes 8 m above the ground")
            session.networkHeight = -1_024
            XCTAssertEqual(session.networkHeightText(), "New nodes 16 m below the ground")
            XCTAssertEqual(session.platformLengthText(), "Platform for 4 cars · 64 m")
            session.platformCars = 1
            XCTAssertEqual(session.platformLengthText(), "Platform for 1 car · 16 m")
        }
        await MainActor.run {
            let session = GameSession(world: world, language: .traditionalChinese)
            session.networkHeight = -1_024
            XCTAssertEqual(session.networkHeightText(), "新節點：地面以下 16 公尺")
            XCTAssertEqual(session.platformLengthText(), "月台長 4 節車廂 · 64 公尺")
        }
    }
}
