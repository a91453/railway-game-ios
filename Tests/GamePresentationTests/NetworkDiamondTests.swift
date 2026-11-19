import GameCore
@testable import GamePresentation
import XCTest

/// Decision 887 (GRADE-CROSSING-TOOL): a stretch drawn across the
/// company's track at one level crosses it on the flat, at a diamond,
/// instead of being refused; too flat a crossing, or one by a switch, is
/// still refused as before.
final class NetworkDiamondTests: XCTestCase {
    private static let reach: Int64 = 128

    /// A north–south line through the middle of a 512 × 256 m world.
    private func northSouthLine(at x: Int64 = 16_384) throws -> (world: GameWorld, north: TrackNodeID, south: TrackNodeID) {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let north = try world.buildTrackNode(at: WorldCoordinate(x: x, y: 2_048))
        let south = try world.buildTrackNode(at: WorldCoordinate(x: x, y: 14_336))
        try world.buildTrackEdge(from: north, to: south)
        return (world, north, south)
    }

    @MainActor
    private func draw(_ world: GameWorld, from: PlanPoint, to: PlanPoint) -> GameSession {
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.tapNetwork(at: from, reach: Self.reach)
        session.tapNetwork(at: to, reach: Self.reach)
        return session
    }

    /// Straight across: the preview says so, and the build splits both
    /// tracks at one node where each runs only straight on; a train goes
    /// across from west to east.
    @MainActor
    func testATrackDrawnAcrossAnotherCrossesItAtADiamond() throws {
        let (world, north, south) = try northSouthLine()
        let session = draw(world, from: PlanPoint(x: 8_192, y: 8_192), to: PlanPoint(x: 24_576, y: 8_192))
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertNil(preview.problem)
        XCTAssertNotNil(preview.cost)
        XCTAssertEqual(preview.crossoverNote, GameSession.diamondText(1, in: session.language))

        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let network = session.world.network
        XCTAssertEqual(network.edges.count, 4, "the line split in two, the new track in two")
        let middle = try XCTUnwrap(network.nodes.first { $0.position.plan == PlanPoint(x: 16_384, y: 8_192) })
        XCTAssertEqual(middle.ends.count, 4)
        for end in middle.ends {
            XCTAssertEqual(end.exits.count, 1, "straight across only: a diamond")
        }
        // North joins south, west joins east.
        func edge(to node: TrackNodeID) throws -> TrackEdgeID {
            try XCTUnwrap(network.edges.first { ($0.from == node && $0.to == middle.id) || ($0.to == node && $0.from == middle.id) }).id
        }
        XCTAssertEqual(middle.end(of: try edge(to: north))?.exits, [try edge(to: south)])
        let west = try XCTUnwrap(network.nodes.first { $0.position.plan == PlanPoint(x: 8_192, y: 8_192) }).id
        let east = try XCTUnwrap(network.nodes.first { $0.position.plan == PlanPoint(x: 24_576, y: 8_192) }).id
        let westEdge = try edge(to: west), eastEdge = try edge(to: east)
        XCTAssertEqual(middle.end(of: westEdge)?.exits, [eastEdge])

        var played = session.world
        let train = try played.purchaseTrain(named: "T").id
        let westward = network.edge(westEdge)?.from == west
        try played.placeTrain(train, at: .onEdge(TrackTraversal(edge: westEdge, direction: westward ? .forward : .backward), offset: 0))
        let eastward = network.edge(eastEdge)?.from == middle.id
        try played.setTrainContinuation(train, along: [TrackTraversal(edge: eastEdge, direction: eastward ? .forward : .backward)])
        try played.setTrainMovementRate(train, to: 60_000)
        played.setSpeed(.normal)
        try played.advance(ticks: 1)
        guard case .onEdge(let traversal, _)? = played.train(id: train)?.position else { return XCTFail("placed") }
        XCTAssertEqual(traversal.edge, eastEdge, "across the diamond")
    }

    /// Across a double line: one diamond on each track.
    @MainActor
    func testACrossingOfADoubleLineMakesTwoDiamonds() throws {
        var (world, _, _) = try northSouthLine(at: 16_384)
        let north = try world.buildTrackNode(at: WorldCoordinate(x: 16_896, y: 2_048))
        let south = try world.buildTrackNode(at: WorldCoordinate(x: 16_896, y: 14_336))
        try world.buildTrackEdge(from: north, to: south)
        let session = draw(world, from: PlanPoint(x: 8_192, y: 8_192), to: PlanPoint(x: 24_576, y: 8_192))
        XCTAssertEqual(session.networkPreview?.crossoverNote, GameSession.diamondText(2, in: session.language))
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        let diamonds = session.world.network.nodes.filter { $0.ends.count == 4 && $0.ends.allSatisfy { $0.exits.count == 1 } }
        XCTAssertEqual(diamonds.map(\.position.plan).sorted { $0.x < $1.x }, [PlanPoint(x: 16_384, y: 8_192), PlanPoint(x: 16_896, y: 8_192)])
        XCTAssertEqual(session.world.network.edges.count, 7)
    }

    /// Flatter than 1 in 4, or within 22 m of a switch or a track's end:
    /// refused as before, and nothing is built.
    @MainActor
    func testATooFlatOrTooNearCrossingIsStillRefused() throws {
        let (world, _, _) = try northSouthLine()
        // 1 in 8 across the line.
        let flat = draw(world, from: PlanPoint(x: 15_872, y: 4_096), to: PlanPoint(x: 16_896, y: 12_288))
        XCTAssertNotNil(flat.networkPreview?.problem)
        flat.buildNetworkTrack()
        XCTAssertEqual(flat.world, world)
        XCTAssertEqual(flat.message?.kind, .failure)
        // 12 m from the line's north end.
        let near = draw(world, from: PlanPoint(x: 8_192, y: 2_816), to: PlanPoint(x: 24_576, y: 2_816))
        XCTAssertNotNil(near.networkPreview?.problem)
        near.buildNetworkTrack()
        XCTAssertEqual(near.world, world)
    }

    /// A curved stretch is cut where it crosses so that its two pieces
    /// leave the node in opposite directions: still a diamond.
    func testACurvedStretchIsCutIntoPiecesThatJoin() throws {
        var (world, _, _) = try northSouthLine()
        let from = try world.buildTrackNode(at: WorldCoordinate(x: 8_192, y: 6_144))
        let to = try world.buildTrackNode(at: WorldCoordinate(x: 24_576, y: 6_144))
        let curve = TrackCurve.cubic(PlanPoint(x: 13_000, y: 10_000), PlanPoint(x: 20_000, y: 10_000))
        let geometry = try XCTUnwrap(TrackGeometry(from: WorldCoordinate(x: 8_192, y: 6_144), to: WorldCoordinate(x: 24_576, y: 6_144), curve: curve))
        let stretch = PlayerCommand.TrackStretch(
            start: .node(from), end: .node(to), from: WorldCoordinate(x: 8_192, y: 6_144), to: WorldCoordinate(x: 24_576, y: 6_144),
            curve: curve, profile: .uniform, structure: .automatic, ground: NetworkBuilding.surveyedPoints(of: geometry)
        )
        var draft = world
        let chain = try XCTUnwrap(NetworkDiamond.chain(for: stretch, in: &draft, heights: nil))
        XCTAssertEqual(chain.pieces.count, 2)
        XCTAssertEqual(chain.nodes.count, 1)
        XCTAssertTrue(NetworkDiamond.isDiamond(chain.nodes[0], in: draft))
        // Built again as the command log replays it: the same world.
        var replayed = world
        var previous: TrackNodeID?
        for piece in chain.pieces {
            previous = try piece.starting(at: previous).build(in: &replayed, heights: nil).to
        }
        XCTAssertEqual(replayed.network, draft.network)
    }
}
